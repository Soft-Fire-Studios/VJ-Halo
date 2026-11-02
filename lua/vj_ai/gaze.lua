-- Server head poses, independent of VJ weapon aim and native CAP_TURN_HEAD.
-- Control rules adapted from Valve Source SDK 2013 CAI_BaseActor:
-- UpdateHeadControl, HeadTargetValidity and RangeCompressor (be57e3d).
-- The body frame and fixed model-local origin replace attachment feedback;
-- scene flexes, body turning, eye targets and bone manipulation are excluded.
local methods = {}
local voiceFields = {"CurrentSpeechSound", "CurrentIdleSound", "CurrentExtraSpeechSound"}

local function profile(actor)
    local settings = actor.AIProfile and actor:AIProfile()
    return settings and settings.gaze
end

function methods:AIReleaseGaze()
    local config = profile(self)
    local state = config and self[config.fields.active]
    if not state then return end
    -- OnRemove can run after the engine has discarded its studio/pose state.
    -- Release Lua ownership first; missing engine values are not zero poses.
    self[config.fields.active] = nil
    if not IsValid(self) then return end
    if self:GetModel() == state.model then
        for name, amount in pairs(state.written or {}) do
            local current = self:GetPoseParameter(name)
            if type(current) == "number" and math.abs(current - amount) < 0.01 then
                self:SetPoseParameter(name, 0)
            end
        end
    end
    -- Preserve replacement aim arrays. Never restore the conflicting native
    -- head writer; remove only capability bits added by the retired bridge.
    if self.PoseParameterLooking_Names == state.filtered then self.PoseParameterLooking_Names = state.names end
    if state.added_caps and state.added_caps ~= 0 then self:CapabilitiesRemove(state.added_caps) end
    self:CapabilitiesRemove(CAP_TURN_HEAD)
    self[config.fields.active] = nil
end

