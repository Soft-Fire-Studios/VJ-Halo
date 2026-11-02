if SERVER then AddCSLuaFile() end
ENT.Type = "anim"
ENT.Base = "obj_ce8_armor"
ENT.PrintName = "Jackal barrier collision"
ENT.Spawnable = false
ENT.IsCE8Barrier = true
ENT.CE8Socket = "shield"
ENT.CE8ImpactSurface = "shield_jackal"
ENT.DisableDuplicator = true
ENT.PhysgunDisabled = true
ENT.VJ_ID_Grabbable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT
-- Halo's shield service supplies the impact flash and sound. Suppress the
-- emitter model's stock metal sparks, ricochet sound and bullet decal.
function ENT:ImpactTrace() return true end

-- MW Base penetrates by recursively firing exit/continuation bullets inside
-- its impact callback. Keep that callback's damage and attachment effects,
-- but absorb its follow-up bullets on a real barrier hit. Scope this to the
-- callback, not a timer: subsequent shots and shots through gaps still work.
-- Run in both realms so predicted tracers stop at the shield as well.
include("campaign_evolved/jackal_collision.lua")

if CLIENT then
    function ENT:Draw() end
    function ENT:DrawTranslucent(flags)
        self:CE8UpdateRenderFrame()
        self:CE8BindRenderer()
        if CE8 and CE8.DrawEmissiveModel then CE8.DrawEmissiveModel(self, flags) end
    end
    return
end
local barrier = include("campaign_evolved/barrier.lua")

function ENT:Initialize()
    self:DrawShadow(false)
    self.BaseClass.Initialize(self)
    CE8.Barriers[self] = true
end

function ENT:OnTakeDamage(damage) barrier.Damage(self, damage) end
function ENT:OnRemove() CE8.Barriers[self] = nil end
function ENT:PhysgunPickup() return false end
function ENT:GravGunPickupAllowed() return false end
