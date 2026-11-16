include("shared.lua")

function ENT:Draw()
    if self:GetNW2Bool("CE8Grenade", false) or self:GetNW2Bool("CE8ProjectileMesh", false) then
        self:DrawModel()
        return
    end
    -- Non-mesh projectiles are drawn entirely by their attached native PCF.
end

ENT.DrawTranslucent = ENT.Draw
