-- Shared model motion adapters. The host binds VJ callbacks; no global hooks.
VJAI = VJAI or {}
local Motion = {}
local methods = {}
local bases = {human = "npc_vj_human_base", creature = "npc_vj_creature_base"}
local state = {
    activity_sets = "AIMotionSets", activities = "AIMotionActivities", activity_model = "AIMotionModel",
    fire_activity = "AIFireActivity", move_direction = "AIMoveDirection", facing_direction = "AIFacingDirection",
    move_intent = "AIMoveIntent", move_time = "AIMoveIntentTime", aim_turn = "AIAimTurn",
    aim_previous = "AIAimPrevious", aim_written = "AIAimWritten",
    controller_target = "AIControllerAimTarget", grip_value = "AIAppliedGrip", grip_model = "AIGripModel",
    schedule_crouch = "AICrouchMove", schedule_weapon = "AICrouchWeapon", reload = "AIReload"
}
local function value(actor, setting, fallback)
    if type(setting) == "function" then setting = setting(actor) end
    if setting == nil then return fallback end
    return setting
end
local function selectAction(actor, config, name)
    if config.action then return config.action(actor, name) end
    if actor.AISelectAction then return actor:AISelectAction(name) end
end
function methods:AIMotionEnabled(name)
    return value(self, self:AIMotionProfile().capabilities[name], false) == true
end
function methods:AIMotionBase(name, ...)
    local base = baseclass.Get(bases[self:AIMotionProfile().adapter])
    local method = base and base[name]
    if not method and name == "GetHeadDirection" then method = FindMetaTable("NPC").GetHeadDirection end
    assert(type(method) == "function", "VJ motion adapter has no base method: " .. tostring(name))
    return method(self, ...)
end

local trackingActions = {patrol_idle = true, patrol_walk = true, patrol_run = true,
    combat_idle = true, crouch_idle = true}
for _, stance in ipairs({"combat", "crouch"}) do
    for _, pace in ipairs({"walk", "move"}) do
        for _, side in ipairs({"front", "back", "left", "right"}) do
            trackingActions[stance .. "_" .. pace .. "_" .. side] = true
        end
    end
end
local function trackingActivity(actor)
    local activities = actor:AIAnimationActivities()
    local current = actor:GetSequenceActivity(actor:GetSequence())
    for action in pairs(trackingActions) do
        if activities and activities[action] == current then return current, action end
    end
end

-- Four authored clips. Use the requested facing when choosing a motor heading,
-- and the actual body frame when choosing an animation during the turn.
function methods:AIMovementDirection(direction, yaw)
    local config = self:AIMotionProfile()
    if config.forward_only then return "front" end
    local fields = config.fields
    if not self:AIMotionEnabled("movement") then return self[fields.move_direction] or "front" end
    local forward = direction:Dot(self:GetForward())
    local right = direction:Dot(self:GetRight())
    if forward * forward + right * right < (config.direction_deadband or 0.01) then return self[fields.move_direction] or "front" end
    local current, angle
    if yaw then
        angle = math.AngleDifference(direction:Angle().y, yaw)
        current = self[fields.facing_direction]
    else
        angle = math.deg((math.atan2 or math.atan)(-right, forward))
        current = self[fields.move_direction]
    end
    -- Eight travel sectors, four authored clips: diagonals belong to forward
    -- or backward movement. Reserve side-steps for the +/-90-degree sectors.
    local absolute = math.abs(angle)
    local selected = absolute <= 67.5 and "front" or absolute >= 112.5 and "back"
        or (angle > 0 and "left" or "right")
    local margin = config.direction_hysteresis or 5
    if (current == "front" and absolute <= 67.5 + margin)
        or (current == "back" and absolute >= 112.5 - margin)
        or (current == "left" and angle >= 67.5 - margin and angle <= 112.5 + margin)
        or (current == "right" and angle <= -67.5 + margin and angle >= -112.5 - margin) then
        return current
    end
    return selected
end

