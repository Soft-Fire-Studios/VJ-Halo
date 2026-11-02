-- Brute bindings to existing squad, shield, charge, audio and reaction services.
local data = ENT:CE8Data()
local profile = include("campaign_evolved/human.lua").Profile(data)
local difficulty = include("campaign_evolved/difficulty.lua")
local shieldSounds = include("campaign_evolved/sounds/elite_shield.lua")
local effects = {impact = "hcea_shield_impact", recharged = "hcea_shield_recharged", disperse = "hcea_shield_disperse"}
local function armed(self) return not self:GetNW2Bool("ce8_berserk", false) end
profile.capabilities.charge = true
profile.capabilities.leap = true
profile.capabilities.cover = armed
profile.capabilities.shield = function(self) return armed(self) and (self.CE8ShieldMax or 0) > 0 end
profile.squad.leader = function(self) return self:CE8RankSettings().leader end
profile.charge = {
    settings = function(self) return self:CE8RankSettings().charge end,
    forced = function(self) return not armed(self) or not IsValid(self:GetActiveWeapon()) end,
    started = function(self, action, now, forced)
        if not forced then self:AIQueueDialogue("charge", now, action) end
    end
}
profile.controller.priority_reaction = function(self, now) return self:CE8TryBerserk(now) end
profile.leap = {}
for key, value in pairs(data.leap) do profile.leap[key] = value end
profile.leap.allowed = function(self)
    local setting = GetConVar("vj_npc_leap")
    return not armed(self) and (not setting or setting:GetBool())
end
profile.leap.started = function(self, action) self.CE8MeleeVictims = action.victims end
profile.leap.contact = function(self) self:ExecuteMeleeAttack() end
profile.footsteps.materials[MAT_METAL] = "metal_thick"
for _, material in ipairs({MAT_GRATE, MAT_VENT, MAT_COMPUTER}) do profile.footsteps.materials[material] = "metal_thin" end
profile.footsteps.properties = {{"ice", "ice"}, {"gravel", "gravel"}, {"mud", "mud"},
    {"grate", "metal_thin"}, {"vent", "metal_thin"}}
profile.reactions.actions = {default_family = "unarmed", families = data.actions}
profile.reactions.family = function(self) local _, key = self:AIAnimationSet() return key end
profile.reactions.damage.families = data.damage_by_set
profile.reactions.damage.default_family = "unarmed"
profile.lifecycle.shutdown = function(self)
    self.CE8PendingBerserk, self.CE8ContactSequence, self.CE8MeleeVictims = nil, nil, nil
    if self.CE8RemoveEquipment then self:CE8RemoveEquipment() end
end
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
    depleted = function(self, damage, now)
        local settings = self:CE8RankSettings().berserk
        if settings.enabled and now >= (self.CE8NextBerserk or 0) and math.Rand(0, 1) < settings.chance then
            self.CE8PendingBerserk = true
        end
    end,
    effect = function(self, kind, position, angles)
        if not CE8.ShieldParticlesReady or not effects[kind] then return end
        if position then ParticleEffect(effects[kind], position, angles or self:GetAngles(), self)
        else ParticleEffectAttach(effects[kind], PATTACH_ABSORIGIN_FOLLOW, self, 0) end
    end,
    sound = function(self, kind)
        -- Reuse the established shield feedback pending Brute-specific armor FX.
        if self.HasSounds == false then return end
        local choices = shieldSounds[kind]
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
        if amount <= blocked and self.CanFlinch and not self.CE8PendingBerserk then
            self.CE8ShieldFlinchAmount = amount
            self:Flinch(damage, hitgroup)
            self.CE8ShieldFlinchAmount = nil
        end
    end
}
return profile
