-- Bounded, opt-in squads. VJ still owns enemy acquisition, orders and routes.
local methods = {}
local function config(actor)
    return actor.AIProfile and actor:AIProfile().squad
end
local function group(actor)
    local c = config(actor)
    return c and actor[c.fields.active]
end
local function eligible(actor)
    return IsValid(actor) and actor.AIHasCapability and actor:AIHasCapability("squad")
        and actor.IsInitialized and not actor.Dead and actor:Health() > 0
        and not actor.VJ_Controlled and actor.CanReceiveOrders ~= false
        and not actor.IsGuard and not actor.IsFollowing
        and actor.Behavior ~= VJ_BEHAVIOR_PASSIVE_NATURE
end
local function compatible(a, b)
    return eligible(b) and config(a).key == config(b).key
        and a:Disposition(b) == D_LI and b:Disposition(a) == D_LI
end
local function leads(actor)
    local setting = config(actor).leader
    if type(setting) == "function" then return setting(actor) == true end
    return setting == true
end
local function elect(squad)
    local first, leader
    for actor in pairs(squad.members) do
        if eligible(actor) then
            if not first or actor:EntIndex() < first:EntIndex() then first = actor end
            if leads(actor) and (not leader or actor:EntIndex() < leader:EntIndex()) then leader = actor end
        end
    end
    -- Retain a living leader instead of oscillating when actors move/spawn.
    local old = squad.leader
    if old and squad.members[old] and eligible(old) and leads(old) then leader = old end
    squad.leader, squad.coordinator = leader, leader or first
end
local function add(squad, actor)
    actor[config(actor).fields.active] = squad
    squad.members[actor] = {}
end
local function count(squad)
    local n = 0
    for _ in pairs(squad.members) do n = n + 1 end
    return n
end

function methods:AILeaveSquad(now, reason)
    self:AIEndSquadPosition(now)
    local squad = group(self)
    if not squad then return end
    local wasLeader = squad.leader == self
    -- Notify before detaching/re-electing: the casualty is still a member,
    -- and morale's existing seen set deduplicates VJ's later OnAllyKilled.
    if reason == "death" then
        for ally in pairs(squad.members) do
            if ally ~= self and eligible(ally) then ally:AIAllyLost(self, now, wasLeader) end
        end
    end
    squad.members[self] = nil
    local c = config(self)
    self[c.fields.active], self[c.fields.next_check] = nil, now + (c.interval or 2)
    elect(squad)
end

