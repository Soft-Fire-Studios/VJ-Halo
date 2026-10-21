include("shared.lua")
local rendererToken = {}

function ENT:CE8BindRenderer()
    if not CE8 or not CE8.ApplyModelDepth then return end
    if self.CE8NPCRendererToken ~= rendererToken then
        if self.CE8NPCRenderer then self.CE8NormalSpawnRenderer = false end
        self.CE8NPCRenderer = nil
        self.CE8NPCRendererToken = rendererToken
    end
    CE8.ApplyModelDepth(self)
    -- CE8 already renders projected lights. The native projector pass draws
    -- ScreenspaceGeneral's full base shading again instead of light only.
    if self.CE8Draft and not self:IsEffectActive(EF_NOFLASHLIGHT) then
        self:AddEffects(EF_NOFLASHLIGHT)
    end
    if self.RenderOverride ~= self.CE8NPCRenderer then
        local draw = self.RenderOverride
        if not draw then return end
        self.CE8NPCRenderer = function(actor, flags)
            -- A Lua Draw callback can enter RenderOverride again through
            -- DrawModel. Reuse the outer pass's materials/blend/depth state.
            if actor.CE8DrawingModel then actor:DrawModel(flags) return end
            local previous = actor.CE8DrawingModel
            actor.CE8DrawingModel = true
            local ok, message = xpcall(function() draw(actor, flags) end, debug.traceback)
            actor.CE8DrawingModel = previous
            if not ok then ErrorNoHalt("CE8 NPC draw: " .. tostring(message) .. "\n") return end
            -- The weapon draws through its own engine/VJ callback after this
            -- scope. A raw weapon DrawModel here bypasses that engine context.
        end
        self.RenderOverride = self.CE8NPCRenderer
        self.CE8NormalSpawnRenderer = self.CE8NPCRenderer
    end
    local weapon = self:GetActiveWeapon()
    if IsValid(weapon) and weapon.CE8BindRenderer then weapon:CE8BindRenderer() end
end

function ENT:Init()
    self:CE8ApplyGrip(self:GetNW2Int("ce8_grip", self:CE8Data().weapon.grip))
    self:CE8BindRenderer()
end

function ENT:Think()
    self:CE8ApplyGrip(self:GetNW2Int("ce8_grip", self:CE8Data().weapon.grip))
    self:CE8BindRenderer()
end

function ENT:Draw(flags)
    if self.CE8DrawingModel then self:DrawModel(flags) return end
    self:CE8BindRenderer()
    if self.RenderOverride then self:RenderOverride(flags) else self:DrawModel(flags) end
end

function ENT:DrawTranslucent(flags)
    self:Draw(flags)
end
