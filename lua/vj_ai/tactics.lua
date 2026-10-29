-- VJ perception, coordinated tactics and interruptible idle/postcombat actions.
local methods = {}
local function value(actor, setting, fallback)
    if type(setting) == "function" then setting = setting(actor) end
    if setting == nil then return fallback end
    return setting
end

function methods:AIRememberSound(source)
    if not self:AIHasCapability("perception") or not IsValid(source) or not source.VJ_SD_InvestTime then return end
    local field = self:AIProfile().perception.fields.heard
    self[field] = self[field] or setmetatable({}, {__mode = "k"})
    self[field][source] = source.VJ_SD_InvestTime
end

function methods:AISetPerception(mode)
    if not self:AIHasCapability("perception") then return false end
    local config = self:AIProfile().perception
    if self[config.fields.mode] == mode then return end
    local settings = value(self, config.modes, {})
    local limits = settings[mode] or settings[config.fallback_mode or "alert"]
    if not limits then return false end
    self:SetMaxLookDistance(limits.vision)
    self:SetFOV(limits.fov)
    self[config.fields.mode] = mode
    return true
end

function methods:AIHearSound(now)
    if not self:AIHasCapability("perception") then return false end
    local config = self:AIProfile().perception
    if self.CanInvestigate == false or self.Dead or self.VJ_Controlled or IsValid(self:GetEnemy())
        or self.Behavior == VJ_BEHAVIOR_PASSIVE_NATURE or self:IsBusy("Activities")
        or (config.allowed and not config.allowed(self, now)) or now < (self.NextInvestigationMove or 0)
        or now < (self.TakingCoverT or 0) or (self.IsFollowing and self:IsMoving()) then return false end
    local perception = value(self, config.modes, {})
    local limits = perception[self[config.fields.mode] or config.initial_mode or "idle"] or perception[config.fallback_mode or "alert"]
    if not limits or not limits.hearing or limits.hearing <= 0 then return false end
    self[config.fields.heard] = self[config.fields.heard] or setmetatable({}, {__mode = "k"})
    local origin = self:GetPos()
    local best, bestPosition, bestScore
    -- VJ already records audible living-entity sounds and excludes quiet
    -- footsteps. Its relationship scan clips hearing at sight range; this
    -- adapter uses the same candidate list without expanding vision.
    for _, source in ipairs(self.RelationshipEnts or {}) do
        local time = IsValid(source) and source.VJ_SD_InvestTime
        local level = time and source.VJ_SD_InvestLevel or 0
        if time and level > 0 and now >= time and now - time <= (config.sound_age or 1) and self[config.fields.heard][source] ~= time
            and source ~= self and not source.Dead and not source.VJ_Controlling then
            local position = source:GetPos()
            -- 75 is VJ's minimum recorded sound level. Quieter mixed-volume
            -- records shorten range; louder sounds never exceed the tag cap.
            local radius = limits.hearing * math.min(1, level / 75)
            local distance = origin:DistToSqr(position)
            if distance <= radius * radius then
                local disposition = self:CheckRelationship(source)
                local memory = self.RelationshipMemory and self.RelationshipMemory[source]
                local override = memory and memory[VJ.MEM_OVERRIDE_DISPOSITION]
                local friendly = disposition == D_LI or override == D_LI
                -- Distant candidates may not have VJ's class disposition yet.
                -- Respect explicit overrides before its shared faction labels.
                if not friendly and not override and self.CanAlly ~= false then
                    for _, class in ipairs(self.VJ_NPC_Class or {}) do
                        if VJ.HasValue(source.VJ_NPC_Class or {}, class) then friendly = true break end
                    end
                end
                if not friendly and disposition ~= D_ER then
                    local score = radius * radius / math.max(1, distance)
                    if not bestScore or score > bestScore then
                        best, bestPosition, bestScore = source, Vector(position), score
                    end
                end
            end
        end
    end
    if not best then return false end
    if config.before_investigate then config.before_investigate(self, best, bestPosition, now) end
    self:DoReadyAlert()
    self:AISetPerception(config.alert_mode or "alert")
    self:SetLastPosition(bestPosition)
    local approach = not self.IsGuard and not self.IsFollowing and not self.DisableWandering
        and not self.DisableChasingEnemy and not self:Visible(best)
    if approach then
        self:SCHEDULE_GOTO_POSITION("TASK_WALK_PATH")
    else
        self:StopMoving()
        self:SCHEDULE_FACE("TASK_FACE_LASTPOSITION")
    end
    self.NextInvestigationMove = now + (approach and 2 or 0.3)
    self:AIRememberSound(best)
    self:OnInvestigate(best, approach and bestPosition or origin)
    self:PlaySoundSystem("Investigate")
    return true
end

function methods:AITryFlank(now, enemy)
    if not self:AIHasCapability("flank") or not IsValid(enemy) then return false end
    local config = self:AIProfile().flank
    local state = config.fields
    local chance = value(self, config.chance, 0)
    if self.IsGuard or self.IsFollowing or self.DisableChasingEnemy then return false end
    if chance <= 0 or now < (self[state.next_check] or 0) or not self:Visible(enemy) then return false end
    self[state.next_check] = now + (config.check_interval or 4)
    local allies = self:Allies_Check(config.ally_range or 900)
    local supported = false
    for _, ally in ipairs(allies or {}) do
        local allyConfig = IsValid(ally) and ally.AIProfile and ally:AIProfile().flank
        if allyConfig and ally[allyConfig.fields.enemy] == enemy and now < (ally[allyConfig.fields.finish] or 0)
            and not ally.Dead and not ally.VJ_Controlled and ally:IsMoving() then return false end
        if IsValid(ally) and ally ~= self and ally:GetEnemy() == enemy then supported = true end
    end
    if not supported or math.Rand(0, 1) >= chance then return false end
    local origin, target = self:GetPos(), enemy:GetPos()
    local distance = origin:Distance(target)
    if distance < (config.minimum_distance or 300) then return false end
    local from = (origin - target):GetNormalized()
    for _, position in ipairs(VJ.TraceDirections(self, "Radial", math.min(config.route_radius or 400, distance * 0.5), true, false, 12, true) or {}) do
        local offset = position - target
        if offset:Length() > (config.target_clearance or 180) and offset:GetNormalized():Dot(from) < (config.angle_dot or 0.9) then
            local eye = position + (self:EyePos() - origin)
            local trace = util.TraceLine({start = eye, endpos = enemy:EyePos(), mask = MASK_SHOT, filter = {self, enemy}})
            if not trace.Hit then
                self:SetLastPosition(position)
                self:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH", function(schedule)
                    schedule.CanShootWhenMoving = true
                    schedule.TurnData = {Type = VJ.FACE_ENEMY_VISIBLE}
                end)
                self[state.finish] = now + (config.route_time or 3)
                self[state.enemy] = enemy
                self.NextChaseTime = now + (config.route_time or 3)
                return true
            end
        end
    end
    return false
end

local function sampleRange(bounds)
    return math.Rand(bounds[1], bounds[2])
