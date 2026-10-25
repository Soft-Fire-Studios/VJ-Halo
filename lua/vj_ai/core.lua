-- Opt-in behavior services for VJ Human and Creature NPCs.
-- Attach installs methods, not engine hooks, schedules or global Think loops.
VJAI = VJAI or {}
local AI = VJAI
local methods = {}
local bases = {human = "npc_vj_human_base", creature = "npc_vj_creature_base"}
local fields = {
    controller = {next_sample = "AINextActionSample", next_tactic = "AINextTactic",
        spacing = "AISpacing", last_spacing = "AILastSpacing"},
    investigation = {active = "AIInvestigation"},
    obstacle = {active = "AIObstacle", context = "AIObstacleContext", count = "AIObstacleCount",
        next_attempt = "AINextObstacle", next_check = "AINextObstacleCheck", move_intent = "AIMoveIntent", move_time = "AIMoveIntentTime"},
    idle = {active = "AIIdlePose", next_pose = "AINextIdlePose"},
    postcombat = {active = "AIPostCombat", transient_target = "AICorpseShot"},
    charge = {active = "AICharge", next_attempt = "AINextCharge"},
    opening = {active = "AIOpening", last = "AILastOpening", count = "AICoordinatedOpenings"},
    search = {active = "AISearch", seen = "AISeenAim"},
    perception = {mode = "AIPerceptionMode", heard = "AIHeardSounds"},
    flank = {next_check = "AINextFlank", enemy = "AIFlankEnemy", finish = "AIFlankUntil"},
    cover = {active = "AICover", next_attempt = "AINextCover"},
    flee = {active = "AIFlee", next_attempt = "AINextFlee", losses = "AIRecentLosses", last = "AILastFlee"},
    shield = {
        value = "AIShield", clock = "AIShieldClock", recharge_at = "AIShieldRechargeAt",
        breaks = "AIShieldBreaks", recharging = "AIShieldRecharging",
        recharge_sound = "AIShieldRechargeSound", impact_at = "AIShieldImpactAt",
        impact_sound_at = "AIShieldImpactSoundAt"
    },
    dialogue = {
        pending = "AIPendingDialogue", queue = "AIDialogueQueue", dispatch = "AIDialogueDispatch",
        repeats = "AIDialogueRepeat", speech_until = "AISpeechUntil",
        last = "AILastDialogue", counts = "AIDialogueCounts", takes = "AIDialogueTakes", spoken = "AISpokenDialogue"
    },
    footsteps = {attachments = "AIFootAttachments", last_choices = "AIFootstepLast", last = "AILastFootstep"},
    reactions = {kind = "AIReaction", finish = "AIReactionEnd", schedule = "AIReactionSchedule", last = "AILastReaction"},
    evasion = {next_evade = "AINextEvade", aim_started = "AIAimStarted", count = "AIEvades", gunfire_count = "AIGunfireEvades",
        next_gunfire = "AINextGunfireCheck", last_gunfire = "AILastGunfire"}
}

local function value(actor, setting, fallback)
    if type(setting) == "function" then setting = setting(actor) end
    if setting == nil then return fallback end
    return setting
end

local function notify(config, event, actor, ...)
    local callback = config[event]
    if callback then return callback(actor, ...) end
end

local function network(actor, config, kind, amount, integer)
    local name = config.network and config.network[kind]
    if not name then return end
    if integer then actor:SetNW2Int(name, amount) else actor:SetNW2Float(name, amount) end
end

function methods:AIHasCapability(name)
    local profile = self.AIProfile and self:AIProfile()
    return profile and value(self, profile.capabilities[name], false) == true or false
end

function methods:AIBaseCall(name, ...)
    local profile = assert(self.AIProfile and self:AIProfile(), "Missing VJ AI profile")
    local base = baseclass.Get(bases[profile.adapter])
    local method = base and base[name]
    assert(type(method) == "function", "VJ AI adapter has no base method: " .. tostring(name))
    return method(self, ...)
end

function methods:AIInitializeShield(now)
    if not self:AIHasCapability("shield") then return false end
    local config = self:AIProfile().shield
    local state = config.fields
    if self[state.value] ~= nil then return true end
    now = now or CurTime()
    local maximum = math.max(0, value(self, config.maximum, 0))
    self[state.value] = maximum
    self[state.clock], self[state.recharge_at], self[state.breaks] = now, now, 0
    network(self, config, "maximum", maximum)
    network(self, config, "value", maximum)
    return true
end

function methods:AIStopShieldRecharge()
    local config = self.AIProfile and self:AIProfile().shield
    if not config then return end
    local state = config.fields
    local sound = self[state.recharge_sound]
    if sound then
        if config.stop_sound then config.stop_sound(self, sound) else self:StopSound(sound) end
    end
    self[state.recharge_sound], self[state.recharging] = nil, nil
end

