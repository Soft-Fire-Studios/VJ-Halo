-- Local cover geometry and bounded recovery states using VJ schedules.
local methods = {}
local function value(actor, setting, fallback)
    if type(setting) == "function" then setting = setting(actor) end
    if setting == nil then return fallback end
    return setting
end
local function pointValid(actor, config, position, enemy)
    if config.validate then return config.validate(actor, position, enemy) end
    return actor:AICoverPoint(position, enemy)
end
local function findCover(actor, config, enemy, excluded)
    if config.find then return config.find(actor, enemy, excluded) end
    return actor:AIFindCover(enemy, excluded)
end
local function routeCover(actor, config, cover, position, now)
    if config.route then return config.route(actor, cover, position, now) end
    return actor:AICoverRoute(cover, position, now)
end
local function reactionEnd(actor)
    local reaction = actor:AIProfile().reactions
    return reaction and actor[reaction.fields.finish] or 0
end
local function reactionReady(actor, config, now)
    if config.can_react then return config.can_react(actor, now) end
    return not actor:AIHasCapability("reactions") or actor:AIReactionReady(now)
end
local function play(actor, config, phase, now)
    if config.play then return config.play(actor, phase, now) end
    local sequence = config.animations and config.animations[phase]
    return sequence and actor:AIPlayReaction("cover_" .. phase, sequence, now) or false
end

function methods:AIFinishCover(now)
    local config = self.AIProfile and self:AIProfile().cover
    if not config then return end
    local cover = self[config.fields.active]
    if not cover then return end
    self[config.fields.active] = nil
    self[config.fields.next_attempt] = now + (config.retry_delay or 3)
    if self.TakingCoverT == cover.taking_until then self.TakingCoverT = now end
    if self.NextChaseTime == cover.chase_until then self.NextChaseTime = now end
    if config.finished then config.finished(self, cover, now) end
end

function methods:AICoverPoint(position, enemy)
    if not self:AIHasCapability("cover") then return false end
    local config = self:AIProfile().cover
    if not IsValid(enemy) then return false end
    local mins, maxs = self:GetCollisionBounds()
    local radius = math.max(math.abs(mins.x), math.abs(mins.y), maxs.x, maxs.y)
    local direction = enemy:EyePos() - position
    direction.z = 0
    if direction:LengthSqr() < 1 then return false end
    direction = direction:GetNormalized()
    local side = Vector(-direction.y, direction.x, 0) * (radius * (config.shoulder_width or 0.8))
    local height = maxs.z - mins.z
    local torso = position + Vector(0, 0, mins.z + height * (config.torso_height or 0.4))
    local weapon = self.GetActiveWeapon and self:GetActiveWeapon()
    local top = value(self, config.head_height, mins.z + height * 0.65)
    local head = position + Vector(0, 0, top)
    -- VJ supplies occlusion and moving-object checks. Bunker poses additionally
    -- require nearby protection for the crouched head and both shoulders.
    for _, point in ipairs({torso, head, head + side, head - side}) do
        local hidden, trace = self:DoCoverTrace(point, enemy:EyePos(), true)
        if not hidden or not trace.Hit or trace.StartSolid or trace.AllSolid
            or point:Distance(trace.HitPos) > radius + (config.protection_distance or 48) or math.abs(trace.HitNormal.z) > (config.wall_normal or 0.65)
            or (IsValid(weapon) and trace.Entity == weapon) then return false end
        local object = trace.Entity
        if IsValid(object) and (object:IsNPC() or object:IsPlayer()) then return false end
    end
    return true
end