end
local function reactionEnd(actor)
    local reaction = actor:AIProfile().reactions
    return reaction and actor[reaction.fields.finish] or 0
end
local function searchReady(actor, config, now)
    if config.can_react then return config.can_react(actor, now) end
    if actor:AIHasCapability("reactions") then return actor:AIReactionReady(now) end
    return not actor.Dead and actor:Health() > 0 and not actor.VJ_Controlled
        and not actor.AttackType and not actor:IsBusy("Activities")
end

function methods:AIFinishSearch(now, expired)
    local config = self.AIProfile and self:AIProfile().search
    local search = config and self[config.fields.active]
    if not search then return end
    self:AIEndSearchAction(now)
    self[config.fields.active] = nil
    if config.finished then config.finished(self, search, now, expired) end
end

function methods:AIStartSearch(now)
    if not self:AIHasCapability("search") then return false end
    local config = self:AIProfile().search
    if self[config.fields.active] then return end
    local settings = value(self, config.settings, {})
    local visibleTime = self.EnemyData and self.EnemyData.VisibleTime or now
    local deadline = visibleTime + (self.EnemyTimeout or 0)
    if now >= deadline then return end
    local mode = value(self, config.mode, config.default_mode or "aggressive")
    if not settings.stimuli or not settings.stimuli[mode] then mode = config.default_mode or "aggressive" end
    if not settings.stimuli or not settings.stimuli[mode] then return false end
    local seen = self[config.fields.seen]
    if seen and seen.enemy ~= self:GetEnemy() then seen = nil end
    local position = seen and seen.origin or self.EnemyData and self.EnemyData.VisiblePos or self:GetEnemyLastKnownPos()
    self[config.fields.active] = {position = Vector(position), deadline = deadline,
        presearch_until = math.min(deadline, now + sampleRange(settings.stimuli[mode].time)),
        next = now, phase = "enter", enemy = self:GetEnemy(), mode = mode}
    if seen then
        self[config.fields.active].aim = Vector(seen.position)
    end
    -- A charge/opening belongs to visible combat. Retaining it here blocks
    -- suppression eligibility even though its action is no longer updated.
    self:AIEndCharge(now)
    self:AIEndOpening(now)
    if config.started then config.started(self, self[config.fields.active], now) end
    return true
end

function methods:AIEndSearchAction(now)
    local config = self.AIProfile and self:AIProfile().search
    if not config then return end
    local search = self[config.fields.active]
    if not search or not search.action then return end
    if self.NextChaseTime == search.chase_until then self.NextChaseTime = search.previous_chase or now end
    if self.NextIdleTime == search.idle_until then self.NextIdleTime = search.previous_idle or now end
    if search.schedule and self.CurrentSchedule == search.schedule then
        self:ClearSchedule()
        self:StopMoving()
    end
    if search.action == "suppress" and self.WeaponAttackAnim == search.activity then
        self.WeaponAttackState = VJ.WEP_ATTACK_STATE_NONE
        self.WeaponAttackAnim = ACT_INVALID
    end
    if self.TurnData and self.TurnData.Target == search.aim and not self.TurnData.IsSchedule then
        self:ResetTurnTarget()
        self:SetIdealYaw(self:GetAngles().y)
    end
    search.action, search.schedule = nil, nil
end

function methods:AISuppressionPoint(weapon, enemy)
    if not self:AIHasCapability("search") or self:AIProfile().adapter ~= "human" then return end
    local config = self:AIProfile().search
    local search = self[config.fields.active]
    if not search or search.action ~= "suppress" then return end
    local disabled = GetConVar("ai_disabled")
    local state = self.GetState and self:GetState()
    if disabled and disabled:GetBool() then return end
    if state and (state == VJ_STATE_FREEZE or state == VJ_STATE_ONLY_ANIMATION_NOATTACK) then return end
    if not search.aim or search.burst_done
        or CurTime() >= search.action_until or self.Dead or self.VJ_Controlled
        or CurTime() < reactionEnd(self)
        or self.IsGuard or self.IsFollowing or self.DisableChasingEnemy or self.DisableWandering
        or (config.suppression_allowed and not config.suppression_allowed(self)) or not IsValid(enemy) or enemy ~= search.enemy
        or enemy ~= self:GetEnemy() or enemy:Health() <= 0 or self:Visible(enemy)
        or not IsValid(weapon) or weapon ~= search.weapon or weapon ~= self:GetActiveWeapon()
        or (search.schedule and self.CurrentSchedule ~= search.schedule)
        or self:IsMoving() or self:IsBusy("Activities") or self.AttackType
        or self:GetWeaponState() == VJ.WEP_STATE_RELOADING then return end
    return search.aim
end

