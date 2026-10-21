-- Server gameplay tuning. These are Source-unit defaults, not Halo tag values.
ENT.CE8ShieldMax = 100
ENT.CE8ShieldRechargeDelay = 6
ENT.CE8ShieldRechargeTime = 4
ENT.CE8ShieldImpactInterval = 0.05
ENT.CE8ShieldImpactSoundInterval = 0.1
ENT.CE8AimEvadeTime = 0.75
ENT.CE8AimEvadeCooldown = 4
ENT.CE8AimEvadeRange = 2400
ENT.CE8AimEvadeMinDistance = 128
ENT.CE8AimEvadeFOV = 160

local data = ENT:CE8Data()
local ballistics = include("campaign_evolved/ballistics.lua")
local difficulty = include("campaign_evolved/difficulty.lua")

local function sample(bounds)
    return math.Rand(bounds[1], bounds[2])
end

function ENT:CE8BehaviorSettings()
    local _, profile = self:CE8RankSettings()
    return data.behavior_profiles[profile.behavior]
end

function ENT:CE8Action(name)
    return self:AISelectAction(name)
end

function ENT:CE8ConfigureAI()
    local settings = self:CE8BehaviorSettings()
    local grenade = settings.grenade
    -- Native reload speech is queued by OnWeaponReload. VJ invokes its sound
    -- category before that callback, so clear the category on spawn and refresh.
    self.SoundTbl_WeaponReload = false
    self.SoundTbl_KilledEnemy = false
    self.CanFlinch = true
    self.FlinchChance = 1
    self.FlinchCooldown = settings.damage.cooldown
    self.MeleeAttackDistance = settings.charge.attack_range
    self.MeleeAttackDamageDistance = settings.charge.attack_range
    self.HasDeathAnimation = true
    self.HasGrenadeAttack = grenade.enabled and (self.CE8Grenades == nil or self.CE8Grenades > 0)
    self.GrenadeAttackEntity = "obj_ce8_projectile"
    self.GrenadeAttackModel = data.grenade.model
    self.GrenadeAttackAttachment = "grenade"
    self.GrenadeAttackBone = "wrist_l"
    self.GrenadeAttackThrowTime = false -- VJ's release timer is advanced by the authored event.
    self.GrenadeAttackChance = grenade.chance > 0 and math.max(1, math.Round(1 / grenade.chance)) or 1000000
    self.GrenadeAttackMinDistance = grenade.range[1]
    self.GrenadeAttackMaxDistance = grenade.range[2]
    self.NextGrenadeAttackTime = VJ.SET(grenade.delay, grenade.delay)
    self.EnemyTimeout = sample(settings.search.time)
    self.AlertTimeout = VJ.SET(settings.search.time[1], settings.search.time[2])
    self.CombatDamageResponse_CoverTime = VJ.SET(settings.cover.time[1], settings.cover.time[2])
    self.CallForHelp = settings.squad
    self.JumpParams = {Enabled = settings.jump.enabled, MaxRise = settings.jump.rise,
        MaxDrop = settings.jump.drop, MaxDistance = settings.jump.distance}
    self.SightDistance = settings.perception.idle.vision
    self.SightAngle = settings.perception.idle.fov
    if self.CE8Grenades == nil then
        self.CE8Grenades = math.random(grenade.count[1], grenade.count[2])
    end
    -- Fresh spawns also pass through VJ's InitConvars. Explicit Lua refreshes
    -- must preserve the same admin switches without reinitializing allegiance.
    for field, name in pairs({CanFlinch = "vj_npc_flinch", HasDeathAnimation = "vj_npc_anim_death",
        HasGrenadeAttack = "vj_npc_grenade", CallForHelp = "vj_npc_callhelp"}) do
        local convar = GetConVar(name)
        if convar and not convar:GetBool() then self[field] = false end
    end
end

function ENT:CE8DamageAnimation(action, damage, hitgroup)
    return self:AISelectDamage(action, damage, hitgroup)
end

function ENT:OnFlinch(damage, hitgroup, status)
    if status ~= "Init" then return end
    local hit = self.CE8LastHit
    local amount = hit and hit.time == CurTime() and hit.amount or damage:GetDamage()
    local shielded = hit and hit.time == CurTime() and hit.shielded
    local settings = self:CE8BehaviorSettings().damage
    if self.CE8PendingShieldBreak or self.CE8Cover or self.AttackType
        or amount < (shielded and settings.hard_shield or settings.hard_body) then return true end
    local animation = self:CE8DamageAnimation("h_ping", damage, hitgroup)
    if not animation then return true end
    self.AnimTbl_Flinch = animation
