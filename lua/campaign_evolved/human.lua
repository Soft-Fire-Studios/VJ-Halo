-- Weapon and wrist-equipment integration for CE8 Human NPCs.
local Actor = include("campaign_evolved/actor.lua")
local Host = {Shared = Actor.Shared, Client = Actor.Client}
function Host.Profile(data)
    local profile = Actor.Profile(data)
    if data.weapon_profiles and profile.squad then
        profile.squad.report = function(self)
            local weapon = self:GetActiveWeapon()
            if not IsValid(weapon) or not weapon.CE8WeaponName then return end
            local now = CurTime()
            return {weapon = weapon.CE8WeaponName, ready = weapon.CE8FireReady == true,
                burst_wait = math.max(0, (weapon.CE8NextBurstT or 0) - now),
                primary_wait = math.max(0, (weapon.NPC_NextPrimaryFireT or 0) - now),
                clip = weapon:Clip1(), overheated = weapon.CE8Overheated == true,
                attack_wait = math.max(0, (self.NextDoAnyAttackT or 0) - now),
                reaction_wait = math.max(0, (self.AIReactionEnd or 0) - now)}
        end
    end
    if data.actions then
        profile.reactions.actions = {families = data.actions, default_family = data.default_weapon}
        profile.reactions.family = function(self) local _, key = self:AIAnimationSet() return key end
        profile.reactions.danger = function(self) return self:CE8RankSettings().danger end
        profile.reactions.started = function(self, kind, sequence, now) self:AISuspendActions(now) end
        profile.reactions.played = function(self, kind, sequence, now)
            local cue = ({danger_dive = "dive", gunfire_evade = "dodge", aim_evade = "dodge"})[kind]
            if cue and not (data.reaction_dialogue and data.reaction_dialogue[sequence]) then self:AIPlayDialogue(cue, now) end
        end
    end
    if data.ranks.minor.evasion then
        profile.capabilities.evasion = function(self) return self:CE8RankSettings().evasion.enabled end
        profile.controller.evasion_allowed = function(self) return not self.AIFlee end
        profile.evasion = {
            choices = function(self) local _, key = self:AIAnimationSet() return data.actions[key] or {} end,
            gunfire = function(self) return self:CE8RankSettings().evasion end,
            cooldown = function(self) return self:CE8RankSettings().evasion.delay end,
            aim_chance = function(self) return self:CE8RankSettings().evasion.chance end,
            -- Reuse the existing Source threat adapters. Crosshair dwell and
            -- near-shot sampling are not Halo's native danger accumulator.
            aim_time = 0.75, minimum_distance = 128,
            range = function(self) return self.Weapon_MaxDistance or 2400 end
        }
    end
    if data.kamikaze then
        profile.capabilities.kamikaze = true
        profile.kamikaze = Host.KamikazeProfile(data)
    end
    if data.behaviors then Host.Behaviors(profile, data) end
    return profile
end

