-- Character-neutral speech arbitration and traced, layered footstep playback.
-- Banks, cue rules, context validity and surface/action mappings come from a profile.
local methods = {}
local durationCache = {}

local function uint32(bytes, at)
    local a, b, c, d = bytes:byte(at, at + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

-- Ogg Vorbis stores its sample rate in the first packet and the exact final
-- sample count in the EOS page. Read page headers only; seek past audio data.
-- Sequential chained Vorbis streams are supported; mixed codecs are rejected.
local function vorbisDuration(stream)
    local size, position, total = stream:Size(), 0, 0
    local serial, rate, sequence
    while position < size do
        local header = stream:Read(27)
        if not header or #header ~= 27 or header:sub(1, 5) ~= "OggS\0" then return end
        local flags, count = header:byte(6), header:byte(27)
        if flags > 7 then return end
        local lacing = count > 0 and stream:Read(count) or ""
        if not lacing or #lacing ~= count then return end
        local length = 0
        for i = 1, count do length = length + lacing:byte(i) end
        local finish = position + 27 + count + length
        if finish > size then return end
        local pageSerial, pageSequence = uint32(header, 15), uint32(header, 19)
        if math.floor(flags / 2) % 2 == 1 then
            if serial or flags % 2 == 1 or pageSequence ~= 0 or count ~= 1 or length ~= 30 then return end
            local packet = stream:Read(30)
            if not packet or #packet ~= 30 or packet:sub(1, 7) ~= "\1vorbis"
                or uint32(packet, 8) ~= 0 or packet:byte(12) == 0 or packet:byte(30) % 2 ~= 1 then return end
            rate, serial, sequence = uint32(packet, 13), pageSerial, 0
            if rate == 0 then return end
        elseif not serial or pageSerial ~= serial or pageSequence ~= sequence + 1 then
            return
        else
            sequence = pageSequence
        end
        if math.floor(flags / 4) % 2 == 1 then
            local high = uint32(header, 11)
            if high >= 2097152 then return end -- Invalid/unsafe 64-bit granule.
            total = total + (uint32(header, 7) + high * 4294967296) / rate
            serial, rate, sequence = nil, nil, nil
        end
        position = finish
        stream:Seek(position)
    end
    if not serial and total > 0 then return total end
end

function methods:AISoundDuration(path)
    local filename = "sound/" .. path
    local stamp = file.Time(filename, "GAME")
    local size = file.Size(filename, "GAME")
    local cached = durationCache[path]
    if not cached or cached.stamp ~= stamp or cached.size ~= size then
        local seconds
        if path:sub(-4):lower() == ".ogg" then
            local stream = file.Open(filename, "rb", "GAME")
            if stream then
                seconds = vorbisDuration(stream)
                stream:Close()
            end
        else
            seconds = SoundDuration(path)
        end
        if not seconds or seconds <= 0 or seconds ~= seconds or seconds == math.huge then seconds = 0 end
        cached = {seconds = seconds, stamp = stamp, size = size}
        durationCache[path] = cached
    end
    return cached.seconds
end

local function settings(actor, name)
    if not actor:AIHasCapability(name) then return end
    return actor:AIProfile()[name]
end

local function bank(actor, config)
    if type(config.bank) == "function" then return config.bank(actor) end
    return config.bank
end

-- Shared queues survive a Lua refresh. A profile chooses an established
-- dialogue allegiance, not its current enemy, squad or nearest player.
VJAI.DialogueDomains = VJAI.DialogueDomains or {}
local domains = VJAI.DialogueDomains

local function speakerConfig(actor)
    return IsValid(actor) and actor.AIProfile and actor:AIProfile().dialogue
end

local function syncPending(domain)
    for actor in pairs(domain.members) do
        local config = speakerConfig(actor)
        if config and actor[config.fields.queue] == domain then actor[config.fields.pending] = nil end
    end
    for _, record in ipairs(domain.records) do
        local config = speakerConfig(record.speaker)
        if config and not record.started and not record.cancelled and not record.speaker[config.fields.pending] then
            record.speaker[config.fields.pending] = record
        end
    end
end

local function cancelRecord(record)
    record.cancelled = true
    -- A notification creates independent response requests. Retiring the caller
    -- afterward must not erase them. Before notification, descendants cancel.
    if not record.notified then
        for _, later in ipairs(record.domain.records) do
            if later.response and later.response.cancelled and not later.response.notified then later.cancelled = true end
        end
    end
end

local function releaseActor(actor, domain)
    for _, record in ipairs(domain.records) do
        if record.speaker == actor then cancelRecord(record) end
    end
    domain.members[actor] = nil
    for i = #domain.records, 1, -1 do
        if domain.records[i].cancelled then table.remove(domain.records, i) end
    end
    syncPending(domain)
end

local function dialogueDomain(actor, config)
    local key = config.domain
    if type(key) == "function" then key = key(actor) end
    local previous = actor[config.fields.queue]
    if previous and previous.key == key then return previous end
    if previous then releaseActor(actor, previous) end
    local domain = key ~= nil and domains[key] or nil
    if not domain then
        domain = {key = key, records = {}, repeats = {}, members = setmetatable({}, {__mode = "k"})}
        if key ~= nil then domains[key] = domain end
    end
    actor[config.fields.queue], actor[config.fields.pending] = domain, nil
    domain.members[actor] = true
    return domain
end

local function duration(actor, config, path)
    local seconds = actor:AISoundDuration(path)
    if seconds <= 0 then seconds = config.minimum_duration or 2 end
    return math.max(0, seconds + (config.duration_offset or 0))
end

local function availableTakes(actor, config, cue, now)
    local voices = bank(actor, config)
    local choices = voices and voices[cue]
    local available = {}
    for _, path in ipairs(choices or {}) do
        if now >= ((actor[config.fields.takes] or {})[path] or 0) then available[#available + 1] = path end
    end
    return available
end

local function shiftRecord(old, new)
    local finish = old.ready + old.spacing
    if new.ready < old.ready or new.ready >= finish then return end
    local delta = new.ready - old.ready
    if old.started and old.speaker == new.speaker and new.priority < 11 then
        new.ready = finish
    elseif new.overlap < old.priority then
        if old.started or delta >= new.window or new.priority < old.priority
            or (new.priority == old.priority and (not new.response or old.response)) then
            new.ready = finish
        end
    end
end

local function reschedule(domain, first)
    local previous = domain.records[first]
    for i = first + 1, #domain.records do
        local nextRecord = domain.records[i]
        if not nextRecord.cancelled then
            nextRecord.ready = math.max(nextRecord.ready, previous.ready + 0.2)
            shiftRecord(previous, nextRecord)
            if nextRecord.ready > nextRecord.admission_expires
                or (nextRecord.response and nextRecord.response.domain == domain and nextRecord.response ~= previous) then
                cancelRecord(nextRecord)
            else
                previous = nextRecord
            end
        end
    end
end

local function insertRecord(record, now, observed)
    local domain = record.domain
    local position, previous = #domain.records + 1, nil
    for i, old in ipairs(domain.records) do
        if not old.cancelled then
            if not observed then shiftRecord(old, record) end
            if record.ready <= old.ready then position = i break end
            previous = old
        end
    end
    if not observed and (record.ready > record.admission_expires
        or (record.response and record.response.domain == domain and record.response ~= previous)) then return false end
    table.insert(domain.records, position, record)
    reschedule(domain, position)
    if not observed then domain.repeats[record.cue] = now + record.repeat_delay end
    syncPending(domain)
    return true
end

local function notifyRecord(record, now)
    if record.notified or record.cancelled then return end
    record.notified = true
    local actor = record.speaker
    if speakerConfig(actor) then actor:AIQueueDialogueResponse(record, now) end
end

local function pruneDomain(domain, now)
    -- Notification can insert a reply, so iterate a snapshot of started lines.
    local started = {}
    for _, record in ipairs(domain.records) do if record.started then started[#started + 1] = record end end
    for _, record in ipairs(started) do
        local actor, config = record.speaker, speakerConfig(record.speaker)
        if not config or actor.Dead or actor:Health() <= 0 or actor.VJ_Controlled
            or actor.HasSounds == false or not actor:AIHasCapability("dialogue") then
            cancelRecord(record)
        else
            local playing = record.handle and record.handle:IsPlaying()
            if (not playing and now < record.finish) or (record.handle and actor.CurrentSpeechSound ~= record.handle) then
                cancelRecord(record)
            elseif not record.cancelled then
                if now >= record.notification_at or (not playing and now >= record.finish + record.post_delay) then notifyRecord(record, now) end
                if not playing and now >= record.finish + record.post_delay then record.complete = true end
            end
        end
    end
    for i = #domain.records, 1, -1 do
        local record = domain.records[i]
        local actor, config = record.speaker, speakerConfig(record.speaker)
        if not config or actor.Dead or actor:Health() <= 0 or actor.VJ_Controlled
            or actor.HasSounds == false or not actor:AIHasCapability("dialogue")
            or (not record.started and now > record.expires) then cancelRecord(record) end
        if record.cancelled or record.complete then table.remove(domain.records, i) end
    end
    syncPending(domain)
end

local function makeRecord(actor, config, cue, path, now, context)
    local rule = config.rules[cue]
    local ready = now + rule.delay
    local seconds = duration(actor, config, path)
    return {speaker = actor, domain = dialogueDomain(actor, config), cue = cue, sound = path,
        context = context, ready = ready, initial = ready, expires = ready + rule.queue,
        admission_expires = ready + rule.queue, priority = rule.priority, overlap = rule.overlap or 0,
        window = 3 * engine.TickInterval(), spacing = 0.75 * seconds + rule.post_delay,
        duration = seconds, post_delay = rule.post_delay, repeat_delay = rule.repeat_delay}
end

local function recordDialogue(self, config, cue, sound, handle, now, context)
    local state = config.fields
    local previous = self[state.spoken]
    if previous and previous.handle == handle and previous.cue == cue then return true end
    if previous and previous.domain and not previous.complete then cancelRecord(previous) end
    local rule = config.rules and config.rules[cue]
    local record = self[state.dispatch]
    local queued = record and record.cue == cue
    if not queued then
        if rule then
            record = makeRecord(self, config, cue, sound, now, context)
            record.ready, record.initial = now, now
        else
            record = {cue = cue, speaker = self, context = context, duration = duration(self, config, sound), post_delay = 0}
        end
    end
    local finish = now + record.duration
    record.started, record.handle, record.finish = true, handle, finish
    record.notification_at = now + (rule and rule.notification or 0)
    self[state.speech_until] = finish + record.post_delay
    if rule then
        self[state.repeats] = self[state.repeats] or {}
        self[state.repeats][cue] = now + rule.repeat_delay -- Direct-event/report history.
        if not queued then
            record.domain.repeats[cue] = now + rule.repeat_delay
            for _, pending in ipairs(record.domain.records) do
                if pending.speaker == self and pending.cue == cue and not pending.started then cancelRecord(pending) end
            end
            insertRecord(record, now, true)
        end
        if (rule.sound_repeat or 0) > 0 then
            self[state.takes] = self[state.takes] or {}
            self[state.takes][sound] = now + rule.sound_repeat
        end
    end
    self.NextPainSoundT = math.max(self.NextPainSoundT or 0, finish)
    self.NextSuppressingSoundT = math.max(self.NextSuppressingSoundT or 0, finish)
    self.IdleSoundBlockTime = math.max(self.IdleSoundBlockTime or 0, finish)
    self[state.last] = {cue = cue, sound = sound, time = now, duration = record.duration}
    self[state.spoken] = record
    self[state.counts] = self[state.counts] or {}
    self[state.counts][cue] = (self[state.counts][cue] or 0) + 1
    if config.played then config.played(self, cue, now, finish) end
    if rule and (rule.notification or 0) <= 0 then notifyRecord(record, now) end
    return true
end

function methods:AIObserveDialogue(handle, path, now, context)
    local config = settings(self, "dialogue")
    local cue = config and config.observed and config.observed[path]
    if not cue or not handle or self.Dead or self:Health() <= 0 or self.HasSounds == false then return false end
    return recordDialogue(self, config, cue, path, handle, now, context)
end

function methods:AIPlayDialogue(cue, now, context)
    local config = settings(self, "dialogue")
    if not config or self.Dead or self:Health() <= 0 or self.HasSounds == false then return false end
    local state = config.fields
    local dispatch = self[state.dispatch]
    local queued = dispatch and dispatch.cue == cue
    local rule = config.rules and config.rules[cue]
    if not queued and rule and now < ((self[state.repeats] or {})[cue] or 0) then return false end
    local available = availableTakes(self, config, cue, now)
    if #available == 0 then return false end
    local sound
    if queued then
        for _, path in ipairs(available) do if path == dispatch.sound then sound = path break end end
        if not sound then return false end
    else
        sound = available[math.random(#available)]
    end
    VJ.STOPSOUND(self.CurrentSpeechSound)
    VJ.STOPSOUND(self.CurrentExtraSpeechSound)
    VJ.STOPSOUND(self.CurrentIdleSound)
    self.CurrentSpeechSound = VJ.CreateSound(self, sound, config.level or 80, config.pitch or 100)
    if not self.CurrentSpeechSound then return false end
    return recordDialogue(self, config, cue, sound, self.CurrentSpeechSound, now, context)
end

local function dialogueRequest(self, config, cue, now, context)
    local domain = dialogueDomain(self, config)
    local visited, weight, requested = {}, 1, cue
    while cue and not visited[cue] do
        visited[cue] = true
        local rule = config.rules and config.rules[cue]
        if not rule then return end
        local eligible = rule.skip <= 0 or math.Rand(0, 1) >= rule.skip
        local available = eligible and now >= (domain.repeats[cue] or 0) and availableTakes(self, config, cue, now) or {}
        if #available > 0 then
            local record = makeRecord(self, config, cue, available[math.random(#available)], now, context)
            record.requested_cue = requested
            return record, weight
        end
        cue = config.fallbacks and config.fallbacks[cue]
        weight = weight * 0.8
    end
end

function methods:AIQueueDialogue(cue, now, context)
    local config = settings(self, "dialogue")
    if not config or self.Dead or self:Health() <= 0 or self.HasSounds == false or self.VJ_Controlled then return false end
    pruneDomain(dialogueDomain(self, config), now)
    local request = dialogueRequest(self, config, cue, now, context)
    return request and insertRecord(request, now) or false
end

-- Distance/facing portion of native speaker relevance. Source unit centers and
-- player aim vectors supply the inputs; no guessed contact-state or vehicle bonus.
-- The profile supplies a range in Source units, so the core has no asset scale.
function methods:AIDialogueRelevance(observers, radius)
    if not radius or radius <= 0 then return 1 end
    local position, maximum, any = self:WorldSpaceCenter(), 0, false
    local rangeSquared = radius * radius
    for _, observer in ipairs(observers) do
        if IsValid(observer) and observer:Alive() then
            any = true
            local offset = position - observer:WorldSpaceCenter()
            local distanceSquared = offset:LengthSqr()
            if distanceSquared <= rangeSquared then
                local contribution = 0
                if distanceSquared > 0.00000001 then
                    local dot = offset:GetNormalized():Dot(observer:GetAimVector())
                    local facing = dot >= 0 and 1 or 1 + 0.5 * math.max(-1, dot)
                    contribution = (1 - distanceSquared / rangeSquared) * facing
                end
                maximum = math.max(maximum, 0.7 + 0.3 * contribution)
            end
        end
    end
    return any and maximum or 1
end

function methods:AIQueueDialogueResponse(spoken, now)
    local config = settings(self, "dialogue")
    local cue = config and config.responses and config.responses[spoken.cue]
    if not cue or not config.listeners or spoken.reply_attempted or not spoken.notified
        or self.Dead or self:Health() <= 0 or self.VJ_Controlled or self.HasSounds == false then return false end
    spoken.reply_attempted = true
    local friends = config.friend_responses and config.friend_responses[spoken.cue]
    local selected, request, nearest, best = nil, nil, nil, 0
    for _, listener in ipairs(config.listeners(self, spoken.cue, spoken.context) or {}) do
        if IsValid(listener) and listener ~= self and listener.AIHasCapability and listener:AIHasCapability("dialogue")
            and not listener.Dead and listener:Health() > 0 and not listener.VJ_Controlled and listener.HasSounds ~= false then
            local other = listener:AIProfile().dialogue
            local voices = bank(listener, other)
            if other.rules and other.rules[cue] and voices
                and (not other.can_respond or other.can_respond(listener, spoken, cue, now)) then
                if friends then
                    local candidate, weight = dialogueRequest(listener, other, cue, now, spoken.context)
                    if candidate then
                        local relevance = other.relevance and other.relevance(listener, spoken, candidate.cue, now) or 1
                        local score = weight * relevance
                        if score > best then selected, request, best = listener, candidate, score end
                    end
                elseif voices[cue] and #voices[cue] > 0 then
                    local distance = listener:GetPos():DistToSqr(self:GetPos())
                    if not nearest or distance < nearest then selected, nearest = listener, distance end
                end
            end
        end
    end
    if not selected then return false end
    local other = selected:AIProfile().dialogue
    if not friends then request = dialogueRequest(selected, other, cue, now, spoken.context) end
    if not request then return false end
    local rule = other.rules[request.cue]
    request.response = spoken
    request.initial = spoken.ready + spoken.spacing + 0.2 + rule.delay
    request.ready, request.expires = request.initial, request.initial + rule.queue
    request.admission_expires = request.initial + (spoken.domain == request.domain and rule.queue or 0.25)
    return insertRecord(request, now)
end

function methods:AICancelDialogue(context)
    local config = self.AIProfile and self:AIProfile().dialogue
    if not config then return end
    local state = config.fields
    local domain = self[state.queue]
    if context ~= nil then
        if domain then
            for _, record in ipairs(domain.records) do
                if record.speaker == self and not record.started and record.context == context then cancelRecord(record) end
            end
            for i = #domain.records, 1, -1 do
                if domain.records[i].cancelled then table.remove(domain.records, i) end
            end
            syncPending(domain)
        end
        return
    end
    if domain then releaseActor(self, domain) end
    self[state.queue], self[state.pending], self[state.spoken], self[state.dispatch] = nil, nil, nil, nil
end

function methods:AIThinkDialogue(now)
    local config = self.AIProfile and self:AIProfile().dialogue
    if not config then return end
    if not self:AIHasCapability("dialogue") or self.Dead or self:Health() <= 0
        or self.HasSounds == false or self.VJ_Controlled then self:AICancelDialogue() return end
    local domain = dialogueDomain(self, config)
    if domain.processing then return end
    domain.processing = true
    local ok, failure = pcall(function()
        pruneDomain(domain, now)
        -- VJ invokes this from each actor's existing think. Dispatch only this
        -- actor, while shared scheduling/cooldowns coordinate every member.
        for _, pending in ipairs(domain.records) do
            if pending.speaker == self and not pending.started and not pending.cancelled then
                local cue, context, response = pending.cue, pending.context, pending.response
                if not config.rules or not config.rules[cue]
                    or (config.valid_context and not config.valid_context(self, cue, context, now))
                    or (response and response.cancelled and not response.notified)
                    or (response and (not speakerConfig(response.speaker)
                        or (config.can_respond and not config.can_respond(self, response, cue, now)))) then
                    cancelRecord(pending)
                elseif now >= pending.ready then
                    local speech = self.CurrentSpeechSound
                    local interrupt = config.can_interrupt and config.can_interrupt(self, cue, context, speech)
                    local blocked = not interrupt and now < (self[config.fields.speech_until] or 0)
                    for _, sound in pairs({speech, self.CurrentExtraSpeechSound, self.CurrentIdleSound}) do
                        if sound and sound:IsPlaying() and not (interrupt and sound == speech) then blocked = true end
                    end
                    if not blocked then
                        self[config.fields.dispatch] = pending
                        local played
                        if config.play then played = config.play(self, cue, now, context)
                        else played = self:AIPlayDialogue(cue, now, context) end
                        self[config.fields.dispatch] = nil
                        if not played then cancelRecord(pending) end
                        break
                    end
                end
            end
        end
        pruneDomain(domain, now)
    end)
    self[config.fields.dispatch] = nil
    domain.processing = nil
    if not ok then error(failure, 0) end
end

function methods:AIFootstep(side)
    local config = settings(self, "footsteps")
    if not config or self.Dead or self:Health() <= 0 or not self.HasSounds or not self.HasFootstepSounds
        or not self:IsOnGround() then return end
    local marker = config.attachments and config.attachments[side]
    if not marker then return end
    local state = config.fields
    self[state.attachments] = self[state.attachments] or {}
    local id = self[state.attachments][side]
    if not id then
        id = self:LookupAttachment(marker)
        if id <= 0 then return end
        self[state.attachments][side] = id
    end
    local foot = self:GetAttachment(id)
    if not foot then return end
    local scale = self:GetModelScale()
    local filter = {self}
    local weapon = self.GetActiveWeapon and self:GetActiveWeapon()
    if IsValid(weapon) then filter[#filter + 1] = weapon end
    local contact = util.TraceLine({start = foot.Pos + Vector(0, 0, (config.trace_up or 12) * scale),
        endpos = foot.Pos - Vector(0, 0, (config.trace_down or 48) * scale), mask = MASK_NPCSOLID, filter = filter})
    if not contact.Hit or contact.StartSolid or contact.HitSky then return end
    local surface = (config.materials or {})[contact.MatType] or config.default_surface
    local property = string.lower(util.GetSurfacePropName(contact.SurfaceProps) or "")
    for _, mapping in ipairs(config.properties or {}) do
        if string.find(property, mapping[1], 1, true) then surface = mapping[2] break end
    end
    if config.water_surface and bit.band(util.PointContents(contact.HitPos + Vector(0, 0, 1)), CONTENTS_WATER) ~= 0 then
        surface = config.water_surface
    end
    local action = config.action and config.action(self) or config.default_action
    local surfaces = bank(self, config)
    local sets = surfaces and (surfaces[surface] or surfaces[config.default_surface])
    local layers = sets and sets[action]
    if not layers then return end
    self[state.last_choices] = self[state.last_choices] or {}
    for _, choices in ipairs(layers) do
        if #choices > 0 then
            local previous = self[state.last_choices][choices]
            local pick = math.random(#choices - (previous and #choices > 1 and 1 or 0))
            if previous and #choices > 1 and pick >= previous then pick = pick + 1 end
            self[state.last_choices][choices] = pick
            self:PlayFootstepSound(choices[pick])
        end
    end
    self[state.last] = {side = side, surface = surface, action = action, time = CurTime()}
end

return methods