function methods:AIUpdateSquad(now)
    local c = config(self)
    if not c then return end
    if not eligible(self) then self:AILeaveSquad(now, "unavailable") return end
    local squad = group(self)
    if not squad then
        if now < (self[c.fields.next_check] or 0) then return end
        -- Stagger first recruitment; no startup combat/animation lock.
        if not self[c.fields.next_check] then
            self[c.fields.next_check] = now + 0.1 + (self:EntIndex() % 10) * 0.05
            return
        end
        self[c.fields.next_check] = now + (c.interval or 2)
        local nearest, distance
        for _, ally in ipairs(self:Allies_Check(c.radius or 900) or {}) do
            local other = group(ally)
            if other and compatible(self, ally) and eligible(other.coordinator)
                and compatible(self, other.coordinator)
                and count(other) < math.min(c.limit or 8, config(other.coordinator).limit or 8) then
                local d = self:GetPos():DistToSqr(other.coordinator:GetPos())
                if d <= (c.radius or 900)^2 and (not distance or d < distance) then nearest, distance = other, d end
            end
        end
        squad = nearest or {members = {}, observations = setmetatable({}, {__mode = "k"}), next_update = now}
        add(squad, self)
        elect(squad)
    end
    if now < squad.next_update then return end
    squad.next_update = now + (c.interval or 2)
    elect(squad)
    local anchor = squad.coordinator
    if not eligible(anchor) then return end
    c = config(anchor)
    local origin = anchor:GetPos()
    for ally, state in pairs(squad.members) do
        if not IsValid(ally) then
            squad.members[ally] = nil
        elseif not eligible(ally) or (ally ~= anchor and not compatible(anchor, ally)) then
            ally:AILeaveSquad(now, "unavailable")
        elseif ally ~= anchor then
            if origin:DistToSqr(ally:GetPos()) > (c.release_radius or 1400)^2 then
                state.far_since = state.far_since or now
                if now - state.far_since >= (c.release_delay or 6) then ally:AILeaveSquad(now, "separated") end
            else state.far_since = nil end
        end
    end
    for enemy, observation in pairs(squad.observations) do
        if not IsValid(enemy) or enemy:Health() <= 0 or now - observation.time > (c.memory_time or 6) then
            squad.observations[enemy] = nil
        end
    end
    local size = count(squad)
    if size >= (c.limit or 8) then return end
    for _, ally in ipairs(anchor:Allies_Check(c.radius or 900) or {}) do
        if compatible(anchor, ally) and group(ally) ~= squad then
            local other = group(ally)
            if not other then
                add(squad, ally)
                size = size + 1
            elseif not (squad.leader and other.leader) and size + count(other) <= (c.limit or 8) then
                -- Merge an unled local group as a whole; never steal members
                -- from another established leader or split a group each tick.
                local nearby = true
                for member in pairs(other.members) do
                    if not compatible(anchor, member) or origin:DistToSqr(member:GetPos()) > (c.radius or 900)^2 then
                        nearby = false break
                    end
                end
                if nearby then
                    for member in pairs(other.members) do add(squad, member) size = size + 1 end
                    other.members, other.leader, other.coordinator = {}, nil, nil
                end
            end
            elect(squad)
            if size >= (c.limit or 8) then break end
        end
    end
end

