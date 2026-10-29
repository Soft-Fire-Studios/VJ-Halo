-- Opt-in direct pursuit along brush surfaces. Slots cover the approach as well
-- as climbing; VJ navigation handles overflow and failed routes. No Think hook.
local methods = {}
local UP, ZERO = Vector(0, 0, 1), Vector()
VJAI.SurfaceBudget = VJAI.SurfaceBudget or {actors = setmetatable({}, {__mode = "k"}), tokens = 32, time = 0, used = 0}
local budget = VJAI.SurfaceBudget

local function reserve(count, now, ground)
    local tick = engine.TickCount()
    if budget.tick ~= tick then budget.tick, budget.used = tick, 0 end
    budget.tokens = math.min(32, budget.tokens + math.max(0, now - budget.time) * 800)
    budget.time = now
    -- Ground discovery yields to attached actors when tokens are scarce.
    if budget.used + count > 32 or budget.tokens < count + (ground and 10 or 0) then return false end
    budget.tokens, budget.used = budget.tokens - count, budget.used + count
    budget.peak = math.max(budget.peak or 0, budget.used)
    return true
end

local function usable(trace)
    return trace.Hit and trace.HitWorld and not trace.HitSky and not trace.StartSolid and not trace.AllSolid
        and trace.HitNormal:LengthSqr() > 0.5
end

local function project(direction, normal)
    return direction - normal * direction:Dot(normal)
end

local function hull(action, normal)
    -- SOLID_BBOX stays axis aligned. Center its compact cube on the rotated
    -- body, so the origin/belly can approach a wall without a floating gap.
    local center = normal * action.radius
    return center - action.extent, center + action.extent,
        action.radius * (math.abs(normal.x) + math.abs(normal.y) + math.abs(normal.z) - 1) + 2
end

local function trace(actor, from, to, mins, maxs)
    local request = {start = from, endpos = to, filter = actor, mask = MASK_NPCSOLID_BRUSHONLY}
    if mins then request.mins, request.maxs = mins, maxs return util.TraceHull(request) end
    return util.TraceLine(request)
end

local function allowed(actor, config)
    local disabled = GetConVar("ai_disabled")
    return actor:AIHasCapability("surface") and not actor.Dead and actor:Health() > 0
        and not actor.Flinching and not actor.PauseAttacks and actor:GetState() ~= VJ_STATE_FREEZE
        and not (disabled and disabled:GetBool()) and (not config.allowed or config.allowed(actor))
end

local function attackRange(actor, enemy, config)
    local delta = enemy:GetPos() - actor:GetPos()
    return delta.x * delta.x + delta.y * delta.y <= (config.stop_distance or 180) ^ 2
        and math.abs(delta.z) <= 64 and actor:Visible(enemy)
end

local function changeSurface(actor, action, normal, direction)
    local low, high = hull(action, normal)
    local pivot = actor:GetPos() + (action.normal - normal) * action.radius
    local clear = trace(actor, pivot, pivot, low, high)
    if clear.StartSolid or clear.AllSolid then return false end
    actor:SetPos(pivot)
    actor:SetCollisionBounds(low, high)
    action.low, action.high, action.normal = low, high, normal
    action.angle = direction:AngleEx(normal)
    return true
end

-- At an outside edge the whole hull must clear the new surface before turning.
-- A short, swept continuation avoids trying to walk into the side of a ledge.
local function roundEdge(actor, action, config, now)
    local edge = action.edge
    if now >= edge.deadline then actor:AIEndSurface(now, "edge_timeout") return false end
    local position, normal = actor:GetPos(), action.normal
    local center = position + normal * action.radius
    local extent = action.radius * (math.abs(edge.normal.x) + math.abs(edge.normal.y) + math.abs(edge.normal.z))
    local remaining = extent + 2 - (center - edge.point):Dot(edge.normal)
    if remaining <= 0.5 then
        local direction = project(-normal, edge.normal):GetNormalized()
        if not changeSurface(actor, action, edge.normal, direction) then actor:AIEndSurface(now, "corner_clearance") return false end
        action.edge = nil
        actor:SetLocalVelocity(direction * config.speed)
        return true
    end
    local direction = project(edge.normal, normal):GetNormalized()
    local alignment = direction:Dot(edge.normal)
    if alignment < 0.1 then actor:AIEndSurface(now, "sharp_edge") return false end
    local distance = math.min(remaining / alignment, config.speed * 0.1)
    local sweep = trace(actor, position, position + direction * distance, action.low, action.high)
    if sweep.Hit or sweep.StartSolid or sweep.AllSolid then actor:AIEndSurface(now, "edge_blocked") return false end
    action.angle = direction:AngleEx(normal)
    actor:SetLocalVelocity(direction * (distance / 0.1))
    return true