function methods:AIUpdateShield(now)
    if not self:AIHasCapability("shield") then
        self:AIStopShieldRecharge()
        local config = self.AIProfile and self:AIProfile().shield
        if config and self[config.fields.clock] ~= nil then self[config.fields.clock] = now end
        return
    end
    self:AIInitializeShield(now)
    local config = self:AIProfile().shield
    local state = config.fields
    local previous = self[state.clock]
    self[state.clock] = now
    if self.Dead or self:Health() <= 0 then self:AIStopShieldRecharge() return end
    local maximum = math.max(0, value(self, config.maximum, 0))
    if self[state.value] >= maximum then return end
    local elapsed = now - math.max(previous, self[state.recharge_at])
    if elapsed <= 0 then return end
    if not self[state.recharging] then
        self[state.recharging] = true
        self[state.recharge_sound] = notify(config, "sound", self, "recharge")
    end
    local rate = maximum / math.max(0.01, value(self, config.recharge_time, 4))
    self[state.value] = math.min(maximum, self[state.value] + elapsed * rate)
    network(self, config, "value", self[state.value])
    notify(config, "regenerated", self, now)
    if self[state.value] >= maximum then notify(config, "effect", self, "recharged") end
end

function methods:AIShieldDamage(damage, hitgroup, now)
    if not self:AIHasCapability("shield") or self.Dead then return 0 end
    local config = self:AIProfile().shield
    if config.accept_damage and not config.accept_damage(self, damage, hitgroup) then return 0 end
    local amount = damage:GetDamage()
    if amount <= 0 then return 0 end
    now = now or CurTime()
    self:AIUpdateShield(now)
    self:AIStopShieldRecharge()
    local state = config.fields
    self[state.recharge_at] = now + value(self, config.recharge_delay, 6)
    local previous = self[state.value]
    notify(config, "before_damage", self, damage, hitgroup, now, previous, amount)
    local resistance = math.max(0.01, value(self, config.resistance, 1))
    local shieldDamage = amount / resistance
    local absorbed = math.min(previous, shieldDamage)
    if absorbed <= 0 then return 0 end
    local blocked = previous >= shieldDamage and amount or absorbed * resistance
    self[state.value] = previous - absorbed
    damage:SetDamage(math.max(0, amount - blocked))
    network(self, config, "value", self[state.value])
    network(self, config, "hit", now)
    if now >= (self[state.impact_at] or 0) then
        if config.effect then
            local position = damage:GetDamagePosition()
            if position:LengthSqr() == 0 then position = self:WorldSpaceCenter() end
            local direction = -damage:GetDamageForce()
            config.effect(self, "impact", position, direction:LengthSqr() > 0 and direction:Angle() or self:GetAngles())
        end
        self[state.impact_at] = now + value(self, config.impact_interval, 0.05)
    end
    if self[state.value] <= 0 then
        self[state.breaks] = self[state.breaks] + 1
        notify(config, "depleted", self, damage, now)
        network(self, config, "breaks", self[state.breaks], true)
        notify(config, "effect", self, "disperse")
        notify(config, "sound", self, "pop")
    elseif now >= (self[state.impact_sound_at] or 0) then
        notify(config, "sound", self, "impact")
        self[state.impact_sound_at] = now + value(self, config.impact_sound_interval, 0.1)
    end
    notify(config, "after_damage", self, damage, hitgroup, now, previous, amount, blocked)
    return blocked
end

-- Called by the host's existing VJ callbacks. These are not engine hooks.
function methods:AIInitialize(now)
    now = now or CurTime()
    self:AIInitializeShield(now)
    local profile = self:AIProfile()
    if self:AIHasCapability("evasion") and self[profile.evasion.fields.count] == nil then
        self[profile.evasion.fields.count] = 0
    end
end

function methods:AIUpdate(now)
    now = now or CurTime()
    local config = self:AIProfile().lifecycle
    if self.AIMotionProfile then
        self:AIAnimateAimTurn(self:AIUpdateAimTurn())
        if self:AIMotionEnabled("grip") then
            local grip = config.grip and config.grip(self)
            self:AIApplyGrip(grip)
        end
    end
    self:AIInitialize(now)
    self:AIUpdateShield(now)
    self:AIThinkDialogue(now)
end

function methods:AIAlert(enemy, now)
    now = now or CurTime()
    local profile = self:AIProfile()
    local search = profile.search and self[profile.search.fields.active]
    local found = search and search.enemy == enemy or false
    local mode = profile.perception and self[profile.perception.fields.mode] or "idle"
    self:AICancelIdle()
    -- The host may use the previous search/perception state for native cues
    -- and surprise policy, before those states are retired.
    if profile.lifecycle.alert then profile.lifecycle.alert(self, enemy, now, found, mode) end
    self:AIEndPostcombat(now)
    self:AIFinishSearch(now, false)
    self:AIFinishInvestigation()
    self:AISetPerception("combat")