end

function ENT:OnDeath(damage, hitgroup, status)
    if status ~= "Init" then return end
    self:AIShutdown(CurTime(), "death")
    local action = damage:GetDamage() >= self:CE8BehaviorSettings().damage.hard_body and "h_kill" or "s_kill"
    local animation = self:CE8DamageAnimation(action, damage, hitgroup)
    self.HasDeathAnimation = self.HasDeathAnimation and animation ~= nil and self:OnGround()
        and not damage:IsDamageType(DMG_BLAST)
    self.AnimTbl_Death = animation and {animation} or {}
end

function ENT:OnMeleeAttack(status)
    if status ~= "Init" then return end
    local charge = self:CE8BehaviorSettings().charge
    self.NextMeleeAttackTime = self.CE8BerserkUntil and charge.berserk_delay or charge.delay
    self:CE8EndCharge(CurTime())
end

function ENT:CE8GrenadeSolution(origin, target, velocity, projectile)
    local settings = self:CE8BehaviorSettings().grenade
    local flight = {speed = settings.speed, gravity = data.grenade.gravity, max_range = settings.range[2]}
    local direction, duration, miss, reachable = ballistics.Aim(flight, origin, target, velocity,
        physenv.GetGravity(), engine.TickInterval())
    if not reachable or miss > 8 then return end
    local previous = origin
    local weapon = self:GetActiveWeapon()
    local filter = {self}
    if IsValid(weapon) then filter[#filter + 1] = weapon end
    -- The release check starts inside the newly spawned grenade's own hull.
    if IsValid(projectile) then filter[#filter + 1] = projectile end
    for i = 1, 12 do
        local delta = ballistics.Predict(flight, direction, duration * i / 12,
            physenv.GetGravity() * flight.gravity, engine.TickInterval())
        local position = origin + delta
        local trace = util.TraceHull({start = previous, endpos = position,
            mins = Vector(-3, -3, -3), maxs = Vector(3, 3, 3), mask = MASK_SHOT, filter = filter})
        if trace.StartSolid or trace.AllSolid then return end
        if trace.Hit and (i < 11 or trace.HitPos:Distance(target + velocity * duration) > 36) then return end
        previous = position
    end
    return direction * settings.speed
end

function ENT:OnGrenadeAttack(status, override, landDir)
    if status ~= "Init" then return end
    local settings = self:CE8BehaviorSettings().grenade
    local now = CurTime()
    if not settings.enabled or (self.CE8Grenades or 0) <= 0 or self.CE8Cover or self.CE8Charge
        or self.CE8PendingShieldBreak or now < (self.CE8ReactionEnd or 0) then return true end
    local enemy = self:GetEnemy()
    if not IsValid(enemy) then return true end
    local target = landDir == "EnemyLastVis" and self.EnemyData.VisiblePos or enemy:GetPos()
    local count = 0
    for _, entity in ipairs(ents.FindInSphere(target, settings.enemy_radius)) do
        if entity ~= self and (entity:IsNPC() or entity:IsPlayer()) and entity:Health() > 0 then
            local hostile = self:Disposition(entity) == D_HT
            if hostile then count = count + 1 end
            if not hostile and entity:GetPos():Distance(target) < settings.safety then return true end
        end
    end
    local vehicle = enemy:IsVehicle()
    if landDir == "EnemyLastVis" then
        if math.Rand(0, 1) >= settings.uncover then return true end
    elseif vehicle then
        if math.Rand(0, 1) >= settings.anti_vehicle then return true end
    elseif count < settings.min_enemies and not self.VJ_Controlled then return true end
    local attachment = self:GetAttachment(self:LookupAttachment("grenade"))
    local origin = attachment and attachment.Pos or self:GetShootPos()
    local distance = self:GetPos():Distance(target)
    if distance < settings.range[1] or distance > settings.range[2] then return true end
    if not self:CE8GrenadeSolution(origin, target, Vector()) then return true end
    local sequence = self:CE8Action("throw")
    if not sequence then return true end
    self.AnimTbl_GrenadeAttack = "vjseq_" .. sequence
    self.CE8ThrowTarget = Vector(target)
end

function ENT:OnGrenadeAttackExecute(status, grenade, override, landDir, landingPos)
    if status == "PreSpawn" then
        grenade.CE8Data = data.grenade
        grenade.CE8Damage = 0
    elseif status == "PostSpawn" then
        local settings = self:CE8BehaviorSettings().grenade
        local target = landDir == "EnemyLastVis" and self.CE8ThrowTarget or landingPos
        if not target or self:GetPos():Distance(target) < settings.safety then grenade:Remove() return true end
        local velocity = self:CE8GrenadeSolution(grenade:GetPos(), target, Vector(), grenade)
        if not velocity then grenade:Remove() return true end
        -- Keep VJ's ownership, spawn, release timing and physics hand-off.
        -- A fresh trajectory and ally check protect the wind-up interval.
        for _, ally in ipairs(ents.FindInSphere(target, settings.safety)) do
            if ally ~= self and (ally:IsNPC() or ally:IsPlayer()) and ally:Health() > 0
                and self:Disposition(ally) ~= D_HT then grenade:Remove() return true end
        end
        local level = self.CE8Difficulty or (CE8.Difficulty and CE8.Difficulty.Get("ce8_difficulty")) or "normal"
        local error = settings.error[({normal = 1, heroic = 2, legendary = 3})[level] or 1]
        local angles = velocity:Angle()
        angles:RotateAroundAxis(angles:Right(), math.deg(math.Rand(-error, error)))
        angles:RotateAroundAxis(angles:Up(), math.deg(math.Rand(-error, error)))
        self.CE8Grenades = math.max(0, self.CE8Grenades - 1)
        if self.CE8Grenades == 0 then self.HasGrenadeAttack = false end
        return angles:Forward() * settings.speed
    end
end

function ENT:CE8ShieldEffect(kind, position, angles)
    local effect = self.CE8ShieldEffects[kind]
    if not effect or not CE8 or not CE8.ShieldParticlesReady then return false end
    if position then
        -- CP0 supplies the actual hit position and its entity supplies the model
        -- for the effect's Position on Model Random initializer.
        ParticleEffect(effect, position, angles or self:GetAngles(), self)
    else
        -- These definitions set CP1 to 55 units above CP0 themselves. Follow
        -- the model origin so their internal offset is applied exactly once.
        ParticleEffectAttach(effect, PATTACH_ABSORIGIN_FOLLOW, self, 0)
    end
    self.CE8ShieldFXCounts = self.CE8ShieldFXCounts or {}
    self.CE8ShieldFXCounts[kind] = (self.CE8ShieldFXCounts[kind] or 0) + 1
    return true
end

function ENT:CE8InitAI()
    return self:AIInitialize(CurTime())
end

function ENT:CE8UpdateShield(now)
    self:CE8InitAI()
    return self:AIUpdateShield(now)
end

function ENT:OnDamaged(damage, hitgroup, status)
    -- VJ has already checked god mode and damage immunity at PreDamage.
    if status == "PreDamage" then
        self:AIShieldDamage(damage, hitgroup, CurTime())
        -- Shield resistance consumes the incoming hit first. Only the damage
        -- left for health receives regular resistance, so the layers do not stack.
        damage:SetDamage(damage:GetDamage() / difficulty.Multiplier("resistance"))
    end
end

function ENT:CE8ReactionSet()
    local weapon = self:GetActiveWeapon()
    local kind = IsValid(weapon) and weapon.CE8AnimationClass or "any"
    return data.reactions[kind] or data.reactions.any
end

function ENT:CE8CanReact(now)
    return self:AIReactionReady(now)
end

function ENT:CE8PlayReaction(kind, sequence, now)
    return self:AIPlayReaction(kind, sequence, now)
end

function ENT:CE8EvadePath(sequence, minimum, obstacle)
    return self:AIValidateMotion(sequence, minimum, obstacle)
end

function ENT:CE8ObstacleOptions(prop)
    return self:AIObstacleOptions(prop)
end

function ENT:CE8TryObstacle(now, failed)
    return self:AITryObstacle(now, failed)
end

function ENT:CE8SmashHit()
    return self:AIObstacleHit()
end

function ENT:OnMeleeAttackExecute(status, ent)
    return self:AIObstacleMelee(status, ent)
end

function ENT:CE8TryAimEvade(now, cooldown, kind)
    return self:AITryEvade(now, cooldown, kind)
end

function ENT:CE8AimThreat(now)
    return self:AIAimThreat(now)
end

function ENT:CE8GunfireThreat(now)
    return self:AIGunfireThreat(now)
end

function ENT:CE8FinishCover(now)
    return self:AIFinishCover(now)
end

function ENT:CE8CoverPoint(position, enemy)
    return self:AICoverPoint(position, enemy)
end

function ENT:CE8FindCover(enemy, excluded)
    return self:AIFindCover(enemy, excluded)
end

function ENT:CE8CoverRoute(cover, position, now)
    return self:AICoverRoute(cover, position, now)
end

function ENT:CE8TakeCover(now)
    return self:AITakeCover(now)
end

function ENT:CE8MaintainCover(now, enemy)
    return self:AIMaintainCover(now, enemy)
end

function ENT:OnCallForHelp(ally)
    return self:AIJoinOpening(ally, CurTime())
end

function ENT:CE8OpeningReady(now)
    return self:AIOpeningReady(now)
end

function ENT:CE8WeaponShotReady(now)
    local ready = self:CE8OpeningReady(now)
    if self.VJ_Controlled then return true end
    return ready and not self.CE8Cover and not self:AIChargeBlocksWeapon(self:GetActiveWeapon(), now)
        and now >= (self.CE8AcquireAt or 0)
end

function ENT:OnWeaponCanFire()
    local ready = self:CE8WeaponShotReady(CurTime())
    if self.VJ_Controlled then return end
    if self.CE8Cover or self:AIChargeBlocksWeapon(self:GetActiveWeapon(), CurTime()) then return false end
    -- VJ uses this hook for aiming and movement as well as firing. Our ranged
    -- SWEPs delay discharge themselves, so acquisition must not block posture.
    -- Other weapons and melee retain the old gate.
    local weapon = self:GetActiveWeapon()
    if (not IsValid(weapon) or not weapon.CE8Data or weapon.IsMeleeWeapon) and not ready then return false end
end

function ENT:CE8SetPerception(mode)
    return self:AISetPerception(mode)
end

function ENT:OnAlert(enemy)
    self:AIAlert(enemy, CurTime())
end

function ENT:OnWeaponReload()
    local enemy, weapon = self:GetEnemy(), self:GetActiveWeapon()
    if self.HasWeaponReloadSounds == false or not IsValid(enemy) or enemy:Health() <= 0
        or not IsValid(weapon) or self:GetWeaponState() ~= VJ.WEP_STATE_RELOADING then return end
    self:CE8QueueDialogue("reloading", CurTime(), {weapon = weapon, seed = self.WeaponReloadSeed})
end

function ENT:OnMaintainRelationships(entity, disposition)
    -- Observe VJ's existing candidates; never change its target or disposition.
    local seen = self.CE8SeenEnemies
    if not seen or seen[entity] or self.Dead or self.VJ_Controlled or self.HasAlertSounds == false
        or disposition ~= D_HT or not IsValid(entity) or entity:Health() <= 0
        or not IsValid(self:GetEnemy()) or not self:IsInViewCone(entity:GetPos()) or not self:Visible(entity) then return end
    seen[entity] = true -- One notice per entity, even when its native skip wins.
    self:CE8QueueDialogue("morefoe", CurTime(), entity)
end

function ENT:OnAllyKilled(entity)
    -- VJ calls this immediately before generic AllyDeath speech. Use the
    -- authored peer line and its own delay/repeat policy once instead.
    self.SoundTbl_AllyDeath = false
    if self.HasAllyDeathSounds == false or not IsValid(entity) or not entity.IsCE8Elite then return end
    self:CE8QueueDialogue("lmnt_deadally", CurTime(), entity)
end

function ENT:CE8StartSearch(now)
    return self:AIStartSearch(now)
end

function ENT:CE8EndSearchAction(now)
    return self:AIEndSearchAction(now)
end

function ENT:CE8BlindFirePoint(weapon, enemy)
    local point, corpse = self:CE8CorpseFirePoint(weapon)
    if point then return point, corpse end
    return self:AISuppressionPoint(weapon, enemy)
end

function ENT:CE8TrySearchAction(now, enemy)
    return self:AITrySearchAction(now, enemy)
end

function ENT:OnResetEnemy()
    self:AIResetEnemy(CurTime())
end

function ENT:CE8HearSound(now)
    return self:AIHearSound(now)
end

function ENT:OnInvestigate(entity, position)
    return self:AIStartInvestigation(entity, position, CurTime())
end

function ENT:OnKilledEnemy(entity, inflictor, wasLast)
    local now = CurTime()
    -- VJ reports every credited kill, including friendly fire. Only hostile
    -- victims qualify for a kill line or postcombat action.
    if not IsValid(entity) or self:Disposition(entity) ~= D_HT then return end
    -- Preserve the confirmed death after removal; a respawn cancels its speech.
    if self.HasKilledEnemySounds ~= false and (entity.Dead or entity:Health() <= 0) then
        self:CE8QueueDialogue("chr_kllfoe", now, {victim = entity})
    end
    return self:AIStartPostcombat(entity, now, wasLast)
end

function ENT:CE8EndCorpseFire(now)
    return self:AIEndCorpseFire(now)
end

function ENT:CE8CorpseFirePoint(weapon)
    return self:AICorpseFirePoint(weapon)
end

function ENT:CE8TryCorpseFire(now, action)
    return self:AITryCorpseFire(now, action)
end

function ENT:CE8CancelIdlePose()
    return self:AICancelIdle()
end

function ENT:CE8ThinkIdle(now)
    return self:AIThinkIdle(now)
end

function ENT:CE8ThinkSearch(now, enemy)
    return self:AIThinkSearch(now, enemy)
end

function ENT:CE8TryFlank(now, enemy)
    return self:AITryFlank(now, enemy)
end

function ENT:OnWeaponStrafe()
    if self.CE8Cover or self.CE8Charge or CurTime() < (self.CE8FlankUntil or 0) then return false end
end

local function dangerWarning(self, grenade)
    local previous = self.CurrentSpeechSound
    -- Neither voice bank contains warn_incmn_grnd. The generic incoming cue
    -- is our Source fallback; VJ owns its sound switch, chance and cooldown.
    self:PlaySoundSystem(grenade and "GrenadeSight" or "DangerSight")
    if self.CurrentSpeechSound ~= previous then self.CE8DangerSpeech = self.CurrentSpeechSound end
    -- VJ's cover fallback calls this category again; its cooldown prevents a
    -- second playback. We keep the sound handle to identify this warning only.
end

function ENT:OnDangerDetected(kind, danger)
    if self.VJ_Controlled or self.Dead or self:Health() <= 0 or self.CanDetectDangers == false then return end
    local disabled = GetConVar("ai_disabled")
    local state = self.GetState and self:GetState()
    if (disabled and disabled:GetBool()) or (state and (state == VJ_STATE_FREEZE
        or state == VJ_STATE_ONLY_ANIMATION_NOATTACK)) then return end
    local now = CurTime()
    local hint, position
    if kind == VJ.DANGER_TYPE_HINT then
        -- VJ deliberately passes nil for sound-hint dangers. Use its sensed
        -- hint position, which may differ from the emitter's current position.
        hint = self:GetBestSoundHint(bit.bor(SOUND_DANGER, SOUND_PHYSICS_DANGER, SOUND_MOVE_AWAY))
        if not hint or not hint.origin or (hint.expires and hint.expiration <= now) then return end
        position, danger = hint.origin, hint.owner
    elseif IsValid(danger) then
        position = danger:GetPos()
    else
        return
    end
    local grenade = kind == VJ.DANGER_TYPE_GRENADE or (IsValid(danger) and danger.VJ_ID_Grenade)
    local attached = grenade and IsValid(danger) and danger:GetParent() == self
    -- CheckForDangers can report both the grenade and its hint in one call.
    -- Resolve the hint owner first so an attachment still takes priority.
    if not attached and now < (self.CE8ReactionEnd or 0) and self.CurrentSchedule == self.CE8ReactionSchedule
        and (self.CE8Reaction == "grenade_dive" or self.CE8Reaction == "danger_dive"
            or self.CE8Reaction == "danger_evade") then return true end
    self:CE8EndCorpseFire(now)
    self.CE8PostCombat = nil
    local settings = self:CE8BehaviorSettings()
    if attached then
        if danger.Dead or now >= (danger.CE8DetonateAt or math.huge) then return true end
        self.CE8NoticedGrenades = self.CE8NoticedGrenades or setmetatable({}, {__mode = "k"})
        if not self.CE8NoticedGrenades[danger] then
            self.CE8NoticedGrenades[danger] = true
            if self.HasDangerSightSounds ~= false then self:CE8QueueDialogue("panic_plsmgrnd", now, danger) end
            if settings.charge.stuck then
                self.CE8PendingBerserk = "stuck"
                self.CE8BerserkGrenade = danger
                self.CE8BerserkRequestExpires = danger.CE8DetonateAt or now + 2
            end
        end
        return true
    end
    if now < (self.CE8NextEvade or 0) or not self:CE8CanReact(now) then return dangerWarning(self, grenade) end
    local dive = grenade or (hint and bit.band(hint.type, SOUND_DANGER) ~= 0)
    if math.Rand(0, 1) >= (dive and settings.evade.dive or settings.evade.chance) then return dangerWarning(self, grenade) end
    local side = (position - self:GetPos()):Dot(self:GetRight()) > 0 and "left" or "right"
    local names = dive and {"dive_" .. side, "dive_front", "dive_" .. (side == "left" and "right" or "left")}
        or {settings.evade.juke and "juke_" .. side or "evade_" .. side, "evade_" .. side}
    for _, name in ipairs(names) do
        local sequence = name:sub(1, 5) == "evade" and (self:CE8ReactionSet()[name] or {})[1] or self:CE8Action(name)
        if sequence then
            local ok, movement = self:GetSequenceMovement(self:LookupSequence(sequence), 0, 1)
            local stationary = name:sub(1, 4) == "juke" and (not ok or movement:LengthSqr() < 1)
            if ok or stationary then
                movement = movement or Vector()
                movement:Rotate(Angle(0, self:GetAngles().y, 0))
                local safer = (self:GetPos() + movement):Distance(position) > self:GetPos():Distance(position) + 16
                -- Some authored jukes move the body within the pose without a
                -- root translation. Do not manufacture movement for those clips.
                if stationary or (safer and self:CE8EvadePath(sequence)) then
                    self:CE8FinishCover(now)
                    if self:CE8PlayReaction(grenade and "grenade_dive" or dive and "danger_dive" or "danger_evade", sequence, now) then
                        self.CE8NextEvade = self.CE8ReactionEnd + settings.evade.delay
                        self.NextDangerDetectionT = self.CE8NextEvade
                        return true
                    end
                end
            end
        end
    end
    -- A rejected/blocked dive falls back to VJ's normal danger-cover schedule.
    dangerWarning(self, grenade)
end

function ENT:CE8EndCharge(now)
    return self:AIEndCharge(now)
end

function ENT:CE8MaintainCharge(now, enemy)
    if self.CE8BerserkUntil and now >= self.CE8BerserkUntil then self.CE8BerserkUntil = nil end
    return self:AIMaintainCharge(now, enemy)
end

function ENT:CE8ThinkTactics(now)
    return self:AIThinkTactics(now)
end

function ENT:CE8TryBerserk(now)
    local charge = self:CE8BehaviorSettings().charge
    if now > (self.CE8BerserkRequestExpires or math.huge) then self.CE8PendingBerserk = nil end
    if self.CE8PendingBerserk == "stuck" and (not IsValid(self.CE8BerserkGrenade)
        or self.CE8BerserkGrenade:GetParent() ~= self or self.CE8BerserkGrenade.Dead) then
        self.CE8PendingBerserk = nil
    end
    if self.CE8PendingShieldBreak and not charge.shield_break then self.CE8PendingShieldBreak = nil end
    local berserk = self.CE8PendingShieldBreak or self.CE8PendingBerserk
    if berserk and self:CE8CanReact(now) and now >= (self.CE8NextBerserk or 0) then
        self:CE8FinishCover(now)
        -- A stuck-grenade reaction uses the existing berserk motion, but its
        -- delayed panic cue replaces our unmarked brsrk fallback. Native
        -- dialogue events on the sequence remain authoritative.
        local kind = self.CE8PendingBerserk == "stuck" and "grenade_stuck" or "shield_break"
        if self:CE8PlayReaction(kind, self:CE8ReactionSet().shield_break, now) then
            self.CE8PendingShieldBreak = nil
            self.CE8PendingBerserk = nil
            self.CE8BerserkGrenade = nil
            self.CE8BerserkUntil = self.CE8ReactionEnd + charge.timeout
            self.CE8NextBerserk = self.CE8BerserkUntil + charge.cooldown
            self.CE8AimStarted = {}
            return true
        end
    end
end

function ENT:CE8ThinkReactions(now)
    return self:AIThinkActions(now)
end
