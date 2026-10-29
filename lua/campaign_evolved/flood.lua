-- Flood-specific attacks on the shared actor hosts. VJ owns navigation,
-- attack scheduling and possession; these callbacks supply authored contacts.
local Flood = {}
local FX = include("campaign_evolved/weapon_fx.lua")
local difficulty = SERVER and include("campaign_evolved/difficulty.lua")
local function enabled(actor)
    local disabled = GetConVar("ai_disabled")
    return not actor.Dead and not (disabled and disabled:GetBool())
        and actor:GetState() ~= VJ_STATE_FREEZE
end

function Flood.Shared(ENT)
    if SERVER then AddCSLuaFile("campaign_evolved/flood.lua") end
    FX.Load(ENT:CE8Data())
end

local function origin(actor, marker)
    local index = marker and actor:LookupAttachment(marker) or 0
    local attachment = index > 0 and actor:GetAttachment(index)
    return attachment and attachment.Pos or actor:WorldSpaceCenter()
end

local function contactSurface(material, position)
    if material == MAT_SLOSH or bit.band(util.PointContents(position + Vector(0, 0, 1)), CONTENTS_WATER) ~= 0 then
        return "liquid"
    end
    if material == MAT_DIRT or material == MAT_GRASS or material == MAT_SAND or material == MAT_SNOW
        or material == MAT_FOLIAGE or material == MAT_FLESH or material == MAT_BLOODYFLESH or material == MAT_ALIENFLESH then
        return "soft"
    end
    return "hard"
end

-- Native carrier bounds retained: full damage in the inner radius, a linear
-- transition to the lower bound at the outer radius. Source visibility traces
-- keep solid walls between a burst and a victim meaningful.
function Flood.Blast(actor, position, burst)
    for _, victim in ipairs(ents.FindInSphere(position, burst.radius)) do
        if IsValid(victim) and victim ~= actor and victim.TakeDamageInfo then
            local point = victim:NearestPoint(position)
            local distance = point:Distance(position)
            if distance <= burst.radius then
                local trace = util.TraceLine({start = position, endpos = point, mask = MASK_SHOT, filter = actor})
                if not trace.StartSolid and (not trace.Hit or trace.Entity == victim) then
                    local fraction = burst.radius > burst.core and math.Clamp((distance - burst.core) / (burst.radius - burst.core), 0, 1) or 0
                    local amount = burst.damage + (burst.minimum - burst.damage) * fraction
                    local damage = DamageInfo()
                    damage:SetAttacker(actor)
                    damage:SetInflictor(actor)
                    damage:SetDamage(amount)
                    damage:SetDamageType(DMG_BLAST)
                    damage:SetDamagePosition(position)
                    damage:SetDamageForce((point - position):GetNormalized() * amount * 40)
                    victim:TakeDamageInfo(damage)
                end
            end
        end
    end
end

-- Shared by Carrier ejection and the swarm fountain. The caller checks the
-- release point; VJ/Source owns the resulting jump, collision and landing.
function Flood.LaunchInfection(actor, position, yaw, launch)
    local child = ents.Create("npc_vj_ce8_flood_infection")
    if not IsValid(child) then return end
    local creator = actor:GetCreator()
    local enemy = actor.GetEnemy and actor:GetEnemy()
    child:SetPos(position)
    child:SetAngles(Angle(0, yaw, 0))
    if IsValid(creator) then child:SetCreator(creator) end
    child:Spawn()
    child:Activate()
    if IsValid(creator) and creator:IsPlayer() then
        creator:AddCount("npcs", child)
        cleanup.Add(creator, "npcs", child)
    end
    if IsValid(enemy) and enemy:Health() > 0 and child:CheckRelationship(enemy) == D_HT then
        child:ForceSetEnemy(enemy, false)
    end
    child:StopCurrentSchedule()
    child:ClearGoal()
    local angle = math.rad(yaw)
    child:ForceMoveJump(Vector(math.cos(angle), math.sin(angle), 0)
        * math.Rand(launch.horizontal[1], launch.horizontal[2])
        + Vector(0, 0, math.Rand(launch.vertical[1], launch.vertical[2])))
    return child
