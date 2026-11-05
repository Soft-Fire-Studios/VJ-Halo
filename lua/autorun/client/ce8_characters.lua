-- Shared character renderer and current model/material controls.
if SERVER then return end
CE8 = CE8 or {}
if include and not CE8.SupportsOverallPaint then
    include("autorun/client/ce8_surface.lua")
end
CE8.Assemblies = nil
if include then include("campaign_evolved/ce8_assembly.lua") end
if include then include("campaign_evolved/ce8_phong.lua") end

-- Native props can be classified as opaque even when a custom shader supplies
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
        render.OverrideBlend(true,BLEND_SRC_ALPHA,ent.CE8EmissiveAdditive and BLEND_ONE or BLEND_ONE_MINUS_SRC_ALPHA,BLENDFUNC_ADD)
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

function CE8.BindCharacter(ent, definition, custom, normalSpawn)
    if definition.material_mode=="phong" then return CE8.BindPhongCharacter(ent,definition,normalSpawn) end
    if definition.ce8_only then custom = true end
    local bindings = definition.material_bindings or definition
    ent.CE8Draft = custom == nil and ent.CE8Draft or custom
    ent.CE8Parameters = ent.CE8Parameters or {}
    ent.CE8CharacterDefinition = definition
    ent.CE8BodygroupDrawCache=nil;ent.CE8BodygroupLayout=nil;ent.CE8ActiveLightMaterials=nil
    if not normalSpawn then
        local assembly = definition.assembly or definition
        CE8.AssemblePreview(ent, assembly, function(part) CE8.BindCharacter(part, definition, ent.CE8Draft) end)
        ent:SetSubMaterial()
    end
    ent.CE8OverrideMaterials, ent.CE8LightMaterials, ent.CE8AllOverrideSlots = {},nil,{}
    if ent.CE8Draft and ent.AddEffects and EF_NOFLASHLIGHT then ent:AddEffects(EF_NOFLASHLIGHT) end
    ent.CE8EmissiveMaterials=nil
    ent.CE8EmissiveAdditive=bindings.emissive_blend=="additive"
    ent.CE8EmissiveAllSubmodels=bindings.emissive_submodels=="all"
    ent.CE8ShadowHiddenMaterials={}
    local emissive=bindings.emissive_materials or {}
    if ent.CE8Draft and next(emissive) then ent.CE8EmissiveMaterials={} end
    for index, original in ipairs(ent:GetMaterials()) do
        local slot, name = index-1, string.lower(original)
        local replacement = (bindings.stock_materials or {})[name]
        if ent.CE8Draft then replacement = (bindings.materials or {})[name] or (bindings.glows or {})[name] or replacement end
        if ent.CE8EmissiveMaterials then
            local hidden=assert(bindings.light_hidden_material,"Emissive slots require a hidden material")
            ent.CE8EmissiveMaterials[slot]=Material(emissive[name] or hidden)
            ent.CE8AllOverrideSlots[slot]=true
            if emissive[name] then
                replacement=hidden
                ent.CE8ShadowHiddenMaterials[slot]=Material(hidden)
            end
        end
        if replacement then
            assert(slot<32,"CE8 region exceeds the indexed material override limit")
            ent.CE8OverrideMaterials[slot] = Material(replacement)
            if CE8.RefreshMaterialTextures then CE8.RefreshMaterialTextures(ent.CE8OverrideMaterials[slot]) end
            ent.CE8AllOverrideSlots[slot] = true
        end

    end
    ent.RenderOverride = function(self, flags)
        -- Networked effects can replace the client flag after initial binding,
        -- especially on Sandbox props/ragdolls. The shader already lights the
        -- beam, so keep the native projector pass excluded at submission time.
        if self.CE8Draft and EF_NOFLASHLIGHT and self.IsEffectActive
            and not self:IsEffectActive(EF_NOFLASHLIGHT) then self:AddEffects(EF_NOFLASHLIGHT) end
        if self.CE8DrawingEmissive then self:DrawModel(flags) return end
        local depth = bit.bor(STUDIO_SHADOWDEPTHTEXTURE or 0,STUDIO_SSAODEPTHTEXTURE or 0)
        if flags and bit.band(flags,depth)~=0 then
            -- CE's plasma surface casts no shadow or SSAO depth. Keep the
            -- physical handle in those passes and restore indexed overrides.
            local hidden=self.CE8ShadowHiddenMaterials
            for slot,material in pairs(hidden) do render.MaterialOverrideByIndex(slot,material) end
            local ok,message=xpcall(function() self:DrawModel(flags) end,debug.traceback)
            for slot in pairs(hidden) do render.MaterialOverrideByIndex(slot,nil) end
            if not ok then ErrorNoHalt("CE8 shadow draw: "..tostring(message).."\n") end
            CE8.DrawAssemblyParts(self,flags)
            return
        end
        if self.CE8EmissiveMaterials and flags and
            bit.band(flags,STUDIO_DRAWTRANSLUCENTSUBMODELS or 4)~=0 then
            CE8.DrawEmissiveModel(self,flags)
            return
        end
        if self.CE8EmissiveMaterials and not self.DrawWorldModelTranslucent then
            pendingEmissive[self]=true
        end
        local baseMaterials,_,activeSlots=CE8.ActiveCharacterMaterials(self)
        -- GetColor creates a Lua Color table. All material/light binds inside
        -- this model submission share the same entity modulation. Scope it to
        -- this draw only so another view or same-frame SetColor stays current.
        local previousColor=self.CE8BoundRenderColor
        self.CE8BoundRenderColor=self.GetColor and self:GetColor() or nil
        local ok,message = xpcall(function()
            for slot,material in pairs(baseMaterials) do render.MaterialOverrideByIndex(slot,material) end
            if self.CE8Draft then render.OverrideDepthEnable(true,true) end
            self:DrawModel(flags)
            render.OverrideDepthEnable(false,false)
            self.CE8LightPasses=0
        end,debug.traceback)
        -- BindCharacter derives these slots from the model's actual GetMaterials.
        -- Bloom selects only current-frame emitting binds, not the catalogue's
        -- bodygroup indices (which can change when a model is recompiled).
        if ok and self.CE8Draft and CE8.QueueEmissionBloom then CE8.QueueEmissionBloom(self,self.CE8OverrideMaterials) end
        self.CE8BoundRenderColor=previousColor
        render.OverrideDepthEnable(false,false)
        render.OverrideBlend(false)
        for slot in pairs(activeSlots) do render.MaterialOverrideByIndex(slot,nil) end
        self.CE8DrawError = not ok and message or nil
        if ok then self.CE8Draws = (self.CE8Draws or 0)+1 else ErrorNoHalt("CE8 character draw: "..tostring(message).."\n") end
        CE8.DrawAssemblyParts(self,flags)
    end
    ent.CE8ApplyError = nil
    return ent
