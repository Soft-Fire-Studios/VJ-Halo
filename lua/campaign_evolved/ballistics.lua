-- Shared flight integration and firing solution; native evidence: needle/guidance.json.
CE8 = CE8 or {}
local ballistics = CE8.Ballistics or {}
CE8.Ballistics = ballistics
-- Native smooth-noise table, shared once. Source owns the random stream and tick
-- duration; this preserves the native evaluator, not deterministic Halo replay.
local noise = "\165\163\146\125\116\123\133\142\151\163\163\134\083\043\040\066\087\081\068\071\088\087\058\032\050\110\163\168\139\122\139\160\148\114\104\139\181\178\128\080\080\112\129\112\094\113\158\182\164\133\135\174\212\215\193\183\198\214\202\170\148\150\160\153" ..
    "\130\110\109\118\121\117\113\114\118\121\127\139\153\158\154\149\148\142\122\098\093\110\125\112\076\047\047\060\059\043\045\082\129\141\108\072\079\123\157\155\140\150\181\188\144\083\064\101\149\158\129\106\116\133\123\091\085\130\198\233\216\180\168\181" ..
    "\190\180\171\186\215\223\191\138\101\094\105\115\123\132\141\137\120\102\096\107\126\149\171\184\176\146\113\100\108\117\110\097\095\102\094\059\021\017\054\095\103\084\078\104\135\134\106\097\132\180\191\155\115\116\146\156\125\088\088\124\148\129\093\090" ..
    "\130\169\170\145\137\168\207\217\198\183\194\212\206\174\144\142\158\166\151\128\114\109\104\096\096\111\133\148\153\150\143\130\119\121\141\164\167\145\117\099\090\071\046\038\064\103\114\083\041\033\061\091\097\097\123\170\195\165\108\082\112\160\174\150" ..
    "\130\138\151\129\076\044\072\137\178\168\138\133\154\169\158\146\168\219\254\243\197\160\153\160\158\147\144\153\158\141\109\084\081\096\115\132\146\153\149\137\130\134\141\142\138\140\147\142\114\076\058\069\086\081\055\042\061\089\091\068\057\085\132\151" ..
    "\130\106\120\164\186\161\121\111\138\157\135\095\085\119\153\144\102\078\102\146\167\158\153\179\215\221\189\157\160\193\218\211\187\168\161\147\119\093\092\115\139\146\136\120\107\098\100\117\145\170\178\170\157\141\119\092\080\097\128\140\113\068\041\042" ..
    "\049\043\038\062\114\150\136\089\064\089\136\159\150\144\166\191\175\116\067\075\124\159\145\112\104\124\136\116\089\102\159\213\221\192\169\178\198\200\182\173\188\207\200\164\126\111\117\123\119\113\116\122\123\118\117\123\132\138\145\154\159\152\136\125" ..
    "\130\135\121\091\067\070\086\085\061\043\054\083\092\070\048\067\119\158\153\124\119\145\167\150\113\107\144\183\174\120\076\080\110\123\107\099\129\176\190\157\118\121\165\209\220\210\208\217\214\180\137\120\140\170\178\160\134\113\098\084\080\094\123\151" ..
    "\165\162\150\133\115\108\123\153\174\167\138\109\093\080\057\037\045\082\114\104\062\032\044\080\100\096\101\136\180\185\142\097\099\142\174\161\127\117\138\148\118\072\063\104\153\163\136\119\140\176\188\170\159\182\219\232\208\176\168\181\185\166\138\126" ..
    "\130\132\123\109\106\114\120\120\118\121\128\136\144\157\167\162\141\119\113\120\121\106\089\090\099\090\054\018\020\060\100\105\088\086\111\132\120\091\092\141\197\206\164\118\111\129\130\103\085\110\158\174\135\081\066\102\147\164\162\176\210\230\208\162" ..
    "\140\163\205\224\211\186\170\156\131\099\084\098\128\148\146\130\114\102\097\106\129\157\174\172\162\150\136\113\090\087\109\130\122\085\050\045\058\061\047\042\072\118\136\112\079\085\128\163\157\131\129\160\182\159\110\087\111\147\144\106\080\098\138\152" ..
    "\130\110\128\172\196\183\162\172\208\232\218\184\165\171\178\167\146\135\142\147\134\107\088\088\102\118\133\147\154\149\135\126\129\136\140\143\151\159\147\107\060\040\056\081\086\072\067\081\091\071\036\032\080\146\178\159\130\129\148\148\119\098\122\175" ..
    "\200\163\099\066\082\110\113\101\113\157\193\182\136\109\133\185\218\217\207\211\219\203\163\129\128\154\174\167\142\120\108\099\091\091\107\131\147\152\150\145\136\126\126\140\158\159\137\111\101\102\092\066\045\053\080\092\071\043\046\083\116\112\090\091" ..
    "\130\167\165\133\118\143\176\171\125\088\099\138\152\124\091\095\128\144\124\098\112\165\211\212\184\168\182\201\198\179\174\195\214\202\159\117\101\106\115\119\125\134\138\128\109\097\101\117\139\164\184\186\162\124\098\097\109\114\107\103\109\106\074\025" ..
    "\000\024\078\112\108\093\099\122\126\100\080\106\169\212\196\143\110\118\133\121\091\089\129\168\160\110\071\084\130\162\162\158\180\215\224\194\159\158\189\216\211\184\164\159\154\133\108\099\111\126\129\121\114\115\118\123\131\144\152\151\144\144\150\148" ..
    "\130\107\100\106\105\081\052\047\071\091\081\050\039\065\102\111\095\095\131\174\177\137\100\110\152\175\155\122\120\142\146\108\061\060\110\162\171\144\128\144\168\169\151\154\195\244\254\219\173\151\154\158\150\145\153\165\157\124\087\070\078\102\127\150"