function methods:AIApplyGrip(amount)
    -- Set by initialization/weapon changes. Source networks this pose; the
    -- client must not rewrite it or force another skeleton build.
    if CLIENT or not self:AIMotionEnabled("grip") then return false end
    local config = self:AIMotionProfile()
    local fields, grip = config.fields, config.grip or {}
    local parameter = grip.parameter or "grip"
    local model, index = self:GetModel(), self:LookupPoseParameter(parameter)
    if index < 0 then return false end
    local low, high
    if grip.minimum == nil or grip.maximum == nil then low, high = self:GetPoseParameterRange(index) end
    amount = amount or value(self, grip.default, 0)
    if grip.integer ~= false then amount = math.Round(amount) end
    amount = math.Clamp(amount, grip.minimum or low, grip.maximum or high)
    local current = self:GetPoseParameter(parameter)
    if self[fields.grip_value] == amount and self[fields.grip_model] == model
        and math.abs(current - amount) < (grip.epsilon or 0.02) then return false end
    self[fields.grip_model], self[fields.grip_value] = model, amount
    self:SetPoseParameter(parameter, amount)
    return true
end

function methods:AIAnimationSet(weapon)
    local config = self:AIMotionProfile()
    local fields = config.fields
    if not self:AIMotionEnabled("movement") and not self:AIMotionEnabled("aim") then return end
    weapon = weapon or (self.GetActiveWeapon and self:GetActiveWeapon())
    local name = IsValid(weapon) and config.weapon_key and config.weapon_key(self, weapon) or config.default_set
    local sets = value(self, config.sets, {})
    if not sets[name] then name = config.default_set end
    return sets[name], name
end

function methods:AIAnimationActivities(weapon)
    local config = self:AIMotionProfile()
    local fields = config.fields
    local profile, name = self:AIAnimationSet(weapon)
    if not profile then return end
    local model = self:GetModel()
    if self[fields.activity_model] ~= model then
        self[fields.activity_sets] = nil
        self[fields.activity_model] = model
    end
    self[fields.activity_sets] = self[fields.activity_sets] or {}
    if self[fields.activity_sets][name] then
        self[fields.activities] = self[fields.activity_sets][name]
        return self[fields.activities]
    end
    local activities = {}
    for action, sequence in pairs(profile.sequences) do
        if sequence then
            local id = self:LookupSequence(sequence)
            if id < 0 then error("VJ AI missing animation sequence: " .. sequence) end
            local activity = self:GetSequenceActivity(id)
            if activity < 0 then error("VJ AI missing animation activity: " .. sequence) end
            activities[action] = activity
        else
            activities[action] = false
        end
    end
    self[fields.activity_sets][name] = activities
    self[fields.activities] = activities
    return activities
end

function methods:AIMotionCombat()
    local config = self:AIMotionProfile()
    local fields = config.fields
    if config.in_combat then return config.in_combat(self) end
    return self.Alerted or IsValid(self:GetEnemy())
end