function methods:AITrySearchAction(now, enemy)
    if not self:AIHasCapability("search") then return false end
    local config = self:AIProfile().search
    local search = self[config.fields.active]
    if not search or search.action or search.presearch_done then return false end
    if not IsValid(enemy) or enemy ~= search.enemy or enemy:Health() <= 0 or self:Visible(enemy)
        or self.IsGuard or self.IsFollowing or self.DisableChasingEnemy or self.DisableWandering then return false end
    local settings = value(self, config.settings, {})
    local mode = value(self, config.mode, config.default_mode or "aggressive")
    if not settings.stimuli or not settings.stimuli[mode] then mode = config.default_mode or "aggressive" end
    search.mode = mode
    local profile = settings.stimuli and settings.stimuli[mode]
    if not profile then self:AIFinishSearch(now) return false end
    -- Existing actors may already be searching when this Lua is refreshed.
    search.presearch_until = search.presearch_until
        or math.min(search.deadline, (search.started or now) + sampleRange(profile.time))
    if now >= search.presearch_until then search.presearch_done = true return false end
    -- The parent's budget is sampled once. A child can be selected again after
    -- completing, but cannot create a fresh parent budget on each activation.
    local untilTime = math.min(search.deadline, search.presearch_until)
    if untilTime <= now then return false end
    local occupied = false
    if value(self, config.squad, false) then
        for _, ally in ipairs(self:Allies_Check(self.CallForHelpDistance or 800) or {}) do
            local allyConfig = IsValid(ally) and ally.AIProfile and ally:AIProfile().search
            local plan = allyConfig and ally[allyConfig.fields.active]
            if IsValid(ally) and not ally.Dead and not ally.VJ_Controlled and ally:GetEnemy() == enemy
                and plan and plan.action == "uncover" and now < plan.action_until
                and ally.CurrentSchedule == plan.schedule then occupied = true break end
        end
    end
    local weapon = self.GetActiveWeapon and self:GetActiveWeapon()
    -- Weapon-specific collateral eligibility is supplied by the host profile.
    local canSuppress = self:AIProfile().adapter == "human" and settings.suppress and search.aim
        and IsValid(weapon) and config.suppress_eligible and config.suppress_eligible(self, weapon, search)
        and config.suppress_activity
    local destination
    if settings.uncover and not occupied and profile.uncover > 0 then
        local radius = sampleRange(settings.uncover_range)
        for _, position in ipairs(VJ.TraceDirections(self, "Radial", radius, true, false, 12, true) or {}) do
            local distance = position:Distance(search.position)
            if distance >= settings.uncover_range[1] and distance <= settings.uncover_range[2] then
                local eye = position + (self:EyePos() - self:GetPos())
                local trace = util.TraceLine({start = eye, endpos = search.aim or search.position + Vector(0,0,50),
                    mask = MASK_SHOT, filter = self})
                if not trace.Hit and not trace.StartSolid then destination = position break end
            end
        end
    end
    local uncover = destination and profile.uncover or 0
    local suppress = canSuppress and profile.suppress or 0
    local choice = math.Rand(0, uncover + suppress + profile.guard + profile.investigate)
    if choice < uncover then
        search.action = "uncover"
        self:SetLastPosition(destination)
        self:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH", function(schedule)
            schedule.CanShootWhenMoving = true
        end)
    elseif choice < uncover + suppress then
        search.action, search.weapon = "suppress", weapon
        if profile.max_suppress > 0 then untilTime = math.min(untilTime, now + profile.max_suppress) end
        search.action_until = untilTime
        local activity = config.suppress_activity(self, weapon)
        self:PlayAnim(activity, false, 0, false, 0, nil, function(schedule)
            -- Keep the looping stance after its first animation task ends.
            -- The search deadline and normal interruptions release it.
            schedule:EngTask("TASK_WAIT", untilTime - now)
        end)
        search.activity = activity
        self.WeaponAttackAnim = activity
        self:SetTurnTarget(search.aim, untilTime - now)
        self:PlaySoundSystem("Suppressing")
    elseif choice < uncover + suppress + profile.guard then
        search.action = "guard"
        self:SetLastPosition(search.position)
        self:SCHEDULE_FACE("TASK_FACE_LASTPOSITION")
    end
    if not search.action then
        -- Investigation transfers to the ordinary search loop. It is not a
        -- failed weighted choice retried every Think while an animation plays.
        search.presearch_done = true
        return false
    end
    search.burst_done = nil
    search.action_until, search.schedule = untilTime, self.CurrentSchedule
    search.started = now
    search.previous_chase, search.previous_idle = self.NextChaseTime, self.NextIdleTime
    search.chase_until, search.idle_until = untilTime, untilTime
    self.NextChaseTime, self.NextIdleTime = untilTime, untilTime
    return true
end

function methods:AIThinkSearch(now, enemy)
    if not self:AIHasCapability("search") or self.Dead or self.VJ_Controlled then self:AIFinishSearch(now) return end
    local config = self:AIProfile().search
    local search = self[config.fields.active]
    if not search then return end
    if now >= search.deadline then
        self:AIFinishSearch(now, true)
        return
    end
    if not IsValid(enemy) or enemy ~= search.enemy or enemy:Health() <= 0 or self:Visible(enemy) then
        self:AIFinishSearch(now, false)
        return
    end
    if search.yield_schedule then
        -- VJ may go directly from danger to idle without exposing a nil
        -- schedule to our sampled Think. Yield through danger/locked actions,
        -- but release the latch when ordinary stationary idle resumes.
        local schedule = self.CurrentSchedule
        local idle = schedule and (schedule.Name == "SCHEDULE_IDLE_STAND"
            or schedule.Name == "SCHEDULE_IDLE_WANDER" or schedule.Name == "SCHEDULE_FACE")
        if schedule and (not idle or self:IsMoving() or not searchReady(self, config, now)
            or now < (self.TakingCoverT or 0)) then
            search.yield_schedule = schedule
            return
        end
        search.yield_schedule = nil
    end
    if search.action then
        if now >= search.action_until or search.burst_done or self.CurrentSchedule ~= search.schedule
            or self.IsGuard or self.IsFollowing or self.DisableChasingEnemy or self.DisableWandering
            or (search.action == "suppress" and not self:AISuppressionPoint(search.weapon, enemy))
            or (search.action == "uncover" and not self:IsMoving() and now > search.started + 0.5) then
            local replacement = self.CurrentSchedule ~= search.schedule and self.CurrentSchedule or nil
            self:AIEndSearchAction(now)
            if replacement then search.yield_schedule = replacement return end
        else return end
    end
    if self:IsMoving() or not searchReady(self, config, now) or now < search.next then return end
    search.started = search.started or now
    if self:AITrySearchAction(now, enemy) then return end
    if search.destination then
        if self.DisableWandering or self.IsGuard or self.IsFollowing then search.destination = nil return end
        self:SetLastPosition(search.destination)
        self:SCHEDULE_GOTO_POSITION("TASK_WALK_PATH")
        search.destination = nil
        search.next = now + (config.move_pause or 2)
        return
    end
    local settings = value(self, config.settings, {})
    local profile = settings.stimuli and settings.stimuli[search.mode]
    if not profile then self:AIFinishSearch(now) return false end
    local duration = config.investigate and config.investigate(self, search.phase, now)
    if type(duration) == "number" then
        search.next = now + duration + (config.pose_pause or 1)
    else search.next = now + (config.move_pause or 2) end
    if search.phase == "enter" then
        search.phase = "idle"
        -- Investigate the observed location before looking around locally.
        -- Radial samples around our current position cannot reach a distant
        -- last-known point, which previously left the actor posing in place.
        if not self.DisableChasingEnemy and not self.DisableWandering and not self.IsGuard and not self.IsFollowing
            and self:GetPos():DistToSqr(search.position) > (config.arrival_distance or 64) ^ 2 then
            search.destination = Vector(search.position)
        end
    elseif not self.DisableWandering and not self.IsGuard and not self.IsFollowing and
        (search.mode == "aggressive" or math.Rand(0, profile.investigate + profile.guard + profile.suppress) < profile.investigate) then
        local choices = VJ.TraceDirections(self, "Quick", settings.radius, true, false, 8, true)
        for _, position in ipairs(choices or {}) do
            if position:Distance(search.position) <= settings.radius then
                -- Let the current authored investigation finish before moving.
                search.destination = position
                break
            end
        end
    end
end

local function openingWeapon(actor, enemy, now)
    if not IsValid(actor) or not actor.AIHasCapability or not actor:AIHasCapability("opening")
        or actor:AIProfile().adapter ~= "human" or not IsValid(enemy) or enemy:Health() <= 0 then return end
    local config = actor:AIProfile().opening
    if actor:GetEnemy() ~= enemy or actor:Disposition(enemy) ~= D_HT or actor.CallForHelp == false
        or actor.IsGuard or actor.IsFollowing or actor.DisableChasingEnemy
        or not searchReady(actor, config, now) or actor:IsMoving() or actor.PauseAttacks
        or actor:GetWeaponState() == VJ.WEP_STATE_RELOADING
        or (config.allowed and not config.allowed(actor, now)) then return end
    local weapon = actor:GetActiveWeapon()
    if IsValid(weapon) and config.weapon_allowed and config.weapon_allowed(actor, weapon) then return weapon end