function methods:AISquadAllies(radius)
    if not self:AIHasCapability("squad") then return self:Allies_Check(radius) end
    local squad, allies = group(self), {}
    if not squad then return allies end
    local origin = self:GetPos()
    for ally in pairs(squad.members) do
        if ally ~= self and compatible(self, ally) and origin:DistToSqr(ally:GetPos()) <= radius^2 then
            allies[#allies + 1] = ally
        end
    end
    return allies
end

function methods:AISquadMember(ally)
    local squad = group(self)
    return squad ~= nil and squad.members[ally] ~= nil
end

function methods:AISquadIsLeader(ally)
    local squad = group(self)
    return squad ~= nil and squad.leader == ally
end

function methods:AISquadObserve(observation)
    local squad = group(self)
    if not squad or not eligible(self) then return end
    -- Caller supplies the existing visible-enemy sample. Never sample a hidden
    -- enemy here, force a target, or extend VJ's enemy-forgetting deadline.
    local previous = squad.observations[observation.enemy]
    if not previous or previous.time < observation.time then
        observation.observer = self
        squad.observations[observation.enemy] = observation
    end
end

function methods:AISquadObservation(enemy, now)
    local squad = group(self)
    local observation = squad and squad.observations[enemy]
    if not observation or not eligible(self) or not IsValid(enemy) or enemy:Health() <= 0
        or self:Disposition(enemy) ~= D_HT or not squad.members[observation.observer]
        or not compatible(self, observation.observer)
        or now - observation.time > (config(self).memory_time or 6)
        or self:GetPos():DistToSqr(observation.observer:GetPos()) > (config(self).radius or 900)^2 then return end
    return observation
end

function methods:AISquadAdvanceBusy(enemy, now)
    if not self:AIHasCapability("squad") then return false end
    for _, ally in ipairs(self:AISquadAllies(config(self).radius or 900)) do
        local profile = ally:AIProfile()
        local move = profile.squad and ally[profile.squad.fields.position]
        if move and move.enemy == enemy and now < move.deadline then return true end
        local flank, search = profile.flank, profile.search
        if flank and ally[flank.fields.enemy] == enemy and now < (ally[flank.fields.finish] or 0)
            and ally[flank.fields.schedule] and ally.CurrentSchedule == ally[flank.fields.schedule] then return true end
        local action = search and ally[search.fields.active]
        if action and action.enemy == enemy and action.action == "uncover" and now < action.action_until
            and action.schedule and ally.CurrentSchedule == action.schedule then return true end
    end
    return false
end

-- Reservations complement VJ's immediate friendly-fire sidestep. They prevent
-- independently chosen cover/spacing routes from converging on one position.
local function blocksLane(start, target, point, spacing, width)
    local offset = target - start
    local length = offset:Length()
    if length <= 1 then return false end
    local direction = offset * (1 / length)
    local along = (point - start):Dot(direction)
    return along > spacing * 0.5 and along < length - spacing * 0.5
        and point:DistToSqr(start + direction * along) < width^2
end

function methods:AISquadPositionFree(position, now, target)
    local squad, c = group(self), config(self)
    if not squad or not c.positioning then return true end
    local spacing = c.positioning.spacing or 96
    for ally in pairs(squad.members) do
        if ally ~= self and eligible(ally) then
            local p = ally:AIProfile()
            local move = ally[p.squad.fields.position]
            local cover = p.cover and ally[p.cover.fields.active]
            local destination = move and now < move.deadline and move.position or cover and cover.destination
            if position:DistToSqr(ally:GetPos()) < spacing^2
                or (destination and position:DistToSqr(destination) < spacing^2) then return false end
            if target then
                local point = position + (self:WorldSpaceCenter() - self:GetPos())
                local other, width = ally:WorldSpaceCenter(), c.positioning.lane_width or 48
                if blocksLane(point, target, other, spacing, width) then return false end
                if ally:GetEnemy() == self:GetEnemy() and ally.EnemyData and ally.EnemyData.Visible
                    and blocksLane(other, target, point, spacing, width) then return false end
            end
        end
    end
    return true
end

local positionTimers = {"NextChaseTime", "NextWeaponStrafeT", "TakingCoverT"}
function methods:AIEndSquadPosition(now)
    local c = config(self)
    local action = c and self[c.fields.position]
    if not action then return end
    self[c.fields.position] = nil
    self[c.fields.next_position] = now + (c.positioning and c.positioning.cooldown or 5)
    for key, previous in pairs(action.timers) do
        if self[key] == action.deadline then self[key] = math.max(now, previous) end
    end
    if self.CurrentSchedule == action.schedule then self:ClearSchedule() self:StopMoving() end
end

function methods:AIStartSquadPosition(position, enemy, now, purpose)
    local c = config(self)
    if not c or not c.positioning or not self:AIHasCapability("squad")
        or not self:AISquadPositionFree(position, now) then return false end
    self:AIEndSquadPosition(now)
    local action = {position = Vector(position), enemy = enemy, purpose = purpose or "spacing",
        deadline = now + (c.positioning.route_time or 4), timers = {}}
    self[c.fields.position] = action
    for _, key in ipairs(positionTimers) do
        local previous = self[key] or 0
        if previous < action.deadline then action.timers[key], self[key] = previous, action.deadline end
    end
    self:SetLastPosition(position)
    self:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH", function(schedule)
        action.schedule = schedule
        schedule.CanShootWhenMoving = purpose ~= "ambush"
        schedule.TurnData = {Type = VJ.FACE_ENEMY_VISIBLE}
        schedule.RunCode_OnFinish = function() action.arrived = true end
        schedule.RunCode_OnFail = function() action.failed = true end
    end)
    return true
end

function methods:AIThinkSquadPosition(now, enemy)
    local c = config(self)
    local action = c and self[c.fields.position]
    if not action then return false end
    if not eligible(self) or self.DisableChasingEnemy or not IsValid(enemy) or enemy ~= action.enemy
        or enemy:Health() <= 0 or self.AttackType or self:IsBusy("Activities")
        or action.failed or now >= action.deadline
        or (not action.arrived and self.CurrentSchedule ~= action.schedule)
        or action.arrived or self:GetPos():DistToSqr(action.position) <= 24^2 then
        self:AIEndSquadPosition(now) return false
    end
    return true
