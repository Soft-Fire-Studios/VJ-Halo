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
    return config and self[config.fields.active] or nil
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
    destination = ground.HitPos + Vector(0, 0, 2)
    delta = destination - origin
    local duration = math.Clamp(distance / config.speed, config.min_time or 0.35, config.max_time or 1.5)
    local gravity = GetConVar("sv_gravity"):GetFloat()
    local scale = self:GetGravity()
    if scale == 0 then scale = 1 end
    gravity = gravity * scale
    if gravity <= 0 then return end
    local velocity = Vector(delta.x / duration, delta.y / duration, delta.z / duration + gravity * duration * 0.5)
    local mins, maxs = self:GetCollisionBounds()
    local previous = origin + Vector(0, 0, 1)
    for i = 1, 12 do
        local t = duration * i / 12
        local point = origin + velocity * t - Vector(0, 0, gravity * t * t * 0.5)
        local trace = util.TraceHull({start = previous, endpos = point, mins = mins, maxs = maxs,
            mask = MASK_NPCSOLID, filter = self, collisiongroup = config.collision_group})
        if trace.StartSolid or trace.AllSolid then return end
        if trace.Hit then
            if trace.Entity == target then break end
            if i ~= 12 or trace.HitNormal.z < 0.7 then return end
        end
        previous = point
    end
    return {velocity = velocity, duration = duration, destination = destination}
end

function methods:AIEndLeap(now, reason)
    local config = self.AIProfile and self:AIProfile().leap
    local action = config and self[config.fields.active]
    if not action then return end
    self[config.fields.active] = nil
    self[config.fields.next_attempt] = now + (config.cooldown or 2)
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
    self[config.fields.last] = {time = now, reason = reason}
    if config.finished then config.finished(self, action, now, reason) end
end

function methods:AILaunchLeap(action, now)
    local config = self:AIProfile().leap
    -- Recheck after takeoff anticipation: obstacles/targets may have moved.
    local plan = self:AIPlanLeap(action.target, config)
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
    self:AISuspendActions(now)
    self:StopCurrentSchedule()
    if self.CurrentSchedule then return false end -- A completion callback installed a new owner.
    self:StopMoving()
    self:ClearSchedule()
    self:ClearGoal()
    self:ResetTurnTarget()
    self:SetIdealYaw(self:GetAngles().y)
    local action = {target = enemy, seed = now, state = self:GetState(), phase = "start", timers = {},
        move_type = self:GetMoveType(), move_collide = self:GetMoveCollide(), had_fly = self:IsFlagSet(FL_FLY), controlled = self.VJ_Controlled == true,
        deadline = now + 6, victims = {}}
    self[config.fields.active] = action
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
    local config = self:AIProfile().leap
    if not self:AIHasCapability("leap") or disabled(self) or (config.allowed and not config.allowed(self)) or self.AttackType ~= VJ.ATTACK_TYPE_CUSTOM
        or self.AttackSeed ~= action.seed or self.PauseAttacks or self:GetState() ~= VJ_STATE_ONLY_ANIMATION_CONSTANT
        or (action.physics and self:GetMoveType() ~= MOVETYPE_FLYGRAVITY)
        or (self.VJ_Controlled == true) ~= action.controlled or self:GetSequence() ~= action.sequence
        or (self.CurrentSchedule and not self:IsScheduleFinished(self.CurrentSchedule)) then
        self:AIEndLeap(now, "interrupted") return false
    end
    if now >= action.deadline then self:AIEndLeap(now, "timeout") return false end
    if action.phase == "start" then
        if now >= action.phase_end then self:AILaunchLeap(action, now) end
    elseif action.phase == "airborne" then
        local elapsed, velocity = now - action.launched, self:GetVelocity()
        if config.airborne_update then
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
        elseif not action.melee and config.melee and elapsed >= math.max(0, action.plan.duration - (config.contact_time or 0.2) - 0.12) then
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
    local config = self:AIProfile().leap
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