end

function methods:AISurfaceActive()
    local config = self.AIProfile and self:AIProfile().surface
    return config and self[config.fields.active] or nil
end

function methods:AIEndSurface(now, reason)
    local action = self:AISurfaceActive()
    if not action then return end
    local config = self:AIProfile().surface
    self[config.fields.active], budget.actors[self] = nil, nil
    self[config.fields.next_attempt] = now + (reason == "attack_range" and 0.5 or 2)
    self[config.fields.last] = {time = now, reason = reason}
    local ownPhysics = self:GetMoveType() == MOVETYPE_FLY and self.MovementType == VJ_MOVETYPE_AERIAL
    -- Keep the occupied body center fixed when returning the origin to feet.
    -- A ceiling-facing hull would otherwise become embedded in the ceiling.
    local mins, maxs = self:GetCollisionBounds()
    if mins == action.low and maxs == action.high then
        self:SetPos(self:GetPos() + action.normal * action.radius - (action.mins + action.maxs) * 0.5)
        self:SetCollisionBounds(action.mins, action.maxs)
    end
    local forward = self:GetForward()
    local yaw = forward.x * forward.x + forward.y * forward.y > 0.01 and forward:Angle().y or action.yaw
    self:SetAngles(Angle(0, yaw, 0))
    if ownPhysics then
        self:DoChangeMovementType(action.movement)
        self:SetMoveType(action.move_type)
        self:SetMoveCollide(action.move_collide)
        self:SetIdealYaw(yaw)
        self:SetGroundEntity(NULL)
        self:SetLocalVelocity(action.normal * 55 + Vector(0, 0, -60))
    end
    local ownsAttack = self.AttackType == VJ.ATTACK_TYPE_CUSTOM and self.AttackSeed == action.seed
    if ownsAttack then
        self.AttackType, self.AttackState, self.AttackSeed = VJ.ATTACK_TYPE_NONE, VJ.ATTACK_STATE_DONE, 0
        if self:GetState() == VJ_STATE_ONLY_ANIMATION_CONSTANT then self:SetState(action.state) end
    end
    for key, previous in pairs(action.timers) do
        if self[key] == action.deadline then self[key] = math.max(now, previous) end
    end
end

