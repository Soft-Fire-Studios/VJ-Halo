-- Combat-form decisions. Existing VJ services own motion, attacks and damage.
local Combat = {}
local difficulty = include("campaign_evolved/difficulty.lua")

function Combat.Profile(data, profile)
    local settings = data.combat
    profile.reactions.actions = {families = data.actions, default_family = "any"}
    profile.reactions.family = function(self) local _, key = self:AIAnimationSet() return key end
    profile.reactions.started = function(self, kind, sequence, now, duration, context)
        self:AISuspendActions(now, context and context.search)
    end
    profile.capabilities.evasion = settings.evasion.enabled
    profile.evasion = {
        choices = function(self) local _, key = self:AIAnimationSet() return data.actions[key] or data.actions.any end,
        gunfire = settings.evasion, cooldown = settings.evasion.delay, aim_chance = settings.evasion.chance,
        aim_time = 0.75, minimum_distance = 128, range = data.charge.range
    }
    profile.controller.evasion_allowed = function(self) return not self.CE8CombatBerserk end
    profile.capabilities.obstacle = settings.obstacle.smash or settings.obstacle.destroy
    profile.obstacle = {
        push = settings.obstacle.smash, damage = settings.obstacle.destroy, maximum_height = 1.5, cooldown = 3,
        allowed = function(self) return not self.CE8Rising and self.HasMeleeAttack end
    }
    -- Shared remembered-position shooting, using the equipped weapon's own
    -- burst/cooldown and rejecting explosive or arcing fire behind cover.
    include("campaign_evolved/human.lua").Behaviors(profile, data)
    profile.search.squad = false
    profile.search.cover_actions = settings.cover
    profile.search.suppression_allowed = function(self)
        return not self.CE8CombatBerserk and not self.AICharge and not self.AILeap
    end
    local forced = profile.charge.forced
    profile.charge.forced = function(self)
        return self.CE8CombatBerserk ~= nil or (type(forced) == "function" and forced(self)) or forced == true
    end
    profile.controller.before_tactics = function(self, now, enemy) self:CE8CombatDecisions(now, enemy) end
    local shutdown = profile.lifecycle.shutdown
    profile.lifecycle.shutdown = function(self, now, reason)
        self.CE8CombatBerserk, self.CE8CombatRoll, self.CE8CombatRequest = nil, nil, nil
        if shutdown then shutdown(self, now, reason) end
    end
    if not data.ranks.shielded then return profile end
    local sounds = include("campaign_evolved/sounds/elite_shield.lua")
    local effects = {impact = "hcea_shield_impact", recharged = "hcea_shield_recharged", disperse = "hcea_shield_disperse"}
    profile.capabilities.shield = function(self) return (self.CE8ShieldMax or 0) > 0 end
    profile.shield = {
        maximum = function(self) return self.CE8ShieldMax or 0 end,
        resistance = function() return difficulty.Multiplier("shield_resistance") end,
        recharge_delay = function(self) return self:CE8RankSettings().recharge_delay end,
        recharge_time = function(self) return self:CE8RankSettings().recharge_time end,
        fields = {value = "CE8Shield", clock = "CE8ShieldClock", recharge_at = "CE8ShieldRechargeAt",
            breaks = "CE8ShieldBreaks", recharging = "CE8ShieldRecharging", recharge_sound = "CE8ShieldRechargeSound",
            impact_at = "CE8NextShieldImpact", impact_sound_at = "CE8NextShieldImpactSound"},
        network = {maximum = "ce8_shield_max", value = "ce8_shield", hit = "ce8_shield_hit", breaks = "ce8_shield_breaks"},
        accept_damage = function(self, damage)
            return not (damage:IsDamageType(DMG_FALL) or damage:IsDamageType(DMG_DROWN)
                or damage:IsDamageType(DMG_DROWNRECOVER) or damage:IsDamageType(DMG_CRUSH))
        end,
        effect = function(self, kind, position, angles)
            if not CE8.ShieldParticlesReady or not effects[kind] then return end
            if position then ParticleEffect(effects[kind], position, angles or self:GetAngles(), self)
            else ParticleEffectAttach(effects[kind], PATTACH_ABSORIGIN_FOLLOW, self, 0) end
        end,
        sound = function(self, kind)
            if self.HasSounds == false then return end
            local choices = sounds[kind]
            if choices and #choices > 0 then
                local path = choices[math.random(#choices)]
                VJ.EmitSound(self, path, 75, 100, 1, CHAN_AUTO)
                return path
            end
        end,
        after_damage = function(self, damage, hitgroup, now, previous, amount, blocked)
            local disabled = GetConVar("ai_disabled")
            if (disabled and disabled:GetBool()) or self.VJ_Controlled or self:GetState() == VJ_STATE_FREEZE then return end
            local attacker = damage:GetAttacker()
            if IsValid(attacker) and attacker ~= self and (attacker:IsNPC() or attacker:IsPlayer() or attacker:IsNextBot()) then
                local relation = self:CheckRelationship(attacker)
                if relation == D_HT or relation == D_NU then
                    self:UpdateEnemyMemory(attacker, attacker:GetPos())
                    self:MarkTookDamageFromEnemy(attacker)
                    local enemy = self:GetEnemy()
                    if not IsValid(enemy) or enemy == attacker or enemy:Health() <= 0 then self:ForceSetEnemy(attacker, false) end
                end
            end
            if amount <= blocked and self.CanFlinch then
                self.CE8ShieldFlinchAmount = amount
                self:Flinch(damage, hitgroup)
                self.CE8ShieldFlinchAmount = nil
            end
        end
    }
    return profile
end

function Combat.Attach(ENT, data)
    local settings = data.combat.berserk
    local think, damage, ally, danger = ENT.OnThink, ENT.OnDamaged, ENT.OnAllyKilled, ENT.OnDangerDetected
    local alert = ENT.OnAlert
    local ready = ENT.CE8WeaponShotReady
    local pickup = ENT.AIWeaponSettings
    if pickup then
        local allowed = pickup.allowed
        pickup.allowed = function(self)
            return not self.CE8CombatBerserk and (not allowed or allowed(self))
        end
    end
    function ENT:CE8CombatBerserkEnd(now)
        if not self.CE8CombatBerserk then return end
        self.CE8CombatBerserk = nil
        self:AIEndCharge(now)
    end
    function ENT:CE8CombatDecisions(now, enemy)
        local disabled = GetConVar("ai_disabled")
        if self.Dead or self:Health() <= 0 or self.VJ_Controlled or self.CE8Rising
            or (disabled and disabled:GetBool()) or self:GetState() == VJ_STATE_FREEZE or not self.HasMeleeAttack
            or not IsValid(enemy) or enemy:Health() <= 0 then
            self:CE8CombatBerserkEnd(now)
            self.CE8CombatRequest = nil
            return
        end
        local active = self.CE8CombatBerserk
        if active then
            if now >= active.finish or active.enemy ~= enemy or not self:Visible(enemy) then self:CE8CombatBerserkEnd(now) end
            return
        end
        if not self:Visible(enemy) then return end
        local distance = self:GetPos():Distance(enemy:GetPos())
        local rolled = self.CE8CombatRoll
        if rolled and (rolled.enemy ~= enemy or distance > settings.distance * 1.2) then self.CE8CombatRoll = nil end
        local request = self.CE8CombatRequest
        if request and now > request.expires then self.CE8CombatRequest = nil request = nil end
        if not request and settings.enabled and distance <= settings.distance and not self.CE8CombatRoll then
            -- Native chance/distance, Source encounter edge. Never roll every
            -- Think or every pellet; leaving/re-entering the band re-arms it.
            self.CE8CombatRoll = {enemy = enemy}
            if math.Rand(0, 1) < settings.chance then request = {reason = "combat", expires = now + settings.duration} end
        end
        if not request then return end
        self.CE8CombatRequest = request
        if now < (self.CE8CombatBerserkAfter or 0) or not self:AIReactionReady(now) then return end
        self:AICancelWeaponPickup()
        self:AISuspendActions(now)
        self.CE8CombatBerserk = {enemy = enemy, finish = now + settings.duration, reason = request.reason}
        self.CE8LastCombatBerserk = {time = now, reason = request.reason}
        self.CE8CombatRequest = nil
        self.CE8CombatBerserkAfter = now + settings.duration + data.charge.delay
        self.AINextCharge = now
        self:AIMaintainCharge(now, enemy)
        -- No authored berserk transition exists. Keep the weapon and normal
        -- melee stance; this is a bounded rush, not Brute weapon abandonment.
    end
    function ENT:OnThink()
        local active, now = self.CE8CombatBerserk, CurTime()
        if active and (now >= active.finish or self.Dead or self.VJ_Controlled or not self.HasMeleeAttack) then
            self:CE8CombatBerserkEnd(now)
        end
        return think(self)
    end
    function ENT:CE8WeaponShotReady(now)
        return not self.CE8CombatBerserk and ready(self, now)
    end
    function ENT:OnAlert(enemy)
        -- Sample once on acquisition; VJ and remembered-position search share
        -- the same expiry instead of restarting a search after its deadline.
        self.EnemyTimeout = math.Rand(data.search.time[1], data.search.time[2])
        return alert(self, enemy)
    end
    function ENT:OnAllyKilled(victim, ...)
        ally(self, victim, ...)
        if not settings.last_man or self.Dead or self.VJ_Controlled or not IsValid(victim)
            or not victim.IsCE8SNPC or (victim.CE8UnitLabel ~= "flood_combat_human" and victim.CE8UnitLabel ~= "flood_combat_elite")
            or victim == self or self:Disposition(victim) ~= D_LI or not self:Visible(victim)
            or self:GetPos():DistToSqr(victim:GetPos()) > settings.group_radius ^ 2 then return end
        -- Event-only local cohort check: no Flood squad scheduler or scan loop.
        for _, member in ipairs(ents.FindInSphere(self:GetPos(), settings.group_radius)) do
            if member ~= self and member ~= victim and IsValid(member) and member.IsCE8SNPC
                and (member.CE8UnitLabel == "flood_combat_human" or member.CE8UnitLabel == "flood_combat_elite")
                and not member.Dead and member:Health() > 0 and self:Disposition(member) == D_LI then return end
        end
        self.CE8CombatRequest = {reason = "last_man", expires = CurTime() + settings.duration}
    end
    function ENT:OnDangerDetected(kind, source)
        if settings.stuck and kind == VJ.DANGER_TYPE_GRENADE and IsValid(source) and source.CE8StuckTo == self then
            self.CE8CombatRequest = {reason = "stuck_grenade", expires = CurTime() + settings.duration}
            self:CE8CombatDecisions(CurTime(), self:GetEnemy())
            return true
        end
        return danger(self, kind, source)
    end
    function ENT:OnDamaged(info, hitgroup, status)
        if status == "PreDamage" then
            local blocked = self:AIShieldDamage(info, hitgroup, CurTime())
            if blocked > 0 then self:AIRecordThreatDamage(info, CurTime(), blocked) end
        end
        return damage(self, info, hitgroup, status)
    end
    local event, melee = ENT.OnAnimEvent, ENT.OnMeleeAttackExecute
    function ENT:OnAnimEvent(id, time, cycle, kind, options)
        event(self, id, time, cycle, kind, options)
        if id == 4001 and options == "primary keyframe" then self:AIObstacleHit() end
    end
    function ENT:OnMeleeAttackExecute(status, victim)
        if self.AIObstacleContext then return self:AIObstacleMelee(status, victim) end
        return melee(self, status, victim)
    end
    local origin = ENT.MeleeAttackTraceOrigin
    function ENT:MeleeAttackTraceOrigin()
        if self.AIObstacleContext then return self:WorldSpaceCenter() end
        if origin then return origin(self) end
        return self:AIBaseCall("MeleeAttackTraceOrigin")
    end
end
return Combat
