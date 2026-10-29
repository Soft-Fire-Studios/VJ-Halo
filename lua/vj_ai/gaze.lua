-- Source owns head turning; VJ owns weapon aim. This bridge separates their
-- pose lists and drives skeletal speech from the existing voice sound handles.
local methods = {}
local voiceFields = {"CurrentSpeechSound", "CurrentIdleSound", "CurrentExtraSpeechSound"}

local function profile(actor)
    local settings = actor.AIProfile and actor:AIProfile()
    return settings and settings.gaze
end

local function closeAngles(a, b)
    if not a or not b then return false end
    return math.abs(math.AngleDifference(a.p, b.p)) < 0.01
        and math.abs(math.AngleDifference(a.y, b.y)) < 0.01
        and math.abs(math.AngleDifference(a.r, b.r)) < 0.01
end

local function restoreBones(actor, state)
    if actor:GetModel() ~= state.model then return end
    for _, bone in ipairs(state.bones or {}) do
        if bone.written and closeAngles(actor:GetManipulateBoneAngles(bone.id), bone.written) then
            actor:ManipulateBoneAngles(bone.id, bone.original)
        end
        bone.written = nil
    end
end

function methods:AIReleaseGaze()
    local config = profile(self)
    local state = config and self[config.fields.active]
    if not state then return end
    -- OnRemove can run after the engine has discarded its studio/pose state.
    -- Release Lua ownership first; missing engine values are not zero poses.
    self[config.fields.active] = nil
    if not IsValid(self) then return end
    restoreBones(self, state)
    if self:GetModel() == state.model then
        for name, amount in pairs(state.written) do
            local current = self:GetPoseParameter(name)
            if type(current) == "number" and math.abs(current - amount) < 0.01 then
                self:SetPoseParameter(name, 0)
            end
        end
    end
    -- Preserve a replacement writer's arrays and engine capability changes.
    if self.PoseParameterLooking_Names == state.filtered then self.PoseParameterLooking_Names = state.names end
    if state.native_head and not self.Dead then self:CapabilitiesAdd(CAP_TURN_HEAD) end
    if state.added_caps and state.added_caps ~= 0 then self:CapabilitiesRemove(state.added_caps) end
    self[config.fields.active] = nil
end

function methods:AIPrepareGaze()
    local config = profile(self)
    if not config then return end
    if self.Dead or self:Health() <= 0 or not self:AIHasCapability("gaze") then
        self:AIReleaseGaze()
        return
    end
    local rig = type(config.rig) == "function" and config.rig(self) or config.rig
    if not rig or (rig.model and rig.model ~= self:GetModel()) then self:AIReleaseGaze() return end
    local state = self[config.fields.active]
    if state and (state.model ~= self:GetModel() or state.rig ~= rig or state.mode ~= "native") then self:AIReleaseGaze() state = nil end
    if not state then
        state = {mode = "native", model = self:GetModel(), rig = rig, owned_poses = {}, written = {}}
        self[config.fields.active] = state
        for _, name in pairs(rig.poses or {}) do
            if self:LookupPoseParameter(name) >= 0 then state.owned_poses[name] = true end
        end
        -- These rigs already expose independent head parameters. The engine
        -- supplies target selection and head motion; Lua never writes them.
        state.native_control = state.owned_poses.head_yaw or state.owned_poses.head_pitch or false
        if state.native_control then
            local eyes, forward = self:LookupAttachment("eyes"), self:LookupAttachment("forward")
            if eyes > 0 and forward > 0 then
                local wanted = bit.bor(CAP_TURN_HEAD, CAP_ANIMATEDFACE)
                state.added_caps = bit.band(wanted, bit.bnot(self:CapabilitiesGet()))
                self:CapabilitiesAdd(wanted)
            end
        end
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
    -- Some Flood libraries currently have only weapon-coupled head_pitch.
    -- Do not let native head control steal that aim parameter. They need model
    -- head blends before enabling the capability, not another Lua look solver.
    if not state.native_control and bit.band(self:CapabilitiesGet(), CAP_TURN_HEAD) ~= 0 then
        state.native_head = true
        self:CapabilitiesRemove(CAP_TURN_HEAD)
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
    if now < (state.next_update or 0) then return end
    local dt = math.Clamp(now - (state.clock or now - interval), 0, 0.15)
    state.clock, state.next_update = now, now + interval
    mouth(self, config, state, now, dt)
end

return methods