-- Optional authored activities share the existing search/idle/postcombat services.
-- Timing without a native equivalent is deliberately a small Source policy.
function Host.Behaviors(profile, data)
    local resources = data.behaviors
    local function supported(self)
        if not resources.weapons then return true end
        local _, key = self:AIAnimationSet()
        for _, weapon in ipairs(resources.weapons) do if key == weapon then return true end end
        return false
    end
    local function pick(self, choices)
        return supported(self) and choices and #choices > 0 and choices[math.random(#choices)] or nil
    end
    local function ordinaryGun(self, weapon)
        local values = weapon.CE8Data
        return values and not values.melee and not weapon.IsMeleeWeapon and values.gravity == 0
            and values.damage and values.damage.radius[2] == 0
            and (not values.explosion or values.explosion.radius[2] == 0)
            and not weapon.CE8Overheated and weapon:Clip1() > 0
    end
    profile.search.settings = function(self) return self:CE8RankSettings().search or data.search end
    profile.search.squad = true
    profile.search.burst_count = 1
    profile.search.suppression_allowed = function(self)
        return not self.AIFlee and not self.AIKamikaze and not self.AICover and not self.AICharge
    end
    profile.search.suppress_eligible = ordinaryGun
    profile.search.suppress_activity = function(self) return self:AIAnimationActivities().combat_idle end
    profile.search.investigate = function(self, phase, now)
        local sequence = pick(self, resources.investigate and resources.investigate[phase])
        if sequence and self:AIValidateMotion(sequence, 0) then
            -- This inspection is interruptible immediately on reacquisition.
            local animation, duration = self:PlayAnim("vjseq_" .. sequence, false, false, false, 0)
            if animation ~= ACT_INVALID then return duration end
        end
    end
    if resources.idle then
        profile.capabilities.idle = true
        profile.idle = {
            settings = function(self) return self:CE8RankSettings().idle or {enabled = false} end,
            select = function(self)
                if not supported(self) then return end
                local settings = self:CE8RankSettings().idle
                -- Optional quiet sleep: a finite entry + 2-4 authored cycles.
                -- Native style enables sleep, but this 10% choice is Source policy.
                if settings.sleep and resources.sleep and math.Rand(0, 1) < 0.1 then
                    local plan = {resources.sleep.enter}
                    for i = 1, math.random(2, 4) do plan[#plan + 1] = resources.sleep.idle end
                    return plan
                end
                return pick(self, resources.idle)
            end
        }
    end
    if resources.postcombat then
        profile.capabilities.postcombat = true
        profile.postcombat = {
            settings = function(self) return self:CE8RankSettings().postcombat end,
            timeout = 12, delay = 1,
            weapon_allowed = ordinaryGun,
            fire_allowed = function(self) return not self.AIFlee and not self.AIKamikaze and not self.AICover end,
            fire_activity = function(self) return self:AIAnimationActivities().combat_idle end,
            burst_count = function(self) return math.random(1, 2) end,
            started = function(self, action, now)
                action.victim.CE8CorpseObserver = self
                self:AIFinishSearch(now) self:AIEndCharge(now) self:AICancelIdle()
            end,
            finished = function(self, action, now)
                local sequence = pick(self, resources.postcombat)
                if sequence and self:AIValidateMotion(sequence, 0) then
                    -- A victory gesture must never delay a newly discovered foe.
                    self:PlayAnim("vjseq_" .. sequence, false, false, false, 0)
                end
            end
        }
    end
end
function Host.Server(ENT, profile)
    Actor.Server(ENT, profile)
    local data = ENT:CE8Data()
    ENT.Weapon_CanMoveFire, ENT.Weapon_Strafe = true, Actor.Option(data, "strafe", true)
    ENT.Weapon_StrafeCooldown = VJ.SET(2, 4)
    ENT.Weapon_CanCrouchAttack = Actor.Option(data, "crouch_fire", true)
    ENT.Weapon_CanSecondaryFire = false
    ENT.Weapon_FindCoverOnReload = Actor.Option(data, "reload_cover", false)
    ENT.Weapon_RetreatDistance = Actor.Option(data, "retreat_distance", data.owner == "grunt" and 90 or 150)
    ENT.Weapon_UnarmedBehavior = Actor.Option(data, "unarmed_flee", true)
    ENT.Weapon_OcclusionDelay = Actor.Option(data, "occlusion_delay", true)
    ENT.Weapon_MinDistance, ENT.Weapon_MaxDistance = 40, Actor.Option(data, "weapon_max_distance", 2400)
    ENT.Weapon_AimTurnDiff = 0.70710678
    ENT.AnimTbl_WeaponAttack, ENT.AnimTbl_WeaponAttackCrouch = ACT_IDLE_ANGRY, ACT_COVER_LOW
    ENT.HasMeleeAttack = false
    function ENT:SetAnimationTranslations(hold, weapon)
        self:AISetAnimationTranslations(hold, weapon)
        if not self:AIHasCapability("cover") then
            self.AnimTbl_TakingCover = false
            self.AnimTbl_WeaponReloadCovered = false
        end
    end
    function ENT:OnWeaponChange(weapon)
        if data.weapon_profiles then self.CE8WeaponProfile = self:CE8RankSettings().native end
        self:SetAnimationTranslations(IsValid(weapon) and weapon:GetHoldType() or "pistol", weapon)
        local grip = self:CE8WeaponGrip(weapon)
        self:AIApplyGrip(grip)
        self:SetNW2Int("ce8_grip", grip)
        if IsValid(weapon) and weapon.CE8Attach then weapon:CE8Attach(self) end
        if self.AIConfigureWeapon then self:AIConfigureWeapon(weapon) end
        self:CE8UpdateEquipment()
    end
    function ENT:CE8WeaponShotReady(now)
        now = now or CurTime()
        return not self.AIFlee and not self.AIKamikaze and not self.Dead and now >= (self.AIReactionEnd or 0)
            and (not self.AICover or self.AICover.phase == "seek")
            and self:AIAmbushCanFire()
            and not self:AIChargeBlocksWeapon(self:GetActiveWeapon(), now)
    end
    -- Gate VJ's firing stance as well as the SWEP; otherwise a standing shot
    -- replaces the chase schedule while the actor is committed to melee.
    function ENT:OnWeaponCanFire()
        if not self:CE8WeaponShotReady(CurTime()) then return false end
    end
    Host.Equipment(ENT)
    if ENT.CE8MergedBarrier then include("campaign_evolved/jackal_collision.lua").Attach(ENT) end
    if Actor.Option(data, "generic_weapons", false) then
        local initialize, active, think, death, remove = ENT.Init, ENT.OnThinkActive, ENT.OnThink, ENT.OnDeath, ENT.CustomOnRemove
        function ENT:Init()
            initialize(self)
            -- VJ has already granted weapon capabilities before calling Init.
            -- Unarmed is valid for combat forms; suppress only its later
            -- missing-weapon warning, without disabling firing or pickup.
            self.Weapon_IgnoreSpawnMenu = true
        end
        function ENT:OnThinkActive()
            if self:AIThinkWeaponPickup(CurTime()) then return end
            return active(self)
        end
        function ENT:OnThink()
            if self.AIWeaponPickup then self:AIThinkWeaponPickup(CurTime()) end
            return think(self)
        end
        function ENT:OnDeath(damage, hitgroup, status)
            if status == "Init" then self:AICancelWeaponPickup() end
            return death(self, damage, hitgroup, status)
        end
        function ENT:CustomOnRemove()
            self:AICancelWeaponPickup()
            return remove(self)
        end
    end
    if data.actions then
        local danger = ENT.OnDangerDetected
        function ENT:OnDangerDetected(kind, source)
            if self.AIKamikaze then return true end
            local result = self:AITryDanger(kind, source, CurTime())
            if result ~= nil then return result end
            return danger(self, kind, source)
        end
    end
    if data.grenade then Host.Grenades(ENT, data) end
    if data.behaviors and data.behaviors.postcombat then
        function ENT:OnKilledEnemy(victim, inflictor, wasLast)
            if not IsValid(victim) or self:Disposition(victim) ~= D_HT then return end
            return self:AIStartPostcombat(victim, CurTime(), wasLast)
        end
    end
    if data.weapon_profiles or data.grenade then
        local initialize = ENT.Init
        function ENT:CE8ConfigureAI()
            local rank = self:CE8RankSettings()
            if rank.search then self.EnemyTimeout = rank.search.time[2] end
            if rank.cover_time then self.CombatDamageResponse_CoverTime = VJ.SET(rank.cover_time[1], rank.cover_time[2]) end
            if rank.defense then
                local motion = self:AIMotionProfile()
                local reload = self[motion.fields.reload]
                if reload and self.Weapon_RetreatDistance == -1 then
                    reload.retreat = rank.defense.retreat_distance
                else self.Weapon_RetreatDistance = rank.defense.retreat_distance end
                self.CombatDamageResponse_CoverTime = VJ.SET(rank.defense.hide_time[1], rank.defense.hide_time[2])
            end
            if data.weapon_profiles then self.CE8WeaponProfile = rank.native end
            if rank.flinch then self.FlinchChance, self.FlinchCooldown = 1, rank.flinch.cooldown end
            if data.grenade then
                local settings = rank.grenade
                if self.CE8Grenades == nil then self.CE8Grenades = math.random(settings.count[1], settings.count[2]) end
                self.HasGrenadeAttack = settings.enabled and self.CE8Grenades > 0
                -- VJ owns attempts; Init tests the exact authored probability.
                self.GrenadeAttackChance = 1
                self.GrenadeAttackMinDistance, self.GrenadeAttackMaxDistance = settings.range[1], settings.range[2]
                self.NextGrenadeAttackTime = VJ.SET(settings.delay, settings.delay)
            end
        end
        function ENT:Init()
            initialize(self)
            self:CE8ConfigureAI()
        end
    end
end

-- Bind optional panic escalation to real shared plasma-grenade entities.
-- The tactic owns decisions/navigation; this host owns weapon/resource APIs.
function Host.KamikazeProfile(data)
    local settings = data.kamikaze
    local difficulty = include("campaign_evolved/difficulty.lua")
    local function discard(action)
        for _, grenade in ipairs(action.grenades or {}) do if IsValid(grenade) then grenade:Remove() end end
    end
    return {
        group = "covenant", chance = settings.chance, attempts = settings.attempts,
        cooldown = settings.cooldown, panic_time = settings.panic_time,
        timeout = settings.timeout, distance = settings.distance,
        limit = function(self) return settings.limits[difficulty.Level(self)] or 1 end,
        allowed = function(self)
            local disabled = GetConVar("ai_disabled")
            return not (disabled and disabled:GetBool()) and self:GetState() ~= VJ_STATE_FREEZE
        end,
        prepare_sequence = function(self)
            local _, weapon = self:AIAnimationSet()
            return settings.prepare[weapon] or settings.fallback
        end,
        prepare = function(self, action)
            if (self.CE8Grenades or 0) < 2 then return false end
            for _, name in ipairs(settings.attachments) do
                local id = self:LookupAttachment(name)
                if id <= 0 or not self:GetAttachment(id) then return false end
            end
            action.grenades = {}
            for _, name in ipairs(settings.attachments) do
                local grenade = ents.Create("obj_ce8_projectile")
                if not IsValid(grenade) then discard(action) return false end
                action.grenades[#action.grenades + 1] = grenade
                grenade.CE8Data, grenade.CE8Damage = data.grenade, 0
                grenade:SetOwner(self)
                grenade:SetPos(self:GetAttachment(self:LookupAttachment(name)).Pos)
                grenade:Spawn()
                grenade:Activate()
                if not grenade.CE8Hold or not grenade:CE8Hold(self, name) then discard(action) return false end
            end
            return true
        end,
        started = function(self, action, now)
            action.committed = true
            self.CE8FleeRequest = nil
            self.CE8Grenades = math.max(0, self.CE8Grenades - 2)
            local weapon = self:GetActiveWeapon()
            if IsValid(weapon) then self:DropWeapon(weapon, nil, self:GetForward()) end
            self:AIApplyGrip(settings.grip or 0)
            self:SetNW2Int("ce8_grip", settings.grip or 0)
            if not data.reaction_dialogue[action.sequence] then self:AIPlayDialogue("kamikaze", now) end
        end,
        finished = function(self, action, now, reason)
            if reason == "detonate" then
                for _, grenade in ipairs(action.grenades or {}) do
                    if IsValid(grenade) then grenade:CE8DetonateHeld() end
                end
                -- VJ blast damage can exclude its owner. Kill the carrier in
                -- that case; nearby damage stays with the normal grenade blast.
                if not self.Dead and self:Health() > 0 then
                    local damage = DamageInfo()
                    damage:SetAttacker(game.GetWorld()) damage:SetInflictor(game.GetWorld())
                    damage:SetDamageType(DMG_BLAST)
                    damage:SetDamage(self:Health() * math.max(1, difficulty.Multiplier("resistance")) + 1)
                    damage:SetDamagePosition(self:GetPos())
                    self:TakeDamageInfo(damage)
                end
            elseif action.committed and (reason == "death" or reason == "lost_target" or reason == "route_ended" or reason == "interrupted") then
                for _, grenade in ipairs(action.grenades or {}) do
                    if IsValid(grenade) then grenade:CE8ReleaseHeld() end
                end
            else discard(action) end
            if not self.Dead then
                local grip = self:CE8WeaponGrip(self:GetActiveWeapon())
                self:AIApplyGrip(grip) self:SetNW2Int("ce8_grip", grip)
                self.HasGrenadeAttack = self:CE8RankSettings().grenade.enabled and (self.CE8Grenades or 0) > 0
            end
        end
    }
end

-- Optional native grenade resources use VJ's scheduler, timer and callbacks.
-- Shared by Grunts/Brutes; no separate Think loop or duplicate projectile.
function Host.Grenades(ENT, data)
    local difficulty = include("campaign_evolved/difficulty.lua")
    local ballistics = include("campaign_evolved/ballistics.lua")
    local event = ENT.OnAnimEvent
    ENT.GrenadeAttackEntity, ENT.GrenadeAttackModel = "obj_ce8_projectile", data.grenade.model
    ENT.GrenadeAttackAttachment, ENT.GrenadeAttackBone = data.grenade_attachment or "grenade", "wrist_l"
    ENT.GrenadeAttackThrowTime = false
    ENT.CanRedirectGrenades = false
    local function retreatThrow(self)
        local action = self.AIFlee
        return action and action.throwing and action.threat == self:GetEnemy()
            and CurTime() < action.deadline and not self.AIKamikaze and not self.Dead
    end
    function ENT:CE8RetreatGrenade(action, now)
        local settings, enemy = self:CE8RankSettings(), self:GetEnemy()
        if action.grenade_tried then return false end
        action.grenade_tried = true
        if self.AIKamikaze or not settings.grenade.enabled or not self.HasGrenadeAttack or self.CE8Grenades <= 0
            or not IsValid(enemy) or not self:Visible(enemy) or self.AttackType or self.Flinching
            or self.PauseAttacks or now < (self.NextDoAnyAttackT or 0) or now < (self.AIReactionEnd or 0)
            or self:GetWeaponState() == VJ.WEP_STATE_RELOADING or self:IsBusy("Activities")
            or now < (self.NextThrowGrenadeT or 0) or not self:AISelectAction("throw_grenade") then return false end
        -- One eligible retreat decision. Ordinary throw chance is not rolled too.
        self.NextThrowGrenadeT = now + settings.grenade.delay
        if math.Rand(0, 1) >= (settings.retreat.grenade or 0) then return false end
        action.throwing, action.deadline = true, now + 6
        if self:GrenadeAttack() then action.grenade_seed = self.AttackSeed return true end
        action.throwing = nil
        return false
    end
    function ENT:OnAnimEvent(id, eventTime, cycle, eventType, options)
        event(self, id, eventTime, cycle, eventType, options)
        if not self.Dead and self.AttackType == VJ.ATTACK_TYPE_GRENADE
            and id == 4001 and options == "primary keyframe" and not self.CE8ThrowReleased
            and self:GetSequenceName(self:GetSequence()) == self.CE8ThrowSequence
            and self.AttackState < VJ.ATTACK_STATE_EXECUTED then
            self.CE8ThrowReleased = true
            timer.Adjust("attack_grenade_start" .. self:EntIndex(), 0)
        end
    end
    local function safeTarget(self, target, settings)
        local enemies = 0
        for _, actor in ipairs(ents.FindInSphere(target, settings.enemy_radius)) do
            if actor ~= self and (actor:IsNPC() or actor:IsPlayer() or actor:IsNextBot()) and actor:Health() > 0 then
                if self:Disposition(actor) == D_HT then enemies = enemies + 1
                elseif actor:GetPos():DistToSqr(target) < settings.safety ^ 2 then return false end
            end
        end
        return self.VJ_Controlled or enemies >= settings.min_enemies
    end
    function ENT:CE8GrenadeVelocity(origin, target, projectile)
        local settings = self:CE8RankSettings().grenade
        local flight = {speed = settings.speed, gravity = data.grenade.gravity, max_range = settings.range[2]}
        local direction, duration, miss, reachable = ballistics.Aim(flight, origin, target, Vector(), physenv.GetGravity(), engine.TickInterval())
        if not reachable or miss > 8 then return end
        local previous, filter = origin, {self, self:GetActiveWeapon(), projectile}
        for i = 1, 12 do
            local nextPos = origin + ballistics.Predict(flight, direction, duration * i / 12, physenv.GetGravity() * flight.gravity, engine.TickInterval())
            local trace = util.TraceHull({start = previous, endpos = nextPos, mins = Vector(-3, -3, -3),
                maxs = Vector(3, 3, 3), mask = MASK_SHOT, filter = filter})
            if trace.StartSolid or trace.AllSolid or (trace.Hit and (i < 11 or trace.HitPos:Distance(target) > 36)) then return end
            previous = nextPos
        end
        return direction * settings.speed
    end
    function ENT:OnGrenadeAttack(status, override, landDir)
        if status ~= "Init" then return end
        local settings, enemy = self:CE8RankSettings().grenade, self:GetEnemy()
        local retreat = retreatThrow(self)
        if not settings.enabled or self.CE8Grenades <= 0 or (not retreat and not self:CE8WeaponShotReady(CurTime()))
            or self.AICharge or not IsValid(enemy) then return true end
        local target = landDir == "EnemyLastVis" and self.EnemyData.VisiblePos or enemy:GetPos()
        if landDir == "EnemyLastVis" and math.Rand(0, 1) >= settings.uncover then return true end
        local distance = self:GetPos():Distance(target)
        if distance < settings.range[1] or distance > settings.range[2] or not safeTarget(self, target, settings) then return true end
        local marker = self:GetAttachment(self:LookupAttachment(self.GrenadeAttackAttachment))
        local sequence = self:AISelectAction("throw_grenade")
        if not marker or not sequence or not self:CE8GrenadeVelocity(marker.Pos, target) then return true end
        if not retreat and not self.VJ_Controlled and math.Rand(0, 1) >= settings.chance then return true end
        self.CE8ThrowReleased, self.CE8ThrowConsumed = nil, nil
        self.CE8ThrowSequence, self.CE8ThrowTarget = sequence, Vector(target)
        self.AnimTbl_GrenadeAttack = "vjseq_" .. sequence
    end
    function ENT:OnGrenadeAttackExecute(status, grenade, override, landDir, landingPos)
        if status == "PreSpawn" then grenade.CE8Data, grenade.CE8Damage = data.grenade, 0
        elseif status == "PostSpawn" then
            local settings = self:CE8RankSettings().grenade
            local target = landDir == "EnemyLastVis" and self.CE8ThrowTarget or landingPos
            if self.Dead or self.CE8Grenades <= 0 or not self.CE8ThrowReleased or self.CE8ThrowConsumed
                or self.AttackType ~= VJ.ATTACK_TYPE_GRENADE
                or self:GetSequenceName(self:GetSequence()) ~= self.CE8ThrowSequence
                or (not retreatThrow(self) and not self:CE8WeaponShotReady(CurTime())) or not target or self:GetPos():Distance(target) < settings.safety
                or not safeTarget(self, target, settings) then grenade:Remove() return true end
            local velocity = self:CE8GrenadeVelocity(grenade:GetPos(), target, grenade)
            if not velocity then grenade:Remove() return true end
            local error = settings.error[({normal = 1, heroic = 2, legendary = 3})[difficulty.Level(self)] or 1]
            local angles = velocity:Angle()
            angles:RotateAroundAxis(angles:Right(), math.deg(math.Rand(-error, error)))
            angles:RotateAroundAxis(angles:Up(), math.deg(math.Rand(-error, error)))
            self.CE8ThrowConsumed = true
            self.CE8Grenades = math.max(0, self.CE8Grenades - 1)
            if self.CE8Grenades == 0 then self.HasGrenadeAttack = false end
            return angles:Forward() * settings.speed
        end
    end
end

-- Merged armor/barriers use bodygroups and PRP's per-surface collision carriers.
function Host.Equipment(ENT)
    local hunter = ENT:CE8Data().owner == "hunter"
    local jackal = ENT.CE8MergedBarrier and include("campaign_evolved/jackal_collision.lua")
    function ENT:CE8RemoveEquipment()
        if (hunter or jackal) and CE8.Collision then CE8.Collision.Remove(self) end
        if jackal then jackal.SetBarrier(self,0) end
        if self.Dead and self.CE8ArmorParts then
            for _, part in pairs(self.CE8ArmorParts) do
                if IsValid(part) then part.CE8AwaitCorpse = true end
            end
            return
        end
        if IsValid(self.CE8Barrier) then self.CE8Barrier:Remove() end
        self.CE8Barrier, self.CE8ShieldProp = nil, nil
        for _, part in pairs(self.CE8ArmorParts or {}) do if IsValid(part) then part:Remove() end end
        self.CE8ArmorParts = nil
    end
    function ENT:CE8UpdateEquipment()
        local rank, weapon = self:CE8RankSettings(), self:GetActiveWeapon()
        if hunter then
            CE8.Collision.Equip(self)
            return
        end
        if jackal then
            -- Dispose of a pre-migration attached barrier on an explicit reload.
            if IsValid(self.CE8Barrier) then self.CE8Barrier:Remove() end
            self.CE8Barrier,self.CE8ShieldProp=nil,nil
            jackal.Update(self)
            return
        end
        local equipped = rank.shield_model and IsValid(weapon)
            and (weapon.CE8WeaponName == "plasma_pistol" or weapon.CE8WeaponName == "needler")
        local emitter = self:FindBodygroupByName("emitter")
        if emitter >= 0 then self:SetBodygroup(emitter, equipped and (rank.bodygroups.emitter or 1) or 0) end
        if not equipped or self.CE8BarrierDown or (self.CE8BarrierMax or 0) <= 0 then self:CE8RemoveEquipment() return end
        if IsValid(self.CE8Barrier) then return end
        local index = self:LookupAttachment("shield")
        local frame = index > 0 and self:GetAttachment(index)
        if not frame then return end
        local part = ents.Create("obj_ce8_barrier")
        if not IsValid(part) then return end
        part:SetModel(rank.shield_model)
        part:SetOwner(self)
        part:SetPos(frame.Pos)
        part:SetAngles(frame.Ang)
        self.CE8Barrier, self.CE8ShieldProp = part, part
        part:SetNW2Entity("ce8_barrier_owner", self)
        part:Spawn()
        part:SetSkin(rank.bodygroups.emitter == 2 and 1 or 0)
        self:DeleteOnRemove(part)
    end
end

return Host
