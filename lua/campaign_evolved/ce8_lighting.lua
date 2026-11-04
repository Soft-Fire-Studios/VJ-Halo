-- Direct-light bridge for the stock 8tex carrier. No renderer module required.
if SERVER then return end
CE8 = CE8 or {}
-- The model metadata layout and bytecode change together. Keep an already
-- running session on its existing bridge until restart clears cached shaders.
if CE8.SceneState and CE8.SceneState.layout~=3 then
    if not CE8.SceneRestartRequired then
        ErrorNoHalt("CE8 regional lighting installed: restart GMod to load the matching shader programs.\n")
        CE8.SceneRestartRequired=true
    end
    return
end
local bridge = CE8.LightBridge or {providers={}, projected=setmetatable({}, {__mode="k"})}
CE8.LightBridge = bridge
bridge.staticProviders = bridge.staticProviders or {}
local maximum = CreateClientConVar("ce8_max_direct_lights", "4", true, false,
    "Maximum contributing map lights and projectors per surface pixel.", 0, 16)
local occlusion = CreateClientConVar("ce8_light_occlusion", "1", true, false,
    "Trace shared regional light visibility; not a pixel shadow map.", 0, 1)
local cookieCache = {}
local frameSources, sourceFrame = {}, -1
local staticCatalog,staticSources,staticRevision,staticDirty = {},{},0,true
local emptySelection={}
local function finite(value, default)
    value = tonumber(value)
    if not value or value ~= value or math.abs(value) == math.huge then return default end
    return value
end
local function linear(value)
    value = math.max(value, 0)
    return value <= .04045 and value/12.92 or ((value+.055)/1.055)^2.4
end
local function color(value, brightness)
    return Vector(linear(value.r/255)*brightness, linear(value.g/255)*brightness, linear(value.b/255)*brightness)
end
local function convar(name, default)
    local value = GetConVar(name)
    return value and value:GetFloat() or default
end
local function cookie(reference)
    if type(reference) ~= "string" or reference == "" then return end
    if cookieCache[reference] then return cookieCache[reference] end
    local material = CreateMaterial("ce8_cookie_" .. util.CRC(reference), "UnlitGeneric", {["$basetexture"]=reference})
    local texture = material:GetTexture("$basetexture")
    if texture and not texture:IsError() then cookieCache[reference] = texture; return texture end
end
local function normalize(source)
    if not source or not isvector(source.position) or not isvector(source.color) then return end
    for _,vector in ipairs({source.position, source.color}) do
        if not finite(vector.x) or not finite(vector.y) or not finite(vector.z) then return end
    end
    if source.near~=nil and finite(source.near,0)<=0 then return end
    local range = math.Clamp(finite(source.range, 0), 0, 32768)
    if range <= 0 then return end
    local angles = source.angles or Angle(0,0,0)
    local colorLimit = source.mapLight and 1e12 or 256
    return {key=source.key or source.source or source, source=source.source, position=source.position,
        color=Vector(math.Clamp(source.color.x,0,colorLimit), math.Clamp(source.color.y,0,colorLimit), math.Clamp(source.color.z,0,colorLimit)),
        range=range, near=math.Clamp(finite(source.near,1),.01,range), spot=source.spot == true,
        forward=source.forward or angles:Forward(), right=source.right or angles:Right(), up=source.up or angles:Up(),
        tangentHorizontal=math.tan(math.rad(math.Clamp(finite(source.horizontalFOV or source.fov,60),1,175))*.5),
        tangentVertical=math.tan(math.rad(math.Clamp(finite(source.verticalFOV or source.fov,60),1,175))*.5),
        attenuation=source.attenuation or Vector(0,100,0), diffuse=source.diffuse == 0 and 0 or 1,
        cookie=source.cookie or cookie(source.texture), cookieFrame=source.cookieFrame, target=source.target, category=source.category or "point",
        directional=source.directional==true, mapLight=source.mapLight==true,
        coneInner=finite(source.coneInner,1),coneOuter=finite(source.coneOuter,-1),
        coneExponent=math.max(finite(source.coneExponent,1),0),style=source.style,record=source.record}
end
function CE8.RegisterLightProvider(name, callback, immutable)
    bridge.providers[name] = callback
    -- Immutable providers replace their array when its contents change. Dynamic
    -- providers retain the per-frame contract for moving projectors.
    bridge.staticProviders[name]=immutable==true
    staticCatalog[name]=nil;staticDirty=true
    sourceFrame = -1