function methods:AIPrepareGaze()
    if CLIENT then return end
    local config = profile(self)
    if not config then return end
    if self.Dead or self:Health() <= 0 or not self:AIHasCapability("gaze") then
        self:AIReleaseGaze()
        return
    end
    local rig = type(config.rig) == "function" and config.rig(self) or config.rig
    if not rig or (rig.model and rig.model ~= self:GetModel()) then self:AIReleaseGaze() return end
    -- VJ can re-add default capabilities during initialization/possession.
    if bit.band(self:CapabilitiesGet(), CAP_TURN_HEAD) ~= 0 then self:CapabilitiesRemove(CAP_TURN_HEAD) end
    local state = self[config.fields.active]
    if state and (state.model ~= self:GetModel() or state.rig ~= rig or state.mode ~= "pose") then self:AIReleaseGaze() state = nil end
    if not state then
        state = {mode = "pose", model = self:GetModel(), rig = rig, owned_poses = {}, controls = {}, written = {}}
        local origin = rig.origin or {0, 0, 0}
        state.origin = Vector(origin[1], origin[2], origin[3])
        self[config.fields.active] = state
        for axis, name in pairs(rig.poses or {}) do
            local index = self:LookupPoseParameter(name)
            if index >= 0 then
                local low, high = self:GetPoseParameterRange(index)
                if type(low) == "number" and type(high) == "number" and high > low then
                    state.owned_poses[name] = true
                    state.controls[axis] = {name = name, low = low, high = high,
                        value = math.Clamp(self:GetPoseParameter(name) or 0, low, high)}
                end
            end
        end
        state.pose_control = next(state.controls) ~= nil
    end
    -- VJ auto-discovers head and weapon poses into one table. Copy once per
    -- discovery/reload, never mutate the class/shared table or the aim entries.
    -- A parameter named head_pitch may actually be a weapon-aim control on a
    -- different rig. Only remove parameters assigned to this gaze controller.
    local namesChanged = self.PoseParameterLooking_Names ~= state.filtered
    if not namesChanged then
        -- VJ discovers pose names in a delayed initializer and appends in place.
        -- A stable table identity therefore does not imply discovery is finished.
        for _, names in pairs(self.PoseParameterLooking_Names or {}) do
            for _, name in ipairs(names) do
                if state.owned_poses[name] then namesChanged = true break end
            end
            if namesChanged then break end
        end
    end
    if namesChanged then
        state.names = self.PoseParameterLooking_Names
        local filtered = {}
        for axis, names in pairs(state.names or {}) do
            filtered[axis] = {}
            for _, name in ipairs(names) do
                if not state.owned_poses[name] then
                    filtered[axis][#filtered[axis] + 1] = name
                end
            end
        end
        state.filtered = filtered
        self.PoseParameterLooking_Names = filtered
    end
    return config, state
end

-- VJ calls OnCreateSound after PlayEx, before assigning its current voice field.
-- Record that start once; IsPlaying can remain true after a one-shot OGG ends.
function methods:AIObserveGazeSound(handle, path, now)
    local config = profile(self)
    if not config or not config.mouth or not handle or type(path) ~= "string" then return end
    local _, state = self:AIPrepareGaze()
    if not state then return end
    local duration = self:AISoundDuration(path)
    if duration <= 0 then return end
    local pitch = handle.GetPitch and handle:GetPitch() or 100
    if pitch <= 0 then return end
    state.voices = state.voices or setmetatable({}, {__mode = "k"})
    state.voices[handle] = {start = now, finish = now + duration * 100 / pitch, path = path}
end

local function writePose(actor, state, name, amount)
    local current = actor:GetPoseParameter(name)
    if type(current) ~= "number" then return end
    if math.abs(current - amount) > 0.025 or (amount == 0 and current ~= 0) then
        actor:SetPoseParameter(name, amount)
        state.written[name] = amount
    end
end

local function approach(current, desired, speed, dt)
    return current + math.Clamp(desired - current, -speed * dt, speed * dt)
end

local function edgeLimit(value, low, high)
    -- Valve's Hermite edge curve, applied separately on either side of neutral.
    -- Without the engine's animated attachment bias, centering an asymmetric
    -- range at its midpoint would pull even tiny requests away from zero.
    if high <= low or value == 0 or (value < 0 and low >= 0) or (value > 0 and high <= 0) then return 0 end
    local limit = value < 0 and -low or high
    local magnitude = math.abs(value) / limit
    if magnitude > 0.75 then
        local x = math.min(1, (magnitude - 0.75) / 1.25)
        magnitude = (2*x^3 - 3*x^2 + 1)*0.75 + (-2*x^3 + 3*x^2) + (x^3 - 2*x^2 + x)*0.75
    end
    return (value < 0 and -1 or 1) * math.min(magnitude, 1) * limit
end

local function pointOf(target)
    return target:IsPlayer() and target:EyePos() or target:WorldSpaceCenter()
end

local function idleTarget(actor, state, now, origin)
    if now < (state.idle_until or 0) then return state.idle_point, state.idle_interest end
    state.idle_until = now + math.Rand(2, 4)
    state.idle_interest = math.Rand(0.3, 0.5) -- Valve idle target influence.
    local best, nearest = nil, 360^2 -- Valve's 30-foot interest radius.
    local ignored = GetConVar("ai_ignoreplayers")
    if not (ignored and ignored:GetBool()) then
        for _, candidate in ipairs(player.GetAll()) do
            if candidate:Alive() and not candidate:IsFlagSet(FL_NOTARGET) then
                local delta = candidate:GetPos() - origin
                local distance = delta:LengthSqr()
                if distance < nearest and delta:Dot(actor:GetForward()) > 0 then best, nearest = candidate, distance end
            end
        end
    end
    -- Snapshot an idle interest point once, not a continuous player/prop scan.
    if best then
        local point = best:EyePos()
        local trace = util.TraceLine({start = origin, endpos = point, mask = MASK_BLOCKLOS, filter = {actor, best}})
        if not trace.Hit and not trace.StartSolid then state.idle_point = point return point, state.idle_interest end
    end
    state.idle_point = actor:LocalToWorld(state.origin + Vector(100, math.Rand(-60, 60), math.Rand(-12, 12)))
    return state.idle_point, state.idle_interest
end

local function headTarget(actor, config, state, now, origin)
    if config.target then return config.target(actor, now) end
    if actor.VJ_Controlled then
        local controller = actor.VJ_Controller
        local target = IsValid(controller) and controller:GetBullseye()
        if IsValid(target) then return target:GetPos(), 1 end
        return
    end
    local enemy = actor:GetEnemy()
    if IsValid(enemy) and enemy:Health() > 0 then
        if enemy ~= state.enemy then
            state.enemy, state.enemy_point, state.next_sample = enemy, nil, 0
        end
        if now >= (state.next_sample or 0) then
            state.next_sample = now + (config.target_interval or 0.1)
            local data = actor.EnemyData
            -- Use VJ's existing visibility result; never sample a hidden
            -- enemy's live position or add a second combat LOS trace.
            if data and data.Visible and (not data.Target or data.Target == enemy) then
                state.enemy_point, state.seen_at = Vector(pointOf(enemy)), now
            end
        end
        if state.enemy_point and now - (state.seen_at or 0) <= (config.memory_time or 0.5) then
            return state.enemy_point, 1
        end
        return
    end
    state.enemy, state.enemy_point = nil, nil
    if config.idle ~= false then return idleTarget(actor, state, now, origin) end
end

local function head(actor, config, state, now, dt)
    if not state.pose_control then return end
    if COND_IN_PVS and actor.HasCondition and not actor:HasCondition(COND_IN_PVS) then return end
    local binding = state.rig.sequences[actor:GetSequenceName(actor:GetSequence())]
    local screen = type(binding) == "string" and state.rig.screens[binding] or binding
    local disabled = GetConVar("ai_disabled")
    local allowed = screen and not actor.AttackType and not actor.Flinching
        and not actor:IsBusy("Activities") and actor:GetState() ~= VJ_STATE_FREEZE
        and not (disabled and disabled:GetBool())
        and (not actor.AILeapActive or not actor:AILeapActive())
        and (not config.allowed or config.allowed(actor, now))
    local yaw, pitch, influence = 0, 0, 0
    if allowed then
        local origin = actor:LocalToWorld(state.origin)
        local point, interest = headTarget(actor, config, state, now, origin)
        if point then
            -- Translation only comes from the fixed anatomical origin. The
            -- model's entity frame supplies axes, never an animated head frame.
            local delta = actor:WorldToLocal(point) - state.origin
            local horizontal = math.sqrt(delta.x^2 + delta.y^2)
            local length = delta:Length()
            if horizontal > 1 and length > 0 then
                local forward = delta.x / length
                influence = (interest or 1) * math.Clamp(3.4142 * (1 + forward), 0, 1)
                influence = influence * math.Clamp((horizontal - 1) / 9, 0, 1)
                -- Valve reduces vertical demand and head influence behind us.
                delta.z = delta.z * math.Clamp(forward, 0.1, 1)
                delta:Normalize()
                influence = influence * math.Clamp(delta.x * 2 + 2, 0, 1)
                local angles = delta:Angle()
                yaw, pitch = math.NormalizeAngle(angles.y), math.NormalizeAngle(angles.p)
            end
        end
    else
        state.enemy_point, state.idle_point, state.idle_until = nil, nil, nil
    end
    -- Valve decays prior correction by .8 and debounces new demand by .3.
    -- Convert its nominal 0.1-second steps to elapsed-time coefficients.
    local step = dt / 0.1
    local blend = 0.7 * math.Clamp(influence, 0, 1)
    local retained = 0.8 * (1 - blend)
    local decay = retained ^ step
    local gain = blend * (1 - decay) / (1 - retained)
    for axis, control in pairs(state.controls) do
        local desired = axis == "yaw" and yaw or axis == "pitch" and pitch or 0
        if screen then
            desired = desired * ((screen.response_sign or {})[axis] or 1)
            local range = screen[axis] or {control.low, control.high}
            desired = edgeLimit(desired, math.max(range[1], control.low), math.min(range[2], control.high))
        end
        local previous = control.value
        local target = previous * decay + desired * gain
        control.value = approach(previous, target, axis == "yaw" and 300 or 100, dt)
        control.value = math.Clamp(control.value, control.low, control.high)
        if math.abs(control.value) < 0.025 then control.value = 0 end
        writePose(actor, state, control.name, control.value)
    end
end

local function mouth(actor, config, state, now, dt)
    local control = config.mouth
    if not control then return end
    local name = control.parameter or "mandibles"
    if state.mouth_index == nil then state.mouth_index = actor:LookupPoseParameter(name) end
    if state.mouth_index < 0 then return end
    local sound, voice
    -- VJ separates idle/combat chatter from alert/pain speech. These are voice
    -- channels, not footstep, weapon or equipment sound handles.
    for _, field in ipairs(voiceFields) do
        local candidate = actor[field]
        local record = candidate and state.voices and state.voices[candidate]
        if record and now < record.finish and candidate:IsPlaying() then
            sound, voice = candidate, record
            break
        end
    end
    local speaking = not actor.Dead and actor:Health() > 0 and actor.HasSounds ~= false
        and sound and sound:IsPlaying()
    state.speech = sound
    local desired = 0
    if speaking then
        -- Two authored jaw endpoints, varied within the actual playing window.
        -- This is restrained speech motion, not invented phoneme/lip-sync data.
        local elapsed = now - voice.start
        desired = (0.5 + 0.5 * math.sin(elapsed * 23)) * (0.35 + 0.25 * math.sin(elapsed * 9 + 1))
        desired = desired * math.min(1, elapsed / 0.08) * (control.amount or 1)
    end
    state.mouth = approach(state.mouth or 0, desired, control.speed or 6, dt)
    writePose(actor, state, name, state.mouth)
end

function methods:AIUpdateGaze(now)
    local config, state = self:AIPrepareGaze()
    if not state then return end
    local interval = config.interval or 0.05
    if now + 0.000001 < (state.next_update or 0) then return end
    local dt = math.Clamp(now - (state.clock or now - interval), 0, 0.15)
    state.clock, state.next_update = now, now + interval
    head(self, config, state, now, dt)
    mouth(self, config, state, now, dt)
end

return methods
