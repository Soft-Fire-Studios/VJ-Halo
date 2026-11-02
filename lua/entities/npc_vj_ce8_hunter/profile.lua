-- Hunter policy on shared charge, search, danger and obstacle services.
local data = ENT:CE8Data()
local profile = include("campaign_evolved/human.lua").Profile(data)
profile.capabilities.obstacle = data.obstacle.smash or data.obstacle.destroy
profile.obstacle = {
    push = data.obstacle.smash and data.obstacle.size > data.obstacle.ignore,
    damage = data.obstacle.destroy and data.obstacle.size > data.obstacle.ignore,
    maximum_height = 1.5, cooldown = 3,
    allowed = function(self) return not self.AICharge and not self.AISearch end
}
profile.search.suppress_eligible = function(self, weapon, search)
    if weapon.CE8WeaponName ~= "cannon" or not search.aim then return false end
    local distance = self:GetPos():Distance(search.aim)
    return distance >= data.cannon.min_range and distance <= data.cannon.max_range
end
return profile
