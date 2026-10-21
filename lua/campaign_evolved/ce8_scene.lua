-- Shared numeric scene data for the one-pass 8tex surface. Uploads run outside
-- model/material callbacks. Map lights and flashlight/projector beams share the surface submission.
if SERVER then return end
CE8=CE8 or {}
if CE8.SceneState then return end
local state={models=setmetatable({}, {__mode="k"}),freeModels={},modelCount=1,
    lights={},lightCount=0,freeLights={},cookies={},cookieSlots={},modelSlots={},modelOwners=setmetatable({}, {__mode="v"}),parameters={},parameterKeys={},pending={},updates={},frame=-1,uploads=0}
CE8.SceneState=state
local target,writer,expander
local vectors={Vector(),Vector(),Vector(),Vector()}
local suffixes={"x","y","z","w"}
local active,camera=false,false
local function resources()
    if target then return end
    target=GetRenderTargetEx("ce8_scene_fp32",1024,1024,RT_SIZE_NO_CHANGE,MATERIAL_RT_DEPTH_NONE,bit.bor(4,8,256,512),0,29)
    assert(target and not target:IsError(),"CE8 scene data target unavailable")
    state.texture=target
    local function material(name,program)
        return CreateMaterial(name,"screenspace_general_8tex",{
            ["$pixshader"]=program,["$vertexshader"]="ce8_parameter_write_v1_vs30",
            ["$vertextransform"]="1",["$basetexture"]="color/white",["$linearread_basetexture"]="1",
            ["$linearwrite"]="1",["$depthtest"]="0",["$writedepth"]="0",["$writealpha"]="1",
            ["$alpha_blend"]="0",["$cull"]="0"})
    end
    writer=material("ce8_scene_numeric_writer","ce8_scene_store_ps30")
    expander=material("ce8_scene_expander","ce8_scene_expand_ps30")
end
local function beginUpload()
    if active then return end
    resources();render.PushRenderTarget(target);active=true
    render.OverrideAlphaWriteEnable(true,true)
    render.OverrideBlend(true,BLEND_ONE,BLEND_ZERO,BLENDFUNC_ADD,BLEND_ONE,BLEND_ZERO,BLENDFUNC_ADD);cam.Start2D();camera=true
end
local function finishUpload()
    if not active then return end
    if camera then cam.End2D();camera=false end
    render.OverrideBlend(false);render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget();active=false
end
local function quad(material,x,y,w,h)
    local a,b,c,d=unpack(vectors)
    a.x,a.y=x,y;b.x,b.y=x+w,y;c.x,c.y=x+w,y+h;d.x,d.y=x,y+h
    render.SetMaterial(material);mesh.Begin(MATERIAL_QUADS,1)
    mesh.Position(a);mesh.TexCoord(0,0,0);mesh.AdvanceVertex()
    mesh.Position(b);mesh.TexCoord(0,1,0);mesh.AdvanceVertex()
    mesh.Position(c);mesh.TexCoord(0,1,1);mesh.AdvanceVertex()
    mesh.Position(d);mesh.TexCoord(0,0,1);mesh.AdvanceVertex();mesh.End()
end
local function write(pixel,rows,count)
    beginUpload()
    for first=1,count,4 do
        for r=0,3 do
            local row=rows[first+r]
            for c=1,4 do writer:SetFloat("$c"..r.."_"..suffixes[c],row and row[c] or 0) end
        end
        local at=(pixel+first-1)*2
        quad(writer,at%1024,math.floor(at/1024),8,1)
        state.uploads=state.uploads+1
    end
end
local function newRows(count)
    local result={};for i=1,count do result[i]={0,0,0,0} end;return result
end
local function row(record,index,x,y,z,w)
    local v=record.rows[index]
    if v[1]~=x or v[2]~=y or v[3]~=z or v[4]~=w then
        record.dirty=true;v[1],v[2],v[3],v[4]=x,y,z,w
    end
end
local function beam(light)
    local texture=light.cookie;local frame=light.cookieFrame or 0
    if not texture then return nil end
    local key=light.cookieFrame and light.key or texture
    local cached=state.cookies[key]
    if cached and cached.texture==texture and cached.textureFrame==frame then cached.used=FrameNumber();return cached end
    local slot=cached
    if slot then
    elseif #state.cookieSlots<8 then slot={index=#state.cookieSlots};state.cookieSlots[#state.cookieSlots+1]=slot
    else
        for _,candidate in ipairs(state.cookieSlots) do
            if candidate.used<FrameNumber()-2 and (not slot or candidate.used<slot.used) then slot=candidate end
        end
    end
    if not slot then state.cookieOverflow=true;return nil end
    if slot.key then state.cookies[slot.key]=nil end
    slot.key=key;slot.texture=texture;slot.textureFrame=frame;slot.used=FrameNumber()
    slot.x,slot.y=(slot.index%4)*256,512+math.floor(slot.index/4)*256
    -- Numeric data and projected images share a sampler. Limit beam images to
    -- 256 square with their native mip filter; original VTFs remain untouched.
    beginUpload();expander:SetTexture("$basetexture",texture);expander:SetInt("$frame",frame);expander:SetFloat("$c0_x",3)
    expander:SetFloat("$c0_y",math.max(0,math.log(math.max(texture:Width(),texture:Height())/256)/math.log(2)))
    quad(expander,slot.x,slot.y,256,256)
    state.cookies[key]=slot
    return slot
