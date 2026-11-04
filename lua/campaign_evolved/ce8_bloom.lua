-- CE8 emission-only bloom. No entity discovery or whole-roster material loads.
if SERVER then return end
CE8=CE8 or {}
local enabled=CreateClientConVar("ce8_bloom","0",true,false,"Bloom from CE8 emission only.",0,1)
local strength=CreateClientConVar("ce8_bloom_strength","0.25",true,false,"CE8 emission bloom strength.",0,2)
local radius=CreateClientConVar("ce8_bloom_radius","4",true,false,"CE8 emission bloom spread.",0,16)
local distance=CreateClientConVar("ce8_bloom_distance","2048",true,false,"CE8 bloom draw distance; 0 is unlimited.",0,32768)
-- Matproxy and Material() can expose different Lua wrappers for the same engine material.
local sources={}
local pending,eligible={},setmetatable({}, {__mode="k"})
local queued=setmetatable({}, {__mode="k"})
local inputSlots={live={0,2,7},plasma={2,3,4,6,7}}
local variants=CE8.BloomMaterials or {};CE8.BloomMaterials=variants
local drawing=false
local effects={ce8_blade_v1_ps30=true,ce8_shield_v1_ps30=true,ce8_gauge_v1_ps30=true}
local programs={live={"ce8_bloom_live_ps30","ce8_bloom_live_ps30"},
    plasma={"ce8_bloom_plasma_packed_ps30","ce8_bloom_plasma_ps30"}}