end

function methods:AITrySquadPosition(now, enemy)
    local c = config(self)
    if not c or not c.positioning or not eligible(self) or not IsValid(enemy)
        or now < (self[c.fields.next_position] or 0) or not self:AITacticalMoveReady(now)
        or self:IsMoving() or not self.EnemyData or not self.EnemyData.Visible then return false end
    self[c.fields.next_position] = now + (c.positioning.interval or 3) + (self:EntIndex() % 5) * 0.1
    local target = enemy:EyePos()
    if self:AISquadPositionFree(self:GetPos(), now, target) or self:AISquadAdvanceBusy(enemy, now) then return false end
    local origin = self:GetPos()
    local weapon = self:GetActiveWeapon()
    if not IsValid(weapon) or weapon.IsMeleeWeapon then return false end
    -- VJ validates walkability. Limit candidates and keep the target in range;
    -- do not move a functioning firing line merely to enforce a formation.
    for _, point in ipairs(VJ.TraceDirections(self, "Radial", c.positioning.radius or 192, true, false, 6, true) or {}) do
        local distance = point:Distance(target)
        if distance >= math.max(self.Weapon_RetreatDistance or 0, 128) and distance <= (self.Weapon_MaxDistance or 2400)
            and self:AISquadPositionFree(point, now, target)
            and not self:DoCoverTrace(point + (weapon:GetBulletPos() - origin), target, true) then
            return self:AIStartSquadPosition(point, enemy, now)
        end
    end
    return false
end

function methods:AISquadReport()
    local squad = group(self)
    if not squad then return {active = false} end
    local report = {active = true, leader = IsValid(squad.leader) and squad.leader:EntIndex() or false,
        coordinator = IsValid(squad.coordinator) and squad.coordinator:EntIndex() or false, members = {}}
    for actor in pairs(squad.members) do
        if IsValid(actor) then
            local p, enemy = actor:AIProfile(), actor:GetEnemy()
            local flee = p.flee and actor[p.flee.fields.active]
            local cover = p.cover and actor[p.cover.fields.active]
            local search = p.search and actor[p.search.fields.active]
            local kamikaze = p.kamikaze and actor[p.kamikaze.fields.active]
            local threat = p.threat and actor[p.threat.fields.active]
            local ambush = p.ambush and actor[p.ambush.fields.active]
            local position = p.squad and actor[p.squad.fields.position]
            local idle = p.idle and actor[p.idle.fields.active]
            local postcombat = p.postcombat and actor[p.postcombat.fields.active]
            report.members[#report.members + 1] = {entity = actor:EntIndex(), class = actor:GetClass(),
                enemy = IsValid(enemy) and enemy:EntIndex() or false,
                enemy_visible = IsValid(enemy) and actor.EnemyData and actor.EnemyData.Visible == true or false,
                flee = flee and flee.reason or false, search = search and (search.action or search.phase) or false,
                flee_phase = flee and (flee.throwing and "grenade" or flee.holding and "cower" or "run") or false,
                flee_detours = flee and flee.detours or 0,
                idle_step = idle and (idle.step or 1) or false,
                postcombat = postcombat and (postcombat.firing and "fire" or "react") or false,
                cover = cover and cover.phase or false,
                threat = threat and {reason = threat.reason, pressure = threat.pressure,
                    visible = threat.visible, can_attack = threat.can_attack} or false,
                positioning = position and position.purpose or false,
                ambush = ambush and ambush.phase or false,
                kamikaze = kamikaze and kamikaze.phase or false,
                details = p.squad and p.squad.report and p.squad.report(actor) or nil}
        end
    end
    table.sort(report.members, function(a, b) return a.entity < b.entity end)
    return report
end

return methods