end

function Flood.ReleaseInfections(actor, position, count)
    local made = 0
    local launch = actor:CE8Data().burst.launch
    local low, high = Vector(-12, -12, 0), Vector(12, 12, 24.12)
    -- At most 24 candidates and eight children. Reject occupied space rather
    -- than stacking bodies in the carrier or spawning through floors/walls.
    for i = 1, 24 do
        if made >= count then break end
        local angle, radius = math.rad((i - 1) * 137.5), 32 + math.floor((i - 1) / 8) * 8
        local outward = Vector(math.cos(angle), math.sin(angle), 0)
        local point = position + outward * radius
        local route = util.TraceLine({start = position, endpos = point + Vector(0, 0, 12), mask = MASK_NPCSOLID, filter = actor})
        local floor = util.TraceLine({start = point + Vector(0, 0, 64), endpos = point - Vector(0, 0, 128), mask = MASK_NPCSOLID, filter = actor})
        if not route.Hit and not route.StartSolid and floor.Hit and not floor.StartSolid and not floor.HitSky and floor.HitNormal.z >= 0.5 then
            -- Release above the floor near the body, not at a grounded destination.
            point = Vector(point.x, point.y, math.max(position.z + 16, floor.HitPos.z + 8))
            local clear = util.TraceHull({start = point, endpos = point, mins = low, maxs = high, mask = MASK_NPCSOLID, filter = actor})
            if not clear.Hit and not clear.StartSolid and bit.band(util.PointContents(point), CONTENTS_WATER) == 0 then
                if Flood.LaunchInfection(actor, point, math.deg(angle), launch) then
                    made = made + 1
                end
            end
        end
    end
    return made
end