end

function CE8.AttachCharacter(ent, character, permutation, custom)
    local definition = CE8.GetAssembly(character,permutation)
    assert(definition,"CE8 character/permutation is absent from the assembly catalog")
    if custom == nil then custom = next((definition.material_bindings or {}).materials or {})~=nil end
    return CE8.BindCharacter(ent,definition,custom)
end

function CE8.SpawnCharacterPreview(character, permutation)
    character=string.lower(character or "")
    permutation=permutation and string.lower(permutation)
    local definition = CE8.GetAssembly(character,permutation)
    assert(definition,"Unknown CE8 character/permutation")
    local entry=(CE8.Assemblies or {}).characters and CE8.Assemblies.characters[character]
    permutation=permutation or (entry and entry.default_rank) or "minor"
    local player = LocalPlayer()
    if not IsValid(player) then return end
    local trace = player:GetEyeTrace()
    local position = trace.HitPos+Vector(0,0,1)
    if trace.Hit == false then position = player:EyePos()+player:GetAimVector()*200 end
    local angles = Angle(0,player:EyeAngles().y+180,0)
    local entities = {}
    local ent = ClientsideModel(definition.parent_model,RENDERGROUP_BOTH)
    if IsValid(ent) then
        ent:SetNoDraw(true)
        ent:SetPos(position);ent:SetAngles(angles)
        ent:SetSequence("bind_pose");ent:SetPlaybackRate(0)
        ent.CE8Draft=true;ent.CE8Parameters={}
        ent.CE8CharacterName,ent.CE8CharacterRank = character,permutation
        local ok,message=xpcall(function() CE8.BindCharacter(ent,definition,true) end,debug.traceback)
        if ok then
            ent:SetPos(position);ent:SetAngles(angles)
            ent.CE8SpawnPosition,ent.CE8SpawnAngles=position,angles
            ent:SetNoDraw(false)
            entities[#entities+1]=ent
        else ent:Remove();ErrorNoHalt("CE8 character setup: "..tostring(message).."\n") end
    end
    return entities
end

-- Remove retired preview/debug aliases from an already running session.
if concommand and concommand.Remove then
    for _,name in ipairs({"ce8_character_list","ce8_character_preview","ce8_character_param",
        "ce8_character_params","ce8_character_envtint","ce8_character_color","ce8_character_bodygroup",
        "ce8_character_status","ce8_character_remove","ce8_ragdoll","ce8_ragdoll_list","ce8_perf_stop"}) do
        concommand.Remove(name)
    end
end
for _,entity in ipairs(CE8CharacterPreviewEntities or {}) do if IsValid(entity) then entity:Remove() end end
CE8CharacterPreviewEntities=nil
if CE8PerfSession and CE8PerfSession.Stop then CE8PerfSession:Stop("retired") end
if hook and hook.Remove then hook.Remove("ShutDown","CE8CharacterCleanup") end
