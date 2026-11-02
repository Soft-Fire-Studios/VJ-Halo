-- Character resources bind to the shared Human integration.
local profile = include("campaign_evolved/human.lua").Profile(ENT:CE8Data())
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
