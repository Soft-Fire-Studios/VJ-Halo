-- Flood-specific attacks on the shared actor hosts. VJ owns navigation,
-- attack scheduling and possession; these callbacks supply authored contacts.
local Flood = {}
local FX = include("campaign_evolved/weapon_fx.lua")
local difficulty = SERVER and include("campaign_evolved/difficulty.lua")
local Infection = SERVER and include("campaign_evolved/flood_infection.lua")
local Gibs = SERVER and include("campaign_evolved/flood_gibs.lua")
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

-- Tank spew is a VJ CUSTOM attack. Five authored contacts remain separate;
-- child budgets/launch velocities are explicit Source adapter settings.
function Flood.Spew(ENT, settings)
    CE8 = CE8 or {}
    CE8.FloodSpewChildren = CE8.FloodSpewChildren or setmetatable({}, {__mode = "k"})
    local children = CE8.FloodSpewChildren
    local locks = {"AttackAnimTime", "AnimLockTime", "NextChaseTime", "NextIdleTime", "NextDoAnyAttackT"}
    local function budget(actor)
        local own, total = 0, 0
        for child, source in pairs(children) do
            if not IsValid(child) or child.Dead or child:Health() <= 0 then children[child] = nil
            else
                total = total + 1
                if source == actor then own = own + 1 end
            end
        end
        return own < settings.live_limit and total < settings.global_limit
    end
    local function point(actor)
        local id = actor:LookupAttachment(settings.attachment)
        local marker = id > 0 and actor:GetAttachment(id)
        if not marker then return end
        local position = marker.Pos + actor:GetForward() * settings.offset_forward
        local clear = util.TraceHull({start = marker.Pos, endpos = position,
            mins = Vector(-12, -12, 0), maxs = Vector(12, 12, 24.12), mask = MASK_NPCSOLID, filter = actor})
        if clear.Hit or clear.StartSolid or clear.AllSolid
            or bit.band(util.PointContents(position), CONTENTS_WATER) ~= 0 then return end
        return position
    end
    function ENT:CE8EndSpew(now, reason)
        local action = self.CE8Spew
        if not action then return end
        self.CE8Spew = nil
        local owns = self.AttackType == VJ.ATTACK_TYPE_CUSTOM and self.AttackSeed == action.seed
        if owns then
            self.AttackType, self.AttackState, self.AttackSeed = VJ.ATTACK_TYPE_NONE, VJ.ATTACK_STATE_DONE, 0
        end
        if action.schedule and self.CurrentSchedule == action.schedule then self:StopCurrentSchedule() end
        for key, previous in pairs(action.timers) do
            if self[key] == action.finish then self[key] = math.max(now, previous) end
        end
        self.CE8LastSpew = {time = now, reason = reason, children = action.children}
    end
    function ENT:CE8UpdateSpew(now)
        local action = self.CE8Spew
        if not action then return false end
        if not enabled(self) or self:Health() <= 0 or self.Flinching or self.PauseAttacks
            or self.AttackType ~= VJ.ATTACK_TYPE_CUSTOM or self.AttackSeed ~= action.seed
            or self:GetState() ~= action.state
            or (self.VJ_Controlled == true) ~= action.controlled
            or self.CurrentSchedule ~= action.schedule
            or (action.started and self:GetSequence() ~= action.sequence) then
            self:CE8EndSpew(now, "interrupted") return false
        end
        if self:GetSequence() == action.sequence then action.started = true end
        if now >= action.finish then self:CE8EndSpew(now, "finished") return false end
        return true
    end
    function ENT:CE8TrySpew(now, enemy)
        if self.CE8Spew or not enabled(self) or self:Health() <= 0 or self.AttackType
            or self.Flinching or self.PauseAttacks or not self:OnGround() or self:GetNavType() ~= NAV_GROUND
            or self:GetState() ~= VJ_STATE_NONE or self:IsBusy("Activities")
            or now < (self.CE8NextSpew or 0) then return false end
        if self.VJ_Controlled then
            local controller = self.VJ_Controller
            local player = IsValid(controller) and controller:GetPlayer()
            if not IsValid(player) or not player:KeyDown(IN_ATTACK2) then return false end
        end
        if not IsValid(enemy) or enemy:Health() <= 0 or self:CheckRelationship(enemy) ~= D_HT or not self:Visible(enemy) then return false end
        local ignored = GetConVar("ai_ignoreplayers")
        if enemy:IsPlayer() and ignored and ignored:GetBool() then return false end
        local delta = enemy:GetPos() - self:GetPos()
        local distance = delta:Length()
        if distance < settings.minimum or distance > settings.maximum
            or self:GetForward():Dot(delta:GetNormalized()) < settings.facing then return false end
        -- One eligible attempt owns its cooldown, including blocked placement
        -- and failed probability. No chance or clearance loop every Think.
        self.CE8NextSpew = now + settings.cooldown
        if not budget(self) or (not self.VJ_Controlled and math.Rand(0, 1) >= settings.chance) then return false end
        local sequence = self:LookupSequence(settings.sequence)
        if sequence < 0 then return false end
        local duration = self:SequenceDuration(sequence)
        if duration <= 0 or not point(self) or not self:AIValidateMotion(settings.sequence, 0, enemy) then return false end
        self:AISuspendActions(now)
        self:StopCurrentSchedule()
        if self.CurrentSchedule then return false end
        self:StopMoving() self:ClearGoal() self:ResetTurnTarget() self:SetIdealYaw(self:GetAngles().y)
        local action = {sequence = sequence, seed = now, state = self:GetState(), controlled = self.VJ_Controlled == true,
            finish = now + duration, contacts = {}, children = 0, timers = {}}
        for _, key in ipairs(locks) do action.timers[key] = self[key] or 0 end
        self.CE8Spew = action
        -- VJ's LetAttacks retains the animation lock without setting its global
        -- PauseAttacks flag; our CUSTOM attack and timers own attack exclusion.
        local animation, actualDuration = self:PlayAnim("vjseq_" .. settings.sequence, "LetAttacks", false, false, 0,
            {PlayBackRate = 1})
        if animation == ACT_INVALID or actualDuration <= 0 then self.CE8Spew = nil return false end
        action.finish, action.schedule = now + actualDuration, self.CurrentSchedule
        for key, previous in pairs(action.timers) do
            if (self[key] or 0) <= action.finish then self[key] = action.finish else action.timers[key] = nil end
        end
        self.AttackType, self.AttackState, self.AttackSeed = VJ.ATTACK_TYPE_CUSTOM, VJ.ATTACK_STATE_STARTED, action.seed
        return true
    end
    function ENT:CE8SpewContact(now, cycle)
        if not self:CE8UpdateSpew(now) or type(cycle) ~= "number" or not self.CE8Spew.started then return false end
        local frame = math.floor(cycle * (settings.frames - 1) + 0.5)
        local action, contact = self.CE8Spew
        for _, authored in ipairs(settings.contacts) do
            if math.abs(frame - authored) <= 1 then contact = authored break end
        end
        if not contact or action.contacts[contact] then return false end
        action.contacts[contact] = true
        if not budget(self) then return false end
        local position = point(self)
        if not position then return false end
        local yaw = self:GetAngles().y + math.Rand(-settings.spread, settings.spread)
        local child = Flood.LaunchInfection(self, position, yaw, settings.launch)
        if not IsValid(child) then return false end
        children[child] = self
        action.children = action.children + 1
        self.AttackState = VJ.ATTACK_STATE_EXECUTED
        return true
    end
    local attack, think, event, death, remove = ENT.OnThinkAttack, ENT.OnThink, ENT.OnAnimEvent, ENT.OnDeath, ENT.CustomOnRemove
    function ENT:OnThinkAttack(isAttacking, enemy)
        if self.CE8Spew or self:CE8TrySpew(CurTime(), enemy) then return end
        if attack then return attack(self, isAttacking, enemy) end
    end
    function ENT:OnThink()
        self:CE8UpdateSpew(CurTime())
        return think(self)
    end
    function ENT:OnAnimEvent(id, eventTime, cycle, eventType, options)
        event(self, id, eventTime, cycle, eventType, options)
        if id == 4001 and options == "primary keyframe" then self:CE8SpewContact(CurTime(), cycle) end
    end
    function ENT:OnDeath(damage, hitgroup, status)
        if status == "Init" then self:CE8EndSpew(CurTime(), "death") end
        return death(self, damage, hitgroup, status)
    end
    function ENT:CustomOnRemove()
        self:CE8EndSpew(CurTime(), "remove")
        return remove(self)
    end