function methods:AISetAnimationTranslations(holdType, weapon)
    local config = self:AIMotionProfile()
    local fields = config.fields
    local reload = self[fields.reload]
    if reload and reload.weapon ~= self:GetActiveWeapon() then self:AIReleaseReload(reload) end
    if not self:AIMotionEnabled("movement") then return self:AIMotionBase("SetAnimationTranslations", holdType, weapon) end
    local profile = self:AIAnimationSet(weapon)
    local a = self:AIAnimationActivities(weapon)
    if config.adapter == "human" then
        local previousFire = self[fields.fire_activity]
        if previousFire and previousFire ~= a.fire then self:RemoveGesture(previousFire) end
        self[fields.fire_activity] = a.fire
        self.AnimTbl_WeaponAttack = profile.melee and ACT_MELEE_ATTACK1 or ACT_IDLE_ANGRY
        self.AnimTbl_WeaponAttackGesture = profile.fire_gesture ~= false and profile.sequences.fire and "vjges_" .. profile.sequences.fire or false
        self.AnimTbl_WeaponReload = profile.sequences.reload and ACT_RELOAD or false
        self.AnimTbl_WeaponReloadCovered = profile.sequences.reload and ACT_RELOAD_LOW or false
        self.DisableWeaponReloadAnimation = not profile.sequences.reload
    end
    if profile.sequences.melee then self.AnimTbl_MeleeAttack = "vjseq_" .. profile.sequences.melee end
    self.AnimationTranslations = self.AnimationTranslations or {}
    local t = self.AnimationTranslations
    local function bind(activity, animation) if animation ~= nil then t[activity] = animation end end
    bind(ACT_IDLE, a.patrol_idle)
    bind(ACT_IDLE_ANGRY, a.combat_idle)
    bind(ACT_WALK, a.patrol_walk)
    bind(ACT_RUN, a.patrol_run)
    for _, act in ipairs({ACT_WALK_AIM, ACT_WALK_AGITATED}) do bind(act, a.combat_walk_front) end
    for _, act in ipairs({ACT_RUN_AIM, ACT_RUN_AGITATED, ACT_RUN_PROTECTED}) do bind(act, a.combat_move_front) end
    for _, act in ipairs({ACT_WALK_CROUCH, ACT_WALK_CROUCH_AIM}) do bind(act, a.crouch_walk_front) end
    for _, act in ipairs({ACT_RUN_CROUCH, ACT_RUN_CROUCH_AIM}) do bind(act, a.crouch_move_front) end
    bind(ACT_RANGE_ATTACK1, profile.melee and a.melee or a.combat_idle)
    bind(ACT_RANGE_ATTACK1_LOW, a.crouch_idle)
    bind(ACT_COVER_LOW, a.crouch_idle)
    bind(ACT_COVER, a.combat_idle)
    local reload = profile.reload_gesture and profile.sequences.reload and "vjges_" .. profile.sequences.reload or a.reload
    bind(ACT_RELOAD, reload)
    local crouchReload = profile.sequences.crouch_reload and
        (profile.crouch_reload_gesture and "vjges_" .. profile.sequences.crouch_reload or a.crouch_reload) or reload
    bind(ACT_RELOAD_LOW, crouchReload)
    bind(ACT_MELEE_ATTACK1, a.melee)
    bind(ACT_TURN_LEFT, a.turn_left)
    bind(ACT_TURN_RIGHT, a.turn_right)
    if a.crouch_idle then self.AnimTbl_TakingCover = ACT_COVER_LOW end
    if a.crouch_move_front then self.AnimTbl_MoveToCover = ACT_RUN_CROUCH end
    for act, name in pairs({[ACT_JUMP] = "jump", [ACT_GLIDE] = "airborne", [ACT_LAND] = "land"}) do
        local sequence = selectAction(self, config, name)
        if sequence then bind(act, self:GetSequenceActivity(self:LookupSequence(sequence))) end
    end
end

local movement = {
    [ACT_WALK] = {"walk"}, [ACT_WALK_AIM] = {"walk"}, [ACT_WALK_AGITATED] = {"walk"},
    [ACT_RUN] = {"move"}, [ACT_RUN_AIM] = {"move"}, [ACT_RUN_AGITATED] = {"move"},
    [ACT_RUN_PROTECTED] = {"move"},
    [ACT_WALK_CROUCH] = {"walk", true}, [ACT_WALK_CROUCH_AIM] = {"walk", true},
    [ACT_RUN_CROUCH] = {"move", true}, [ACT_RUN_CROUCH_AIM] = {"move", true}
}