function methods:AITrySurface(now, enemy)
    if not self:AIHasCapability("surface") or self:AISurfaceActive() then return false end
    local config = self:AIProfile().surface
    if now < (self[config.fields.next_attempt] or 0) then return false end
    self[config.fields.next_attempt] = now + 0.4 + (self:EntIndex() % 11) * 0.02
    -- First pass is AI driven; possession retains its existing movement/leaps.
    if not allowed(self, config) or self.VJ_Controlled or self.AttackType or self:AILeapActive()
        or not self:OnGround() or self:GetMoveType() ~= MOVETYPE_STEP or self:GetState() ~= VJ_STATE_NONE
        or self:IsBusy("Activities") or self.IsFollowing or self.IsGuard
        or not IsValid(enemy) or enemy:Health() <= 0 or self:CheckRelationship(enemy) ~= D_HT then return false end
    local ignored = GetConVar("ai_ignoreplayers")
    if enemy:IsPlayer() and ignored and ignored:GetBool() then return false end
    local origin = self:GetPos()
    local toward = enemy:WorldSpaceCenter() - self:WorldSpaceCenter()
    if toward:LengthSqr() > (config.range or 1200) ^ 2 or attackRange(self, enemy, config) then return false end
    local active = 0
    for actor in pairs(budget.actors) do
        if IsValid(actor) and actor:AISurfaceActive() then active = active + 1 else budget.actors[actor] = nil end
    end
    if active >= config.limit(self) or not reserve(3, now, true) then return false end
    -- Claim the slot on the floor. Waiting for a wall beside the actor lets
    -- node navigation steer around it before this action can ever start.
    local floor = trace(self, origin + UP * 8, origin - UP * 24)
    if not usable(floor) or floor.HitNormal.z < 0.7 then return false end
    local mins, maxs = self:GetCollisionBounds()
    local radius = math.max(math.abs(mins.x), math.abs(mins.y), maxs.x, maxs.y, (maxs.z - mins.z) * 0.5)
    local action = {normal = floor.HitNormal:GetNormalized(), radius = radius, extent = Vector(radius, radius, radius),
        mins = mins, maxs = maxs, movement = self.MovementType, move_type = self:GetMoveType(),
        move_collide = self:GetMoveCollide(), state = self:GetState(), yaw = self:GetAngles().y,
        climb_sign = toward.z < -90 and -1 or 1,
        target = enemy, seed = now, deadline = now + 10, timers = {}, next_probe = now,
        progress = Vector(origin), progress_at = now}
    local low, high, offset = hull(action, action.normal)
    local attached = floor.HitPos + action.normal * offset
    local lift = trace(self, origin, attached, mins, maxs)
    if lift.Hit or lift.StartSolid or lift.AllSolid then return false end
    local clear = trace(self, attached, attached, low, high)
    if clear.StartSolid or clear.AllSolid then return false end
    local sequence = self:LookupSequence(config.sequence)
    if not sequence or sequence < 0 then return false end
    self:AISuspendActions(now)
    self:StopCurrentSchedule()
    if self.CurrentSchedule then return false end
    self:StopMoving()
    self:ClearGoal()
    self:ResetTurnTarget()
    self:AA_StopMoving()
    self[config.fields.active], budget.actors[self] = action, true
    for _, key in ipairs({"NextChaseTime", "NextIdleTime", "NextDoAnyAttackT", "AttackAnimTime"}) do
        if (self[key] or 0) < action.deadline then action.timers[key], self[key] = self[key] or 0, action.deadline end
    end
    self:DoChangeMovementType(VJ_MOVETYPE_AERIAL)
    self:SetMoveType(MOVETYPE_FLY)
    self:SetMoveCollide(MOVECOLLIDE_FLY_SLIDE)
    self:SetPos(attached)
    self:SetCollisionBounds(low, high)
    action.low, action.high = low, high
    action.progress = attached
    self:SetGroundEntity(NULL)
    self:SetState(VJ_STATE_ONLY_ANIMATION_CONSTANT)
    self.AttackType, self.AttackState, self.AttackSeed = VJ.ATTACK_TYPE_CUSTOM, VJ.ATTACK_STATE_STARTED, action.seed
    self:PlaySequence(sequence)
    self:SetPlaybackRate(1, true)
    action.sequence = sequence
    return true
end

