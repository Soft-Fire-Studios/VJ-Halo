ENT.Base = "npc_vj_human_base"
ENT.Type = "ai"
ENT.PrintName = "Elite Minor"
ENT.Author = "Halo-DT"
ENT.Category = "Halo - Campaign Evolved"
ENT.IsCE8Elite = true
ENT.IsCE8SNPC = true
ENT.AISquadLeader = true
ENT.CE8UnitLabel = "elite"
ENT.CE8Rank = "minor"

local data = include("campaign_evolved/elite_anims.lua")
function ENT:CE8Data() return data end
local effects = include("campaign_evolved/weapon_fx.lua")
ENT.CE8ShieldParticleFile = "particles/halo/main_effects.pcf"
ENT.CE8ShieldEffects = {
    impact = "hcea_shield_impact",
    disperse = "hcea_shield_disperse",
    recharged = "hcea_shield_recharged"
}

-- Reuse SNPC-PRP's mounted library. Both realms must load its definitions;
-- the server dispatches each transient effect once through Source's particle API.
CE8.ShieldParticlesReady = effects.Load({effects = {file = ENT.CE8ShieldParticleFile,
    normal = ENT.CE8ShieldEffects, charged = {}}})
effects.Load(data.grenade)

if SERVER then AddCSLuaFile("vj_ai/motion.lua") AddCSLuaFile("campaign_evolved/human.lua") end
include("vj_ai/motion.lua").Attach(ENT, {
    adapter = "human", capabilities = {movement = true, aim = true, grip = true},
    sets = data.weapon_sets, default_set = "needle_rifle",
    track_without_firing = true,
    weapon_key = function(self, weapon) return weapon.CE8WeaponName end,
    action = function(self, name) return self:CE8Action(name) end,
    crouch_allowed = function(self) return not self.CE8Cover and not self.CE8Charge end,
    aim_allowed = function(self)
        return (self.VJ_Controlled or not self.CE8Cover) and CurTime() >= (self.CE8ReactionEnd or 0)
    end,
    blind_point = function(self, target) return self:CE8BlindFirePoint(self:GetActiveWeapon(), target) end,
    grip = {parameter = "grip", minimum = 0, maximum = 17, default = data.weapon.grip},
    fields = {
        activity_sets = "CE8ActivitySets", activities = "CE8Activities", activity_model = "CE8ActivityModel",
        fire_activity = "CE8FireActivity", move_direction = "CE8MoveDirection", facing_direction = "CE8FacingDirection",
        move_intent = "CE8MoveIntent", move_time = "CE8MoveIntentTime", aim_turn = "CE8AimTurn",
        aim_previous = "CE8AimPrevious", aim_written = "CE8AimWritten",
        controller_target = "CE8ControllerAimTarget", grip_value = "CE8AppliedGrip", grip_model = "CE8GripModel",
        schedule_crouch = "CE8CrouchMove", schedule_weapon = "CE8CrouchWeapon"
    }
})

function ENT:CE8MovementDirection(direction, yaw)
    return self:AIMovementDirection(direction, yaw)
end

function ENT:CE8ApplyGrip(value)
    return self:AIApplyGrip(value)
end

-- VJ's server event hook dispatches the character-local sound bank. Suppress
-- client defaults for our custom event numbers to avoid a second playback.
function ENT:FireAnimationEvent(pos, ang, event, options)
    if event == 4001 or event == 4003 or event == 4004 or event == 4005 or event == 4006 or event == 4007 then return true end
end