local function positive(value)
    return value and value > 0 and value or 1
end

function ballistics.Scale(data, level, ai)
    local flight = data.flight
    return ai and flight and flight.ai_speed and positive(flight.ai_speed[level]) or 1
end

function ballistics.Random(state)
    state.random = (state.random * 1664525 + 1013904223) % 4294967296
    return math.floor(state.random / 65536)
end

function ballistics.State(data, scale, level, ai, seed, forward)
    local state = {scale = scale or 1, distance = 0,
        nominal = data.speed * (scale or 1), random = seed or math.random(0, 2147483647),
        forward = forward or Vector(1, 0, 0)}
    local guidance = data.flight and data.flight.guidance
    if guidance then
        local low, high = guidance.rate[1], guidance.rate[2]
        state.turn = low == high and low or low + (high - low) * (ballistics.Random(state) / 65535)
        if ai then state.turn = state.turn * positive(guidance.ai_turn[level]) end
        state.player_scale = guidance.player_scale[level] or 1
    end
    return state
end

function ballistics.Speed(data, distance, scale)
    scale = scale or 1
    local flight = data.flight
    -- Native AI speed scaling bypasses both interpolation and nominal-distance
    -- advancement. Actual movement/range is tracked separately by the entity.
    if not flight or math.abs(scale - 1) > 0.0001 then return data.speed * scale end
    local start, finish = flight.acceleration_range[1], flight.acceleration_range[2]
    local inverse = flight.acceleration_inverse or (finish > start and 1 / (finish - start) or 0)
    local fraction = math.Clamp((distance - start * scale) * inverse, 0, 1)
    return (data.speed + (flight.final_speed - data.speed) * fraction) * scale
end

function ballistics.Advance(data, state, velocity, dt)
    if not data.flight or math.abs(state.scale - 1) > 0.0001 or dt <= 0 then return velocity end
    local nominal = ballistics.Speed(data, state.distance, state.scale)
    local along = velocity:Dot(state.forward)
    local adjusted = along + nominal - state.nominal
    if data.flight.final_speed > data.speed then
        adjusted = math.min(data.flight.final_speed, adjusted)
    else
        adjusted = math.max(data.flight.final_speed, adjusted)
    end
    -- Adjust the previous completed step's forward component only. Steering
    -- precedes this projection; gravity and the new orientation follow it.
    velocity = velocity + state.forward * (adjusted - along)
    state.nominal = nominal
    state.distance = state.distance + nominal * dt
    return velocity
end

function ballistics.Lifetime(data, scale)
    local flight = data.flight
    local range = flight and flight.range or data.max_range
    local speed = data.speed * (scale or 1)
    if flight and math.abs((scale or 1) - 1) <= 0.0001 then speed = math.min(speed, flight.final_speed) end
    return math.min(12, range / math.max(1, speed) + 1)
end

local function sampleNoise(value)
    local position = value * 36.57143020629883
    local index = math.floor(position)
    local fraction = position - index
    return (noise:byte(index % 1024 + 1) * (1 - fraction)
        + noise:byte((index + 1) % 1024 + 1) * fraction) / 255
end

