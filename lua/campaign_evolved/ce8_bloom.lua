-- CE8 emission-only bloom. No entity discovery or whole-roster material loads.
if SERVER then return end
CE8=CE8 or {}
local enabled=CreateClientConVar("ce8_bloom","0",true,false,"Bloom from CE8 emission only.",0,1)
local strength=CreateClientConVar("ce8_bloom_strength","0.25",true,false,"CE8 emission bloom strength.",0,2)
local radius=CreateClientConVar("ce8_bloom_radius","4",true,false,"CE8 emission bloom spread.",0,16)
local distance=CreateClientConVar("ce8_bloom_distance","2048",true,false,"CE8 bloom draw distance; 0 is unlimited.",0,32768)
-- Matproxy and Material() can expose different Lua wrappers for the same engine material.
local pending,eligible={},setmetatable({}, {__mode="k"})
local queued=setmetatable({}, {__mode="k"})
local variants=CE8.BloomMaterials or {};CE8.BloomMaterials=variants
local drawing=false
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

-- Queue only actual main-view submissions, including held weapons and ragdolls.
-- Inspect the actual model materials; visible meshes/bodygroups decide which
-- pixels render. No rank-specific emission slot lists.
function CE8.QueueEmissionBloom(ent,materials)
    if not allowed(ent) then return end
    local row=pending[ent]
    for slot,material in pairs(materials) do
        local shader=material.GetShader and material:GetShader()
        -- Pure unlit model materials already contain only emission. Reuse them
        -- in the isolated emission buffer; no material/slot lists or light bind.
        local unlit=shader=="UnlitGeneric" and material:GetTexture("$basetexture")
            and material:GetInt("$no_draw")~=1 and (material:GetFloat("$alpha") or 1)>0
        local effect=unlit
        local native=material.GetShader and material:GetShader()=="VertexLitGeneric"
            and material:GetInt("$emissiveblendenabled")==1
            and (material:GetFloat("$emissiveblendstrength") or 0)>0
            and material:GetTexture("$emissiveblendbasetexture")
        if native or effect then
            if not row then
                row=queued[ent]
                if not row or row.model~=ent:GetModel() then
                    row={slots={},count=#ent:GetMaterials(),model=ent:GetModel()};queued[ent]=row
                end
                pending[ent]=row
            end
            local entry=row.slots[slot] or {};row.slots[slot]=entry
            entry.material,entry.effect,entry.frame=material,effect,FrameNumber()
            entry.native=native
        end
    end
end

local function emissionMaterial(entry)
    if entry.effect then return entry.material end -- These shaders already evaluate only emission.
    if entry.native then
        local key=entry.material:GetName().."/native_emission"
        local material=variants[key]
        if not material then
            material=CreateMaterial("ce8_bloom/"..key,"UnlitGeneric",{
                ['$model']=1,['$nodecal']=1,['$basetexture']=entry.native:GetName()})
            variants[key]=material
        end
        material:SetTexture("$basetexture",entry.native)
        local tint=entry.material:GetVector("$emissiveblendtint") or Vector(1,1,1)
        material:SetVector("$color",tint*(entry.material:GetFloat("$emissiveblendstrength") or 1))
        return material
    end
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
    -- Private copies of GMod's stock pp/copy material. $linearwrite=0
    -- is required for a framebuffer texture, matching the engine halo path.
    local function blitter(name,texture)
        return CreateMaterial(name,"UnlitGeneric",{
            ['$basetexture']=texture:GetName(),['$fbtexture']="_rt_FullFrameFB",
            ['$ignorez']=1,['$writez']=0,['$linearwrite']=0,['$color']="[1 1 1]"})
    end
    copy=blitter("ce8_emission_native_copy",store)
    add=blitter("ce8_emission_native_add",blur)
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
local white,black=Vector(1,1,1),Vector(0,0,0)
local gainColor=Vector()
local function drawCopy(material)
    render.SetMaterial(material)
    render.DrawScreenQuad()
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
        copy:SetTexture("$basetexture",store);copy:SetVector("$color",black)
        drawCopy(copy)
        render.SetStencilEnable(false)
        copy:SetVector("$color",white)
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
    copy:SetTexture("$basetexture",store);copy:SetVector("$color",white)
    drawCopy(copy)
    if ok then
        -- Only isolated emission is added; retain the restored scene's alpha.
        render.OverrideBlend(true,BLEND_ONE,BLEND_ONE,BLENDFUNC_ADD,BLEND_ZERO,BLEND_ONE,BLENDFUNC_ADD)
        local gain=strength:GetFloat()
        add:SetTexture("$basetexture",blur);gainColor.x,gainColor.y,gainColor.z=gain,gain,gain;add:SetVector("$color",gainColor)
        drawCopy(add)
    elseif CE8.BloomError~=message then ErrorNoHalt("CE8 emission bloom: "..tostring(message).."\n") end
    render.OverrideDepthEnable(false,false)
    render.OverrideBlend(false);render.SetBlend(savedBlend);render.SetColorModulation(red,green,blue)
    CE8.BloomError=not ok and message or nil
    drawing=false;table.Empty(pending)
end)
