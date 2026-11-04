-- Opt-in custom attack, entered through VJ OnThinkAttack and serviced by OnThink.
-- Navigation remains VJ-owned. Only the bounded flight uses Source fly-gravity
-- physics: this preserves swept collisions and excludes ground AutoMovement.
local methods = {}
local timers = {"AttackAnimTime", "AnimLockTime", "NextChaseTime", "NextIdleTime", "NextDoAnyAttackT"}

local function disabled(actor)
    local setting = GetConVar("ai_disabled")
    return actor.Dead or actor:Health() <= 0 or (setting and setting:GetBool())
        or actor:GetState() == VJ_STATE_FREEZE or actor.Flinching
end

local function sequence(actor, name)
    if not name then return end
    local id = actor:LookupSequence(name)
    if id and id >= 0 then return id, actor:SequenceDuration(id) end
end

local function play(actor, action, name, now)
    local id, duration = sequence(actor, name)
    if not id then return false end
    actor:PlaySequence(id) -- Does not StopMoving or clear a flight velocity.
    actor:SetPlaybackRate(1, true)
    action.sequence, action.phase_end = id, now + duration
    return true
end

local function ownsLayer(actor, action)
    return action.layer and actor:IsValidLayer(action.layer)
        and actor:GetLayerSequence(action.layer) == action.melee_sequence
end

function methods:AILeapActive()
    local config = self.AIProfile and self:AIProfile().leap
    local control = self.AIProfile and self:AIProfile().possession
    return (config and self[config.fields.active]) or (control and self[control.fields.jump]) or nil
end

-- Cover discovery is optional and finite. This shared budget includes the
-- support, clearance and ballistic sweeps, including a takeoff recheck.
VJAI.CoverLeapBudget = VJAI.CoverLeapBudget or {used = 0}
local function coverTrace(request, hull)
    local budget, tick = VJAI.CoverLeapBudget, engine.TickCount()
    if budget.tick ~= tick then budget.tick, budget.used = tick, 0 end
    if budget.used >= 64 then return end
    budget.used = budget.used + 1
    return hull and util.TraceHull(request) or util.TraceLine(request)
end

function methods:AICoverTrace(request, hull)
    return coverTrace(request, hull)
end

local function stableSupport(trace)
    if not trace or not trace.Hit or trace.StartSolid or trace.AllSolid or trace.HitSky
        or trace.HitNormal.z < 0.7 then return false end
    if trace.HitWorld then return true end
    local prop = trace.Entity
    if not IsValid(prop) or prop:IsNPC() or prop:IsPlayer() or prop:IsNextBot() or prop:IsVehicle()
        or prop.VJ_ID_Living or prop.VJ_ID_Grenade or prop.VJ_ID_Danger
        or prop:GetMoveType() ~= MOVETYPE_VPHYSICS or IsValid(prop:GetParent()) or prop:IsPlayerHolding() then return false end
    local physics = prop:GetPhysicsObject()
    return IsValid(physics) and not physics:IsMotionEnabled()
end

