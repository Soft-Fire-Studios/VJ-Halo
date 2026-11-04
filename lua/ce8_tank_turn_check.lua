-- Bounded observation of existing Hunter/Tank attacks. No behavior changes.
if CLIENT then return end
if CE8AttackTurnCapture then CE8AttackTurnCapture() end
local actors = {}
for _, e in ipairs(ents.GetAll()) do
    if e.IsCE8SNPC and (e.CE8UnitLabel == "hunter" or e.CE8UnitLabel == "flood_tank") then
        actors[#actors + 1] = e
        if #actors == 4 then break end
    end
end
if #actors == 0 then print("CE8 turn check: no Hunter or Tank present.") return end
local report = {started = CurTime(), actors = {}, rows = {}}
local cleanup = {}
local function directional(name)
    local side = type(name) == "string" and name:match("_melee_(%a+)$")
    return side == "back" or side == "left" or side == "right"
end
local function sample(e, kind, extra)
    if #report.rows >= 16000 then return end
    local seq = e:GetSequence()
    local name = e:GetSequenceName(seq)
    if not directional(name) and kind == "tick" then return end
    local task = e.CurrentTask and e.CurrentTask.Data or {}
    local turn = e.TurnData or {}
    local enemy = e:GetEnemy()
    local enemyPosition = IsValid(enemy) and enemy:GetPos() or nil
    local bearing = enemyPosition and (enemyPosition - e:GetPos()):Angle().y or nil
    local success, position, angle = e:GetSequenceMovement(seq, 0, e:GetCycle())
    report.rows[#report.rows + 1] = {time = CurTime(), tick = engine.TickCount(), entity = e:EntIndex(),
        kind = kind, sequence = name, cycle = e:GetCycle(), yaw = e:GetAngles().y, ideal_yaw = e:GetIdealYaw(),
        interval = e:GetAnimTimeInterval(), playback = e:GetPlaybackRate(), moving = e:IsMoving(),
        finished = e:IsSequenceFinished(), ideal_sequence = e:GetIdealSequence(), activity = e:GetActivity(),
        distance = e:GetSequenceMoveDist(seq), compiled_yaw = success and angle.y or nil,
        turn_type = turn.Type, turn_yaw = turn.LastYaw, turn_target = tostring(turn.Target),
        attack = e.AttackType, attack_animation = e.AnimTbl_MeleeAttack,
        task_animation = task.animation, task_sequence = task.seqID, task_deadline = task.animEndTime,
        position = e:GetPos(), enemy_position = enemyPosition, enemy_bearing = bearing,
        enemy_angle = bearing and math.AngleDifference(bearing, e:GetAngles().y) or nil,
        extra = extra}
end
for _, actor in ipairs(actors) do
    local e = actor
    local details = {class = e:GetClass(), model = e:GetModel(), methods = {}, curves = {}}
    report.actors[e:EntIndex()] = details
    local prefix = e.CE8UnitLabel == "hunter" and "any_any_melee_" or "any_melee_"
    for _, side in ipairs({"back", "left", "right"}) do
        local id = e:LookupSequence(prefix .. side)
        local samples = {}
        if id >= 0 then
            for i = 0, 10 do
                local ok, pos, ang = e:GetSequenceMovement(id, 0, i / 10)
                samples[#samples + 1] = {cycle = i / 10, success = ok, position = pos, angle = ang}
            end
        end
        details.curves[prefix .. side] = {id = id, samples = samples}
    end
    for _, methodName in ipairs({"TASK_VJ_PLAY_SEQUENCE", "AutoMovement", "SetTurnTarget", "SetIdealYawAndUpdate", "OnAnimEvent", "AIPrepareAttackTurn"}) do
        local name = methodName
        local original, own = e[name], rawget(e:GetTable(), name)
        if type(original) == "function" then
            local info = debug.getinfo(original, "S")
            details.methods[name] = {source = info.short_src, line = info.linedefined}
            local wrapper
            wrapper = function(self, ...)
                local a, b, cycle, eventType, options = ...
                local capture = directional(self:GetSequenceName(self:GetSequence()))
                    or (name == "TASK_VJ_PLAY_SEQUENCE" and type(b) == "table" and directional(b.animation))
                    or (name == "AIPrepareAttackTurn" and directional(a))
                if capture then
                    local extra = {argument = tostring(a)}
                    if name == "OnAnimEvent" then extra = {event = a, cycle = cycle, options = options} end
                    sample(self, name .. "_before", extra)
                end
                local result = original(self, ...)
                if capture then sample(self, name .. "_after", {result = tostring(result)}) end
                return result
            end
            e[name] = wrapper
            cleanup[#cleanup + 1] = function()
                if IsValid(e) and rawget(e:GetTable(), name) == wrapper then e[name] = own end
            end
        end
    end
end
local stopped = false
local function finish()
    if stopped then return end
    stopped = true
    hook.Remove("Tick", "CE8AttackTurnCapture")
    timer.Remove("CE8AttackTurnCapture")
    for _, restore in ipairs(cleanup) do restore() end
    report.finished = CurTime()
    file.CreateDir("campaign_evolved")
    file.Write("campaign_evolved/attack_turn.json", util.TableToJSON(report))
    CE8AttackTurnCapture = nil
    print("CE8 attack turn report saved: data/campaign_evolved/attack_turn.json")
end
CE8AttackTurnCapture = finish
hook.Add("Tick", "CE8AttackTurnCapture", function()
    for _, e in ipairs(actors) do if IsValid(e) then sample(e, "tick") end end
end)
timer.Create("CE8AttackTurnCapture", 18, 1, finish)
print("CE8 attack turn capture: trigger Hunter or Tank side/rear attacks for 18 seconds.")