function methods:AITranslateActivity(act)
    local config = self:AIMotionProfile()
    local fields = config.fields
    if not self:AIMotionEnabled("movement") then return self:AIMotionBase("TranslateActivity", act) end
    local a = self:AIAnimationActivities()
    local crouched = self.AIControlCrouched and self:AIControlCrouched()
    if crouched and a.crouch_idle and (act == ACT_IDLE or act == ACT_IDLE_ANGRY or act == ACT_COVER_LOW
        or act == ACT_RANGE_ATTACK1 or act == ACT_RANGE_ATTACK1_LOW) then return a.crouch_idle end
    if act == ACT_JUMP and self:GetNavType() == NAV_JUMP and self:IsGoalActive() then
        local drop = self:GetPos().z - self:GetCurWaypointPos().z
        if drop > 0 then
            local best, closest = nil, math.huge
            for _, name in ipairs({"jump_down_short", "jump_down_long"}) do
                local sequence = selectAction(self, config, name)
                local id = sequence and self:LookupSequence(sequence) or -1
                if id >= 0 then
                    local ok, motion = self:GetSequenceMovement(id, 0, 1)
                    local activity = self:GetSequenceActivity(id)
                    if ok and motion.z < 0 and activity >= 0 and math.abs(drop + motion.z) < closest then
                        best, closest = activity, math.abs(drop + motion.z)
                    end
                end
            end
            if best then return best end
        end
    end
    if act == ACT_IDLE then
        local idle = self:AIMotionCombat() and a.combat_idle or a.patrol_idle
        if idle ~= nil then return idle end
        return self:AIMotionBase("TranslateActivity", act)
    end
    local mode = movement[act]
    if mode then
        local crouch = mode[2] or crouched
        local schedule, weapon = self.CurrentSchedule, self.GetActiveWeapon and self:GetActiveWeapon()
        if not crouch and not self.VJ_Controlled and (not config.crouch_allowed or config.crouch_allowed(self))
            and schedule and schedule.CanShootWhenMoving and IsValid(self:GetEnemy())
            and IsValid(weapon) and not weapon.IsMeleeWeapon then
            -- VJ's strafe requests ordinary walk/run even after crouch fire.
            -- Keep that posture for this route, including direction changes;
            -- a new schedule chooses its stance afresh.
            if schedule[fields.schedule_crouch] == nil then
                schedule[fields.schedule_crouch] = self.WeaponAttackAnim == a.crouch_idle
                schedule[fields.schedule_weapon] = weapon
            end
            crouch = schedule[fields.schedule_crouch] and schedule[fields.schedule_weapon] == weapon
        end
        -- Keep VJ's firing-while-moving state transitions and scheduling.
        local baseActivity = self:AIMotionBase("TranslateActivity", act)
        -- The motor's current step is authoritative. Its previous velocity can
        -- still point along the old stride when it begins a strafe or turns.
        local direction = self[fields.move_intent]
        if not direction or not self[fields.move_time] or CurTime() - self[fields.move_time] > (config.intent_age or 0.25) then
            direction = self:GetMoveVelocity()
        end
        local side = self:AIMovementDirection(direction)
        self[fields.move_direction] = side
        if not crouch and not self:AIMotionCombat() and side == "front" then
            local idleMove = mode[1] == "walk" and a.patrol_walk or a.patrol_run
            if idleMove ~= nil then return idleMove end
            return baseActivity
        end
        local stride = a[(crouch and "crouch_" or "combat_") .. (crouched and "walk" or mode[1]) .. "_" .. side]
        if stride ~= nil then return stride end
        return baseActivity
    end
    return self:AIMotionBase("TranslateActivity", act)
end

local movementYaw = {front = 0, back = 180, left = 90, right = -90}
function methods:AIGetTurnAngle(angle)
    local config = self:AIMotionProfile()
    local fields = config.fields
    local result = self:AIMotionBase("GetTurnAngle", angle)
    if not self:AIMotionEnabled("movement") then return result end
    local activity, action = trackingActivity(self)
    if self.Dead or not self.CanTurnWhileMoving
        or self:GetNavType() ~= NAV_GROUND or self:IsBusy("Activities") or self.AttackType
        or self.Flinching or not activity
        or (self.TurnData and self.TurnData.StopOnFace) then
        self[fields.facing_direction] = nil
        return result
    end
    if not self:IsMoving() then
        self[fields.facing_direction] = nil
        local schedule, turn = self.CurrentSchedule, self.TurnData
        -- A strafe route can own facing before its first motor step. Do not
        -- turn straight at the enemy and then back to the cardinal stride.
        -- An exhausted route has no goal: allow its final face task normally.
        if turn and turn.IsSchedule and schedule and schedule.HasMovement
            and schedule.CanShootWhenMoving and self:GetCurGoalType() ~= 0 then
            local yaw = self:GetAngles().y % 360
            return Angle(result.p, yaw == 0 and 360 or yaw, result.r)
        end
        return result
    end
    local direction = self[fields.move_intent]
    if not direction or not self[fields.move_time] or CurTime() - self[fields.move_time] > (config.intent_age or 0.25) then
        direction = self:GetMoveVelocity()
    end
    if direction:Length2DSqr() < (config.direction_deadband or 0.01) then return result end
    -- Pick a cardinal stride relative to VJ's unmodified target, then align
    -- the entity to that stride. Never accumulate an offset from current yaw.
    local side = self:AIMovementDirection(direction, result.y)
    local previous = self[fields.facing_direction]
    if previous and side ~= previous and previous == self:AIMovementDirection(direction) then
        -- A changing enemy bearing must not rotate a straight strafe by 90
        -- degrees while its existing firing stance can still aim at the enemy.
        local profile = self:AIAnimationSet()
        local stance = string.sub(action, 1, 7) == "crouch_" and "crouch_idle" or "combat_idle"
        local limits = profile and profile.aim_limits and profile.aim_limits[stance]
        if limits and not profile.melee and self.HasPoseParameterLooking then
            local heading = direction:Angle().y - movementYaw[previous]
            local aim = math.AngleDifference(result.y, heading)
            if aim >= limits[1] and aim <= limits[2] then side = previous end
        end
    end
    self[fields.facing_direction] = side
    local yaw = (direction:Angle().y - movementYaw[side]) % 360
    -- VJ treats LastYaw == 0 as inactive. An equivalent full turn preserves
    -- a valid zero heading while strafing; StopOnFace requests are excluded.
    if yaw == 0 then yaw = 360 end
    return Angle(result.p, yaw, result.r)
