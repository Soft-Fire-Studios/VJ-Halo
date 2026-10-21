include("shared.lua")
local glow = Material("sprites/light_glow02_add")

function ENT:Draw()
    if self:GetNW2Bool("CE8Grenade", false) or self:GetNW2Bool("CE8ProjectileMesh", false) then
        self:DrawModel()
        return
    end
    if self:GetNW2Bool("CE8ParticleFlight", false) then return end
    local position, color = self:GetPos(), self:GetColor()
    render.SetMaterial(glow)
    render.DrawSprite(position, 7, 7, color)
    local velocity = self:GetVelocity()
    render.DrawBeam(position, position - velocity:GetNormalized() * 16, 2, 0, 1, color)
end

ENT.DrawTranslucent = ENT.Draw
