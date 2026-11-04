-- Character resources bind to the shared Human integration.
local data = ENT:CE8Data()
local profile = include("campaign_evolved/human.lua").Profile(data)
profile.capabilities.obstacle = function(self)
    local setting = self:CE8RankSettings().obstacle
    return setting and setting.size > 0 and (setting.push or setting.damage) or false
end
profile.obstacle = {
    prop_only = true,
    push = function(self) return self:CE8RankSettings().obstacle.push end,
    damage = function(self) return self:CE8RankSettings().obstacle.damage end,
    maximum_height = data.obstacle.maximum_height, minimum_width = data.obstacle.minimum_width,
    maximum_mass = data.obstacle.maximum_mass, cooldown = data.obstacle.cooldown,
    allowed = function(self) return not self.AIFlee and not self.AIKamikaze and not self.AICover end
}
profile.reactions.surprise = function(self) return self:CE8RankSettings().surprise end
profile.lifecycle.alert = function(self, enemy, now, found, mode, quiet)
    if not self.AIFlee and not self.AIKamikaze and not self.AICover then
        self:AITrySurprise(enemy, now, found, mode, quiet)
    end
end
profile.cover.hide_time = function(self)
    local time = self:CE8RankSettings().cover_time
    return math.Rand(time[1], time[2])
end
profile.cover.maximum_hold = function(self) return self:CE8RankSettings().cover_time[2] + 2 end
profile.flee.grenade = function(self, action, now) return self:CE8RetreatGrenade(action, now) end
profile.flee.finished = function(self, action)
    if action.throwing and self.AttackType == VJ.ATTACK_TYPE_GRENADE and self.AttackSeed == action.grenade_seed then
        self:StopAttacks()
    end
end
return profile