function Flood.Server(ENT, profile)
    local data = ENT:CE8Data()
    local voices = profile.sounds.dialogue[data.voice] or {}
    if profile.sounds.footsteps.hard then
        profile.footsteps.materials = {
            [MAT_DIRT] = "soft", [MAT_GRASS] = "soft", [MAT_SAND] = "soft", [MAT_SNOW] = "soft",
            [MAT_FOLIAGE] = "soft", [MAT_FLESH] = "soft", [MAT_BLOODYFLESH] = "soft", [MAT_ALIENFLESH] = "soft",
            [MAT_SLOSH] = "liquid"
        }
        profile.footsteps.default_surface, profile.footsteps.water_surface = "hard", "liquid"
        profile.footsteps.properties = {{"mud", "soft"}, {"gravel", "soft"}}
        local movement = profile.footsteps.action
        profile.footsteps.action = function(self)
            local name = "_" .. self:GetSequenceName(self:GetSequence()) .. "_"
            if name:find("_land_", 1, true) then return "land" end
            if name:find("_jump_", 1, true) then return "jump" end
            return movement(self)
        end
    end
    if profile.charge and voices.charge then
        profile.charge.started = function(self, action, now) self:AIPlayDialogue("charge", now, action) end
    end
    if voices.foundfoe then
        -- VJ plays Alert immediately after OnAlert; choose its bank, not a
        -- second overlapping voice. The shared lifecycle already tracks searches.
        profile.lifecycle.alert = function(self, enemy, now, found)
            self.SoundTbl_Alert = found and voices.foundfoe or voices.seefoe
        end
    end
    if data.owner == "flood_carrier" then
        -- Its native FS_Walk cue is generic; no authored surface-specific steps.
        profile.footsteps.default_surface = "default"
        profile.footsteps.action = function() return "walk" end
    end
    if data.owner == "flood_infection" then
        profile.capabilities.surface = true
        profile.surface = {speed = 180, range = 1200, stop_distance = 180,
            sequence = data.weapon_sets.unarmed.sequences.combat_move_front,
            allowed = function() return tonumber(difficulty.Get("ce8_infection_crawl")) == 1 end,
            limit = function() return tonumber(difficulty.Get("ce8_infection_crawl_limit")) or 16 end}
        profile.reactions.actions = {default_family = "any", families = {any = {
            jump = {data.leap.airborne}, airborne = {data.leap.airborne}, land = {data.leap.land}
        }}}
    end
    if data.leap then
        profile.capabilities.leap = true
        profile.leap = {}
        for key, value in pairs(data.leap) do profile.leap[key] = value end
        profile.leap.allowed = function(self)
            local setting = GetConVar("vj_npc_leap")
            return not setting or setting:GetBool()
        end
        profile.leap.started = function(self, action)
            self.CE8MeleeVictims = action.victims
            if data.melee then self.MeleeAttackDamage = math.Rand(data.melee.damage[1], data.melee.damage[2]) end
        end
        profile.leap.launched = function(self, action, now)
            if data.owner == "flood_infection" then
                action.bite_position, action.bite_next = self:WorldSpaceCenter(), now
                local sounds = profile.sounds.events.infector_leap
                local setting = GetConVar("vj_npc_snd_leap")
                if self.HasSounds ~= false and (not setting or setting:GetBool()) and sounds and #sounds > 0 then
                    self:EmitSound(sounds[math.random(#sounds)], 70, 100, 1, CHAN_BODY)
                end
            end
        end
        profile.leap.contact = function(self) self:ExecuteMeleeAttack() end
        if data.owner == "flood_infection" then
            profile.leap.collision_group = COLLISION_GROUP_DEBRIS_TRIGGER
            profile.leap.airborne_update = function(self, action, now)
                if action.bitten or now < (action.bite_next or 0) then return end
                action.bite_next = now + 0.05
                local position = self:WorldSpaceCenter()
                -- Actor pass-through removes physical contacts. A swept attack
                -- hull tests only during the leap, at most 20 times per second.
                local contact = util.TraceHull({start = action.bite_position or position, endpos = position,
                    mins = Vector(-12, -12, -12), maxs = Vector(12, 12, 12), filter = self,
                    mask = MASK_SHOT_HULL, collisiongroup = COLLISION_GROUP_NONE})
                action.bite_position = position
                if contact.Hit and IsValid(contact.Entity) then self:OnTouch(contact.Entity, contact.HitPos) end
            end
        end
    end
    include(data.adapter == "human" and "campaign_evolved/human.lua" or "campaign_evolved/actor.lua").Server(ENT, profile)
    local initialize, actorEvent, death, createCorpse = ENT.Init, ENT.OnAnimEvent, ENT.OnDeath, ENT.OnCreateDeathCorpse
    local function event(self, id, eventTime, cycle, eventType, options)
        if id == 4001 and options == "body impact" then
            local setting = GetConVar("vj_npc_snd_footstep")
            if self.HasSounds == false or (setting and not setting:GetBool()) then return end
            local contact = util.TraceLine({start = self:WorldSpaceCenter(), endpos = self:GetPos() - Vector(0, 0, 24),
                mask = MASK_NPCSOLID, filter = self})
            if contact.Hit and not contact.StartSolid and not contact.HitSky then
                FX.Sound(profile.sounds.playback["bodyfalls/" .. contactSurface(contact.MatType, contact.HitPos)], contact.HitPos, 75)
            end
            return
        elseif id == 4005 and data.owner == "flood_combat_elite" and options == "combatform_elite_jump" then
            -- The generic native event has no cooked audio. Its three authored
            -- material variants are already in the shared traced footstep bank.
            self:AIFootstep("left", "jump")
            return
        end
        return actorEvent(self, id, eventTime, cycle, eventType, options)
    end
    ENT.OnAnimEvent = event

    if not data.burst then
        function ENT:OnCreateDeathCorpse(damage, hitgroup, corpse)
            createCorpse(self, damage, hitgroup, corpse)
            if not IsValid(corpse) or self.HasSounds == false or self.HasDeathSounds == false or corpse.CE8BodyfallCallback then return end
            local playback = profile.sounds.playback
            -- The engine owns ragdoll motion. One callback handles real contacts;
            -- a shared cooldown prevents every colliding bone from playing a thud.
            corpse.CE8BodyfallCallback = corpse:AddCallback("PhysicsCollide", function(body, collision)
                local now = CurTime()
                local setting = GetConVar("vj_npc_snd_death")
                local allSounds = GetConVar("vj_npc_snd")
                if (setting and not setting:GetBool()) or (allSounds and not allSounds:GetBool())
                    or now < (body.CE8BodyfallAfter or 0) or collision.HitEntity == body
                    or collision.OurOldVelocity:LengthSqr() < 80 * 80 then return end
                local surface = util.GetSurfaceData(collision.TheirSurfaceProps)
                local tree = playback["bodyfalls/" .. contactSurface(surface and surface.material, collision.HitPos)]
                if FX.Sound(tree, collision.HitPos, 75) then body.CE8BodyfallAfter = now + 0.35 end
            end)
        end
    end
    ENT.HasLeapAttack = false -- Shared CUSTOM attack works on Human and Creature hosts.
    if data.leap then
        function ENT:OnThinkAttack(isAttacking, enemy) self:AITryLeap(CurTime(), enemy) end
    end
    ENT.BloodColor = VJ.BLOOD_COLOR_YELLOW
    ENT.CE8WeaponProfile = "floodcombat"
    ENT.HasMeleeAttack = data.melee ~= nil or data.owner == "flood_carrier"
    ENT.TimeUntilMeleeAttackDamage = false
    ENT.MeleeAttackDamageType = DMG_SLASH
    ENT.MeleeAttackAnimationFaceEnemy = false
    ENT.HasMeleeAttackKnockBack = data.owner == "flood_tank"
    ENT.HasMeleeAttackSounds, ENT.HasExtraMeleeAttackSounds, ENT.HasMeleeAttackMissSounds = false, false, false
    ENT.SoundTbl_MeleeAttack, ENT.SoundTbl_MeleeAttackExtra, ENT.SoundTbl_MeleeAttackMiss = false, false, false
    ENT.CanFlinch = false -- Keep contact attacks coherent until native flinches are integrated.
    ENT.Weapon_CanReload = data.adapter == "human" -- VJ refills without animation or cover.
    ENT.Weapon_RetreatDistance = 0
    ENT.Weapon_UnarmedBehavior = false
    ENT.HasDeathAnimation = false
    ENT.HasDeathCorpse = not data.burst
    if data.owner == "flood_infection" then
        local thinkActive = ENT.OnThinkActive
        function ENT:OnThinkActive()
            local now, enemy = CurTime(), self:GetEnemy()
            if self:AISurfaceActive() or self:AITrySurface(now, enemy) then return end
            -- VJ skips MaintainAlertBehavior while its chase schedule runs.
            -- Reconsider only near the target, not by rebuilding every route.
            if self.CurrentScheduleName == "SCHEDULE_ALERT_CHASE" and now >= (self.CE8SpaceCheck or 0) then
                self.CE8SpaceCheck = now + 0.2
                if IsValid(enemy) and self:GetPos():DistToSqr(enemy:GetPos()) < 180 ^ 2 then self:MaintainAlertBehavior() end
            end
            return thinkActive(self)
        end
    end

    function ENT:Init()
        initialize(self)
        local bank = profile.sounds.dialogue[data.voice] or {}
        self.SoundTbl_BeforeMeleeAttack = bank.melee_attack or false
        if data.owner == "flood_carrier" then
            -- Native idle foley, scheduled by VJ's existing idle sound system.
            self.SoundTbl_Idle = profile.sounds.effects.carrier_idle_oneoff
            self.SoundTbl_CombatIdle = self.SoundTbl_Idle
        end
        if data.owner == "flood_infection" then
            -- Engine collision policy: shootable and trigger-aware, with world
            -- and static geometry collision, but no actor/physics-prop blocking.
            self:SetCollisionGroup(COLLISION_GROUP_DEBRIS_TRIGGER)
            self.SoundTbl_Idle = profile.sounds.events.infector_vo_idle
            self.SoundTbl_CombatIdle = profile.sounds.events.infector_vo_move
            self.SoundTbl_Alert = false
            self.SoundTbl_Pain = profile.sounds.events.infector_damage
            self.SoundTbl_Death = false -- The burst plays its positional pop below.
        end
    end

    function ENT:MeleeAttackTraceDirection() return self:GetForward() end

    if data.melee then
        ENT.MeleeAttackDistance, ENT.MeleeAttackDamageDistance = data.melee.range, data.melee.hit_range
        ENT.MeleeAttackAngleRadius, ENT.MeleeAttackDamageAngleRadius = data.melee.angle, data.melee.hit_angle
        ENT.MeleeAttackDamage = data.melee.damage[2]
        ENT.NextMeleeAttackTime = data.melee.cooldown
        function ENT:OnMeleeAttack(status, enemy)
            if status == "PreInit" then
                local _, key = self:AIAnimationSet()
                local choices = data.melee_by_set[key] or data.melee_by_set.unarmed
                local sequence = choices[math.random(#choices)]
                if not self:AIValidateMotion(sequence, 0, enemy) then return true end
                self.CE8ContactSequence = sequence
                self.AnimTbl_MeleeAttack = "vjseq_" .. sequence
            elseif status == "Init" then
                self:AIEndCharge(CurTime())
                self.CE8MeleeVictims = {}
                self.CE8MeleeTurnTarget = nil
                self.MeleeAttackDamage = math.Rand(data.melee.damage[1], data.melee.damage[2])
                -- Preserve VJ's initial facing correction. It already applies
                -- before this callback; clearing it here cancelled that turn.
            elseif status == "PostInit" and not self.VJ_Controlled and not self.MeleeAttack_IsPropAttack
                and IsValid(enemy) and self.AttackAnimDuration > 0 then
                -- VJ owns interpolation, visibility, completion and expiry.
                -- Stop once aligned or after this short opening, whichever first.
                local duration = math.min(data.melee.tracking_time, self.AttackAnimDuration)
                if duration > 0 and self:SetTurnTarget(enemy, duration, true, true) then
                    self.CE8MeleeTurnTarget = enemy
                end
            end
        end
        function ENT:OnMeleeAttackExecute(status, victim)
            if status ~= "PreDamage" then return end
            local victims = self.CE8MeleeVictims
            if not victims or victims[victim] then return true end
            victims[victim] = true
        end
        function ENT:OnAnimEvent(id, eventTime, cycle, eventType, options)
            event(self, id, eventTime, cycle, eventType, options)
            if id == 4001 and options == "primary keyframe" and enabled(self) then
                if self:AILeapActive() then self:AILeapContact(cycle, eventTime)
                elseif self.AttackType == VJ.ATTACK_TYPE_MELEE
                    and self:GetSequenceName(self:GetSequence()) == self.CE8ContactSequence then
                    -- Faster playback can reach contact before the timed opening.
                    -- Retire only this attack's turn, never a replacement action.
                    local target = self.CE8MeleeTurnTarget
                    if target and self.TurnData and self.TurnData.Target == target and self.TurnData.StopOnFace then
                        self:ResetTurnTarget()
                        self:SetIdealYaw(self:GetAngles().y)
                    end
                    self.CE8MeleeTurnTarget = nil
                    self:ExecuteMeleeAttack()
                end
            end
        end
    end

    if data.owner == "flood_carrier" then
        ENT.MeleeAttackAngleRadius = 70 -- Existing suicide approach; the blast is radial.
        function ENT:OnAnimEvent(id, eventTime, cycle, eventType, options)
            if id == 4005 and (options == "carrier_swell" or options == "carrier_shortmove") then
                if self.HasSounds ~= false then
                    -- Independent world voices retain native gain/variation and
                    -- let the swell finish after the burst removes the body.
                    FX.Sound(profile.sounds.playback[options], origin(self, data.anchors.body), 70)
                end
                return
            end
            return event(self, id, eventTime, cycle, eventType, options)
        end
        ENT.MeleeAttackDistance = data.burst.range
        ENT.MeleeAttackDamageDistance, ENT.MeleeAttackDamage = 0, 0
        ENT.NextMeleeAttackTime = 1
        ENT.AnimTbl_MeleeAttack = "vjseq_" .. data.burst.sequence
        function ENT:OnMeleeAttack(status, enemy)
            if status == "PreInit" then
                if not self:AIValidateMotion(data.burst.sequence, 0, enemy) then return true end
                -- Translation refreshes may select the ordinary native melee.
                self.AnimTbl_MeleeAttack = "vjseq_" .. data.burst.sequence
            elseif status == "Init" then
                self:ResetTurnTarget()
                self:SetIdealYaw(self:GetAngles().y)
            elseif status == "PostInit" and self.AttackAnimDuration > 0 then
                local seed = self.AttackSeed
                -- Last authored frame, before VJ resets its attack. There is
                -- no native detonation event; do not reinterpret body impact.
                timer.Simple(math.max(0, self.AttackAnimDuration - engine.TickInterval()), function()
                    if not IsValid(self) or not enabled(self) or self.AttackSeed ~= seed
                        or self:GetSequenceName(self:GetSequence()) ~= data.burst.sequence then return end
                    self.SoundTbl_Death = false -- Already voiced by this clip.
                    local damage = DamageInfo()
                    damage:SetAttacker(game.GetWorld())
                    damage:SetInflictor(game.GetWorld())
                    damage:SetDamage((self:Health() + 1) * difficulty.Multiplier("resistance"))
                    damage:SetDamageType(DMG_GENERIC)
                    damage:SetDamagePosition(self:WorldSpaceCenter())
                    self:TakeDamageInfo(damage) -- Preserve VJ's complete death lifecycle.
                end)
            end
        end
        function ENT:OnMeleeAttackExecute() return true end -- No fictional claw strike.
    elseif data.owner == "flood_infection" then
        function ENT:MaintainAlertBehavior(...)
            local enemy, now = self:GetEnemy(), CurTime()
            if not enabled(self) or self.VJ_Controlled or self.AttackType or not self:OnGround()
                or self:GetState() ~= VJ_STATE_NONE or self:IsBusy("Activities") or self.IsFollowing or self.IsGuard
                or not IsValid(enemy) or enemy:Health() <= 0 or not self:Visible(enemy) then
                return self:AIBaseCall("MaintainAlertBehavior", ...)
            end
            local position, target = self:GetPos(), enemy:GetPos()
            local away = position - target
            if math.abs(away.z) > 64 then return self:AIBaseCall("MaintainAlertBehavior", ...) end
            away.z = 0
            local distance = away:Length()
            if distance > 180 then return self:AIBaseCall("MaintainAlertBehavior", ...) end
            if self:AITryLeap(now, enemy) then return end
            local schedule = self.CurrentSchedule
            if schedule and not self:IsScheduleFinished(schedule) then
                if schedule == self.CE8BackAwaySchedule then return end
                local name = schedule.Name
                if name ~= "SCHEDULE_ALERT_CHASE" and name ~= "SCHEDULE_ALERT_CHASELOS" and name ~= "SCHEDULE_IDLE_WANDER" then
                    return self:AIBaseCall("MaintainAlertBehavior", ...)
                end
                self:StopCurrentSchedule()
                if self.CurrentSchedule then return end
                self:StopMoving()
                self:ClearGoal()
            end
            if distance < 90 and now >= (self.CE8BackAwayAfter or 0) then
                self.CE8BackAwayAfter = now + 0.6
                if distance < 1 then away = -self:GetForward() else away = away:GetNormalized() end
                local destination = position + away * (140 - distance)
                local mins, maxs = self:GetCollisionBounds()
                local path = util.TraceHull({start = position + Vector(0, 0, 2), endpos = destination + Vector(0, 0, 2),
                    mins = mins, maxs = maxs, filter = self, mask = MASK_NPCSOLID, collisiongroup = COLLISION_GROUP_DEBRIS_TRIGGER})
                local floor = util.TraceLine({start = destination + Vector(0, 0, 24), endpos = destination - Vector(0, 0, 32),
                    filter = self, mask = MASK_NPCSOLID_BRUSHONLY})
                if not path.Hit and not path.StartSolid and floor.Hit and not floor.StartSolid and not floor.HitSky
                    and floor.HitNormal.z > 0.7 then
                    self:SetLastPosition(floor.HitPos)
                    self:SCHEDULE_GOTO_POSITION("TASK_WALK_PATH", function(schedule)
                        schedule:EngTask("TASK_FACE_ENEMY", 0)
                        schedule.TurnData = {Type = VJ.FACE_ENEMY}
                        schedule.CanShootWhenMoving = true
                    end)
                    self.CE8BackAwaySchedule = self.CurrentSchedule
                    return
                end
            end
            -- Hold at jumping distance until the existing leap cooldown clears.
            self:MaintainIdleBehavior(2)
            self:SetTurnTarget(enemy, 0.3, true, true)
        end
        function ENT:OnTouch(victim, contactPosition)
            local leap = self:AILeapActive()
            if not leap or leap.phase ~= "airborne" or leap.bitten
                or self.AttackType ~= VJ.ATTACK_TYPE_CUSTOM or self.AttackSeed ~= leap.seed then return end
            -- VJ invokes OnTouch before its own disabled/controller checks.
            if not enabled(self) or not IsValid(victim) or victim == self
                or not (victim:IsNPC() or victim:IsNextBot() or victim:IsPlayer()) or victim:Health() <= 0
                or self:CheckRelationship(victim) ~= D_HT or CurTime() < (self.CE8BiteAfter or 0) then return end
            local ignored = GetConVar("ai_ignoreplayers")
            if victim:IsPlayer() and ignored and ignored:GetBool() then return end
            local position = contactPosition or self:WorldSpaceCenter()
            local point = victim:NearestPoint(position)
            if point:DistToSqr(position) > data.bite.reach ^ 2 then return end
            local trace = util.TraceLine({start = position, endpos = point, mask = MASK_SHOT, filter = self})
            if trace.Hit and trace.Entity ~= victim then return end
            -- Same shield eligibility as needles, sampled before the hit can
            -- consume the last shield point. Player suit armor counts as shields.
            local shielded = (victim.CE8Shield or 0) > 0 or (victim:IsPlayer() and victim:Armor() > 0)
            self.CE8BiteAfter, self.CE8BiteSeed = CurTime() + data.bite.cooldown, self.AttackSeed
            leap.bitten = true
            local damage = DamageInfo()
            damage:SetAttacker(self)
            damage:SetInflictor(self)
            damage:SetDamage(shielded and data.bite.shield_damage or data.bite.damage)
            damage:SetDamageType(shielded and DMG_SHOCK or DMG_SLASH)
            damage:SetDamagePosition(point)
            victim:TakeDamageInfo(damage)
            if shielded and IsValid(self) and not self.Dead then
                local pop = DamageInfo()
                pop:SetAttacker(game.GetWorld())
                pop:SetInflictor(game.GetWorld())
                pop:SetDamage((self:Health() + 1) * difficulty.Multiplier("resistance"))
                pop:SetDamageType(DMG_GENERIC)
                pop:SetDamagePosition(self:WorldSpaceCenter())
                self:TakeDamageInfo(pop) -- VJ performs the normal death/burst lifecycle.
                return
            end
            local sounds = profile.sounds.events.infector_wrestle
            if self.HasSounds ~= false and sounds and #sounds > 0 then self:EmitSound(sounds[math.random(#sounds)], 65, 100, 1, CHAN_BODY) end
        end
    end

    if data.burst then
        function ENT:OnDeath(damage, hitgroup, status)
            death(self, damage, hitgroup, status)
            if status ~= "Init" or self.CE8BurstPlayed then return end
            self.CE8BurstPlayed = true
            local position = origin(self, data.anchors.explosion or data.anchors.body)
            local soundSetting = GetConVar("vj_npc_snd_death")
            if self.HasSounds ~= false and self.HasDeathSounds ~= false and (not soundSetting or soundSetting:GetBool()) then
                -- World playback preserves the pop after the body is removed.
                FX.Sound(profile.sounds.playback["effects/pop"], position, self.DeathSoundLevel or 80)
            end
            self:SetNoDraw(true)
            self:SetSolid(SOLID_NONE)
            if FX.Load(data) then ParticleEffect(data.effects.normal.death, position, Angle()) end
            if not data.burst.chance or math.Rand(0, 1) < data.burst.chance then Flood.Blast(self, position, data.burst) end
            if data.burst.children then
                self.CE8ReleasedInfections = Flood.ReleaseInfections(self, origin(self, data.anchors.spawn), data.burst.children)
            end
        end
    end
end
return Flood
