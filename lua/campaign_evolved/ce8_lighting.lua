-- Direct-light bridge for the stock 8tex carrier. No renderer module required.
if SERVER then return end
CE8 = CE8 or {}
local bridge = CE8.LightBridge or {providers={}, projected=setmetatable({}, {__mode="k"})}
CE8.LightBridge = bridge
bridge.staticProviders = bridge.staticProviders or {}
local maximum = CreateClientConVar("ce8_max_direct_lights", "4", true, false,
    "Maximum selected map lights and projectors per CE8 model in its surface pass.", 0, 16)
local occlusion = CreateClientConVar("ce8_light_occlusion", "1", true, false,
    "Trace coarse light visibility at the model center; not a pixel shadow map.", 0, 1)
local cookieCache, visibility = {}, setmetatable({}, {__mode="k"})
local selections = setmetatable({}, {__mode="k"})
local traceScratch = setmetatable({}, {__mode="k"})
local frameSources, sourceFrame = {}, -1
local staticCatalog,staticSources,staticRevision,staticDirty = {},{},0,true
local staticSelections=setmetatable({}, {__mode="k"})
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
    selections = setmetatable({}, {__mode="k"})
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
                        if value and (value.mapLight or value.spot) and value.category~="lamp" then cached.lights[#cached.lights+1]=value end
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
local function offer(ranked,source,score,limit)
    if score==nil or (#ranked>=limit and score<=ranked[#ranked].score) then return end
    local at=math.min(#ranked+1,limit)
    while at>1 and score>ranked[at-1].score do ranked[at]=ranked[at-1];at=at-1 end
    ranked[at]={source=source,score=score}
end
local function visibleFrom(ent,source,position)
    local scratch=traceScratch[ent]
    if not scratch then
        scratch={filter={},output={},sky=Vector(0,0,0)}
        scratch.data={filter=scratch.filter,output=scratch.output,mask=MASK_OPAQUE}
        traceScratch[ent]=scratch
    end
    local filter,data=scratch.filter,scratch.data
    filter[1]=ent
    if ent.CE8AssemblyParts then
        for _,part in pairs(ent.CE8AssemblyParts) do
            if IsValid(part) then filter[#filter+1]=part end
        end
    end
    if IsValid(source.source) then filter[#filter+1]=source.source end
    if source.directional then
        local f,sky=source.forward,scratch.sky
        sky.x,sky.y,sky.z=position.x-f.x*32768,position.y-f.y*32768,position.z-f.z*32768
        data.start,data.endpos=position,sky
    else data.start,data.endpos=source.position,position end
    -- Trace.output is the engine's supported reusable result table. Clear the
    -- consumed fields first so a trace unavailable during startup cannot leak
    -- its predecessor's result. Keep no entity references in weak-key caches.
    local output=scratch.output
    output.Hit,output.HitSky,output.Fraction=nil,nil,nil
    local trace=util.TraceLine(data) or output
    local seen=source.directional and trace.HitSky==true
        or not source.directional and (trace.Hit==false or (trace.Fraction or 0)>=.99)
    output.Entity=nil
    data.start,data.endpos=nil,nil
    for i=#filter,1,-1 do filter[i]=nil end
    return seen
end
function CE8.GetDirectLights(ent)
    if CE8.MaterialOwner then ent = CE8.MaterialOwner(ent) end
    local limit = math.floor(maximum:GetFloat())
    if not IsValid(ent) or limit <= 0 then return {} end
    if ent.CE8Parameters and (ent.CE8Parameters.debugview or 0) > .5 then return {} end
    local frame=FrameNumber()
    local specular=true
    if CE8.MaterialLOD then
        local _,_,weight=CE8.MaterialLOD(ent)
        specular=math.floor(weight*255+.5)>0
    end
    local traceLights=occlusion:GetFloat()>.5
    local selected=selections[ent]
    if selected and selected.frame==frame and selected.specular==specular and selected.limit==limit
        and selected.traceLights==traceLights then return selected.lights end
    local position = CE8.LightPosition and CE8.LightPosition(ent) or ent:WorldSpaceCenter()
    local radius = CE8.LightRadius and CE8.LightRadius(ent) or ent:BoundingRadius()
    local dynamic,static,revision=collect()
    local candidateLimit=limit*4
    local cached=staticSelections[ent]
    if not cached or cached.x~=position.x or cached.y~=position.y or cached.z~=position.z
        or cached.radius~=radius or cached.specular~=specular or cached.limit~=candidateLimit or cached.revision~=revision then
        cached={x=position.x,y=position.y,z=position.z,radius=radius,specular=specular,
            limit=candidateLimit,revision=revision,ranked={}}
        for _,source in ipairs(static) do
            offer(cached.ranked,source,lightScore(source,position,radius,specular),candidateLimit)
        end
        staticSelections[ent]=cached
    end
    local result=cached.ranked
    if #dynamic>0 then
        result={};for i,row in ipairs(cached.ranked) do result[i]=row end
        for _,source in ipairs(dynamic) do offer(result,source,lightScore(source,position,radius,specular),candidateLimit) end
    end
    local cache = visibility[ent]
    if not cache then cache={};visibility[ent]=cache end
    local visible={}
    for index,row in ipairs(result) do
        if #visible>=limit or index>limit*4 then break end
        local source=row.source
        local seen=not IsValid(source.target) or CE8.MaterialOwner and CE8.MaterialOwner(source.target)==ent or source.target==ent
        if seen and traceLights then
            local sample = cache[source.key]
            if not sample or RealTime() >= sample.next then
                sample=sample or {}
                sample.visible=visibleFrom(ent,source,position)
                sample.next=RealTime()+.05
                cache[source.key] = sample
            end
            seen=sample.visible
        end
        if seen then
            -- Share immutable source data; per-model visibility stays in this cache.
            visible[#visible+1]=source
        end
    end
    selected=selected or {}
    selected.frame,selected.specular,selected.limit=frame,specular,limit
    selected.traceLights,selected.lights=traceLights,visible
    selections[ent]=selected
    return visible
end
if include then include("campaign_evolved/ce8_map_lights.lua") end
-- Model redraws are removed. The shared scene uploader consumes this selection.
CE8.DrawDirectLights=nil
if hook then hook.Remove("PreRender","CE8LightBatchUpload");hook.Remove("PostRender","CE8LightBatchMaterials") end
if include then include("campaign_evolved/ce8_scene.lua") end