end

function methods:AIJoinOpening(ally, now)
    if not self:AIHasCapability("opening") then return false end
    -- VJ has already alerted this previously idle ally. Coordinate only the
    -- initial acquisition window; established combat never waits for recruits.
    now = now or CurTime()
    local enemy = self:GetEnemy()
    local config = self:AIProfile().opening
    local allyConfig = IsValid(ally) and ally.AIProfile and ally:AIProfile().opening
    local ownWeapon, allyWeapon = openingWeapon(self, enemy, now), openingWeapon(ally, enemy, now)
    if not ownWeapon or not allyWeapon or not self:Visible(enemy) or not ally:Visible(enemy)
        or value(self, config.acquire_at, 0) <= now or value(ally, allyConfig.acquire_at, 0) <= now then return end
    local plan = self[config.fields.active]
    if plan and (plan.finished or plan.enemy ~= enemy or now >= plan.ready_at) then return end
    if ally[allyConfig.fields.active] and ally[allyConfig.fields.active] ~= plan then return end
    local deadline = plan and plan.deadline or now + value(self, config.window, 2)
    if math.max(value(self, config.acquire_at, 0), value(ally, allyConfig.acquire_at, 0)) > deadline then return end
    if not plan then
        plan = {leader = self, enemy = enemy, started = now, deadline = deadline,
            ready_at = value(self, config.acquire_at, 0), members = setmetatable({}, {__mode = "k"})}
        plan.members[self] = {weapon = ownWeapon, hit = value(self, config.hit, nil)}
        self[config.fields.active] = plan
    end
    if not plan.members[ally] then
        plan.members[ally] = {weapon = allyWeapon, hit = value(ally, allyConfig.hit, nil)}
        plan.ready_at = math.max(plan.ready_at, value(ally, allyConfig.acquire_at, 0))
        ally[allyConfig.fields.active] = plan
    end
end

function methods:AIOpeningReady(now)
    local config = self.AIProfile and self:AIProfile().opening
    if not config then return true end
    local plan = self[config.fields.active]
    if not plan then return true end
    if not plan.finished then
        local member = plan.members[self]
        local interrupted = not member or openingWeapon(self, plan.enemy, now) ~= member.weapon
            or value(self, config.hit, nil) ~= member.hit or not self:Visible(plan.enemy)
            or not IsValid(plan.leader) or plan.leader.Dead
        -- Check the group once per server tick. Recheck the caller even within
        -- that tick so damage, possession or weapon changes release it promptly.
        if plan.checked_at ~= now and not interrupted then
            plan.checked_at = now
            local count = 0
            for actor, state in pairs(plan.members) do
                count = count + 1
                local memberConfig = IsValid(actor) and actor.AIProfile and actor:AIProfile().opening
                if openingWeapon(actor, plan.enemy, now) ~= state.weapon or not memberConfig or actor[memberConfig.fields.active] ~= plan
                    or value(actor, memberConfig.hit, nil) ~= state.hit or not actor:Visible(plan.enemy) then
                    interrupted = true
                    break
                end
            end
            interrupted = interrupted or count < 2
        end
        if interrupted then plan.finished = "interrupted"
        elseif now >= plan.ready_at or now >= plan.deadline then plan.finished = "ready" end
    end
    if not plan.finished then return false end
    self[config.fields.active] = nil
    self[config.fields.last] = {result = plan.finished, members = table.Count(plan.members),
        waited = now - plan.started, time = now}
    if plan.finished == "ready" then self[config.fields.count] = (self[config.fields.count] or 0) + 1 end
    return true
end

function methods:AIEndOpening(now)
    local config = self.AIProfile and self:AIProfile().opening
    local plan = config and self[config.fields.active]
    if not plan then return end
    plan.finished = plan.finished or "interrupted"
    self:AIOpeningReady(now)
end

-- A committed melee approach must not be replaced by a stationary ranged
-- firing stance. The host consults this in both its VJ weapon hook and SWEP
-- discharge gate. Melee weapons keep their own attack path available.
function methods:AIChargeBlocksWeapon(weapon, now)
    if not self:AIHasCapability("charge") or self.VJ_Controlled or self.Dead then return false end
    local config = self:AIProfile().charge
    local charge = self[config.fields.active]
    if not charge or (now or CurTime()) >= charge.deadline
        or (IsValid(weapon) and weapon.IsMeleeWeapon) then return false end
    local enemy = self:GetEnemy()
    return IsValid(enemy) and enemy == charge.enemy
end

function methods:AIEndCharge(now)
    local config = self.AIProfile and self:AIProfile().charge
    if not config then return end
    local charge = self[config.fields.active]
    if not charge then return end
    if self:AIProfile().adapter == "human" and self.Weapon_RetreatDistance == 0 then self.Weapon_RetreatDistance = charge.retreat end
    self[config.fields.active] = nil
end

function methods:AIMaintainCharge(now, enemy)
    if not self:AIHasCapability("charge") or self.Dead or self.VJ_Controlled then self:AIEndCharge(now) return false end
    local config = self:AIProfile().charge
    local forced = value(self, config.forced, false)
    local settings = value(self, config.settings, {})
    if self.IsGuard or self.IsFollowing or self.DisableChasingEnemy then self:AIEndCharge(now) return false end
    local charge = self[config.fields.active]
    if charge then
        local distance = IsValid(enemy) and self:GetPos():Distance(enemy:GetPos()) or math.huge
        if enemy ~= charge.enemy or now >= charge.deadline or distance > settings.abort
            or distance < self.MeleeAttackDistance or not self:Visible(enemy) then
            self:AIEndCharge(now)
            return false
        end
        if not self:IsMoving() and searchReady(self, config, now) then self:SCHEDULE_ALERT_CHASE(false) end
        return true
    end
    if not IsValid(enemy) or not searchReady(self, config, now) or now < (self[config.fields.next_attempt] or 0) then return false end
    local distance = self:GetPos():Distance(enemy:GetPos())
    if distance <= self.MeleeAttackDistance or distance > settings.range or not self:Visible(enemy) then return false end
    if not forced and math.Rand(0, 1) >= settings.chance then
        self[config.fields.next_attempt] = now + settings.delay
        return false
    end
    self[config.fields.active] = {enemy = enemy, deadline = now + settings.timeout, retreat = self.Weapon_RetreatDistance}
    if self:AIProfile().adapter == "human" then self.Weapon_RetreatDistance = 0 end
    self[config.fields.next_attempt] = now + settings.timeout + settings.delay
    self:SCHEDULE_ALERT_CHASE(false)
    if config.started then config.started(self, self[config.fields.active], now, forced) end
    return true
end


-- Quiet actions remain interruptible; only release the VJ values they own.
function methods:AICancelIdle()
    local config = self.AIProfile and self:AIProfile().idle
    if not config then return end
    local pose = self[config.fields.active]
    self[config.fields.active], self[config.fields.next_pose] = nil, nil
    if pose and self.NextIdleTime == pose.idle_until then self.NextIdleTime = pose.previous_idle or 0 end
    if pose and pose.schedule and self.CurrentSchedule == pose.schedule then self:ClearSchedule() end
