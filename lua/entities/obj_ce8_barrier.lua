if SERVER then AddCSLuaFile() end
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Jackal barrier collision"
ENT.Spawnable = false
ENT.IsCE8Barrier = true
ENT.CE8ImpactSurface = "shield_jackal"
ENT.DisableDuplicator = true
ENT.PhysgunDisabled = true
ENT.VJ_ID_Grabbable = false
function ENT:Draw() end
-- Halo's shield service supplies the impact flash and sound. Suppress the
-- emitter model's stock metal sparks, ricochet sound and bullet decal.
function ENT:ImpactTrace() return true end
if CLIENT then return end
local barrier = include("campaign_evolved/barrier.lua")

function ENT:Initialize()
    self:SetNoDraw(true)
    self:DrawShadow(false)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_OBB)
    self:SetCollisionGroup(COLLISION_GROUP_BREAKABLE_GLASS)
    -- Expanded broad phase follows once per tick; precise testing uses the
    -- current wrist attachment, including its pose, on every incoming trace.
    self:SetCollisionBounds(Vector(-12, -42, -42), Vector(18, 42, 42))
    self:EnableCustomCollisions(true)
    self:SetHealth(1)
    self:SetSaveValue("m_takedamage", 2)
    CE8.Barriers[self] = true
    self:Think()
end

function ENT:Think()
    local actor = self:GetOwner()
    if not IsValid(actor) or actor.Dead or not IsValid(actor.CE8ShieldProp) then self:Remove() return end
    local at = actor:GetAttachment(actor:LookupAttachment("shield"))
    if at then self:SetPos(at.Pos) self:SetAngles(at.Ang) end
    self:NextThink(CurTime())
    return true
end

function ENT:TestCollision(start, delta, isBox, extents, mask)
    -- Shot traces only. Navigation, player movement and sight remain VJ/Source
    -- owned; this detector never becomes an obstacle or an opaque sight wall.
    if bit.band(mask, CONTENTS_HITBOX + CONTENTS_MONSTER) == 0 then return false end
    if isBox and math.max(extents.x, extents.y, extents.z) > 8 then return false end
    return barrier.Trace(self, start, delta) or false
end

function ENT:OnTakeDamage(damage) barrier.Damage(self, damage) end
function ENT:OnRemove() CE8.Barriers[self] = nil end
function ENT:PhysgunPickup() return false end
function ENT:GravGunPickupAllowed() return false end