function ballistics.Steer(data, state, position, velocity, target, targetVelocity, playerTarget, dt)
    local flight = data.flight
    local guidance = flight and flight.guidance
    if not guidance or not state.turn or state.turn <= 0 or dt <= 0 then return velocity end
    local speed = velocity:Length()
    if speed <= 0 then return velocity end
    local distance = position:Distance(target)
    local targetSpeed = targetVelocity:Length()
    if targetSpeed > 0 and guidance.leading > 0 then
        local time = math.Clamp(distance / speed, 0, 2)
        local lead = math.Clamp(time * targetSpeed * guidance.leading, 0, 240)
        target = target + targetVelocity * (lead / targetSpeed)
    end
    local motion = guidance.source_motion
    local random = ballistics.Random(state)
    if motion then
        -- Optional Source Needler motion. CE has this circular target-offset
        -- mode, but its Needler tag leaves the ROBOTRON steering flag off.
        -- Use continuous simulation time, not a new noise phase every tick.
        local direction = target - position
        local length = direction:Length()
        if length > 0 then
            direction = direction * (1 / length)
            local side = Vector(-direction.y, direction.x, 0)
            if side:LengthSqr() < 0.000001 then side = Vector(1, 0, 0)
            else side = side:GetNormalized() end
            local up = direction:Cross(side)
            local phase = CurTime() * motion.weave_rate
            local radius = math.min(length * motion.weave_fraction, motion.weave_radius)
            target = target + (side * math.cos(phase) + up * math.sin(phase)) * radius
        end
    elseif guidance.error > 0 then
        local error = guidance.error * math.Clamp((position:Distance(target) - 240) / 960, 0, 1)
        local a = math.pi - math.pi * 0.5 * sampleNoise(random * dt)
        local b = math.pi * 2 * sampleNoise(random * dt * 7 / 3)
        target = target + Vector(math.cos(a) * math.cos(b), math.cos(a) * math.sin(b), math.sin(a)) * error
    end
    local aim = target - position
    if not guidance.behind and velocity:Dot(aim) <= 0 then return velocity end
    local axis = velocity:Cross(aim)
    -- Native threshold is in world units; Source distances/velocities use120.
    if axis:Length() < 0.0001 * 120 * 120 then return velocity end
    axis = axis:GetNormalized()
    local fraction = math.Clamp((state.distance - state.scale * flight.acceleration_range[1])
        * flight.acceleration_inverse, 0, 1)
    local rate = guidance.rest + (state.turn - guidance.rest) * fraction
    if playerTarget then rate = rate * state.player_scale end
    if motion then rate = rate * motion.turn_scale end
    local angle = rate * dt
    if motion then
        -- Source stabilization: a tick must not turn past its current target.
        -- Leave the retained native path unchanged when the adapter is absent.
        local remaining = math.acos(math.Clamp(velocity:Dot(aim) / (speed * aim:Length()), -1, 1))
        angle = math.min(angle, remaining)
    end
    -- Native rotation has no clamp to the remaining target angle.
    return velocity * math.cos(angle) + axis:Cross(velocity) * math.sin(angle)
        + axis * (axis:Dot(velocity) * (1 - math.cos(angle)))
end

-- Predict unobstructed travel using the same speed-by-distance curve and
-- gravity impulse as the live physics object. This runs only when firing.
function ballistics.Predict(data, direction, time, gravity, step, scale)
    local position = Vector()
    local velocity = direction * data.speed * (scale or 1)
    local state = ballistics.State(data, scale, "normal", false, 0, direction)
    local elapsed = 0
    while elapsed < time do
        local dt = math.min(step, time - elapsed)
        velocity = ballistics.Advance(data, state, velocity, dt)
        velocity = velocity + gravity * dt
        if data.flight and data.flight.orient and velocity:LengthSqr() > 0 then state.forward = velocity:GetNormalized() end
        local movement = velocity * dt
        position = position + movement
        elapsed = elapsed + dt
    end
    return position, velocity
end

function ballistics.Aim(data, origin, target, targetVelocity, worldGravity, step, scale)
    local offset = target - origin
    local distance = offset:Length()
    if distance < 0.01 or data.speed <= 0 then return Vector(), 0, distance, false end
    local direction = offset * (1 / distance)
    local gravity = worldGravity * data.gravity
    local limit = ballistics.Lifetime(data, scale)
    local time = math.Clamp(distance / (data.speed * (scale or 1)), step, limit)
    local bestDirection, bestTime, bestMiss = direction, time, math.huge
    -- Refine the low, direct arc. Account for the actual slowdown instead of
    -- treating the Fuel Rod as a constant-speed grenade or increasing speed.
    for _ = 1, 8 do
        local displacement, velocity = ballistics.Predict(data, direction, time, gravity, step, scale)
        local error = offset + targetVelocity * time - displacement
        local miss = error:Length()
        if miss < bestMiss then bestDirection, bestTime, bestMiss = direction, time, miss end
        if miss <= 0.5 then return direction, time, miss, true end
        local relativeVelocity = velocity - targetVelocity
        local along = direction:Dot(relativeVelocity)
        if along <= 0.01 then break end
        local change = math.Clamp(direction:Dot(error) / along, -time * 0.5, time * 0.5)
        local nextTime = math.Clamp(time + change, step, limit)
        local correction = error - relativeVelocity * (nextTime - time)
        local nextDirection = direction + correction * (1 / math.max(1, displacement:Length()))
        if nextDirection:LengthSqr() == 0 then break end
        direction = nextDirection:GetNormalized()
        time = nextTime
    end
    -- Unreachable/fast-moving targets retain the closest finite solution;
    -- never manufacture extra projectile speed or a high, blind lob.
    return bestDirection, bestTime, bestMiss, false
end

return ballistics