end

function methods:AIThinkIdle(now)
    if not self:AIHasCapability("idle") then self:AICancelIdle() return false end
    local config = self:AIProfile().idle
    local fields = config.fields
    local settings = value(self, config.settings, {})
    if settings.enabled == false or self.Dead or self.VJ_Controlled then self:AICancelIdle() return false end
    if self.Alerted or self:IsMoving() or self.IsGuard or self.IsFollowing then
        self[fields.next_pose] = nil
        return false
    end
    local pose = self[fields.active]
    if pose then
        if now < pose.finish and self.CurrentSchedule == pose.schedule then return true end
        self:AICancelIdle()
    end
    if now < (self.NextIdleTime or 0) then return false end
    local delay = settings.pose or {10, 20}
    if not self[fields.next_pose] then self[fields.next_pose] = now + sampleRange(delay) return false end
    if now < self[fields.next_pose] then return false end
    self[fields.next_pose] = now + sampleRange(delay)
    local sequence
    if config.select then sequence = config.select(self) else sequence = self:AISelectAction("idle_pose") end
    if not sequence or self:LookupSequence(sequence) < 0 then return false end
    local moving = self:GetSequenceMovement(self:LookupSequence(sequence), 0, 1)
    if moving then
        local clear
        if config.validate_path then clear = config.validate_path(self, sequence)
        else clear = self:AIValidateMotion(sequence, 0) end
        if not clear then return false end
    end
    -- Do not lock combat/navigation or reset facing for a quiet fidget.
    local animation, duration = self:PlayAnim("vjseq_" .. sequence, false, false, false, 0, {PlayBackRate = 1})
    if animation == ACT_INVALID or duration <= 0 then return false end
    self[fields.active] = {schedule = self.CurrentSchedule, finish = now + duration,
        idle_until = now + duration, previous_idle = self.NextIdleTime}
    self.NextIdleTime = now + duration
    return true
end

function methods:AIEndCorpseFire(now)
    local config = self.AIProfile and self:AIProfile().postcombat
    local action = config and self[config.fields.active]
    if not action or not action.firing then return end
    action.firing = nil
    if self.NextIdleTime == action.deadline then self.NextIdleTime = action.previous_idle or now end
    if action.schedule and self.CurrentSchedule == action.schedule then self:ClearSchedule() end
    if self:AIProfile().adapter == "human" and self.WeaponAttackAnim == action.activity then
        self.WeaponAttackAnim = ACT_INVALID
        self.WeaponAttackState = VJ.WEP_ATTACK_STATE_NONE
    end
    if self.TurnData and self.TurnData.Target == action.corpse and not self.TurnData.IsSchedule then
        self:ResetTurnTarget()
        self:SetIdealYaw(self:GetAngles().y)
    end
end

function methods:AIEndPostcombat(now)
    local config = self.AIProfile and self:AIProfile().postcombat
    if not config then return end
    self:AIEndCorpseFire(now)
    self[config.fields.active] = nil
end

function methods:AIStartPostcombat(victim, now, wasLast)
    if not self:AIHasCapability("postcombat") or not wasLast or not IsValid(victim)
        or self.Dead or self.VJ_Controlled or self.IsGuard or self.IsFollowing then return false end
    local config = self:AIProfile().postcombat
    if value(self, config.settings, {}).enabled == false then return false end
    self:AIEndPostcombat(now)
    local action = {victim = victim, corpse = victim.Corpse, position = Vector(victim:GetPos()),
        ready = now + value(self, config.delay, 2), deadline = now + value(self, config.timeout, 20)}
    self[config.fields.active] = action
    if config.started then config.started(self, action, now) end
    return true
end

function methods:AICorpseFirePoint(weapon)
    if not self:AIHasCapability("postcombat") or self:AIProfile().adapter ~= "human" then return end
    local config = self:AIProfile().postcombat
    local action = self[config.fields.active]
    if not action or not action.firing then return end
    local now, enemy = CurTime(), self:GetEnemy()
    local disabled = GetConVar("ai_disabled")
    local state = self.GetState and self:GetState()
    if disabled and disabled:GetBool() then return end
    if state and (state == VJ_STATE_FREEZE or state == VJ_STATE_ONLY_ANIMATION_NOATTACK) then return end
    local settings = value(self, config.settings, {})
    if settings.enabled == false or not settings.shoot_corpse or action.burst_done or now >= action.deadline
        or not searchReady(self, config, now) or self.IsGuard or self.IsFollowing or self:IsMoving()
        or (config.fire_allowed and not config.fire_allowed(self, action, now))
        or self.CurrentSchedule ~= action.schedule or not IsValid(action.corpse)
        or action.corpse:IsNPC() or action.corpse:IsPlayer()
        or (IsValid(enemy) and enemy ~= self[config.fields.transient_target] and enemy:Health() > 0)
        or (IsValid(action.victim) and action.victim:IsPlayer() and action.victim:Alive())
        or not IsValid(weapon) or weapon ~= action.weapon or weapon ~= self:GetActiveWeapon()
        or not config.weapon_allowed or not config.weapon_allowed(self, weapon) then return end
    local position = action.corpse:WorldSpaceCenter()
    local distance = self:GetPos():Distance(position)
    if distance <= (self.Weapon_MinDistance or 0) or distance >= (self.Weapon_MaxDistance or math.huge) then return end
    action.aim:Set(position) -- Keep the burst context identity while the body moves.
    return action.aim, action.corpse
end

function methods:AITryCorpseFire(now, action)
    if not self:AIHasCapability("postcombat") or self:AIProfile().adapter ~= "human" then return false end
    local config = self:AIProfile().postcombat
    if not action or action ~= self[config.fields.active] or action.fire_tried then return false end
    local enemy = self:GetEnemy()
    if not searchReady(self, config, now) or self:IsMoving()
        or (IsValid(enemy) and enemy:Health() > 0) then return false end
    action.fire_tried = true
    local settings = value(self, config.settings, {})
    if settings.enabled == false or not settings.shoot_corpse or self.Dead or self.VJ_Controlled
        or self.IsGuard or self.IsFollowing or now >= action.deadline
        or (config.fire_allowed and not config.fire_allowed(self, action, now)) then return false end
    local corpse, victim = action.corpse, action.victim
    if not IsValid(corpse) and IsValid(victim) then
        corpse = victim.Corpse
        if not IsValid(corpse) and victim:IsPlayer() then corpse = victim:GetRagdollEntity() end
    end
    local weapon = self:GetActiveWeapon()
    if not IsValid(corpse) or corpse:IsNPC() or corpse:IsPlayer()
        or (IsValid(victim) and victim:IsPlayer() and victim:Alive())
        or not IsValid(weapon) or not config.weapon_allowed or not config.weapon_allowed(self, weapon)
        or not config.fire_activity then return false end
    local position = corpse:WorldSpaceCenter()
    local distance = self:GetPos():Distance(position)
    if distance <= (self.Weapon_MinDistance or 0) or distance >= (self.Weapon_MaxDistance or math.huge) then return false end
    local trace = util.TraceLine({start = self:EyePos(), endpos = position, mask = MASK_SHOT, filter = {self, weapon}})
    if trace.StartSolid or (trace.Hit and trace.Entity ~= corpse) then return false end
    action.corpse, action.weapon, action.aim = corpse, weapon, Vector(position)
    action.activity = config.fire_activity(self, weapon)
    if not action.activity then return false end
    local animation = self:PlayAnim(action.activity, false, 0, false, 0, nil, function(schedule)
        schedule:EngTask("TASK_WAIT", action.deadline - now)
    end)
    if animation == ACT_INVALID then return false end
    action.schedule, action.previous_idle, action.firing = self.CurrentSchedule, self.NextIdleTime, true
    action.burst_limit, action.bursts_fired = value(self, config.burst_count, 1), 0
    self.NextIdleTime = action.deadline
    self.WeaponAttackAnim = action.activity
    self:SetTurnTarget(corpse, action.deadline - now)
    return true