end
local function lightSlot(light)
    local cached=state.lights[light.key]
    if not cached then
        local slot=table.remove(state.freeLights)
        if not slot and state.lightCount<4096 then slot=state.lightCount;state.lightCount=slot+1 end
        if not slot then state.lightOverflow=true;return nil end
        cached={slot=slot,rows=newRows(8),dirty=true};state.lights[light.key]=cached
    end
    cached.used=FrameNumber()
    if light.mapLight and cached.source==light then return cached.slot end
    local rect=not light.mapLight and beam(light) or nil
    if light.cookie and not light.mapLight and not rect then return nil end
    local p,c,f,a=light.position,light.color,light.forward,light.attenuation
    row(cached,1,p.x,p.y,p.z,light.directional and -1 or light.mapLight and (light.spot and 3 or 2) or 1)
    row(cached,2,c.x,c.y,c.z,light.range)
    row(cached,3,f.x,f.y,f.z,light.mapLight and light.coneInner or light.near)
    if light.mapLight then
        row(cached,4,a.x,a.y,a.z,light.coneOuter);row(cached,5,light.coneExponent,0,0,0)
        cached.source=light
    else
        local r,u=light.right,light.up
        row(cached,4,r.x,r.y,r.z,light.tangentHorizontal);row(cached,5,u.x,u.y,u.z,light.tangentVertical)
        row(cached,6,a.x,a.y,a.z,light.diffuse or 1)
        row(cached,7,rect and rect.x or 0,rect and rect.y or 0,rect and 256 or 0,rect and 256 or 0)
    end
    if cached.dirty then write(cached.slot*8,cached.rows,8);cached.dirty=false end
    return cached.slot
end
function CE8.SceneModel(ent)
    if CE8.MaterialOwner then ent=CE8.MaterialOwner(ent) end
    if not IsValid(ent) then return 0 end
    local model=state.models[ent]
    if not model then
        local slot=table.remove(state.freeModels)
        if not slot and state.modelCount<1024 then slot=state.modelCount;state.modelCount=slot+1 end
        if not slot then return 0 end
        model={slot=slot,ready=false,rows=newRows(16),dirty=true};state.models[ent]=model
        state.modelSlots[slot]=model;state.modelOwners[slot]=ent
    end
    model.used=FrameNumber()
    return model.ready and model.slot or 0