end

function methods:AIOverrideMoveFacing(interval, move)
    local config = self:AIMotionProfile()
    local fields = config.fields
    if not self:AIMotionEnabled("movement") then return self:AIMotionBase("OverrideMoveFacing", interval, move) end
    if self.Dead or self.Flinching or self.AttackType or self:IsBusy("Activities")
        or not trackingActivity(self) then
        self[fields.move_intent], self[fields.move_time] = nil, nil
        self[fields.move_direction], self[fields.facing_direction] = nil, nil
        return self:AIMotionBase("OverrideMoveFacing", interval, move)
    end
    if move and move.dir then
        self[fields.move_intent] = Vector(move.dir)
        self[fields.move_time] = CurTime()
    end
    -- VJ updates the actual body yaw; classify the stride in that new frame.
    local result = self:AIMotionBase("OverrideMoveFacing", interval, move)
    if move and move.dir then
        local direction = self:AIMovementDirection(move.dir)
        if direction ~= self[fields.move_direction] and self:IsMoving() and not self:IsBusy("Activities") then
            self[fields.move_direction] = direction
            self:SetMovementActivity(self:GetMovementActivity())
        end
    end
    return result
end

-- VJ owns aim-angle calculation and pose interpolation. Only gate when the
-- tracker may run; full-body actions retain their authored motion in both AI
-- and possession, including the tail after VJ releases its attack flag.
function methods:AIUpdatePoseTracking(resetPoses)
    if CLIENT then return end
    if self.AIPrepareGaze then self:AIPrepareGaze() end
    local config = self:AIMotionProfile()
    if not self:AIMotionEnabled("aim") or config.adapter ~= "human" or not config.track_without_firing then
        return self:AIMotionBase("UpdatePoseParamTracking", resetPoses)
    end
    if not self.HasPoseParameterLooking or self.Dead or self.Flinching or self.AttackType
        or self:IsBusy("Activities") or self:GetNavType() ~= NAV_GROUND
        or self:GetWeaponState() == VJ.WEP_STATE_RELOADING
        or (config.aim_allowed and not config.aim_allowed(self))
        or not trackingActivity(self) then return end
    if self.VJ_Controlled or self.WeaponAttackState then
        return self:AIMotionBase("UpdatePoseParamTracking", resetPoses)
    end
    local enemy = self:GetEnemy()
    if not IsValid(enemy) or not self:Visible(enemy) then return end
    -- VJ's Creature tracker uses the same pose calculation without requiring
    -- a weapon firing state. Reuse it for ordinary movement on the Human host.
    baseclass.Get("npc_vj_creature_base").UpdatePoseParamTracking(self, resetPoses)
    self.UpdatedPoseParam = true
end

function methods:AIHeadDirection()
    local config = self:AIMotionProfile()
    local fields = config.fields
    -- The native eyes marker's axes are a socket frame. VJ's weapon cone uses
    -- the actual aim direction rather than interpreting that socket as a view.
    if not self:AIMotionEnabled("aim") then return self:AIMotionBase("GetHeadDirection") end
    local aim = config.aim or {}
    return Angle((aim.pitch_sign or -1) * self:GetPoseParameter(aim.pitch or "aim_pitch"),
        self:GetAngles().y + self:GetPoseParameter(aim.yaw or "aim_yaw"), 0):Forward()
end

function methods:AIMotionAimPosition(target, origin, predictionRate, projectileSpeed)
    local config = self:AIMotionProfile()
    local fields = config.fields
    local point = self:AIMotionEnabled("aim") and config.blind_point and config.blind_point(self, target)
    -- VJ's pose tracker subtracts EyePos from this return value in place.
    -- Keep the saved world target intact for later shots and motor facing.
    if point then return Vector(point) end
    return self:AIMotionBase("GetAimPosition", target, origin, predictionRate, projectileSpeed)
end