end

-- A weapon reports an actual completed shot, not merely a firing attempt.
-- Keep this notification independent of any particular weapon or voice bank.
function methods:AINotifyCorpseShot(weapon, now)
    if not self:AIHasCapability("postcombat") or self:AIProfile().adapter ~= "human" then return false end
    local config = self:AIProfile().postcombat
    local action = self[config.fields.active]
    local enemy = self:GetEnemy()
    if not action or not action.firing or action.shot_notified or action.weapon ~= weapon
        or self.CurrentSchedule ~= action.schedule or self.Dead or self.VJ_Controlled
        or (IsValid(enemy) and enemy ~= self[config.fields.transient_target] and enemy:Health() > 0) then return false end
    action.shot_notified = true
    if config.fired then config.fired(self, action, now) end
    return true
end

function methods:AIUpdatePostcombat(now, enemy)
    local config = self.AIProfile and self:AIProfile().postcombat
    local action = config and self[config.fields.active]
    if not action then return end
    if not self:AIHasCapability("postcombat") or value(self, config.settings, {}).enabled == false
        or self.Dead or self.VJ_Controlled or self.IsGuard or self.IsFollowing or now >= action.deadline
        or (IsValid(enemy) and enemy:Health() > 0)
        or (action.firing and not self:AICorpseFirePoint(action.weapon)) then
        self:AIEndPostcombat(now)
        return
    end
    return action
end

function methods:AIThinkPostcombat(now)
    if not self:AIHasCapability("postcombat") then self:AIEndPostcombat(now) return false end
    local action = self:AIUpdatePostcombat(now, self:GetEnemy())
    if not action then return false end
    if now < action.ready or action.firing or self:IsMoving() then return true end
    local config = self:AIProfile().postcombat
    if not searchReady(self, config, now) then return true end
    local settings = value(self, config.settings, {})
    local distance = self:GetPos():Distance(action.position)
    if not action.approached and not self.DisableWandering and settings.approach
        and distance > (config.approach_minimum or 180) and distance < (config.approach_maximum or 800) then
        action.approached = true
        action.ready = now + (config.approach_wait or 5)
        self:SetLastPosition(action.position)
        self:SCHEDULE_GOTO_POSITION("TASK_WALK_PATH")
    else
        if self:AITryCorpseFire(now, action) then return true end
        self:AIEndPostcombat(now)
        if config.finished then config.finished(self, action, now) end
    end
    return true -- Do not start a quiet idle in the same tick as a postcombat action.
end


function methods:AIFinishInvestigation()
    local config = self.AIProfile and self:AIProfile().investigation
    local action = config and self[config.fields.active]
    if not action then return end
    self[config.fields.active] = nil
    if action.schedule and self.CurrentSchedule == action.schedule then
        self:ClearSchedule()
        self:StopMoving()
    end
end

function methods:AIStartInvestigation(source, position, now)
    if not self:AIHasCapability("investigation") or IsValid(self:GetEnemy()) then return false end
    local config = self:AIProfile().investigation
    self:AIEndPostcombat(now)
    self:AIRememberSound(source)
    self:AICancelIdle()
    local faceOnly = not position and IsValid(source) and self:GetTarget() == source
    self[config.fields.active] = {position = Vector(position or (faceOnly and self:GetPos() or self:GetLastPosition())),
        deadline = now + value(self, config.timeout, 20), phase = "enter", schedule = self.CurrentSchedule}
    return true
end

function methods:AIThinkInvestigation(now)
    if not self:AIHasCapability("investigation") then self:AIFinishInvestigation() return false end
    local config = self:AIProfile().investigation
    local action = self[config.fields.active]
    if not action then return false end
    local enemy = self:GetEnemy()
    if self.Dead or self.VJ_Controlled or (IsValid(enemy) and enemy:Health() > 0) or now >= action.deadline then
        self:AIFinishInvestigation()
        return false
    end
    if not self:IsMoving() and self:GetPos():Distance(action.position) < (config.arrival_distance or 80) then
        local sequence
        if config.select then sequence = config.select(self, action.phase)
        else sequence = self:AISelectAction("investigate_" .. action.phase) end
        action.phase = ({enter = "idle", idle = "exit"})[action.phase]
        if not action.phase then self[config.fields.active] = nil end
        if sequence then
            if config.play then config.play(self, sequence, now)
            else self:AIPlayReaction("investigate", sequence, now) end
            return true
        end
    end
    return false
end