end
function CE8.SceneParameters(record,rows,key,pinned)
    local slot=state.parameterKeys[key]
    if slot then slot.used=FrameNumber();return slot.ready and slot.index or nil end
    if #state.parameters<256 then
        slot={index=#state.parameters,used=FrameNumber()};state.parameters[#state.parameters+1]=slot
    else
        for _,candidate in ipairs(state.parameters) do
            if not candidate.pinned and candidate.ready and candidate.used<FrameNumber()-2
                and (not slot or candidate.used<slot.used) then slot=candidate end
        end
    end
    if not slot then return nil end
    if slot.key then state.parameterKeys[slot.key]=nil end
    slot.key,slot.ready,slot.pinned=key,false,pinned
    slot.record,slot.rows=record,rows
    state.parameterKeys[key]=slot;state.pending[#state.pending+1]=slot
end
local function channel(row)
    for selected=1,4 do
        local match=true
        for c=1,4 do if row[c]~=(c==selected and 1 or 0) then match=false;break end end
        if match then return selected-1 end
    end
    return -1
end
local function prepareParameters(slot)
    local record,rows=slot.record,slot.rows
    beginUpload()
    expander:SetTexture("$basetexture",assert(CE8.NamedTexture(record.textures.MaterialParameterTexture,false),"Missing CE8 parameter texture"));expander:SetInt("$frame",0)
    expander:SetFloat("$c0_x",0)
    local pixel=32768+slot.index*256
    quad(expander,(pixel*2)%1024,math.floor(pixel*2/1024),320,1)
    for first=1,#rows,4 do
        local changed=false
        for i=first,math.min(first+3,#rows) do
            for c=1,4 do if rows[i][c]~=record.default_parameter_rows[i][c] then changed=true end end
        end
        if changed then write(pixel+first-1,{rows[first],rows[first+1],rows[first+2],rows[first+3]},4) end
    end
    local routes,masked=0,0
    for i=1,rows[3][2] do
        local selected=channel(rows[8+i])
        if selected<0 then routes=-1;break end
        routes=routes+selected*4^(i-1)
        if rows[8][i]~=0 then masked=masked+2^(i-1) end
    end
    write(pixel,{rows[1],rows[2],{rows[3][1],rows[3][2],routes,masked},rows[4]},4)
    local derived={}
    for i=0,7 do
        local at=21+i*7
        derived[i+1]={channel(rows[at]),rows[at+5][4],rows[at+5][1],(rows[at+1][4]+1)*.5}
    end
    write(pixel+200,derived,8)
    slot.ready=true;slot.rows=nil;slot.record=nil
end
local programs={ce8_live_detail_v8_ps30="ce8_scene_live_ps30",ce8_live_detail_v8_packed_ps30="ce8_scene_live_ps30",
    ce8_atlas_surface_v3_ps30="ce8_scene_atlas_ps30",ce8_atlas_worm_v3_ps30="ce8_scene_worm_ps30",
    ce8_plasma_v2_ps30="ce8_scene_plasma_ps30"}
function CE8.SceneMaterial(material,ready)
    local current=material:GetString("$pixshader") or ""
    if programs[current] and ready then state.updates[material]=programs[current] end
    return current:sub(1,10)=="ce8_scene_"
end
hook.Remove("PreRender","CE8LightBatchUpload")
hook.Remove("PostRender","CE8LightBatchMaterials")
local function updateScene(parameters)
    state.uploads=0
    local ok,message=xpcall(function()
        if not next(state.modelSlots) and #state.pending==0 then return end
        if not state.neutral then
            local rows={}
            for i=1,16 do rows[i]=i<=6 and {.25,.25,.25,0} or {0,0,0,0} end
            write(98304,rows,16);state.neutral=true
            -- Preserve the Hunter's original Clouds texture and every native mip.
            local noise=CE8.NamedTexture("models/campaign_evolved/ce8/material_sets/hunter/textures/plasma_noise3",false)
            if noise then
                expander:SetTexture("$basetexture",noise);expander:SetInt("$frame",0);expander:SetFloat("$c0_x",2)
                for mip=0,8 do
                    local size=2^(8-mip)
                    expander:SetFloat("$c0_y",mip);quad(expander,768-2*size,224,size,size)
                end
            end
        end
        if not state.brdf then
            local brdf=assert(CE8.NamedTexture("models/campaign_evolved/ce8/shader_inputs/environment_brdf",false),"Missing CE8 BRDF")
            beginUpload();expander:SetTexture("$basetexture",brdf);expander:SetInt("$frame",0)
            expander:SetFloat("$c0_x",4);quad(expander,0,224,128,128);state.brdf=true
        end
        for _=1,parameters and 4 or 0 do
            if #state.pending==0 then break end
            prepareParameters(state.pending[1]);table.remove(state.pending,1)
        end
        for slot,model in pairs(state.modelSlots) do
            local ent=state.modelOwners[slot]
            if not IsValid(ent) or FrameNumber()-model.used>120 then
                state.freeModels[#state.freeModels+1]=slot;state.modelSlots[slot]=nil;state.modelOwners[slot]=nil
                if ent then state.models[ent]=nil end
            elseif not parameters and FrameNumber()-model.used<=2 then
                local ambient=CE8.AmbientLighting(ent)
                for i=1,6 do local c=ambient[i];row(model,i,c.x,c.y,c.z,0) end
                local ids=model.ids or {};model.ids=ids
                for i=1,16 do ids[i]=0 end
                local count=0
                for _,light in ipairs(CE8.GetDirectLights(ent)) do
                    local id=lightSlot(light)
                    if id and count<16 then count=count+1;ids[count]=id end
                end
                for i=0,3 do local at=i*4;row(model,7+i,ids[at+1],ids[at+2],ids[at+3],ids[at+4]) end
                row(model,11,count,0,0,0)
                if model.dirty then write(98304+model.slot*16,model.rows,16);model.dirty=false end
                model.ready=true;ent.CE8SelectedLights=count;ent.CE8LightPasses=0
            end
        end
        if not parameters and FrameNumber()%120==0 then
            for key,light in pairs(state.lights) do
                if FrameNumber()-light.used>120 then state.freeLights[#state.freeLights+1]=light.slot;state.lights[key]=nil end
            end
        end
    end,debug.traceback)
    finishUpload()
    if not ok then state.error=message;ErrorNoHalt("CE8 scene upload: "..tostring(message).."\n");return end
    state.error=nil
    if not parameters then return end
    for material,program in pairs(state.updates) do
        material:SetString("$pixshader",program);material:SetInt("$linearread_texture7",1)
        material:Recompute();state.updates[material]=nil
    end
end
hook.Add("PreRender","CE8SceneLights",function() updateScene(false) end)
hook.Add("PostRender","CE8SceneParameters",function() updateScene(true) end)