function methods:AIUpdateAimTurn(activity)
    local config = self:AIMotionProfile()
    local fields = config.fields
    -- Moving combat keeps VJ's existing motor-facing behavior.
    if not self:AIMotionEnabled("aim") or config.adapter ~= "human" then self:AIRestoreAimCone() return false end
    if self[fields.aim_written] == nil then self[fields.aim_previous] = self.Weapon_AimTurnDiff end
    self.Weapon_AimTurnDiff = config.moving_aim_dot or 0.70710678
    self[fields.aim_written] = self.Weapon_AimTurnDiff
    local enemy, weapon = self:GetEnemy(), self:GetActiveWeapon()
    if not IsValid(enemy) or not IsValid(weapon) or not weapon.IsVJBaseWeapon or weapon.IsMeleeWeapon
        or self.Dead or not self.HasPoseParameterLooking then return false end
    local controlled = self.VJ_Controlled
    if controlled then
        local controller = self.VJ_Controller
        local player = IsValid(controller) and controller:GetPlayer()
        if not IsValid(player) or enemy ~= controller:GetBullseye()
            or player:KeyDown(IN_FORWARD) or player:KeyDown(IN_BACK)
            or player:KeyDown(IN_MOVELEFT) or player:KeyDown(IN_MOVERIGHT) then return false end
    else
        self[fields.controller_target] = nil
    end
    if self:IsMoving() or self:IsBusy("Activities") or self.AttackType or (config.aim_allowed and not config.aim_allowed(self)) or self:GetWeaponState() == VJ.WEP_STATE_RELOADING
        or (not controlled and not self:Visible(enemy)) then return false end
    local profile = self:AIAnimationSet(weapon)
    if profile.melee then return false end
    local a = self:AIAnimationActivities(weapon)
    activity = activity or self:GetSequenceActivity(self:GetSequence())
    local posture = activity == a.combat_idle and "combat_idle" or activity == a.crouch_idle and "crouch_idle"
    local limits = posture and (profile.aim_limits or {})[posture]
    if not limits then return false end
    local yaw = math.AngleDifference((enemy:GetPos() - self:GetPos()):Angle().y, self:GetAngles().y)
    self.Weapon_AimTurnDiff = math.cos(math.rad(yaw < 0 and -limits[1] or limits[2]))
    self[fields.aim_written] = self.Weapon_AimTurnDiff
    -- Retire an old firing-idle facing timer (including on live reload), but
    -- never steal a movement schedule's turn target or a reaction's facing.
    local turn = self.TurnData
    local inside = yaw >= limits[1] and yaw <= limits[2]
    local controllerTurn = controlled and turn and turn.Target ~= nil
        and (turn.Target == enemy or turn.Target == self[fields.controller_target])
    if inside and turn and not turn.IsSchedule
        and (turn.Type == VJ.FACE_ENEMY or turn.Type == VJ.FACE_ENEMY_VISIBLE or controllerTurn) then
        self:ResetTurnTarget()
        self:SetIdealYaw(self:GetAngles().y)
        self[fields.controller_target] = nil
    end
    return true, inside, yaw, posture
end

function methods:AIRestoreAimCone()
    local fields = self:AIMotionProfile().fields
    local written = self[fields.aim_written]
    if written ~= nil and self.Weapon_AimTurnDiff == written then self.Weapon_AimTurnDiff = self[fields.aim_previous] end
    self[fields.aim_previous], self[fields.aim_written] = nil, nil
end

function methods:AIClearAimTurn()
    local fields = self:AIMotionProfile().fields
    local turn = self[fields.aim_turn]
    if not turn then return end
    if self:IsValidLayer(turn.layer) and self:GetLayerSequence(turn.layer) == turn.sequence then
        self:SetLayerBlendIn(turn.layer, 0)
        self:SetLayerBlendOut(turn.layer, 0)
        self:RemoveLayer(turn.layer)
    end
    self[fields.aim_turn] = nil
end

