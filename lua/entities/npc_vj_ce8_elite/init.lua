AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local data = ENT:CE8Data()
local difficulty = include("campaign_evolved/difficulty.lua")
local profile = include("profile.lua")
local sounds, shieldSounds = profile.sounds, profile.shield_sounds
include("vj_ai/core.lua").Attach(ENT, profile)
include("ai.lua")

ENT.Model = data.model
ENT.StartHealth = data.rank_profiles.elite.health
ENT.HullType = HULL_MEDIUM_TALL
ENT.BloodColor = VJ.BLOOD_COLOR_PURPLE
ENT.VJ_NPC_Class = {"CLASS_COVENANT"}
ENT.MovementType = VJ_MOVETYPE_GROUND
ENT.CanTurnWhileMoving = true
ENT.UsePoseParameterMovement = false
-- Combat schedules maintain facing while strafing. Forced one-frame enemy
-- turns clear their TurnData and let navigation turn the body away again.
ENT.ConstantlyFaceEnemy = false
ENT.TurningSpeed = 30
ENT.FollowPlayer = false
ENT.CallForHelp = false
ENT.AnimTbl_CallForHelp = false
ENT.AnimTbl_DamageAllyResponse = false
ENT.HasGrenadeAttack = false
ENT.CanRedirectGrenades = false
ENT.JumpParams = {Enabled = false}
ENT.HasFootstepSounds = true
ENT.DisableFootStepSoundTimer = true
ENT.FootstepSoundPitch = VJ.SET(100, 100)
ENT.CanFlinch = false
ENT.HasDeathAnimation = false
ENT.MainSoundPitch = 100
ENT.MainSoundPitchStatic = true
ENT.ControllerParams = {
    CameraMode = 1, ThirdP_Offset = Vector(), FirstP_Bone = "head_m",
    FirstP_Offset = Vector(), FirstP_ShrinkBone = true,
    FirstP_CameraBoneAng = 0, FirstP_CameraBoneAng_Offset = 0
}

ENT.HasPoseParameterLooking = true
ENT.PoseParameterLooking_InvertPitch = true
ENT.PoseParameterLooking_Names = {pitch = {}, yaw = {}, roll = {}}
ENT.PoseParameterLooking_TurningSpeed = 8

ENT.Weapon_CanMoveFire = true
ENT.Weapon_Strafe = true
ENT.Weapon_StrafeCooldown = VJ.SET(2, 4)
ENT.Weapon_CanCrouchAttack = true
ENT.Weapon_CanSecondaryFire = false
ENT.Weapon_FindCoverOnReload = false
ENT.Weapon_RetreatDistance = 180
ENT.Weapon_MinDistance = 55
ENT.Weapon_MaxDistance = 2400
ENT.Weapon_AimTurnDiff = 0.70710678
ENT.AnimTbl_WeaponAttack = ACT_IDLE_ANGRY
ENT.AnimTbl_WeaponAttackCrouch = ACT_COVER_LOW
ENT.AnimTbl_WeaponAttackGesture = "vjges_" .. data.sequences.fire
ENT.AnimTbl_WeaponReload = ACT_RELOAD
ENT.AnimTbl_WeaponReloadCovered = ACT_RELOAD_LOW

ENT.HasMeleeAttack = true
ENT.AnimTbl_MeleeAttack = "vjseq_" .. data.sequences.melee
ENT.MeleeAttackDistance = data.melee.range
ENT.MeleeAttackDamageDistance = data.melee.hit_range
ENT.MeleeAttackAngleRadius = data.melee.angle
ENT.MeleeAttackDamageAngleRadius = data.melee.hit_angle
ENT.MeleeAttackDamage = 30
ENT.TimeUntilMeleeAttackDamage = false -- Native melee hit marker triggers damage.
ENT.HasExtraMeleeAttackSounds = false
ENT.HasMeleeAttackMissSounds = false
ENT.SoundTbl_MeleeAttackExtra = false
ENT.SoundTbl_MeleeAttackMiss = false

function ENT:CE8RankSettings()
    local rank = assert(data.ranks[self.CE8Rank or "minor"], "Unknown CE8 Elite rank")
    return rank, data.rank_profiles[rank.profile]
end

-- CE's global combat controls own scaling. VJ still supplies its attack,
-- damage and health lifecycle, without stacking its separate difficulty factor.
function ENT:ScaleByDifficulty(amount)
    return amount
end

function ENT:CE8ApplyStats(initialize)
    local _, settings = self:CE8RankSettings()
    return difficulty.ApplyVitality(self, settings, initialize)
end

function ENT:OnTaskFailed(code, message)
    -- VJ retains normal failure cleanup. If a smash replaces the failed route,
    -- its existing schedule-identity guard protects the new action.
    self:AITaskFailed(code, message, CurTime())