function methods:AIUpdateSurface(now)
    local action = self:AISurfaceActive()
    if not action then return false end
    local config = self:AIProfile().surface
    if not allowed(self, config) or self.VJ_Controlled or self.AttackType ~= VJ.ATTACK_TYPE_CUSTOM
        or self.AttackSeed ~= action.seed or self:GetState() ~= VJ_STATE_ONLY_ANIMATION_CONSTANT
        or self:GetMoveType() ~= MOVETYPE_FLY or self.MovementType ~= VJ_MOVETYPE_AERIAL
        or self:GetSequence() ~= action.sequence or self.CurrentSchedule
        or not IsValid(action.target) or action.target:Health() <= 0 or self:GetEnemy() ~= action.target then
        self:AIEndSurface(now, "interrupted") return false
    end
    local ignored = GetConVar("ai_ignoreplayers")
    if action.target:IsPlayer() and ignored and ignored:GetBool() then self:AIEndSurface(now, "ignored") return false end
    if now >= action.deadline then self:AIEndSurface(now, "timeout") return false end
    if action.angle then
        self:SetAngles(LerpAngle(math.min(FrameTime() * 12, 1), self:GetAngles(), action.angle))
    end
    if now < action.next_probe then return true end
    action.next_probe = now + 0.1
    if not reserve(5, now, false) then
        self:SetLocalVelocity(ZERO) -- Never travel blindly when the probe budget is exhausted.
        return true
    end
    local position, normal = self:GetPos(), action.normal
    if position:DistToSqr(action.progress) > 12 * 12 then action.progress, action.progress_at = Vector(position), now end
    if now - action.progress_at > 1.2 then self:AIEndSurface(now, "stalled") return false end
    if action.edge then return roundEdge(self, action, config, now) end
    if normal.z > 0.7 and attackRange(self, action.target, config) then
        self:AIEndSurface(now, "attack_range") return false
    end
    local toward = action.target:WorldSpaceCenter() - self:WorldSpaceCenter()
    if toward:LengthSqr() > ((config.range or 1200) * 1.25) ^ 2 then self:AIEndSurface(now, "target_range") return false end
    if normal.z < -0.7 and toward.z < -48 and toward.x * toward.x + toward.y * toward.y < 100 * 100 then
        self:AIEndSurface(now, "drop_to_target") return false
    end
    local direction = project(toward, normal)
    if normal.z > 0.7 and direction:LengthSqr() < 1 then direction = project(self:GetForward(), normal) end
    if math.abs(normal.z) < 0.5 then
        -- Retain the chosen climb direction instead of reversing above the
        -- target and repeatedly oscillating up/down the same obstruction.
        direction = project(Vector(toward.x, toward.y, action.climb_sign * math.max(math.abs(toward.z), 160)), normal)
    end
    if direction:LengthSqr() < 1 then self:AIEndSurface(now, "no_direction") return false end
    direction = direction:GetNormalized()
    local low, high, offset = hull(action, normal)
    local support = trace(self, position + normal * 8, position - normal * (offset + 38))
    if not usable(support) then self:AIEndSurface(now, "lost_support") return false end
    local ahead = position + direction * (config.speed * 0.12 + 12)
    local front = trace(self, position, ahead, low, high)
    local nextNormal = normal
    local concave = false
    if usable(front) and front.HitNormal:Dot(normal) < 0.7 then
        nextNormal = front.HitNormal:GetNormalized()
        concave = true
    elseif front.StartSolid or front.AllSolid then
        self:AIEndSurface(now, "blocked") return false
    else
        local future = trace(self, ahead + normal * 8, ahead - normal * (offset + 32))
        if usable(future) then
            nextNormal = future.HitNormal:GetNormalized()
        else
            -- One bounded convex-edge probe. No radial search or retry fan.
            local outside = ahead - normal * (offset + 16)
            local edge = trace(self, outside, outside - direction * 64)
            if usable(edge) then
                nextNormal = edge.HitNormal:GetNormalized()
                if nextNormal:Dot(normal) < -0.1 then self:AIEndSurface(now, "sharp_edge") return false end
                action.edge = {normal = nextNormal, point = edge.HitPos, deadline = now + 0.8}
                return roundEdge(self, action, config, now)
            else self:AIEndSurface(now, "edge") return false end
        end
    end
    if nextNormal:Dot(normal) < -0.1 then self:AIEndSurface(now, "sharp_edge") return false end
    if nextNormal:Dot(normal) < 0.99 then
        direction = project(direction, nextNormal):GetNormalized()
        if direction:LengthSqr() < 0.1 then direction = project(concave and normal or -normal, nextNormal):GetNormalized() end
        if not changeSurface(self, action, nextNormal, direction) then self:AIEndSurface(now, "corner_clearance") return false end
    end
    action.angle = direction:AngleEx(action.normal)
    local distance = (position - support.HitPos):Dot(normal)
    local adhesion = nextNormal:Dot(normal) >= 0.99 and normal * math.Clamp((offset - distance) * 8, -100, 100) or ZERO
    self:SetLocalVelocity(direction * config.speed + adhesion)
    return true
end

return methods