function methods:AIAnimateAimTurn(eligible, inside, yaw, posture)
    local config = self:AIMotionProfile()
    local fields = config.fields
    if not self:AIMotionEnabled("aim") or config.adapter ~= "human" then self:AIClearAimTurn() return end
    local now, weapon = CurTime(), self:GetActiveWeapon()
    local turn = self[fields.aim_turn]
    local side = yaw and (yaw < 0 and "right" or "left")
    if turn then
        local valid = self:IsValidLayer(turn.layer) and self:GetLayerSequence(turn.layer) == turn.sequence
        if not eligible or weapon ~= turn.weapon or now >= turn.finish or not valid
            or (not inside and side ~= turn.side) then
            self:AIClearAimTurn()
        else
            return -- Finish the step instead of restarting it on each shot.
        end
    end
    if not eligible or inside then return end
    local profile = self:AIAnimationSet(weapon)
    local mode = posture == "crouch_idle" and "crouch" or "combat"
    local name = profile.sequences[mode .. "_turn_" .. side]
    if not name then return end
    local sequence = self:LookupSequence(name)
    if sequence < 0 then return end
    -- VJ owns body yaw and firing/idle schedules. A transient authored turn
    -- layer presents the footwork without applying root yaw a second time.
    local layer = self:AddGestureSequence(sequence, true)
    if layer < 0 then return end
    local rate = math.max(self.AnimPlaybackRate or 1, 0.01)
    self:SetLayerPriority(layer, 0) -- Fire gestures retain VJ's priority 1.
    self:SetLayerPlaybackRate(layer, rate)
    self:SetLayerBlendIn(layer, 0.1)
    self:SetLayerBlendOut(layer, 0.15)
    self[fields.aim_turn] = {layer = layer, sequence = sequence, weapon = weapon, side = side,
        finish = now + self:SequenceDuration(sequence) / rate}
end

function methods:AIMotionTurnTarget(target, faceTime, stopOnFace, visibleOnly)
    local config = self:AIMotionProfile()
    local fields = config.fields
    -- Possession bypasses Human Base's aim cone: it faces the bullseye entity
    -- while idle, and its position every firing tick. Filter just those calls.
    if self.VJ_Controlled then
        local controller = self.VJ_Controller
        local bullseye = IsValid(controller) and controller:GetBullseye()
        if IsValid(bullseye) and (target == bullseye or target == "Enemy"
            or (isvector(target) and target:DistToSqr(bullseye:GetPos()) < 1)) then
            local eligible, inside = self:AIUpdateAimTurn()
            if eligible then
                if inside then return self:GetAngles() end
                local result = self:AIMotionBase("SetTurnTarget", target, faceTime, stopOnFace, visibleOnly)
                self[fields.controller_target] = self.TurnData and self.TurnData.Target
                return result
            end
        end
    end
    return self:AIMotionBase("SetTurnTarget", target, faceTime, stopOnFace, visibleOnly)
end

function methods:AIIsReloading()
    local config = self:AIMotionProfile()
    if config.adapter ~= "human" then return false end
    if self:GetWeaponState() == VJ.WEP_STATE_RELOADING then return true end
    local reload = self[config.fields.reload]
    return reload ~= nil and reload.seed == self.WeaponReloadSeed and reload.weapon == self:GetActiveWeapon()
        and CurTime() < reload.finish
end

function methods:AIReleaseReload(expected)
    local field = self:AIMotionProfile().fields.reload
    local reload = self[field]
    if not reload or expected and reload ~= expected then return false end
    self[field] = nil
    if reload.attack ~= nil and self.NextDoAnyAttackT == reload.finish then
        self.NextDoAnyAttackT = math.max(CurTime(), reload.attack)
    end
    if self.Weapon_RetreatDistance == -1 then self.Weapon_RetreatDistance = reload.retreat end
    local inventory = reload.inventory
    if inventory and self.WeaponInventory == inventory and inventory.Melee == nil then inventory.Melee = reload.melee end
    return true
end