-- Recover only ordinary close-range firing routes. VJ owns route selection;
-- this guard releases a stalled route and backs off its spacing retries.
function methods:AIUpdateSpacing(now, failed)
    local profile = self:AIProfile()
    local driver = profile.controller
    local config = driver and driver.spacing
    if not config then return end
    local fields = driver.fields
    local function cancel() self[fields.spacing] = nil end
    if not self:AIHasCapability("controller") or profile.adapter ~= "human" then cancel() return end
    local schedule, enemy = self.CurrentSchedule, self:GetEnemy()
    if self.Dead or self.VJ_Controlled or not searchReady(self, driver, now)
        or not schedule or schedule.Name ~= "SCHEDULE_GOTO_POSITION" or not schedule.CanShootWhenMoving
        or self:GetNavType() ~= NAV_GROUND or not self:OnGround() or self.PauseAttacks
        or not IsValid(enemy) or enemy:Health() <= 0
        or self:GetPos():DistToSqr(enemy:GetPos()) > (config.distance or 300) ^ 2
        or not self:Visible(enemy) then cancel() return end
    if self:GetMoveDelay() > 0 or IsValid(self:GetInternalVariable("m_hOpeningDoor")) then cancel() return end
    -- Never retire a route owned by cover, search, charge or a reaction.
    for _, name in ipairs({"cover", "search", "charge", "investigation", "postcombat", "idle", "obstacle", "flee"}) do
        local service = profile[name]
        if service and self[service.fields.active] then cancel() return end
    end
    local flank, reactions = profile.flank, profile.reactions
    if (flank and now < (self[flank.fields.finish] or 0))
        or (reactions and self[reactions.fields.kind]) then cancel() return end
    local weapon = self:GetActiveWeapon()
    if not IsValid(weapon) or weapon.IsMeleeWeapon or self:GetWeaponState() == VJ.WEP_STATE_RELOADING then cancel() return end
    local position = self:GetPos()
    if not failed then
        if not self:IsGoalActive() then cancel() return end
        local state = self[fields.spacing]
        if not state or state.schedule ~= schedule or state.enemy ~= enemy
            or position:DistToSqr(state.position) >= (config.progress or 8) ^ 2 then
            self[fields.spacing] = {schedule = schedule, enemy = enemy, position = Vector(position), time = now}
            return
        end
        if now - state.time < (config.stall_time or 1.2) then return end
    end
    cancel()
    local deadline = now + (config.retry_delay or 2)
    -- These are VJ's spacing gates, not its attack or chase timers. Keep firing
    -- available and preserve any longer cover/strafe cooldown already present.
    self.TakingCoverT = math.max(self.TakingCoverT or 0, deadline)
    self.NextWeaponStrafeT = math.max(self.NextWeaponStrafeT or 0, deadline)
    self[fields.last_spacing] = {time = now, reason = failed and "path_failed" or "no_progress"}
    if not failed then
        self:StopMoving()
        self:ClearGoal()
        self:ClearSchedule()
        self:ScheduleFinished(schedule)
    end -- Real task failures retain VJ's delayed cleanup and replacement guard.
    return true
end

-- A host calls this driver from VJ's active-update hook. It is not a Think hook
-- or a second navigation loop; it chooses which existing service may act next.
function methods:AISuspendActions(now)
    self:AIEndSurface(now, "suspended")
    self:AIEndFlee(now, "suspended")
    self:AIEndOpening(now)
    self:AIEndPostcombat(now)
    self:AIFinishSearch(now, false)
    self:AIEndCharge(now)
    self:AIFinishCover(now)
    self:AIFinishInvestigation()
    self:AICancelIdle()
    local profile = self:AIProfile()
    if profile.evasion then self[profile.evasion.fields.aim_started] = {} end
    if profile.obstacle then self[profile.obstacle.fields.active] = nil end
    if profile.controller then self[profile.controller.fields.spacing] = nil end
end

function methods:AIThinkTactics(now)
    if not self:AIHasCapability("controller") then self:AISuspendActions(now) return end
    if self.Dead or self:Health() <= 0 or self.VJ_Controlled then self:AISuspendActions(now) return end
    local profile = self:AIProfile()
    local config = profile.controller
    if now < (self[config.fields.next_tactic] or 0) then return end
    self[config.fields.next_tactic] = now + (config.tactic_interval or 0.2)
    local enemy = self:GetEnemy()
    self:AIUpdatePostcombat(now, enemy)
    if config.before_tactics then config.before_tactics(self, now, enemy) end
    if self:AIThinkFlee(now) then return end
    self:AIUpdateSpacing(now)
    local visible = IsValid(enemy) and self.EnemyData and self.EnemyData.Visible and self:Visible(enemy)
    local search = profile.search
    if self:AIHasCapability("search") then
        if visible then
            local previous = self[search.fields.active]
            if previous and previous.enemy == enemy and search.reacquired then search.reacquired(self, enemy, now) end
            self:AIFinishSearch(now, false)
            self[search.fields.seen] = {enemy = enemy, origin = Vector(enemy:GetPos()),
                position = Vector(self:GetAimPosition(enemy, self:EyePos(), 0)), time = now}
        elseif IsValid(enemy) and enemy:Health() > 0 then self:AIStartSearch(now) end
    elseif search then self:AIFinishSearch(now, false) end
    local searching = search and self[search.fields.active]
    self:AISetPerception(visible and "combat" or searching and "search" or self.Alerted and "alert" or "idle")
    if self:AIMaintainCover(now, enemy) then self:AIEndSearchAction(now) return end
    if not searchReady(self, config, now) then self:AIEndSearchAction(now) return end
    if self:AITryObstacle(now) then return end
    if not IsValid(enemy) and self:AIHearSound(now) then return end
    if searching then self:AIThinkSearch(now, enemy) return end
    if not IsValid(enemy) or enemy:Health() <= 0 then
        self:AIEndCharge(now)
        if self:AIThinkInvestigation(now) then return end
        if self:AIThinkPostcombat(now) then return end
        local investigation = profile.investigation
        if not investigation or not self[investigation.fields.active] then self:AIThinkIdle(now) end
        return
    end
    if self:AIHasCapability("cover") and config.cover_requested and config.cover_requested(self, now, enemy) then
        self:AIEndCharge(now)
        self:AITakeCover(now)
        return
    end
    if not self:AIMaintainCharge(now, enemy) then self:AITryFlank(now, enemy) end
end

function methods:AIThinkActions(now)
    if self:AILeapActive() or self:AISurfaceActive() then return end
    if not self:AIHasCapability("controller") then self:AISuspendActions(now) return end
    local profile = self:AIProfile()
    local config = profile.controller
    self:AIOpeningReady(now)
    if config.initialize then config.initialize(self, now) else self:AIInitializeShield(now) end
    self:AIUpdateReaction(now)
    if self.Dead or self:Health() <= 0 or self.VJ_Controlled then self:AISuspendActions(now) return end
    if config.priority_reaction and config.priority_reaction(self, now) then return end
    if now < (self[config.fields.next_sample] or 0) then return end
    self[config.fields.next_sample] = now + (config.sample_interval or 0.1)
    local evasion = profile.evasion
    if self:AIHasCapability("evasion") and self:AIHasCapability("reactions") then
        local threat = self:AIAimThreat(now)
        if (not config.evasion_allowed or config.evasion_allowed(self, now))
            and now >= (self[evasion.fields.next_evade] or 0) and searchReady(self, config, now) then
            if threat then self:AITryEvade(now)
            elseif self:AIGunfireThreat(now) then
                local settings = value(self, evasion.gunfire, {})
                if math.Rand(0, 1) < (settings.chance or 0) and self:AITryEvade(now, settings.delay, "gunfire_evade") then
                    self[evasion.fields.gunfire_count] = (self[evasion.fields.gunfire_count] or 0) + 1
                end
            end
        end
    elseif evasion then self[evasion.fields.aim_started] = {} end
    if self.IsInitialized and now >= reactionEnd(self) then self:AIThinkTactics(now) end
end

-- Retreat uses one VJ route per attempt. It never steers the actor with SetPos
-- or refreshes a path each Think; ownership and a finite deadline release it.
local fleeTimers = {"NextChaseTime", "NextDoAnyAttackT", "NextWeaponStrafeT", "TakingCoverT"}