end

function methods:AIResetEnemy(now)
    now = now or CurTime()
    self:AIEndCharge(now)
    local profile = self:AIProfile()
    if not self:AIHasCapability("search") then return end
    local enemy = self:GetEnemy()
    local postcombat = profile.postcombat and self[profile.postcombat.fields.active]
    if IsValid(enemy) and enemy:Health() > 0 and not postcombat then self:AIStartSearch(now) end
end

function methods:AIShutdown(now, reason)
    now = now or CurTime()
    self:AISuspendActions(now)
    self:AIStopShieldRecharge()
    local profile = self:AIProfile()
    self:AICancelDialogue()
    if profile.reactions then
        local fields = profile.reactions.fields
        local active = self[fields.kind] ~= nil
        self[fields.kind], self[fields.finish], self[fields.schedule] = nil, nil, nil
        if active and profile.reactions.network then self:SetNW2String(profile.reactions.network, "") end
    end
    if self.AIMotionProfile then
        self:AIClearAimTurn()
        self:AIRestoreAimCone()
    end
    -- Do not stop all speech or destroy a replacement schedule: VJ owns its
    -- death/removal pipeline and the service cleanup only releases owned state.
    if profile.lifecycle.shutdown then profile.lifecycle.shutdown(self, now, reason) end
end

function methods:AITaskFailed(code, message, now)
    local schedule = self.CurrentSchedule
    self:AIBaseCall("OnTaskFailed", code, message)
    now = now or CurTime()
    self:AITryObstacle(now, true)
    -- A successful obstacle reaction owns its replacement schedule.
    if self.CurrentSchedule == schedule then self:AIUpdateSpacing(now, true) end
end

for name, method in pairs(include("vj_ai/audio.lua")) do methods[name] = method end
for name, method in pairs(include("vj_ai/cover.lua")) do methods[name] = method end
for name, method in pairs(include("vj_ai/tactics.lua")) do methods[name] = method end
local actions = include("vj_ai/actions.lua")
for name, method in pairs(actions.methods) do methods[name] = method end
AI.RecordGunfire, AI.ObserveBullet = actions.RecordGunfire, actions.ObserveBullet

function AI.Attach(definition, profile)
    assert(type(profile) == "table" and bases[profile.adapter], "VJ AI profile needs a human or creature adapter")
    local prepared = {adapter = profile.adapter, capabilities = {}, lifecycle = {}}
    local hostCallbacks = {grip = true, alert = true, shutdown = true}
    for name, callback in pairs(profile.lifecycle or {}) do
        assert(hostCallbacks[name] and type(callback) == "function", "Invalid VJ AI lifecycle callback: " .. tostring(name))
        prepared.lifecycle[name] = callback
    end
    for name, enabled in pairs(profile.capabilities or {}) do
        assert(fields[name], "Unknown VJ AI capability: " .. tostring(name))
        assert(type(enabled) == "boolean" or type(enabled) == "function", "Invalid VJ AI capability: " .. name)
        if enabled ~= false then assert(type(profile[name]) == "table", "Missing VJ AI settings: " .. name) end
        prepared.capabilities[name] = enabled
    end
    -- Copy only configuration containers. Asset banks remain shared read-only;
    -- timers, queues and random-choice history live on each entity's own fields.
    local used = {}
    for name, defaults in pairs(fields) do
        if profile[name] then
            local config = {}
            for key, item in pairs(profile[name]) do config[key] = item end
            config.fields = {}
            for key in pairs(profile[name].fields or {}) do
                assert(defaults[key], "Unknown VJ AI state field: " .. name .. "." .. tostring(key))
            end
            for key, fallback in pairs(defaults) do
                local binding = profile[name].fields and profile[name].fields[key] or fallback
                assert(type(binding) == "string" and binding ~= "" and binding ~= "AIProfile"
                    and not methods[binding] and not used[binding], "Duplicate/invalid VJ AI state binding")
                used[binding] = true
                config.fields[key] = binding
            end
            prepared[name] = config
        end
    end
    if prepared.capabilities.evasion then
        assert(prepared.capabilities.reactions, "VJ AI evasion requires reactions")
    end
    if prepared.capabilities.obstacle then
        assert(prepared.capabilities.reactions, "VJ AI obstacle handling requires reactions")
    end
    local reaction = prepared.reactions
    if reaction and reaction.path_samples ~= nil then
        local count = reaction.path_samples
        assert(type(count) == "number" and count >= 1 and count <= 64 and count % 1 == 0,
            "VJ AI path_samples must be an integer from 1 to 64")
    end
    -- GMod deep-copies table fields while deriving/spawning scripted entities.
    -- A getter preserves shared resource tables instead of cloning each bank.
    definition.AIProfile = function() return prepared end
    for name, method in pairs(methods) do definition[name] = method end
    return prepared
end

return AI