function methods:AIFindCover(enemy, excluded)
    if not self:AIHasCapability("cover") then return false end
    local config = self:AIProfile().cover
    if not IsValid(enemy) then return end
    local origin = self:GetPos()
    local mins, maxs = self:GetCollisionBounds()
    local radius = math.max(math.abs(mins.x), math.abs(mins.y), maxs.x, maxs.y)
    local gap, candidates, objects = radius + (config.spacing or 8), {}, {}
    local weapon = self.GetActiveWeapon and self:GetActiveWeapon()
    local function add(position)
        position = Vector(position.x, position.y, origin.z)
        if position:Distance(origin) > (config.range or 512) then return end
        for _, previous in ipairs(excluded or {}) do
            if position:Distance(previous) < (config.exclude_distance or 48) then return end
        end
        candidates[#candidates + 1] = position
    end
    add(origin)
    -- Move up to an occluding wall instead of accepting a distant sightline break.
    local _, trace = self:DoCoverTrace(self:WorldSpaceCenter(), enemy:EyePos(), true)
    if trace.Hit and math.abs(trace.HitNormal.z) < (config.wall_normal or 0.65) then add(trace.HitPos + trace.HitNormal * gap) end
    for _, object in ipairs(ents.FindInSphere(origin, config.range or 512)) do
        if object ~= self and object ~= weapon and not object.VJ_ID_Living
            and not object:IsNPC() and not object:IsPlayer() and not object:IsWorld()
            and object:GetSolid() ~= SOLID_NONE and object:GetVelocity():LengthSqr() <= 1000 then
            objects[#objects + 1] = object
        end
    end
    table.sort(objects, function(a, b) return a:NearestPoint(origin):Distance(origin) < b:NearestPoint(origin):Distance(origin) end)
    -- A bounded local search handles props absent from Source's cover nodes.
    for i = 1, math.min(config.max_objects or 8, #objects) do
        local object = objects[i]
        local center = object:WorldSpaceCenter()
        local away = center - enemy:EyePos()
        away.z = 0
        if away:LengthSqr() > 1 then
            away = away:GetNormalized()
            local back = object:NearestPoint(center + away * 512) + away * gap
            local side = Vector(-away.y, away.x, 0) * gap
            add(back); add(back + side); add(back - side)
        end
    end
    for _, distance in ipairs(config.search_rings or {256, 512}) do
        for _, point in ipairs(VJ.TraceDirections(self, "Radial", distance, false, false, 8) or {}) do
            local offset = point - origin
            if offset:LengthSqr() > gap * gap then add(point - offset:GetNormalized() * gap) end
        end
    end
    table.sort(candidates, function(a, b) return (a - origin):LengthSqr() < (b - origin):LengthSqr() end)
    local filter = IsValid(weapon) and {self, weapon} or self
    for _, position in ipairs(candidates) do
        local ground = util.TraceHull({start = position + Vector(0, 0, 48), endpos = position - Vector(0, 0, 96),
            mins = Vector(mins.x, mins.y, 0), maxs = Vector(maxs.x, maxs.y, 2), mask = MASK_NPCSOLID, filter = filter})
        if ground.Hit and not ground.StartSolid and not ground.AllSolid and ground.HitNormal.z >= 0.7 then
            position = ground.HitPos + Vector(0, 0, 2)
            local space = util.TraceHull({start = position, endpos = position,
                mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = filter})
            if not space.Hit and not space.StartSolid and not space.AllSolid and pointValid(self, config, position, enemy) then
                return position
            end
        end
    end
end

function methods:AICoverRoute(cover, position, now)
    if not self:AIHasCapability("cover") then return false end
    local config = self:AIProfile().cover
    cover.phase, cover.arrived, cover.failed = "seek", false, false
    cover.tries = (cover.tries or 0) + 1
    cover.tried = cover.tried or {}
    cover.search_deadline = cover.search_deadline or now + (config.search_time or 10)
    cover.deadline = math.min(now + (config.route_time or 5), cover.search_deadline)
    if position then cover.tried[#cover.tried + 1] = position else cover.used_native = true end
    self.TakingCoverT = cover.deadline
    self.NextChaseTime = cover.deadline
    cover.taking_until, cover.chase_until = cover.deadline, cover.deadline
    local function configure(schedule)
        cover.route = (cover.route or 0) + 1
        local route = cover.route
        schedule.CanShootWhenMoving = true
        schedule.TurnData = {Type = VJ.FACE_ENEMY}
        if schedule.Name ~= "SCHEDULE_FACE" then schedule:EngTask("TASK_FACE_ENEMY", 0) end
        schedule.RunCode_OnFinish = function()
            if self[config.fields.active] == cover and cover.route == route then cover.arrived = not cover.failed end
        end
        if position then
            schedule.RunCode_OnFail = function()
                if self[config.fields.active] == cover and cover.route == route then cover.failed = true end
            end
        end
    end
    if position then
        if position:Distance(self:GetPos()) < 8 then
            self:StopMoving()
            self:SCHEDULE_FACE("TASK_FACE_ENEMY", configure)
        else
            self:SetLastPosition(position)
            self:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH", configure)
        end
    else
        -- Keep VJ's node search and its fallback; validate their endpoints too.
        self:SCHEDULE_COVER_ENEMY("TASK_RUN_PATH", configure)
    end
end

function methods:AITakeCover(now)
    if not self:AIHasCapability("cover") then return false end
    local config = self:AIProfile().cover
    local cover = {phase = "seek", search_deadline = now + (config.search_time or 10), hide_time = value(self, config.hide_time, 2)}
    self[config.fields.active] = cover
    routeCover(self, config, cover, findCover(self, config, self:GetEnemy()), now)
    if config.started then config.started(self, cover, now) end
    return true
end

function methods:AIMaintainCover(now, enemy)
    if not self:AIHasCapability("cover") then self:AIFinishCover(now) return false end
    local config = self:AIProfile().cover
    local cover = self[config.fields.active]
    if not cover then return false end
    if not IsValid(enemy) or self.Dead or self.VJ_Controlled then self:AIFinishCover(now) return false end
    if cover.phase == "seek" then
        if not cover.failed and now < cover.deadline and (self:IsMoving() or not cover.arrived) then return true end
        if not cover.failed and not self:IsMoving() and pointValid(self, config, self:GetPos(), enemy) then
            cover.phase = "hold"
            cover.minimum = now + cover.hide_time
            cover.deadline = now + value(self, config.maximum_hold, cover.hide_time + 5)
            cover.check_at = now + (config.check_interval or 0.5)
            if play(self, config, "enter", now) then return true end
        else cover.phase = "retry" end
    end
    local recovered = value(self, config.recovered, true)
    if cover.phase == "hold" and ((recovered and now >= cover.minimum) or now >= cover.deadline) then
        self:AIFinishCover(now)
        if reactionReady(self, config, now) then play(self, config, "exit", now) end
        return true
    end
    if cover.phase == "hold" and now >= (cover.check_at or 0) and now >= reactionEnd(self)
        and not self:IsBusy("Activities") then
        cover.check_at = now + (config.check_interval or 0.5)
        if not pointValid(self, config, self:GetPos(), enemy) then
            cover.phase, cover.tries, cover.used_native = "retry", 0, false
            cover.search_deadline, cover.tried = now + (config.search_time or 10), {self:GetPos()}
        end
    end
    if cover.phase == "retry" then
        if (cover.tries or 0) < (config.max_attempts or 3) and now < (cover.search_deadline or 0) then
            local position = findCover(self, config, enemy, cover.tried)
            if position or not cover.used_native then
                routeCover(self, config, cover, position, now)
                return true
            end
        end
        self:AIFinishCover(now)
        return false
    end
    -- Short VJ animation locks keep recovery interruptible by danger and prevent
    -- leaving an NPC frozen when its target is removed or the state is cancelled.
    if (self.TakingCoverT or 0) <= now or self.TakingCoverT == cover.taking_until then
        self.TakingCoverT = now + (config.lock_interval or 0.6)
        cover.taking_until = self.TakingCoverT
    end
    if (self.NextChaseTime or 0) <= now or self.NextChaseTime == cover.chase_until then
        self.NextChaseTime = now + (config.lock_interval or 0.6)
        cover.chase_until = self.NextChaseTime
    end
    if now >= reactionEnd(self) and not self:IsBusy("Activities") then
        play(self, config, "idle", now)
    end
    return true
end

return methods