function methods:AIPlayReloadGesture(animation, lockAnimTime, faceEnemy, delay, extra, customFunc)
    if not extra or not extra.OnFinish or not self:AIIsReloading() then return end
    local profile = self:AIAnimationSet()
    if not profile then return end
    local name, gesture = profile.sequences.reload, profile.reload_gesture
    local crouch = profile.sequences.crouch_reload
    if crouch and (animation == ACT_RELOAD_LOW or animation == "vjges_" .. crouch) then
        name, gesture = crouch, profile.crouch_reload_gesture
    end
    if not name or not gesture then return end
    local sequence = "vjges_" .. name
    if animation ~= sequence and animation ~= ACT_RELOAD and animation ~= ACT_RELOAD_LOW then return end
    local fields = self:AIMotionProfile().fields
    local reload = {weapon = self:GetActiveWeapon(), seed = self.WeaponReloadSeed}
    local options = {}
    for key, value in pairs(extra) do options[key] = value end
    options.OnFinish = function(interrupted, played)
        -- Record identity also handles two reloads started in the same tick,
        -- for which VJ's CurTime-based WeaponReloadSeed can be identical.
        if not self:AIReleaseReload(reload) then return end
        -- VJ still owns completion, ammo and OnReload("Finish"). A different
        -- weapon must never receive completion of the old weapon's gesture.
        if self:GetActiveWeapon() ~= reload.weapon then interrupted = true end
        extra.OnFinish(interrupted, played)
    end
    local played, duration, kind = self:AIMotionBase("PlayAnim", sequence, false, lockAnimTime, faceEnemy, delay, options, customFunc)
    if played ~= ACT_INVALID then
        self:AIReleaseReload()
        reload.finish = CurTime() + duration
        self[fields.reload] = reload
        -- Allow the current path/controller movement to continue. VJ adds a
        -- two-second chase delay before starting a reload; release only that.
        if self.NextChaseTime == reload.seed + 2 then self.NextChaseTime = CurTime() end
        -- Melee cannot interrupt the reload. VJ's nearby retreat and automatic
        -- switch to its melee inventory also cancel reloading; defer only those
        -- choices, keeping normal chase/navigation available.
        reload.retreat, self.Weapon_RetreatDistance = self.Weapon_RetreatDistance, -1
        reload.inventory = self.WeaponInventory
        if reload.inventory then
            reload.melee, reload.inventory.Melee = reload.inventory.Melee, nil
        end
        local attack = self.NextDoAnyAttackT or 0
        if attack < reload.finish then
            reload.attack, self.NextDoAnyAttackT = attack, reload.finish
        end
    end
    return played, duration, kind
end

function methods:AIMotionPlayAnim(animation, lockAnim, lockAnimTime, faceEnemy, delay, extra, customFunc)
    local played, duration, kind = self:AIPlayReloadGesture(animation, lockAnimTime, faceEnemy, delay, extra, customFunc)
    if played ~= nil then return played, duration, kind end
    local config = self:AIMotionProfile()
    local fields = config.fields
    if self.AttackType or self.Flinching or lockAnim then
        self:AIClearAimTurn()
        self[fields.move_intent], self[fields.move_time] = nil, nil
        self[fields.move_direction], self[fields.facing_direction] = nil, nil
    end
    -- VJ's ranged idle asks to face for the whole clip. Let its native aim-cone
    -- check decide when to turn instead; all other animations retain VJ rules.
    if faceEnemy == true and lockAnim == false and lockAnimTime == 0 and self:AIUpdateAimTurn(animation) then
        faceEnemy = false
    end
    return self:AIMotionBase("PlayAnim", animation, lockAnim, lockAnimTime, faceEnemy, delay, extra, customFunc)
end


function Motion.Attach(definition, profile)
    assert(type(profile) == "table" and bases[profile.adapter], "VJ motion profile needs a human or creature adapter")
    local prepared = {}
    for name, setting in pairs(profile) do prepared[name] = setting end
    prepared.capabilities, prepared.fields = {}, {}
    for name, enabled in pairs(profile.capabilities or {}) do
        assert(name == "movement" or name == "aim" or name == "grip", "Unknown VJ motion capability")
        assert(type(enabled) == "boolean" or type(enabled) == "function", "Invalid VJ motion capability")
        prepared.capabilities[name] = enabled
    end
    if prepared.capabilities.movement or prepared.capabilities.aim then
        assert(type(profile.sets) == "table" or type(profile.sets) == "function", "Missing VJ animation sets")
        assert(type(profile.default_set) == "string", "Missing VJ default animation set")
    end
    for key in pairs(profile.fields or {}) do assert(state[key], "Unknown VJ motion state field: " .. tostring(key)) end
    local used = {}
    for key, fallback in pairs(state) do
        local binding = profile.fields and profile.fields[key] or fallback
        assert(type(binding) == "string" and binding ~= "" and binding ~= "AIMotionProfile"
            and not methods[binding] and not used[binding], "Duplicate/invalid VJ motion state binding")
        used[binding] = true
        prepared.fields[key] = binding
    end
    definition.AIMotionProfile = function() return prepared end
    for name, method in pairs(methods) do definition[name] = method end
    return prepared
end
VJAI.Motion = Motion
return Motion
