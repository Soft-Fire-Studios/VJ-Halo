-- Hunter policy on shared charge, search, danger and obstacle services.
local data = ENT:CE8Data()
local profile = include("campaign_evolved/human.lua").Profile(data)
profile.capabilities.defense = data.defense.enabled
profile.threat.minimum_hit_pressure = data.defense.minimum_hit_pressure
profile.threat.near_pressure = data.defense.near_pressure
profile.defense = {
    enter_pressure = data.defense.enter_pressure, exit_pressure = data.defense.exit_pressure,
    pressure_scale = data.defense.pressure_scale,
    raise_time = data.defense.raise_time, lower_time = data.defense.lower_time,
    pose = "defense", yaw_pose = "defense_yaw", yaw_limit = 174,
    allowed = function(self) return not self.AISearch and not self.AIObstacle end
}
profile.capabilities.obstacle = data.obstacle.smash or data.obstacle.destroy
profile.obstacle = {
    push = data.obstacle.smash and data.obstacle.size > data.obstacle.ignore,
    damage = data.obstacle.destroy and data.obstacle.size > data.obstacle.ignore,
    maximum_height = 1.5, cooldown = 3,
    allowed = function(self)
        local search = self.AISearch
        return not self.AICharge and (not search or not search.action or search.action == "destroy_cover")
    end
}
-- Search-selected obstacle strikes remain children of the existing search.
profile.reactions.started = function(self, kind, sequence, now, duration, context)
    self:AISuspendActions(now, context and context.search)
end
profile.charge.started = function(self, action, now)
    self:AIQueueDialogue("charge", now, action)
end
profile.search.cover_actions = {interval = 2, approach_distance = data.search.radius}
profile.search.suppress_eligible = function(self, weapon, search)
    if weapon.CE8WeaponName ~= "cannon" or not search.aim then return false end
    local distance = self:GetPos():Distance(search.aim)
    return distance >= data.cannon.min_range and distance <= data.cannon.max_range
end
return profile