end

-- Bind native damage regions to the current compiled hitbox set. The shared
-- anatomy service owns all damage/weapon transitions; this supplies resources.
function Flood.Anatomy(ENT, data, sounds)
    local sets, regions = {}, data.anatomy.regions
    for _, preset in pairs(data.anatomy.presets) do
        for _, row in pairs(preset) do sets[row.index] = row.regions end
    end
    local settings = {regions = regions,
        hit_regions = function(self) return sets[self:GetHitboxSet()] end,
        direct_trace = function(self, damage)
            local projectile = damage:GetInflictor()
            return IsValid(projectile) and projectile.CE8ConsumeDamageTrace
                and projectile:CE8ConsumeDamageTrace(self, damage) or nil
        end,
        hitbox_sets = function(self, lost)
            local preset = data.anatomy.presets[self:CE8RankSettings().hitbox_set]
            if not preset then return end
            local left = lost.l_upperarm and 2 or lost.l_forearm and 1 or 0
            local right = lost.r_upperarm and 2 or lost.r_forearm and 1 or 0
            local key = "l" .. left .. "_r" .. right .. "_h" .. (lost.corpse_head and 1 or 0)
                .. "_i" .. (lost.infection and 1 or 0)
            local row = preset[key]
            return row and row.index
        end}
    include("vj_ai/anatomy.lua").Attach(ENT, settings, {
        severed = function(self, changed, state, damage)
            Gibs.Sever(self, data.owner, regions, changed, damage)
        end,
        changed = function(self, region, state, damage)
            if self.HasSounds == false or state.sound_at == CurTime() then return end
            state.sound_at = CurTime()
            -- Reuse the native shared limb sound, including its variation/gain.
            FX.Sound(sounds.playback.combatform_limb_destroyed, damage:GetDamagePosition(), 75)
        end
    })
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
                    VJ.EmitSound(self, sounds, 70, 100, 1, CHAN_AUTO)
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
    ENT.CanFlinch = true -- VJ playback; shared gate protects contact attacks and leaps.
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

    if data.owner == "flood_carrier" then
        -- This bank is body foley, not a voice. Retain the existing VJ idle
        -- requests/chances/timer while keeping it outside CurrentIdleSound.
        function ENT:PlayIdleSound(combatIdle)
            if not self.HasSounds or not self.HasIdleSounds then return end
            local now = CurTime()
            if self.IdleSoundBlockTime > now or self.NextIdleSoundT > now then return end
            local combat = combatIdle and self.SoundTbl_CombatIdle
            local chance = combat and self.CombatIdleSoundChance or self.IdleSoundChance
            if math.random(1, chance) == 1 then
                VJ.EmitSound(self, combat or self.SoundTbl_Idle,
                    combat and self.CombatIdleSoundLevel or self.IdleSoundLevel,
                    self:GetSoundPitch(combat and self.CombatIdleSoundPitch or self.IdleSoundPitch), 1, CHAN_AUTO)
            end
            self.NextIdleSoundT = now + math.Rand(self.NextSoundTime_Idle.a, self.NextSoundTime_Idle.b)
        end
    end

    function ENT:MeleeAttackTraceDirection() return self:GetForward() end

    if data.melee then
        ENT.MeleeAttackDistance, ENT.MeleeAttackDamageDistance = data.melee.range, data.melee.hit_range
        ENT.MeleeAttackAngleRadius, ENT.MeleeAttackDamageAngleRadius = data.melee.angle, data.melee.hit_angle
        ENT.MeleeAttackDamage = data.melee.damage[2]
        ENT.NextMeleeAttackTime = data.melee.cooldown
        function ENT:OnMeleeAttack(status, enemy)
            if status == "PreInit" and self:AIIsReloading() then return true end
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
            local infection = not shielded and Infection.PrepareBite(self, victim, damage:GetDamage())
            victim:TakeDamageInfo(damage)
            if infection then Infection.FinishBite(self, victim, infection) end
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
            if self.HasSounds ~= false and sounds and #sounds > 0 then VJ.EmitSound(self, sounds, 65, 100, 1, CHAN_AUTO) end
        end
    end

    if data.burst then
        function ENT:OnDeath(damage, hitgroup, status)
            death(self, damage, hitgroup, status)
            if status ~= "Init" or self.CE8BurstPlayed then return end
            self.CE8BurstPlayed = true
            if self.CanGibOnDeath then Gibs.Destroy(self, data.owner, damage) end
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
    if data.spew then Flood.Spew(ENT, data.spew) end
    if data.anatomy then Flood.Anatomy(ENT, data, profile.sounds) end
    Infection.Attach(ENT, data)
    Gibs.Attach(ENT, data, profile.sounds)
end
return Flood