function methods:AIEndFlee(now, reason)
    local config = self.AIProfile and self:AIProfile().flee
    local action = config and self[config.fields.active]
    if not action then return end
    self[config.fields.active] = nil
    local settings = value(self, config.settings, {})
    self[config.fields.next_attempt] = now + (settings.cooldown or 8)
    for key, previous in pairs(action.timers) do
        if self[key] == action.deadline then self[key] = math.max(now, previous) end
    end
    if action.schedule and self.CurrentSchedule == action.schedule then
        self:ClearSchedule()
        self:StopMoving()
    end
    self[config.fields.last] = {reason = action.reason, ended = reason, time = now}
    if config.finished then config.finished(self, action, now) end
end

function methods:AIFleeDestination(threat, position)
    local config = self:AIProfile().flee
    if config.destination then return config.destination(self, threat, position) end
    -- Prefer real nearby protection, then choose a grounded point away from
    -- the observed threat. VJ owns pathfinding to that candidate.
    if self:AIHasCapability("cover") and IsValid(threat) then
        local cover = self:AIFindCover(threat)
        if cover and cover:DistToSqr(self:GetPos()) > 64 ^ 2 then return cover end
    end
    local origin, best, score = self:GetPos(), nil, -math.huge
    local mins, maxs = self:GetCollisionBounds()
    local away = origin - position
    away.z = 0
    if away:LengthSqr() < 1 then away = -self:GetForward() else away:Normalize() end
    for _, point in ipairs(VJ.TraceDirections(self, "Radial", config.distance or 384, false, false, 8) or {}) do
        local delta = point - origin
        local progress = delta:Dot(away)
        if progress > 64 then
            local ground = util.TraceLine({start = point + Vector(0, 0, 24), endpos = point - Vector(0, 0, 72),
                mask = MASK_NPCSOLID, filter = self})
            if ground.Hit and not ground.StartSolid and ground.HitNormal.z > 0.7 then
                local target = ground.HitPos + Vector(0, 0, 2)
                local room = util.TraceHull({start = target, endpos = target, mins = mins, maxs = maxs,
                    mask = MASK_NPCSOLID, filter = self})
                if not room.Hit and not room.StartSolid and progress > score then best, score = target, progress end
            end
        end
    end
    return best
end

function methods:AIStartFlee(reason, threat, now)
    if not self:AIHasCapability("flee") or self.Dead or self:Health() <= 0 or self.VJ_Controlled
        or not IsValid(threat) or threat:Health() <= 0 or self:GetNavType() ~= NAV_GROUND
        or not self:OnGround() or self.IsGuard or self.IsFollowing or self.DisableChasingEnemy then return false end
    local config = self:AIProfile().flee
    if self[config.fields.active] or now < (self[config.fields.next_attempt] or 0)
        or self:IsBusy("Activities") or self.AttackType or (config.allowed and not config.allowed(self, reason)) then return false end
    local settings = value(self, config.settings, {})
    local position = Vector(threat:GetPos())
    local destination = self:AIFleeDestination(threat, position)
    if not destination then self[config.fields.next_attempt] = now + (config.failed_retry or 2) return false end
    self:AISuspendActions(now)
    local cower = settings.cower or {0, 0}
    local action = {reason = reason, threat = threat, position = position, destination = destination,
        deadline = now + math.max(1, settings.duration or 4), cower_time = math.Rand(cower[1], cower[2]), timers = {}}
    self[config.fields.active] = action
    for _, key in ipairs(fleeTimers) do
        local previous = self[key] or 0
        if previous < action.deadline then action.timers[key], self[key] = previous, action.deadline end
    end
    self:SetLastPosition(destination)
    self:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH", function(schedule)
        action.schedule = schedule
        schedule.CanShootWhenMoving = false
        schedule.TurnData = nil
        schedule.RunCode_OnFinish = function()
            if self[config.fields.active] == action then action.arrived = true end
        end
        schedule.RunCode_OnFail = function()
            if self[config.fields.active] == action then action.failed = true end
        end
    end)
    if config.started then config.started(self, action, now) end
    return true
end

function methods:AIThinkFlee(now)
    local config = self:AIProfile().flee
    if not config then return false end
    local action = self[config.fields.active]
    if not self:AIHasCapability("flee") or self.Dead or self.VJ_Controlled then self:AIEndFlee(now, "disabled") return false end
    if not action then
        local enemy, settings = self:GetEnemy(), value(self, config.settings, {})
        if IsValid(enemy) and enemy:Health() > 0 and self:Visible(enemy)
            and self:GetPos():DistToSqr(enemy:GetPos()) < (settings.proximity or 0) ^ 2 then
            return self:AIStartFlee("proximity", enemy, now)
        end
        return false
    end
    if action.failed or not IsValid(action.threat) or action.threat:Health() <= 0
        or self.AttackType or (not action.arrived and self.CurrentSchedule ~= action.schedule) then
        self:AIEndFlee(now, "interrupted") return false
    end
    if action.arrived and not action.holding then
        if self.CurrentSchedule and self.CurrentSchedule ~= action.schedule then
            self:AIEndFlee(now, "interrupted") return false
        end
        if action.cower_time > 0 and self:AIHasCapability("cover") and self:AICoverPoint(self:GetPos(), action.threat) then
            action.holding = true
            local old = action.deadline
            action.deadline = now + action.cower_time
            for key in pairs(action.timers) do if self[key] == old then self[key] = action.deadline end end
            self:SCHEDULE_IDLE_STAND()
            action.schedule = self.CurrentSchedule
            if config.cower then config.cower(self, action, now) end
        else self:AIEndFlee(now, "escaped") return false end
    elseif action.holding and (self:Visible(action.threat) or self.CurrentSchedule ~= action.schedule) then
        self:AIEndFlee(now, "exposed") return false
    end
    if now >= action.deadline then self:AIEndFlee(now, "timeout") return false end
    return true
end

function methods:AIAllyLost(ally, now)
    if not self:AIHasCapability("flee") or not IsValid(ally) then return false end
    local config = self:AIProfile().flee
    if config.notice_loss and not config.notice_loss(self, ally) then return false end
    if self:GetPos():DistToSqr(ally:GetPos()) > (config.loss_range or 1200) ^ 2 then return false end
    local settings = value(self, config.settings, {})
    local losses = self[config.fields.losses]
    if not losses or now - losses.time > (config.loss_window or 10) then
        losses = {time = now, count = 0, seen = setmetatable({}, {__mode = "k"})}
        self[config.fields.losses] = losses
    end
    if losses.seen[ally] then return false end
    losses.seen[ally] = true
    local leader = config.is_leader and config.is_leader(self, ally)
    if not leader then losses.count = losses.count + 1 end
    local chance = leader and settings.leader_chance
        or (losses.count > 1 and settings.second_peer_chance or settings.peer_chance)
    if math.Rand(0, 1) >= (chance or 0) then return false end
    return self:AIStartFlee(leader and "leader_lost" or "peer_lost", self:GetEnemy(), now)
end

return methods
