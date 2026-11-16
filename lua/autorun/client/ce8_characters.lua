-- Shared character renderer and current model/material controls.
if SERVER then return end
CE8 = CE8 or {}
if include and not CE8.MaterialLODReady then
    include("autorun/client/ce8_surface.lua")
end
if include then include("campaign_evolved/ce8_phong.lua") end

-- Native props can be classified as opaque even when a material supplies
-- a translucent section. Remember only props actually submitted in this view;
-- the translucent-stage fallback never redraws their body or direct lights.
local pendingEmissive={}
function CE8.QueueEmissiveModel(ent) pendingEmissive[ent]=true end
if hook then
    hook.Add("PreDrawOpaqueRenderables","CE8EmissiveView",function(depth)
        if not depth then pendingEmissive={};CE8.EnergyRefractUpdated=false end
    end)
    hook.Add("PostDrawTranslucentRenderables","CE8EmissiveProps",function(depth)
        if depth then return end
        local queued=pendingEmissive;pendingEmissive={}
        local ordered={}
        local eye=EyePos()
        for ent in pairs(queued) do
            if IsValid(ent) and not ent:GetNoDraw() and ent.CE8EmissiveMaterials then
                ordered[#ordered+1]={ent=ent,distance=ent:GetPos():DistToSqr(eye)}
            end
        end
        table.sort(ordered,function(a,b) return a.distance>b.distance end)
        for _,row in ipairs(ordered) do CE8.DrawEmissiveModel(row.ent,STUDIO_RENDER or 1) end
    end)
end

-- Draw only after opaque scene depth is complete. A native translucent callback
-- consumes the queued fallback, so each section is drawn once per view.
function CE8.DrawEmissiveModel(ent, flags)
    pendingEmissive[ent]=nil
    local materials=ent.CE8EmissiveMaterials
    if not (ent.CE8Draft or ent.CE8Native) or not materials then return end
    local previous=ent.CE8DrawingEmissive
    ent.CE8DrawingEmissive=true
    if ent.CE8Native and EF_NOFLASHLIGHT then ent:AddEffects(EF_NOFLASHLIGHT) end
    local bloomMaterials=materials
    local ok,message=xpcall(function()
        render.OverrideDepthEnable(true,false)
        if ent.CE8EnergyLayers then
            bloomMaterials=CE8.DrawNativeEnergyLayers(ent,flags)
            return
        end
        render.OverrideBlend(false) -- Native materials own their blend state.
        for slot,material in pairs(materials) do render.MaterialOverrideByIndex(slot,material) end
        -- Indexed overrides isolate the energy mesh. The Jackal prop must submit
        -- all submodels: STUDIO_TWOPASS filters out its barrier before shading.
        local drawFlags=ent.CE8EmissiveAllSubmodels and (STUDIO_RENDER or 1)
            or bit.bor(flags or STUDIO_RENDER or 1,STUDIO_TWOPASS or 8)
        ent:DrawModel(drawFlags)
    end,debug.traceback)
    if ok and bloomMaterials and CE8.QueueEmissionBloom then CE8.QueueEmissionBloom(ent,bloomMaterials) end
    ent.CE8DrawingEmissive=previous
    if ent.CE8Native and EF_NOFLASHLIGHT then ent:RemoveEffects(EF_NOFLASHLIGHT) end
    render.OverrideBlend(false)
    render.OverrideDepthEnable(false,false)
    for slot in pairs(materials) do render.MaterialOverrideByIndex(slot,nil) end
    ent.CE8DrawError=not ok and message or nil
    if not ok then ErrorNoHalt("CE8 emissive draw: "..tostring(message).."\n") end
end

function CE8.BindCharacter(ent,definition,custom,normalSpawn)
    return CE8.BindPhongCharacter(ent,definition,normalSpawn)
end