end

function ENT:MeleeAttackTraceOrigin()
    return self:AIObstacleTraceOrigin()
end

function ENT:MeleeAttackTraceDirection()
    return self:AIObstacleTraceDirection()
end

function ENT:PreInit()
    local _, profile = self:CE8RankSettings()
    self.StartHealth = profile.health
    self.CE8ShieldMax = profile.shield
    self.CE8ShieldRechargeDelay = profile.recharge_delay
    self.CE8ShieldRechargeTime = profile.recharge_time
    self:CE8ConfigureAI()
end

function ENT:CE8WeaponSet(weapon)
    return self:AIAnimationSet(weapon)
end

function ENT:CE8CacheActivities(weapon)
    return self:AIAnimationActivities(weapon)
end

function ENT:CE8InCombat()
    return self:AIMotionCombat()
end

function ENT:SetAnimationTranslations(holdType, weapon)
    return self:AISetAnimationTranslations(holdType, weapon)
end

function ENT:TranslateActivity(act)
    return self:AITranslateActivity(act)
end

function ENT:GetTurnAngle(angle)
    return self:AIGetTurnAngle(angle)
end

function ENT:OverrideMoveFacing(interval, move)
    return self:AIOverrideMoveFacing(interval, move)
end

function ENT:UpdatePoseParamTracking(resetPoses)
    return self:AIUpdatePoseTracking(resetPoses)
end

function ENT:GetHeadDirection()
    return self:AIHeadDirection()
end

function ENT:GetAimPosition(target, origin, predictionRate, projectileSpeed)
    return self:AIMotionAimPosition(target, origin, predictionRate, projectileSpeed)
end

function ENT:CE8UpdateAimTurn(activity)
    return self:AIUpdateAimTurn(activity)
end

function ENT:CE8AnimateAimTurn(eligible, inside, yaw, posture)
    return self:AIAnimateAimTurn(eligible, inside, yaw, posture)
end

function ENT:SetTurnTarget(target, faceTime, stopOnFace, visibleOnly)
    return self:AIMotionTurnTarget(target, faceTime, stopOnFace, visibleOnly)
end

function ENT:PlayAnim(animation, lockAnim, lockAnimTime, faceEnemy, delay, extra, customFunc)
    return self:AIMotionPlayAnim(animation, lockAnim, lockAnimTime, faceEnemy, delay, extra, customFunc)
end

