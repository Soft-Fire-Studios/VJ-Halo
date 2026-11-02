ENT.Base = "npc_vj_human_base"
ENT.Type = "ai"
ENT.PrintName = "Brute Minor"
ENT.Category = "Halo - Campaign Evolved"
ENT.Author = "VJ-Halo"
ENT.IsCE8SNPC = true
ENT.CE8UnitLabel = "brute"
ENT.CE8Rank = "minor"
include("campaign_evolved/human.lua").Shared(ENT, "brute")
local selectSet = ENT.AIAnimationSet
function ENT:AIAnimationSet(weapon)
    if self:GetNW2Bool("ce8_berserk", false) then return self:CE8Data().weapon_sets.berserk, "berserk" end
    return selectSet(self, weapon)
end
local direction = ENT.AIMovementDirection
function ENT:AIMovementDirection(...)
    -- The authored berserk set has no side-step cycles; VJ faces its chase route.
    if self:GetNW2Bool("ce8_berserk", false) then return "front" end
    return direction(self, ...)
end