end
function CE8.RegisterProjectedTexture(projector)
    if IsValid(projector) then bridge.projected[projector] = true end
    sourceFrame = -1
end
if FindMetaTable then
    local meta=FindMetaTable("ProjectedTexture")
    if meta and meta.Update and not CE8.ProjectorUpdateHook then
        local original=meta.Update
        CE8.ProjectorUpdateHook=function(projector,...)
            CE8.RegisterProjectedTexture(projector)
            return original(projector,...)
        end
        meta.Update=CE8.ProjectorUpdateHook
    end
end
local function flashlightTransform(ply)
    local model
    if ply == LocalPlayer() and not ply:ShouldDrawLocalPlayer() then model = ply:GetViewModel()
    else model = ply:GetActiveWeapon() end
    for _,candidate in ipairs({model or false, ply}) do
        if IsValid(candidate) then
            local attachment = candidate:LookupAttachment("gmod_flashlight")
            local transform = attachment and attachment > 0 and candidate:GetAttachment(attachment)
            if transform then return transform.Pos, transform.Ang end
        end
    end
    return ply:EyePos(), ply:EyeAngles()
end
local function collect()
    if sourceFrame == FrameNumber() then return frameSources,staticSources,staticRevision end
    sourceFrame, frameSources = FrameNumber(), {}
    local function add(source)
        local value = normalize(source)
        if value and (value.mapLight or value.spot) and value.category~="lamp" then frameSources[#frameSources+1] = value end
    end
    if convar("r_flashlightmodels",1) ~= 0 and convar("r_flashlightrender",1) ~= 0 then
        for _,ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:FlashlightIsOn() then
                local position, angles = flashlightTransform(ply)
                add({key=ply, source=ply, position=position, angles=angles, spot=true, category="flashlight",
                    color=color(ply:GetFlashlightColor(),1), near=convar("r_flashlightnear",4), range=convar("r_flashlightfar",750),
                    fov=convar("r_flashlightfov",60), texture="effects/flashlight001",
                    attenuation=Vector(convar("r_flashlightconstant",0),convar("r_flashlightlinear",100),convar("r_flashlightquadratic",0))})
            end
        end
    end
    for projector in pairs(bridge.projected) do
        if IsValid(projector) then
            add({key=projector,position=projector:GetPos(),angles=projector:GetAngles(),spot=true,category="projector",
                color=color(projector:GetColor(),projector:GetBrightness()), range=projector:GetFarZ(),near=projector:GetNearZ(),
                horizontalFOV=projector:GetHorizontalFOV(),verticalFOV=projector:GetVerticalFOV(),cookie=projector:GetTexture(),
                cookieFrame=projector:GetTextureFrame(),target=projector:GetTargetEntity(),
                attenuation=Vector(projector:GetConstantAttenuation(),projector:GetLinearAttenuation(),projector:GetQuadraticAttenuation())})
        end
    end
    for name,provider in pairs(bridge.providers) do
        local ok, sources = pcall(provider)
        if ok and istable(sources) then
            if bridge.staticProviders[name] then
                local cached=staticCatalog[name]
                if not cached or cached.sources~=sources then
                    cached={sources=sources,lights={}}
                    for _,source in ipairs(sources) do
                        local value=normalize(source)
                        if value and (value.mapLight or value.spot) and value.category~="lamp" then
                            value.immutable=true;cached.lights[#cached.lights+1]=value
                        end
                    end
                    staticCatalog[name]=cached;staticDirty=true
                end
            else
                for _,source in ipairs(sources) do add(source) end
            end
        else
            if staticCatalog[name] then staticCatalog[name]=nil;staticDirty=true end
            if not ok then ErrorNoHalt("CE8 light provider "..tostring(name)..": "..tostring(sources).."\n") end
        end
    end
    if staticDirty then
        staticSources={};staticRevision=staticRevision+1;staticDirty=false
        for _,cached in pairs(staticCatalog) do
            for _,source in ipairs(cached.lights) do staticSources[#staticSources+1]=source end
        end
    end
    return frameSources,staticSources,staticRevision
end
local function lightScore(source,position,radius,specular)
    if not specular and (source.diffuse or 1)==0 then return end
    local x,y,z=position.x-source.position.x,position.y-source.position.y,position.z-source.position.z
    local squared=x*x+y*y+z*z
    if not source.directional and squared>=(source.range+radius)^2 then return end
    local f=source.forward
    if source.spot and source.mapLight then
        local distance=math.sqrt(math.max(squared,1e-12))
        if (x*f.x+y*f.y+z*f.z+radius)/distance<source.coneOuter then return end
    elseif source.spot then
        local axial=x*f.x+y*f.y+z*f.z
        local r,u=source.right,source.up
        if axial+radius<source.near or axial-radius>source.range
            or math.abs(x*r.x+y*r.y+z*r.z)>math.max(axial,0)*source.tangentHorizontal+radius*math.sqrt(1+source.tangentHorizontal^2)
            or math.abs(x*u.x+y*u.y+z*u.z)>math.max(axial,0)*source.tangentVertical+radius*math.sqrt(1+source.tangentVertical^2) then return end
    end
    local score=math.max(source.color.x,source.color.y,source.color.z)
    if source.mapLight and not source.directional then
        local a=source.attenuation
        return score/math.max(a.x+a.y*math.sqrt(squared)+a.z*squared,1e-6)
    end
    return source.directional and score or score/(1+squared/(source.range*source.range))
end
local function clearRanking(ranked,pool)
    for i=#ranked,1,-1 do
        local row=ranked[i];row.source=nil
        pool[#pool+1]=row;ranked[i]=nil
    end
end
local function offer(ranked,source,score,limit,pool)
    if score==nil or (#ranked>=limit and score<=ranked[#ranked].score) then return end
    local row=#ranked>=limit and ranked[#ranked] or table.remove(pool) or {}
    local at=math.min(#ranked+1,limit)
    while at>1 and score>ranked[at-1].score do ranked[at]=ranked[at-1];at=at-1 end
    row.source,row.score=source,score;ranked[at]=row
end
-- Regions are allocated only where a rendered model needs them. A hull check
-- prevents sharing across a wall/prop inside the region; obstructed regions
-- subdivide from 64 to 8 units, then use a private receiver point. This is still
-- coarse visibility, not a shadow map: shadow edges can vary inside a clear cell.
local MAX_REGIONS,TRACE_BUDGET,REFRESH=1024,128,.1
local regions,regionSlots={},{}
local cursor,workFrame,budget=1,-1,0
local currentDynamic,currentStatic,currentRevision={},{},0
local currentLimit,currentOcclusion=4,true
local stats={regions=0,traces=0,hulls=0,rankings=0,projectorRankings=0,budget=TRACE_BUDGET}
CE8.LightRegions=stats
local raySource
local function geometryFilter(ent)
    if ent==raySource or ent.CE8AssemblyPart
        or CE8.SceneState and CE8.SceneState.models[ent] then return false end
    -- A regional sample cannot use one actor as its self filter. Coarse
    -- occlusion belongs to world/props/doors, not the swarm's own bodies.
    if ent.IsNPC and ent:IsNPC() or ent.IsPlayer and ent:IsPlayer()
        or ent.IsNextBot and ent:IsNextBot() or ent.IsWeapon and ent:IsWeapon() then return false end
    return true
end
local traceOutput={}
local ray={filter=geometryFilter,output=traceOutput,mask=MASK_OPAQUE}
local hull={filter=geometryFilter,output=traceOutput,mask=MASK_OPAQUE,mins=Vector(0,0,0),maxs=Vector(0,0,0)}
local sky=Vector(0,0,0)
local function trace(data,isHull)
    if budget<=0 then return end
    budget=budget-1;stats.traces=stats.traces+1
    if isHull then stats.hulls=stats.hulls+1 end
    traceOutput.Hit,traceOutput.HitSky,traceOutput.HitWorld=nil,nil,nil
    traceOutput.StartSolid,traceOutput.AllSolid,traceOutput.Fraction=nil,nil,nil
    local result
    if isHull then result=util.TraceHull(data) else result=util.TraceLine(data) end
    result=result or traceOutput
    local hit,world,hitSky,fraction=result.Hit,result.HitWorld,result.HitSky,result.Fraction
    local solid=result.StartSolid or result.AllSolid
    traceOutput.Entity=nil;raySource=nil
    return true,hit,world,hitSky,fraction,solid
end
local function clearRegion(region,now)
    if region.size==0 or not currentOcclusion then region.clear=true;return true end
    if region.solidWorld then region.clear=false;return false end
    if now<(region.clearNext or 0) then return region.clear end
    local half=region.size*.5-.125
    hull.mins.x,hull.mins.y,hull.mins.z=-half,-half,-half
    hull.maxs.x,hull.maxs.y,hull.maxs.z=half,half,half
    hull.start,hull.endpos=region.position,region.position
    local done,hit,world,_,_,solid=trace(hull,true)
    hull.start,hull.endpos=nil,nil
    if not done then return region.clear and now<(region.clearNext or 0)+.25 end
    region.clear=hit==false and not solid
    region.solidWorld=not region.clear and world==true
    region.clearNext=now+REFRESH
    return region.clear
end
local function visible(region,source,now)
    if not currentOcclusion then return true end
    local cache=region.visibility
    local sample=cache[source.key]
    local p,f=source.position,source.forward
    local same=sample and sample.px==p.x and sample.py==p.y and sample.pz==p.z
        and (not source.directional or sample.fx==f.x and sample.fy==f.y and sample.fz==f.z)
        and (not source.immutable or sample.source==source)
    if same and (sample.worldBlocked and source.immutable or now<sample.next) then return sample.visible end
    if region.allowance<=0 or budget<=0 then
        return same and sample.visible and now<sample.next+.25 or false
    end
    local position=region.position
    if source.directional then
        sky.x,sky.y,sky.z=position.x-f.x*32768,position.y-f.y*32768,position.z-f.z*32768
        ray.start,ray.endpos=position,sky
    else ray.start,ray.endpos=p,position end
    raySource=source.source
    local done,hit,world,hitSky,fraction=trace(ray,false)
    ray.start,ray.endpos=nil,nil
    if not done then return false end
    region.allowance=region.allowance-1
    local seen=source.directional and hitSky==true
        or not source.directional and (hit==false or (fraction or 0)>=.99)
    sample=sample or {};cache[source.key]=sample
    sample.visible,sample.worldBlocked,sample.next=seen,not seen and world==true,now+REFRESH
    sample.px,sample.py,sample.pz,sample.fx,sample.fy,sample.fz=p.x,p.y,p.z,f.x,f.y,f.z
    sample.source=source.immutable and source or nil
    return seen
end
local function updateRegion(region,now)
    if region.frame==FrameNumber() then return end
    region.frame=FrameNumber();region.allowance=32
    local lights=region.lights
    for i=#lights,1,-1 do lights[i]=nil end
    region.projectorCount=0
    if not clearRegion(region,now) then return end
    local radius=region.radius+region.size*.8660254
    if region.revision~=currentRevision or region.limit~=currentLimit then
        region.revision,region.limit=currentRevision,currentLimit
        region.visibility={}
        clearRanking(region.static,region.staticPool)
        for _,source in ipairs(currentStatic) do
            offer(region.static,source,lightScore(source,region.position,radius,true),currentLimit*4,region.staticPool)
        end
        stats.rankings=stats.rankings+1
    end
    -- Moving projectors never invalidate the static ranking. Their records and
    -- lists are shared across occupants, and target-entity filtering happens in
    -- the shader, after the per-model receiver ID has been uploaded.
    clearRanking(region.dynamic,region.dynamicPool)
    if #currentDynamic>0 then
        for _,source in ipairs(currentDynamic) do
            offer(region.dynamic,source,lightScore(source,region.position,radius,true),16,region.dynamicPool)
        end
        stats.projectorRankings=stats.projectorRankings+1
    end
    for _,candidate in ipairs(region.dynamic) do
        if visible(region,candidate.source,now) then lights[#lights+1]=candidate.source end
        if #lights>=16 then break end
    end
    region.projectorCount=#lights
    local count=0
    for _,candidate in ipairs(region.static) do
        if visible(region,candidate.source,now) then lights[#lights+1]=candidate.source;count=count+1 end
        if count>=currentLimit then break end
    end
    -- Drop stale projector keys; static samples live with their provider revision.
    if region.frame%120==0 then
        for key,sample in pairs(region.visibility) do
            if not sample.source and now>sample.next+1 then region.visibility[key]=nil end
        end
    end
end
function CE8.BeginLightFrame()
    if workFrame==FrameNumber() then return end
    workFrame=FrameNumber();budget=TRACE_BUDGET
    stats.traces,stats.hulls,stats.rankings,stats.projectorRankings=0,0,0,0
    currentDynamic,currentStatic,currentRevision=collect()
    currentLimit=math.Clamp(math.floor(maximum:GetFloat()),0,16)
    local traceLights=occlusion:GetFloat()>.5
    if currentOcclusion~=traceLights then
        for _,region in ipairs(regionSlots) do
            region.clearNext=0;region.clear=nil;region.visibility={};region.frame=-1
        end
    end
    currentOcclusion=traceLights
    if currentLimit==0 then return end
    -- Rotate the start of the work queue so a crowded view cannot indefinitely
    -- starve later regions. The hard budget includes hull checks and light rays.
    local count=#regionSlots
    local now=RealTime()
    local nextCursor
    for i=0,count-1 do
        local index=(cursor+i-1)%count+1
        local region=regionSlots[index]
        if workFrame-region.used<=2 then updateRegion(region,now) end
        if budget==0 and not nextCursor then nextCursor=index%count+1 end
    end
    cursor=nextCursor or (count>0 and cursor%count+1 or 1)
    stats.remaining=budget
end
local function regionAt(key,x,y,z,size,radius)
    local region=regions[key]
    if not region then
        local slot
        if #regionSlots<MAX_REGIONS then slot=#regionSlots+1
        else
            for index,candidate in ipairs(regionSlots) do
                if workFrame-candidate.used>2 and (not slot or candidate.used<regionSlots[slot].used) then slot=index end
            end
        end
        if not slot then stats.overflow=true;return end
        local previous=regionSlots[slot]
        if previous then regions[previous.key]=nil end
        region={key=key,position=Vector(x,y,z),size=size,radius=radius,used=workFrame,frame=-1,
            static={},staticPool={},dynamic={},dynamicPool={},visibility={},lights={}}
        regions[key]=region;regionSlots[slot]=region;stats.regions=#regionSlots
    elseif size==0 and (region.position.x~=x or region.position.y~=y or region.position.z~=z) then
        region.position.x,region.position.y,region.position.z=x,y,z
        region.visibility={};region.revision=nil;region.frame=-1
    end
    region.used=workFrame
    updateRegion(region,RealTime())
    stats.remaining=budget
    return region
end
local receivers=setmetatable({}, {__mode="k"})
local receiverID=0
function CE8.GetDirectLights(ent)
    if CE8.MaterialOwner then ent=CE8.MaterialOwner(ent) end
    if not IsValid(ent) then return emptySelection end
    CE8.BeginLightFrame()
    if currentLimit<=0 or ent.CE8Parameters and (ent.CE8Parameters.debugview or 0)>.5 then return emptySelection end
    local specular=true
    if CE8.MaterialLOD then local _,_,weight=CE8.MaterialLOD(ent);specular=weight>0 end
    if not specular and #currentDynamic==0 then return emptySelection end
    local position=CE8.LightPosition and CE8.LightPosition(ent) or ent:WorldSpaceCenter()
    local radius=CE8.LightRadius and CE8.LightRadius(ent) or ent:BoundingRadius()
    radius=math.ceil(radius/32)*32
    local cached=receivers[ent]
    if cached and cached.frame==workFrame and cached.x==position.x and cached.y==position.y and cached.z==position.z
        and cached.radius==radius then
        local region=cached.region
        return region and region.lights or emptySelection,region
    end
    local region
    local pointFallback=false
    for level=0,3 do
        local size=64/2^level
        local x,y,z=math.floor(position.x/size),math.floor(position.y/size),math.floor(position.z/size)
        local key=size..":"..x..":"..y..":"..z..":"..radius
        region=regionAt(key,(x+.5)*size,(y+.5)*size,(z+.5)*size,size,radius)
        if not region or region.clear then break end
        -- An untested region must not be treated as a solid one and subdivided
        -- indefinitely while its trace is waiting for next frame's budget.
        if region.clear==nil then region=nil;break end
        region=nil;pointFallback=level==3
    end
    if pointFallback then
        if not cached then receiverID=receiverID+1;cached={id=receiverID};receivers[ent]=cached end
        region=regionAt("receiver:"..cached.id,position.x,position.y,position.z,0,radius)
    end
    if not cached then receiverID=receiverID+1;cached={id=receiverID};receivers[ent]=cached end
    cached.frame,cached.x,cached.y,cached.z,cached.radius,cached.region=workFrame,position.x,position.y,position.z,radius,region
    return region and region.lights or emptySelection,region
end
if include then include("campaign_evolved/ce8_map_lights.lua") end
CE8.DrawDirectLights=nil
if hook then hook.Remove("PreRender","CE8LightBatchUpload");hook.Remove("PostRender","CE8LightBatchMaterials") end
if include then include("campaign_evolved/ce8_scene.lua") end