function ENT:Init()
    local rank, profile = self:CE8RankSettings()
    -- Scale the rank's default values once, independently of VJ stat overrides.
    self:CE8ApplyStats(true)
    self:CE8InitAI()
    self:CapabilitiesAdd(CAP_MOVE_SHOOT)
    if self.JumpParams.Enabled then self:CapabilitiesAdd(CAP_MOVE_JUMP) end
    self:SetCollisionBounds(Vector(-18, -18, 0), Vector(18, 18, 98))
    self:SetSaveValue("m_HackedGunPos", Vector(12, 0, 72))
    for name, value in pairs(rank.bodygroups) do
        local id = self:FindBodygroupByName(name)
        if id >= 0 then self:SetBodygroup(id, value) end
    end
    self:SetHitboxSet(rank.hitbox_set)
    self:SetNW2String("ce8_rank", self.CE8Rank or "minor")
    self:CE8CacheActivities()
    self:SetPoseParameter("look_suppress", 0)
    self:CE8ApplyGrip(data.weapon.grip)
    self:SetNW2Int("ce8_grip", data.weapon.grip)
    local voices = {"newelite1", "newelite2"}
    self.CE8Voice = voices[math.random(#voices)]
    local bank = sounds.dialogue[self.CE8Voice]
    local mapping = {
        Idle = "idle", CombatIdle = "thrtn", Alert = "seefoe", Investigate = "invsgt",
        LostEnemy = "lst_cntct", BeforeMeleeAttack = "melee_attack",
        AllyDeath = "lmnt_deadally", Pain = "pain", Death = "dth",
        DangerSight = "warn_incmn", GrenadeSight = "warn_incmn", Suppressing = "thrtn",
        GrenadeAttack = "thrwn", CallForHelp = "newordr_advance"
    }
    for category, cue in pairs(mapping) do self["SoundTbl_" .. category] = bank[cue] or false end
    self:SetNW2String("ce8_voice", self.CE8Voice)
    -- Sandbox equips exactly one choice from this rank's registered pool after
    -- Spawn. Do not create another weapon/IK target in the character Init.
end

function ENT:OnWeaponChange(weapon, previous, inventory)
    self:CE8CancelIdlePose()
    self:SetAnimationTranslations(IsValid(weapon) and weapon:GetHoldType() or "ar2", weapon)
    local value = IsValid(weapon) and weapon.CE8Grip or 0
    self:CE8ApplyGrip(value)
    self:SetNW2Int("ce8_grip", value)
    local weaponData = IsValid(weapon) and weapon.CE8Data
    local angle = weaponData and weaponData.melee and weaponData.melee_angle
    self.MeleeAttackAngleRadius = angle or data.melee.angle
    self.MeleeAttackDamageAngleRadius = angle or data.melee.hit_angle
    if IsValid(weapon) and weapon.CE8Attach then weapon:CE8Attach(self) end
end

function ENT:OnWeaponAttack()
    local profile = self:CE8WeaponSet()
    if not profile.melee or not profile.melee_variants then return end
    if CurTime() <= (self.NextMeleeWeaponAttackT or 0) then return end
    -- VJ calls this before choosing a melee weapon animation. Pick once when
    -- a swing can start, then let VJ use that clip's own duration and cooldown.
    local choices = profile.melee_variants
    local sequence = choices[math.random(#choices)]
    local id = self:LookupSequence(sequence)
    if id < 0 then error("CE8 Elite is missing Sword attack: " .. sequence) end
    self.AnimTbl_WeaponAttack = self:GetSequenceActivity(id)
    local weapon = self:GetActiveWeapon()
    if IsValid(weapon) and weapon.CE8BeginMeleeSwing then weapon:CE8BeginMeleeSwing(self, id) end
end

function ENT:OnThink()
    self:AIUpdate(CurTime())
end

function ENT:OnThinkActive()
    self:CE8ThinkReactions(CurTime())
end

function ENT:CustomOnRemove()
    self:AIShutdown(CurTime(), "remove")
end

function ENT:CE8PlayShieldSound(kind)
    if self.HasSounds == false then return end
    local choices = shieldSounds[kind]
    if not choices or #choices == 0 then return end
    local sound = choices[math.random(#choices)]
    -- Equipment sounds stay separate from VJ speech and animation Foley.
    self:EmitSound(sound, 75, 100, 1, CHAN_ITEM)
    self.CE8ShieldSoundCounts = self.CE8ShieldSoundCounts or {}
    self.CE8ShieldSoundCounts[kind] = (self.CE8ShieldSoundCounts[kind] or 0) + 1
    return sound
end

function ENT:CE8StopShieldRechargeSound()
    return self:AIStopShieldRecharge()
end

function ENT:OnCreateSound(sound, path)
    self:AIObserveDialogue(sound, path, CurTime(), self:GetEnemy())
end

function ENT:CE8PlayDialogue(cue, now, context)
    return self:AIPlayDialogue(cue, now, context)
end

function ENT:CE8QueueDialogue(cue, now, context)
    return self:AIQueueDialogue(cue, now, context)
end

function ENT:CE8ThinkDialogue(now)
    return self:AIThinkDialogue(now)
end

function ENT:CE8Footstep(side)
    return self:AIFootstep(side)
end

function ENT:OnAnimEvent(event, eventTime, cycle, eventType, options)
    if event == 4005 then
        local choices = sounds.events[options]
        if choices and #choices > 0 then
            self:EmitSound(choices[math.random(#choices)], 70, 100, 1, CHAN_BODY)
        end
    elseif event == 4003 then
        self:CE8PlayDialogue(options, CurTime())
    elseif event == 4001 and (options == "left foot" or options == "right foot") then
        self:CE8Footstep(options == "left foot" and "left" or "right")
    elseif event == 4001 and options == "primary keyframe" then
        if self.CE8Reaction == "obstacle_smash" then
            self:CE8SmashHit()
        elseif self.AttackType == VJ.ATTACK_TYPE_MELEE then
            self:ExecuteMeleeAttack()
        elseif self.AttackType == VJ.ATTACK_TYPE_GRENADE and self.AttackState < VJ.ATTACK_STATE_EXECUTED then
            timer.Adjust("attack_grenade_start" .. self:EntIndex(), 0)
        else
            local weapon = self:GetActiveWeapon()
            if IsValid(weapon) and weapon.CE8MeleeEvent then weapon:CE8MeleeEvent(self) end
        end
    end
end

function ENT:OnCreateDeathCorpse(damage, hitgroup, corpse)
    if not IsValid(corpse) then return end
    corpse:SetSkin(self:GetSkin())
    for _, group in ipairs(self:GetBodyGroups()) do corpse:SetBodygroup(group.id, self:GetBodygroup(group.id)) end
    local rank = self:CE8RankSettings()
    corpse:SetHitboxSet(rank.hitbox_set)
end
