-- Jackal defensive choices; shared services and VJ own routes and playback.
local profile = include("campaign_evolved/human.lua").Profile(ENT:CE8Data())
profile.capabilities.ambush = function(self)
    local settings = self:CE8RankSettings().tactics
    local weapon = self:GetActiveWeapon()
    return settings and settings.ambush == true and IsValid(weapon)
        and (weapon.CE8WeaponName == "beam_rifle" or weapon.CE8WeaponName == "needle_rifle") or false
end
profile.ambush = {
    policy = function(self) return self:CE8RankSettings().tactics end,
    minimum_distance = 480, wait_time = 1.5, fire_time = 3, cooldown = 12, timeout = 10
}
local function recovering(self)
    local weapon = self:GetActiveWeapon()
    return self:CE8RankSettings().defense.shield_loss and self.CE8BarrierDown
        and (self.CE8BarrierMax or 0) > 0 and IsValid(weapon)
        and (weapon.CE8WeaponName == "plasma_pistol" or weapon.CE8WeaponName == "needler")
end

profile.controller.cover_requested = function(self, now)
    return recovering(self) and self:CE8RankSettings().defense.cover
        and not self.Dead and not self.VJ_Controlled
        and now >= (self.AINextCover or 0) and not self.IsGuard and not self.IsFollowing
        and not self.DisableChasingEnemy and self:OnGround() and self:GetNavType() == NAV_GROUND
end
profile.controller.cover_before_search = true
profile.controller.before_tactics = function(self, now)
    local settings = self:CE8RankSettings().defense
    local pressured = settings.crouch and CE8.Barrier.ActorActive(self)
        and now - self:GetNW2Float("ce8_barrier_hit", -100) <= settings.pressure_time
    -- VJ still checks distance, firing line and stance before selecting crouch.
    self.Weapon_CrouchAttackChance = pressured and 1 or 2
end
profile.cover.hide_time = function(self)
    local time = self:CE8RankSettings().defense.hide_time
    return math.Rand(time[1], time[2])
end
profile.cover.maximum_hold = function(self)
    local rank = self:CE8RankSettings()
    return rank.recharge_delay + rank.recharge_time + rank.defense.hide_time[2]
end
profile.cover.recovered = function(self) return not recovering(self) end
profile.cover.play = function(self, phase, now)
    if phase ~= "idle" or not self:AIReactionReady(now) then return false end
    local set = self:AIAnimationSet()
    local sequence = set and set.sequences.crouch_idle
    return sequence and self:AIPlayReaction("cover_hold", sequence, now) or false
end
local started = profile.reactions.started
profile.reactions.started = function(self, kind, ...)
    -- A cover idle belongs to its existing recovery state. Evasions and other
    -- reactions still release that state through the normal shared callback.
    if kind ~= "cover_hold" then return started(self, kind, ...) end
end
return profile