local fields={}
for row=0,3 do for _,axis in ipairs({"x","y","z","w"}) do fields[#fields+1]="$c"..row.."_"..axis end end

local function allowed(ent)
    if drawing or not enabled:GetBool() or strength:GetFloat()<=0 or not IsValid(ent)
        or render.GetRenderTarget()~=nil then return false end
    local frame=FrameNumber();local cache=eligible[ent]
    if cache and cache.frame==frame then return cache.allowed end
    local cutoff=distance:GetFloat()
    local near=cutoff<=0 or ent:WorldSpaceCenter():DistToSqr(EyePos())<=(cutoff+ent:BoundingRadius())^2
    cache=cache or {};eligible[ent]=cache;cache.frame,cache.allowed=frame,near
    return near
end

-- Called by the ORIGINAL material bind, after its existing parameters are ready.
-- Snapshot only emitting inputs; never run its lighting/detail binder a second time.
function CE8.CaptureEmissionBloom(self,material,ent,kind,cache,scene)
    if not allowed(ent) then return end
    local source=sources[material:GetName()]
    local previous=source and source.entities[ent]
    if previous then previous.frame=-1 end
    if kind=="live" and not scene then return end
    local gain=scene and self.matrixA:GetField(2,2) or self.matrixA:GetField(3,4)
    if gain<=0 then return end
    if kind=="live" then
        local rows=cache.rows
        if rows[19][1]<=0 or (self.liveRecord.emission_mask_max or 1)<=rows[16][4] then return end
        local mode=rows[15][4];local maximum=mode<.5 and 1 or 0
        for i=mode>1.5 and 16 or 15,mode>1.5 and 18 or 15 do
            for j=1,3 do maximum=math.max(maximum,rows[i][j]) end
        end
        if maximum<=0 then return end
    end
    if not source then source={kind=kind,entities=setmetatable({}, {__mode="k"})};sources[material:GetName()]=source end
    local row=source.entities[ent]
    if not row then row={a=Matrix(),b=Matrix(),constants={},textures={}};source.entities[ent]=row end
    row.frame,row.scene=FrameNumber(),scene
    row.a:Set(self.matrixA);row.b:Set(self.matrixB)
    for _,i in ipairs(inputSlots[kind]) do row.textures[i]=material:GetTexture(i==0 and "$basetexture" or "$texture"..i) end
    if kind=="plasma" then for i,name in ipairs(fields) do row.constants[i]=material:GetFloat(name) end end
end

-- Queue only actual main-view submissions, including held weapons and ragdolls.
-- Inputs are the model's existing material bindings. A current-frame emission
-- snapshot selects the visible bodygroups automatically; no rank/slot lists.
function CE8.QueueEmissionBloom(ent,materials)
    if not allowed(ent) then return end
    local owner=CE8.MaterialOwner and CE8.MaterialOwner(ent) or ent
    local row=pending[ent]
    for slot,material in pairs(materials) do
        local source=sources[material:GetName()]
        local data=source and source.entities[owner]
        local effect=effects[material:GetString("$pixshader") or ""]
        if effect or (data and data.frame==FrameNumber()) then
            if not row then
                row=queued[ent]
                if not row or row.model~=ent:GetModel() then
                    row={slots={},count=#ent:GetMaterials(),model=ent:GetModel()};queued[ent]=row
                end
                pending[ent]=row
            end
            local entry=row.slots[slot] or {};row.slots[slot]=entry
            entry.material,entry.source,entry.data,entry.effect,entry.frame=material,source,data,effect,FrameNumber()
        end
    end
end

local function emissionMaterial(entry)
    if entry.effect then return entry.material end -- These shaders already evaluate only emission.
    local data,kind=entry.data,entry.source.kind
    local program=programs[kind][data.scene and 2 or 1]
    local key=entry.material:GetName().."/"..program
    local material=variants[key]
    if not material then
        local kv={['$pixshader']=program,['$vertexshader']=entry.material:GetString("$vertexshader"),
            ['$model']=1,['$vertextransform']=1,['$vertexnormal']=1,['$depthtest']=1,
            ['$writedepth']=0,['$writealpha']=0,['$alpha_blend']=0,['$linearwrite']=1,
            ['$cull']=entry.material:GetInt("$cull") or 1,['$nodecal']=1}
        for slot,texture in pairs(data.textures) do
            local name=slot==0 and "$basetexture" or "$texture"..slot
            kv[name]=texture:GetName();kv['$linearread_'..name:sub(2)]=slot==0 and 0 or 1
        end
        material=CreateMaterial("ce8_bloom/"..key,"screenspace_general_8tex",kv)
        variants[key]=material
    end
    for slot,texture in pairs(data.textures) do material:SetTexture(slot==0 and "$basetexture" or "$texture"..slot,texture) end
    material:SetMatrix("$viewprojmat",data.a);material:SetMatrix("$invviewprojmat",data.b)
    if kind=="plasma" then for i,name in ipairs(fields) do material:SetFloat(name,data.constants[i]) end end
    return material
end

local copy,add,blurX,blurY,hidden,store,emission,blur,scratch
local function resources()
    if copy then return end
    -- Fixed names/sizing modes: four reusable CE8 targets, also across Lua reloads.
    -- Never share the engine's scene/bloom buffers or its additive blur materials.
    -- TEXTUREFLAGS names are documentation-only, not GMod Lua globals.
    local flags=0x000C -- Clamp S (4) + clamp T (8).
    local function target(name,size)
        return GetRenderTargetEx(name,1024,1024,size,MATERIAL_RT_DEPTH_NONE,flags,0,IMAGE_FORMAT_RGBA8888)
    end
    store=target("ce8_emission_scene",RT_SIZE_FULL_FRAME_BUFFER)
    emission=target("ce8_emission_mask",RT_SIZE_FULL_FRAME_BUFFER)
    blur=target("ce8_emission_blur",RT_SIZE_HDR)
    scratch=target("ce8_emission_scratch",RT_SIZE_HDR)
    -- Dedicated raw copy: framebuffer colors are already encoded. UnlitGeneric
    -- can apply another color-space conversion during the full-screen restore.
    local function blitter(name,texture)
        return CreateMaterial(name,"screenspace_general_8tex",{
            ['$pixshader']="ce8_bloom_copy_ps30",['$vertexshader']="ce8_bloom_quad_vs30",
            ['$basetexture']=texture:GetName(),['$linearread_basetexture']=1,['$linearwrite']=1,
            ['$vertextransform']=0,['$depthtest']=0,['$writedepth']=0,['$writealpha']=1,
            ['$alpha_blend']=0,['$cull']=0,['$c0_x']=1})
    end
    copy=blitter("ce8_emission_raw_copy",store)
    add=blitter("ce8_emission_raw_add",blur)
    blurX=CreateMaterial("ce8_emission_blur_x","g_blurx",{['$basetexture']=blur:GetName(),['$ignorez']=1,['$additive']=0})
    blurY=CreateMaterial("ce8_emission_blur_y","g_blury",{['$basetexture']=scratch:GetName(),['$ignorez']=1,['$additive']=0})
    -- CreateMaterial reuses existing objects after Lua reloads. SetTexture must
    -- replace their previous bindings; otherwise the old shared bloom RT survives.
    blurX:SetTexture("$basetexture",blur);blurY:SetTexture("$basetexture",scratch)
    hidden=Material("models/campaign_evolved/ce8/shader_inputs/hidden")
end
local function replacePixels()
    render.OverrideBlend(true,BLEND_ONE,BLEND_ZERO,BLENDFUNC_ADD,BLEND_ONE,BLEND_ZERO,BLENDFUNC_ADD)
end
-- DrawScreenQuad supplies pixel-space vertices in GMod; the clip-space VS
-- cannot consume those. Submit explicit clip positions/UVs with D3D9's half-
-- texel alignment, sized to the CURRENT target (full-size scene or quarter blur).
local corners={Vector(),Vector(),Vector(),Vector()}
local function drawCopy(material)
    local target=render.GetRenderTarget()
    local width,height=target and target:Width() or ScrW(),target and target:Height() or ScrH()
    local left,right,top,bottom=-1-1/width,1-1/width,1+1/height,-1+1/height
    local a,b,c,d=corners[1],corners[2],corners[3],corners[4]
    a.x,a.y=left,top;b.x,b.y=right,top;c.x,c.y=right,bottom;d.x,d.y=left,bottom
    render.SetMaterial(material);mesh.Begin(MATERIAL_QUADS,1)
    mesh.Position(a);mesh.TexCoord(0,0,0);mesh.AdvanceVertex()
    mesh.Position(b);mesh.TexCoord(0,1,0);mesh.AdvanceVertex()
    mesh.Position(c);mesh.TexCoord(0,1,1);mesh.AdvanceVertex()
    mesh.Position(d);mesh.TexCoord(0,0,1);mesh.AdvanceVertex();mesh.End()
end
local function drawEntity(ent,row)
    local previous=ent.CE8DrawingEmissive;ent.CE8DrawingEmissive=true
    local ok,message=xpcall(function()
        for slot=0,row.count-1 do
            local entry=row.slots[slot]
            render.MaterialOverrideByIndex(slot,entry and entry.frame==FrameNumber() and emissionMaterial(entry) or hidden)
        end
        ent:DrawModel(bit.bor(STUDIO_RENDER or 1,STUDIO_SKIP_DECALS or 0))
    end,debug.traceback)
    for slot=0,row.count-1 do render.MaterialOverrideByIndex(slot,nil) end
    ent.CE8DrawingEmissive=previous
    if not ok then error(message,0) end
end

hook.Add("PreRender","CE8EmissionBloom",function() table.Empty(pending) end)
hook.Add("RenderScreenspaceEffects","CE8EmissionBloom",function()
    if drawing or not enabled:GetBool() or strength:GetFloat()<=0 or not next(pending)
        or render.GetRenderTarget()~=nil or not render.SupportsPixelShaders_2_0() then return end
    if GAMEMODE and GAMEMODE.PostProcessPermitted and not GAMEMODE:PostProcessPermitted("bloom") then return end
    resources()
    local scene=render.GetRenderTarget();local in3D,inRT=false,false
    local savedBlend=render.GetBlend()
    local red,green,blue=render.GetColorModulation()
    drawing=true
    render.CopyRenderTargetToTexture(store)
    local ok,message=xpcall(function()
        -- Like Facepunch's halo renderer, keep the REAL scene depth, including MSAA.
        -- Separate/shared-depth RTs lose the scene depth when MSAA is enabled.
        render.SetBlend(1);render.SetColorModulation(1,1,1)
        render.OverrideBlend(false)
        render.SetStencilEnable(false)
        render.Clear(0,0,0,255,false,true) -- Color/stencil only; keep scene depth.
        render.SetStencilWriteMask(1);render.SetStencilTestMask(1);render.SetStencilReferenceValue(1)
        render.SetStencilCompareFunction(STENCIL_ALWAYS)
        render.SetStencilPassOperation(STENCIL_REPLACE)
        render.SetStencilFailOperation(STENCIL_KEEP);render.SetStencilZFailOperation(STENCIL_KEEP)
        render.SetStencilEnable(true)
        cam.Start3D();in3D=true
        render.OverrideDepthEnable(true,false)
        local ordered={};local eye=EyePos()
        for ent,row in pairs(pending) do
            if IsValid(ent) then ordered[#ordered+1]={ent=ent,row=row,d=ent:WorldSpaceCenter():DistToSqr(eye)} end
        end
        table.sort(ordered,function(a,b) return a.d>b.d end)
        for _,item in ipairs(ordered) do drawEntity(item.ent,item.row) end
        render.OverrideDepthEnable(false,false)
        cam.End3D();in3D=false
        -- Only depth-visible emissive submissions may contribute. Explicitly
        -- black out everything outside their stencil before extracting the mask.
        render.SetStencilCompareFunction(STENCIL_NOTEQUAL);render.SetStencilPassOperation(STENCIL_KEEP)
        replacePixels()
        copy:SetTexture("$basetexture",store);copy:SetFloat("$c0_x",0)
        drawCopy(copy)
        render.SetStencilEnable(false)
        copy:SetFloat("$c0_x",1)
        render.CopyRenderTargetToTexture(emission)
        replacePixels()
        render.PushRenderTarget(blur);inRT=true
        copy:SetTexture("$basetexture",emission);drawCopy(copy)
        render.PopRenderTarget();inRT=false
        blurX:SetTexture("$basetexture",blur);blurY:SetTexture("$basetexture",scratch)
        blurX:SetFloat("$size",radius:GetFloat());blurY:SetFloat("$size",radius:GetFloat())
        render.PushRenderTarget(scratch);inRT=true
        render.SetMaterial(blurX);render.DrawScreenQuad()
        render.PopRenderTarget();inRT=false
        render.PushRenderTarget(blur);inRT=true
        render.SetMaterial(blurY);render.DrawScreenQuad()
        render.PopRenderTarget();inRT=false
    end,debug.traceback)
    -- The scene restore is a raw replacement, never a brightness/color operation.
    -- Disable our stencil on every exit; glow may spread beyond the source mesh.
    render.SetStencilEnable(false)
    render.SetStencilWriteMask(0);render.SetStencilTestMask(0);render.SetStencilReferenceValue(0)
    render.SetStencilCompareFunction(STENCIL_ALWAYS);render.SetStencilPassOperation(STENCIL_KEEP)
    render.OverrideDepthEnable(false,false)
    render.SetBlend(1);render.SetColorModulation(1,1,1)
    if in3D then cam.End3D() end
    if inRT then render.PopRenderTarget() end
    render.SetRenderTarget(scene)
    render.OverrideDepthEnable(true,false)
    replacePixels()
    copy:SetTexture("$basetexture",store);copy:SetFloat("$c0_x",1)
    drawCopy(copy)
    if ok then
        -- Only isolated emission is added; retain the restored scene's alpha.
        render.OverrideBlend(true,BLEND_ONE,BLEND_ONE,BLENDFUNC_ADD,BLEND_ZERO,BLEND_ONE,BLENDFUNC_ADD)
        local gain=strength:GetFloat()
        add:SetTexture("$basetexture",blur);add:SetFloat("$c0_x",gain)
        drawCopy(add)
    elseif CE8.BloomError~=message then ErrorNoHalt("CE8 emission bloom: "..tostring(message).."\n") end
    render.OverrideDepthEnable(false,false)
    render.OverrideBlend(false);render.SetBlend(savedBlend);render.SetColorModulation(red,green,blue)
    CE8.BloomError=not ok and message or nil
    drawing=false;table.Empty(pending)
end)
