-- Native Source lighting for baked CE8 materials. Only cubemap tint is Lua-driven.
if SERVER then return end
CE8=CE8 or {}
local samples=setmetatable({}, {__mode="k"})

matproxy.Add({
    name="CE8Phong",
    init=function(self,material,values)
        local x,y,z=(values.EnvTint or values.envtint or "1 1 1"):match("(%S+)%s+(%S+)%s+(%S+)")
        self.tint=Vector(tonumber(x) or 1,tonumber(y) or 1,tonumber(z) or 1)
        self.output=Vector()
    end,
    bind=function(self,material,ent)
        local gain=1
        if IsValid(ent) then
            local now=CurTime()
            local sample=samples[ent]
            if not sample or now>=sample.next then
                local light=render.GetLightColor(ent:WorldSpaceCenter())
                -- Engine probe is linear; the cubemap tint is a display-space
                -- multiplier. Keep the shared neutral cube subdued in darkness.
                gain=math.min(1,math.max(0,.2126*light.x+.7152*light.y+.0722*light.z)^(1/2.2))
                sample=sample or {};samples[ent]=sample
                sample.gain,sample.next=gain,now+.1
            else gain=sample.gain end
        end
        -- This cache belongs to the MATERIAL, so alternating NPCs cannot leave
        -- another actor's lighting behind. The probe cache is per entity.
        if self.last==gain then return end
        self.output.x,self.output.y,self.output.z=self.tint.x*gain,self.tint.y*gain,self.tint.z*gain
        material:SetVector("$envmaptint",self.output)
        self.last=gain
    end
})

function CE8.BindPhongCharacter(ent,definition,normalSpawn)
    if not normalSpawn then
        CE8.AssemblePreview(ent,definition.assembly or definition)
        ent:SetSubMaterial()
    end
    ent.CE8CharacterDefinition=definition
    ent.CE8Draft=false
    ent.CE8Native=true
    ent.CE8LightMaterials,ent.CE8EmissiveMaterials=nil,nil
    ent.CE8EnergyLayers,ent.CE8RefractionMaterials,ent.CE8FarEnergyMaterials=nil,nil,nil
    if ent.RemoveEffects and EF_NOFLASHLIGHT then ent:RemoveEffects(EF_NOFLASHLIGHT) end
    local materials,native,custom,hiddenBase,customPass={},{},{},{},{}
    local bindings=definition.material_bindings or {}
    local emissive=bindings.emissive_materials or {}
    local hidden=Material(bindings.light_hidden_material or "models/campaign_evolved/ce8/shader_inputs/hidden")
    ent.CE8EmissiveAdditive=bindings.emissive_blend=="additive"
    ent.CE8EmissiveAllSubmodels=bindings.emissive_submodels=="all"
    for i,name in ipairs(ent:GetMaterials()) do
        local slot=i-1
        local material=Material(name)
        materials[slot]=material
        local energy=CE8.NativeEnergy and material.GetName and CE8.NativeEnergy[material:GetName()]
        if energy then
            hiddenBase[slot]=hidden
            ent.CE8EnergyLayers=ent.CE8EnergyLayers or {}
            ent.CE8RefractionMaterials=ent.CE8RefractionMaterials or {}
            ent.CE8FarEnergyMaterials=ent.CE8FarEnergyMaterials or {}
            ent.CE8EmissiveMaterials=ent.CE8EmissiveMaterials or {}
            ent.CE8EnergyLayers[slot]=energy
            ent.CE8RefractionMaterials[slot]=Material(energy.refract)
            ent.CE8FarEnergyMaterials[slot]=Material(energy.far)
            ent.CE8EmissiveMaterials[slot]=material
        elseif material.GetShader and material:GetShader()=="screenspace_general_8tex" then
            hiddenBase[slot]=hidden
            if emissive[name] then
                ent.CE8EmissiveMaterials=ent.CE8EmissiveMaterials or {}
                ent.CE8EmissiveMaterials[slot]=material
            else custom[slot]=material end
        else native[slot]=material end
    end
    if ent.CE8EmissiveMaterials then
        for slot in pairs(materials) do ent.CE8EmissiveMaterials[slot]=ent.CE8EmissiveMaterials[slot] or hidden end
    end
    if ent.CE8EnergyLayers then
        for slot in pairs(materials) do
            ent.CE8RefractionMaterials[slot]=ent.CE8RefractionMaterials[slot] or hidden
            ent.CE8FarEnergyMaterials[slot]=ent.CE8FarEnergyMaterials[slot] or hidden
        end
    end
    if next(custom) then
        for slot in pairs(materials) do customPass[slot]=custom[slot] or hidden end
    end
    ent.CE8OverrideMaterials=materials
    local depth=bit.bor(STUDIO_SHADOWDEPTHTEXTURE or 0,STUDIO_SSAODEPTHTEXTURE or 0)
    local function submit(self,flags,overrides,customDepth)
        for slot,material in pairs(overrides) do render.MaterialOverrideByIndex(slot,material) end
        if customDepth then render.OverrideDepthEnable(true,true) end
        local ok,message=xpcall(function() self:DrawModel(flags) end,debug.traceback)
        if customDepth then render.OverrideDepthEnable(false,false) end
        for slot in pairs(overrides) do render.MaterialOverrideByIndex(slot,nil) end
        if not ok then ErrorNoHalt("CE8 native draw: "..tostring(message).."\n") end
        return ok
    end
    ent.RenderOverride=function(self,flags)
        if self.CE8DrawingEmissive then self:DrawModel(flags) return end
        -- Server effect snapshots may contain the previous custom-renderer bit.
        if self.RemoveEffects and EF_NOFLASHLIGHT then self:RemoveEffects(EF_NOFLASHLIGHT) end
        local shadow=flags and bit.band(flags,depth)~=0
        if not shadow and self.CE8EmissiveMaterials and flags and
            bit.band(flags,STUDIO_DRAWTRANSLUCENTSUBMODELS or 4)~=0 then
            CE8.DrawEmissiveModel(self,flags)
            return
        end
        if not next(hiddenBase) then
            -- Ordinary actors submit once; Source owns every lighting pass.
            self:DrawModel(flags)
        else
            -- Keep the existing animated effects out of native flashlight
            -- repeats. Only mixed-material models need this isolated submission.
            submit(self,flags,hiddenBase,false)
            if next(custom) then
                self:AddEffects(EF_NOFLASHLIGHT)
                submit(self,flags,customPass,not shadow)
                self:RemoveEffects(EF_NOFLASHLIGHT)
            end
        end
        if not shadow then
            if self.CE8EmissiveMaterials and not self.DrawWorldModelTranslucent and CE8.QueueEmissiveModel then
                CE8.QueueEmissiveModel(self)
            end
            if CE8.QueueEmissionBloom then CE8.QueueEmissionBloom(self,materials) end
        end
    end
    return ent
end