local function coverSupport(actor, position, support, world, config)
    local mins, maxs = actor:GetCollisionBounds()
    local filter = {actor}
    local weapon = actor.GetActiveWeapon and actor:GetActiveWeapon()
    if IsValid(weapon) then filter[#filter + 1] = weapon end
    -- A thin lip can collide with a hull without supporting its footprint.
    -- Require the center and all four corners on the same stable top.
    for _, offset in ipairs({Vector(), Vector(mins.x, mins.y, 0), Vector(mins.x, maxs.y, 0),
        Vector(maxs.x, mins.y, 0), Vector(maxs.x, maxs.y, 0)}) do
        local trace = coverTrace({start = position + offset + Vector(0, 0, 4),
            endpos = position + offset - Vector(0, 0, 8), mask = MASK_NPCSOLID,
            filter = filter, collisiongroup = config.collision_group})
        if not stableSupport(trace) or (world and not trace.HitWorld)
            or (not world and trace.Entity ~= support) or math.abs(trace.HitPos.z - (position.z - 2)) > 3 then return false end
    end
    local clear = coverTrace({start = position, endpos = position, mins = mins, maxs = maxs,
        mask = MASK_NPCSOLID, filter = filter, collisiongroup = config.collision_group}, true)
    return clear and not clear.Hit and not clear.StartSolid and not clear.AllSolid
end

local function planArc(actor, destination, config, target, cover)
    local origin = actor:GetPos()
    local delta = destination - origin
    local distance = math.sqrt(delta.x * delta.x + delta.y * delta.y)
    if cover and (distance < config.minimum or distance > config.maximum or math.abs(delta.z) > (config.max_height or 128)) then return end
    local duration = math.Clamp(distance / config.speed, config.min_time or 0.35, config.max_time or 1.5)
    local gravity = GetConVar("sv_gravity"):GetFloat()
    local scale = actor:GetGravity()
    if scale == 0 then scale = 1 end
    gravity = gravity * scale
    if gravity <= 0 then return end
    local velocity = Vector(delta.x / duration, delta.y / duration, delta.z / duration + gravity * duration * 0.5)
    local mins, maxs = actor:GetCollisionBounds()
    local previous = origin + Vector(0, 0, 1)
    for i = 1, 12 do
        local t = duration * i / 12
        local point = origin + velocity * t - Vector(0, 0, gravity * t * t * 0.5)
        local request = {start = previous, endpos = point, mins = mins, maxs = maxs,
            mask = MASK_NPCSOLID, filter = actor, collisiongroup = config.collision_group}
        local trace
        if cover then trace = coverTrace(request, true) else trace = util.TraceHull(request) end
        if not trace or trace.StartSolid or trace.AllSolid then return end
        if trace.Hit then
            if target and trace.Entity == target then break end
            if i ~= 12 or trace.HitNormal.z < 0.7 then return end
        end
        previous = point
    end
    return {velocity = velocity, duration = duration, destination = Vector(destination)}
end

-- Solve once for a visible target. No homing, position teleport, or target
-- tracking during flight. Both the landing floor and sampled hull arc must fit.
function methods:AIPlanLeap(target, config)
    if not IsValid(target) or target:Health() <= 0 then return end
    local origin, destination = self:GetPos(), target:GetPos()
    local delta = destination - origin
    local distance = math.sqrt(delta.x * delta.x + delta.y * delta.y)
    if distance < config.minimum or distance > config.maximum or math.abs(delta.z) > (config.max_height or 128) then return end
    local ground = util.TraceLine({start = destination + Vector(0, 0, 48), endpos = destination - Vector(0, 0, 128),
        mask = MASK_NPCSOLID, filter = {self, target}, collisiongroup = config.collision_group})
    if ground.StartSolid or not ground.Hit or ground.HitSky or ground.HitNormal.z < 0.7 then return end
    return planArc(self, ground.HitPos + Vector(0, 0, 2), config, target)
end

function methods:AIPlanCoverLeap(cover, config)
    if not coverSupport(self, cover.position, cover.support, cover.world, config) then return end
    return planArc(self, cover.position, config, nil, true)
end

function methods:AIProbeCover(now, aim, settings, obstruction)
    local config = self.AIProfile and self:AIProfile().leap
    if not self:AIHasCapability("leap") or not config.cover or not config.cover.enabled then return end
    local field = config.fields.cover_check or "AICoverProbeNext"
    if now < (self[field] or 0) then return end
    self[field] = now + math.max(0.5, settings.interval or 1)
    local origin = self:GetPos()
    local direction = Vector(aim) - origin
    direction.z = 0
    if direction:LengthSqr() < 1 then return end
    direction = direction:GetNormalized()
    if self:GetForward():Dot(direction) < (config.facing or 0.5) then return end
    if not obstruction then
        obstruction = coverTrace({start = self:EyePos(), endpos = aim, filter = self, mask = MASK_NPCSOLID})
    end
    if not obstruction or obstruction.StartSolid or obstruction.AllSolid or obstruction.HitSky then return end
    local mins, maxs = self:GetCollisionBounds()
    local width = math.max(maxs.x - mins.x, maxs.y - mins.y)
    local point = obstruction.Hit and obstruction.HitPos or aim - direction * (width * 2)
    local height = math.min(settings.maximum_height or 128, config.max_height or 128)
    for index = 1, math.Clamp(settings.probes or 3, 1, 3) do
        local above = point + direction * (width * 0.75 + (index - 1) * (settings.depth or 48))
        above.z = origin.z + height + 8
        local top = coverTrace({start = above,
            endpos = Vector(above.x, above.y, origin.z + (settings.minimum_height or 24)),
            mask = MASK_NPCSOLID, filter = self, collisiongroup = config.collision_group})
        if stableSupport(top) and top.HitPos.z - origin.z <= height then
            local cover = {position = top.HitPos + Vector(0, 0, 2), support = top.Entity, world = top.HitWorld == true}
            if self:AIPlanCoverLeap(cover, config) then return cover end
        end
    end
end

function methods:AITryCoverLeap(now, cover, enemy, search)
    local config = self.AIProfile and self:AIProfile().leap
    if not cover or not self:AIHasCapability("leap") or not config.cover or not config.cover.enabled
        or self.VJ_Controlled or self:AILeapActive() or self:AISurfaceActive() or disabled(self)
        or self.AttackType or self.PauseAttacks or not self:OnGround() or self:GetNavType() ~= NAV_GROUND
        or self:GetMoveType() ~= MOVETYPE_STEP or self:GetState() ~= VJ_STATE_NONE or self:IsBusy("Activities")
        or self.IsGuard or self.IsFollowing or self.DisableChasingEnemy or self.DisableWandering
        or now < (self[config.fields.next_attempt] or 0) or (config.allowed and not config.allowed(self)) then return false end
    if not sequence(self, config.airborne) or (config.start and not sequence(self, config.start))
        or (config.start and not self:AIValidateMotion(config.start, 0)) then return false end
    cover.search, cover.enemy = search, enemy
    return self:AICommitLeap(now, nil, config, false, cover)
end

-- Source mapping for the native perch switch: a visible elevated opponent
-- can expose a nearby stable top. No scan, artificial perch pose or new route.
function methods:AITryPerch(now, enemy)
    local config = self.AIProfile and self:AIProfile().leap
    local settings = config and config.cover
    if not settings or not settings.enabled or not settings.perch or not self:AIHasCapability("leap")
        or self:AILeapActive() or self.VJ_Controlled or not IsValid(enemy) or enemy:Health() <= 0
        or self:CheckRelationship(enemy) ~= D_HT or not self:Visible(enemy) or disabled(self)
        or self.AttackType or self.PauseAttacks or not self:OnGround()
        or self.IsGuard or self.IsFollowing or self.DisableChasingEnemy or self.DisableWandering
        or (config.allowed and not config.allowed(self)) then return false end
    local ignored = GetConVar("ai_ignoreplayers")
    if enemy:IsPlayer() and ignored and ignored:GetBool() then return false end
    local field = config.fields.perch_check or "AIPerchNext"
    if now < (self[field] or 0) or now < (self[config.fields.next_attempt] or 0) then return false end
    self[field] = now + math.max(1, settings.interval or 2)
    local target = Vector(enemy:GetPos())
    if target.z - self:GetPos().z < (settings.minimum_height or 24) then return false end
    return self:AITryCoverLeap(now, self:AIProbeCover(now, target, settings), enemy)
end

function methods:AIEndLeap(now, reason)
    local config = self.AIProfile and self:AIProfile().leap
    local action = self:AILeapActive()
    if not action then return end
    config = action.config or config
    self[action.field or config.fields.active] = nil
    self[action.next_field or config.fields.next_attempt] = now + (config.cooldown or 2)
    if ownsLayer(self, action) then self:RemoveLayer(action.layer) end
    -- A death/freeze/other attack can supersede our state. Release only values
    -- still owned by this attack, preserving newer schedules and locks.
    if action.physics and self:GetMoveType() == MOVETYPE_FLYGRAVITY then
        self:SetMoveType(action.move_type)
        self:SetMoveCollide(action.move_collide)
        if action.had_fly then self:AddFlags(FL_FLY) end
    end
    local replacement = self.AttackType and (self.AttackType ~= VJ.ATTACK_TYPE_CUSTOM or self.AttackSeed ~= action.seed)
    if not replacement and self:GetState() == VJ_STATE_ONLY_ANIMATION_CONSTANT then self:SetState(action.state) end
    if self.AttackType == VJ.ATTACK_TYPE_CUSTOM and self.AttackSeed == action.seed then
        self.AttackType, self.AttackState, self.AttackSeed = VJ.ATTACK_TYPE_NONE, VJ.ATTACK_STATE_DONE, 0
    end
    for key, previous in pairs(action.timers) do
        if self[key] == action.deadline then self[key] = math.max(now, previous) end
    end
    self[action.last_field or config.fields.last] = {time = now, reason = reason}
    if config.finished then config.finished(self, action, now, reason) end
end

function methods:AILaunchLeap(action, now)
    local config = action.config or self:AIProfile().leap
    -- Recheck after takeoff anticipation: obstacles/targets may have moved.
    local plan
    if action.cover then plan = self:AIPlanCoverLeap(action.cover, config)
    elseif action.manual then plan = self:AIPlanControlLeap(config)
    else plan = self:AIPlanLeap(action.target, config) end
    if not plan then self:AIEndLeap(now, "blocked_takeoff") return false end
    if not play(self, action, config.airborne, now) then self:AIEndLeap(now, "missing_airborne") return false end
    action.phase, action.launched, action.plan = "airborne", now, plan
    action.physics = true
    self:SetMoveType(MOVETYPE_FLYGRAVITY)
    self:SetMoveCollide(MOVECOLLIDE_FLY_SLIDE)
    if action.had_fly then self:RemoveFlags(FL_FLY) end
    self:SetGroundEntity(NULL)
    self:SetLocalVelocity(plan.velocity)
    if config.launched then config.launched(self, action, now) end
    return true
end

function methods:AITryLeap(now, enemy)
    if self.VJ_Controlled and self:AIProfile().possession then return false end
    if not self:AIHasCapability("leap") or self:AILeapActive() or self:AISurfaceActive() or disabled(self) or self.AttackType
        or self.PauseAttacks or not self:OnGround() or self:GetNavType() ~= NAV_GROUND
        or self:GetMoveType() ~= MOVETYPE_STEP or self:GetState() ~= VJ_STATE_NONE or self:IsBusy("Activities") then return false end
    local config = self:AIProfile().leap
    if now < (self[config.fields.next_attempt] or 0) then return false end
    if config.allowed and not config.allowed(self) then return false end
    if self.VJ_Controlled then
        local controller = self.VJ_Controller
        local player = IsValid(controller) and controller:GetPlayer()
        if not IsValid(player) or not player:KeyDown(IN_JUMP) then return false end
    end
    if not IsValid(enemy) or enemy:Health() <= 0 or self:CheckRelationship(enemy) ~= D_HT or not self:Visible(enemy) then return false end
    local ignore = GetConVar("ai_ignoreplayers")
    if enemy:IsPlayer() and ignore and ignore:GetBool() then return false end
    local delta = enemy:GetPos() - self:GetPos()
    delta.z = 0
    if delta:LengthSqr() == 0 or self:GetForward():Dot(delta:GetNormalized()) < (config.facing or 0.5) then return false end
    if not sequence(self, config.airborne) or (config.start and not sequence(self, config.start)) then return false end
    local plan = self:AIPlanLeap(enemy, config)
    if not plan then self[config.fields.next_attempt] = now + 0.5 return false end
    local retry = config.retry or {config.cooldown or 2, config.cooldown or 2}
    self[config.fields.next_attempt] = now + math.Rand(retry[1], retry[2])
    if not self.VJ_Controlled and math.Rand(0, 1) >= (config.chance or 1) then return false end
    if config.start and not self:AIValidateMotion(config.start, 0, enemy) then return false end
    return self:AICommitLeap(now, enemy, config, false)
end

-- Manual possession jumps use the same launch/landing/cleanup as attack leaps.
-- Only takeoff clearance is required: Source swept flight handles walls and
-- landing on intermediate ledges. The chosen impulse never tracks a target.
function methods:AIPlanControlLeap(config)
    local origin = self:GetPos()
    local mins, maxs = self:GetCollisionBounds()
    local filter = {self, self.GetActiveWeapon and self:GetActiveWeapon()}
    for _, part in pairs(config.manual_ignore or {}) do filter[#filter + 1] = part end
    local trace = util.TraceHull({start = origin + Vector(0,0,1),
        endpos = origin + Vector(0,0,math.min(16, config.manual_velocity.z * 0.04)),
        mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = filter,
        collisiongroup = config.collision_group})
    if trace.Hit or trace.StartSolid or trace.AllSolid then return end
    return {velocity = Vector(config.manual_velocity), duration = config.manual_duration}
end

function methods:AIStartControlLeap(now, config)
    if not self.VJ_Controlled or not self:AIProfile().possession or self:AILeapActive()
        or self:AISurfaceActive() or disabled(self) or self.AttackType or self.PauseAttacks
        or self:IsBusy("Activities") or not self:OnGround() or self:GetNavType() ~= NAV_GROUND
        or self:GetMoveType() ~= MOVETYPE_STEP or self:GetState() ~= VJ_STATE_NONE then return false end
    if not sequence(self, config.airborne) or (config.start and not sequence(self, config.start)) then return false end
    if not self:AIPlanControlLeap(config) then return false end
    if config.start and not self:AIValidateMotion(config.start, 0) then return false end
    return self:AICommitLeap(now, nil, config, true)
end

function methods:AICommitLeap(now, enemy, config, manual, cover)
    self:AISuspendActions(now, cover and cover.search)
    self:StopCurrentSchedule()
    if self.CurrentSchedule then return false end -- A completion callback installed a new owner.
    self:StopMoving()
    self:ClearSchedule()
    self:ClearGoal()
    self:ResetTurnTarget()
    self:SetIdealYaw(self:GetAngles().y)
    local control = self:AIProfile().possession
    local action = {manual = manual, config = config, cover = cover,
        field = manual and control.fields.jump or config.fields.active,
        next_field = manual and control.fields.next_jump or config.fields.next_attempt,
        last_field = manual and control.fields.last_jump or config.fields.last, target = enemy, seed = now, state = self:GetState(), phase = "start", timers = {},
        move_type = self:GetMoveType(), move_collide = self:GetMoveCollide(), had_fly = self:IsFlagSet(FL_FLY), controlled = self.VJ_Controlled == true,
        deadline = now + 6, victims = {}}
    self[action.field] = action
    for _, key in ipairs(timers) do
        local previous = self[key] or 0
        if previous < action.deadline then action.timers[key], self[key] = previous, action.deadline end
    end
    self:SetState(VJ_STATE_ONLY_ANIMATION_CONSTANT)
    self.AttackType, self.AttackState, self.AttackSeed = VJ.ATTACK_TYPE_CUSTOM, VJ.ATTACK_STATE_STARTED, action.seed
    if config.started then config.started(self, action, now) end
    if config.start then play(self, action, config.start, now) else self:AILaunchLeap(action, now) end
    return self:AILeapActive() ~= nil
end

function methods:AIUpdateLeap(now)
    local action = self:AILeapActive()
    if not action then return false end
    local config = action.config or self:AIProfile().leap
    if (not action.manual and not self:AIHasCapability("leap")) or disabled(self) or (config.allowed and not config.allowed(self)) or self.AttackType ~= VJ.ATTACK_TYPE_CUSTOM
        or self.AttackSeed ~= action.seed or self.PauseAttacks or self:GetState() ~= VJ_STATE_ONLY_ANIMATION_CONSTANT
        or (action.physics and self:GetMoveType() ~= MOVETYPE_FLYGRAVITY)
        or (self.VJ_Controlled == true) ~= action.controlled or self:GetSequence() ~= action.sequence
        or (self.CurrentSchedule and not self:IsScheduleFinished(self.CurrentSchedule)) then
        self:AIEndLeap(now, "interrupted") return false
    end
    if action.cover then
        local enemy = action.cover.enemy
        if not config.cover or not config.cover.enabled
            or self.IsGuard or self.IsFollowing or self.DisableChasingEnemy or self.DisableWandering
            or not IsValid(enemy) or enemy ~= self:GetEnemy() or enemy:Health() <= 0 then
            self:AIEndLeap(now, "interrupted") return false
        end
        local search = action.cover.search
        local searchConfig = self:AIProfile().search
        if search and (not self:AIHasCapability("search") or not searchConfig or self[searchConfig.fields.active] ~= search
            or now >= search.deadline or now >= search.presearch_until or self:Visible(enemy)) then
            self:AIEndLeap(now, "search_ended") return false
        end
    end
    if now >= action.deadline then self:AIEndLeap(now, "timeout") return false end
    if action.phase == "start" then
        if now >= action.phase_end then self:AILaunchLeap(action, now) end
    elseif action.phase == "airborne" then
        local elapsed, velocity = now - action.launched, self:GetVelocity()
        if not action.cover and config.airborne_update then
            config.airborne_update(self, action, now)
            if self:AILeapActive() ~= action then return false end
        end
        local mins, maxs = self:GetCollisionBounds()
        local floor
        if elapsed > 0.08 and velocity.z <= 0 then
            floor = util.TraceHull({start = self:GetPos(), endpos = self:GetPos() - Vector(0, 0, 4),
                mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = self, collisiongroup = config.collision_group})
        end
        if floor and floor.Hit and not floor.StartSolid and floor.HitNormal.z >= 0.7 then
            self:SetMoveType(action.move_type)
            self:SetMoveCollide(action.move_collide)
            if action.had_fly then self:AddFlags(FL_FLY) end
            action.physics = false
            self:SetLocalVelocity(Vector())
            if IsValid(floor.Entity) then self:SetGroundEntity(floor.Entity) end
            if ownsLayer(self, action) then self:RemoveLayer(action.layer) end
            action.layer = nil
            action.phase = "landing"
            if not config.land or not self:AIValidateMotion(config.land, 0, action.target)
                or not play(self, action, config.land, now) then self:AIEndLeap(now, "landed") end
        elseif not action.cover and not action.melee and config.melee and elapsed >= math.max(0, action.plan.duration - (config.contact_time or 0.2) - 0.12) then
            local id = sequence(self, config.melee)
            action.melee = true
            if id then
                -- Native overlays/replacements remain layers over the airborne
                -- base; they do not replace its root or overwrite velocity.
                local layer = self:AddGestureSequence(id, true)
                if layer >= 0 then
                    action.layer, action.melee_at, action.melee_sequence = layer, now, id
                    self:SetLayerPriority(layer, 2)
                    self:SetLayerWeight(layer, 1)
                    self:SetLayerPlaybackRate(layer, 1)
                end
            end
        end
    elseif now >= action.phase_end then self:AIEndLeap(now, "landed") end
    return self:AILeapActive() ~= nil
end

function methods:AILeapContact(eventCycle, eventTime)
    local action = self:AILeapActive()
    if not action or action.phase ~= "airborne" or not ownsLayer(self, action)
        or disabled(self) or self.AttackType ~= VJ.ATTACK_TYPE_CUSTOM or self.AttackSeed ~= action.seed then return false end
    local config = action.config or self:AIProfile().leap
    if type(eventTime) ~= "number" or eventTime < action.melee_at then return false end
    -- Source supplies no layer ID with events. Require our live strike layer
    -- and its authored contact window before allowing aerial damage.
    if type(eventCycle) ~= "number" or eventCycle < config.contact_start - 0.001
        or eventCycle > config.contact_end + 0.001 then return false end
    -- Dispatch reports the event's authored cycle, even if a coarse update has
    -- already advanced the layer beyond its contact window.
    if self:GetLayerCycle(action.layer) < config.contact_start - 0.01 then return false end
    if config.contact then config.contact(self, action) end
    return true
end

return methods
