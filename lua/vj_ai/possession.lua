-- VJ controller extension. Ground navigation stays in Controller_Movement;
-- one input edge owns a crouch toggle or the existing phased flight service.
local methods = {}
local function settings(actor)
    local profile = actor:AIProfile().possession
    if not profile then return end
    return profile, type(profile.settings) == "function" and profile.settings(actor) or profile.settings
end

function methods:AIControlCrouched()
    local config = self:AIProfile().possession
    local state = config and self[config.fields.active]
    return state and state.crouched == true or false
end

function methods:AISetControlCrouch(enabled, force)
    local config, data = settings(self)
    local state = config and self[config.fields.active]
    if not state or enabled == state.crouched then return false end
    if enabled then
        local _, key = self:AIAnimationSet()
        if not data or not data.crouch or not data.crouch.enabled or not data.crouch.sets[key]
            or not self:OnGround() or self.AttackType or self:IsBusy("Activities") then return false end
    end
    local mins, maxs = state.mins, state.maxs
    if enabled then maxs = Vector(maxs.x, maxs.y, math.min(maxs.z, data.crouch.height)) end
    if not force then
        local filter = {self, state.player, self.GetActiveWeapon and self:GetActiveWeapon()}
        for _, part in pairs(config.ignore and config.ignore(self) or {}) do filter[#filter + 1] = part end
        local trace = util.TraceHull({start = self:GetPos() + Vector(0,0,1), endpos = self:GetPos() + Vector(0,0,1),
            mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = filter})
        if trace.Hit or trace.StartSolid or trace.AllSolid then return false end
    end
    self:SetCollisionBounds(mins, maxs)
    state.crouched = enabled
    if not self.AttackType and not self:IsBusy("Activities") then
        self.WeaponAttackAnim = ACT_IDLE_ANGRY
        if self:IsMoving() then self:SetMovementActivity(ACT_WALK)
        else self:SCHEDULE_IDLE_STAND() end
    end
    if config.changed then config.changed(self, state) end
    return true
end

function methods:AIControlJump(now)
    local config, data = settings(self)
    local state = config and self[config.fields.active]
    if not state or state.released or not IsValid(state.player) or not self.VJ_Controlled
        or not data or not data.jump or not data.jump.enabled or self:AILeapActive() or self:AISurfaceActive()
        or now < (self[config.fields.next_jump] or 0) then return false end
    if state.crouched and not self:AISetControlCrouch(false) then return false end
    local jump = data.jump
    local set = self:AIAnimationSet()
    local family = set and (set.family or set.weapon_class)
    local clips = jump.families and (jump.families[family] or jump.families.any)
    local flight = {}
    local original = jump.route == "leap" and self:AIProfile().leap
    if original then for key, item in pairs(original) do flight[key] = item end
    elseif clips then flight.airborne, flight.land = clips.airborne, clips.land
    else return false end
    if flight.allowed and not flight.allowed(self) then return false end
    local player = state.player
    local forward = player:GetAimVector()
    forward.z = 0
    if forward:LengthSqr() < 0.001 then forward = self:GetForward() forward.z = 0 end
    forward:Normalize()
    local right = Vector(forward.y, -forward.x, 0)
    local direction = forward * ((player:KeyDown(IN_FORWARD) and 1 or 0) - (player:KeyDown(IN_BACK) and 1 or 0))
        + right * ((player:KeyDown(IN_MOVERIGHT) and 1 or 0) - (player:KeyDown(IN_MOVELEFT) and 1 or 0))
    if original and direction:LengthSqr() < 0.001 then direction = forward end
    direction:Normalize()
    local speed = jump.horizontal_speed
    if not speed then
        local action = player:KeyDown(IN_SPEED) and "combat_move_front" or "combat_walk_front"
        local name = set and set.sequences[action]
        local id = name and self:LookupSequence(name) or -1
        speed = id >= 0 and self:GetSequenceGroundSpeed(id) or 0
    end
    local gravity = GetConVar("sv_gravity"):GetFloat()
    local scale = self:GetGravity()
    gravity = gravity * (scale == 0 and 1 or scale)
    if gravity <= 0 then return false end
    local up = jump.velocity
    -- Creature-only Infection forms have no native biped impulse. Reuse their
    -- existing leap speed/time envelope instead of inventing a biped value.
    if not up and original then
        local duration = math.Clamp((flight.maximum or flight.speed) / flight.speed, flight.min_time or 0.35, flight.max_time or 1.5)
        up = gravity * duration * 0.5
    end
    if not up or up <= 0 then return false end
    flight.manual_velocity = direction * math.max(0, speed or 0) + Vector(0,0,up)
    flight.manual_duration = 2 * up / gravity
    flight.manual_gravity = gravity
    flight.manual_ignore = config.ignore and config.ignore(self) or nil
    flight.cooldown = math.max(0.25, flight.cooldown or 0.25)
    return self:AIStartControlLeap(now, flight)
end

function methods:AIEndControl(force)
    local config = self:AIProfile().possession
    local state = config and self[config.fields.active]
    if not state then return end
    state.released = true
    local leap = self:AILeapActive()
    if leap and leap.manual then self:AIEndLeap(CurTime(), "possession_ended") end
    local controller = state.controller
    if IsValid(controller) then
        if controller.OnKeyBindPressed == state.key_hook then controller.OnKeyBindPressed = state.previous_key end
        if controller.OnStopControlling == state.stop_hook then controller.OnStopControlling = state.previous_stop end
        if controller.VJC_Player_DrawHUD == false then
            controller.VJC_Player_DrawHUD = state.hud
            if config.stopped then config.stopped(self, state) end
        end
    end
    if state.crouched and not self:AISetControlCrouch(false, force) then return end
    self[config.fields.active] = nil
end

function methods:AIStartControl(player, controller)
    local config, data = settings(self)
    if not config or not data then return end
    self:AIEndControl(true)
    self:AISuspendActions(CurTime())
    self:AIEndSurface(CurTime(), "possessed")
    self:AIEndLeap(CurTime(), "possessed")
    local mins, maxs = self:GetCollisionBounds()
    local state = {controller = controller, player = player, crouched = false,
        mins = Vector(mins), maxs = Vector(maxs), hud = controller.VJC_Player_DrawHUD,
        previous_key = controller.OnKeyBindPressed, previous_stop = controller.OnStopControlling}
    self[config.fields.active] = state
    state.key_hook = function(control, key)
        if state.previous_key then state.previous_key(control, key) end
        if not IsValid(self) or self[config.fields.active] ~= state or self.Dead then return end
        if key == IN_DUCK then self:AISetControlCrouch(not state.crouched)
        elseif key == IN_JUMP then self:AIControlJump(CurTime()) end
    end
    state.stop_hook = function(control, ...)
        if IsValid(self) and self[config.fields.active] == state then self:AIEndControl(self.Dead) end
        if state.previous_stop then state.previous_stop(control, ...) end
    end
    controller.OnKeyBindPressed, controller.OnStopControlling = state.key_hook, state.stop_hook
    if config.started then config.started(self, state) end
end

function methods:AIUpdateControl(now)
    local config, data = settings(self)
    local state = config and self[config.fields.active]
    if not state then return end
    if state.released or not self.VJ_Controlled or not IsValid(state.controller) or not IsValid(state.player) or self.Dead then
        self:AIEndControl(self.Dead)
        return
    end
    if state.crouched then
        local _, key = self:AIAnimationSet()
        if not data.crouch.sets[key] then self:AISetControlCrouch(false) end
    end
    if config.update and now >= (state.next_update or 0) then
        state.next_update = now + 0.1
        config.update(self, state, now)
    end
end

return methods
