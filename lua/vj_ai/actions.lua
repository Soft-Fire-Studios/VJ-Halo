-- Grounded reaction playback, authored motion checks and shared threat samples.
local actions = {methods = {}}
local methods = actions.methods
VJAI.AimCache = VJAI.AimCache or {samples = {}, next_sample = 0, last_sample = 0}
VJAI.Gunfire = VJAI.Gunfire or setmetatable({}, {__mode = "k"})
local ignoredWeapons = {weapon_physgun = true, gmod_tool = true, gmod_camera = true}

local function value(actor, setting, fallback)
    if type(setting) == "function" then setting = setting(actor) end
    if setting == nil then return fallback end
    return setting
end

function methods:AISelectAction(name)
    if not self:AIHasCapability("reactions") then return end
    local config = self:AIProfile().reactions
    local mapping = config.actions
    if not mapping then return end
    local family = value(self, config.family, mapping.default_family or "any")
    local entries = mapping.families[family] or mapping.families[mapping.default_family or "any"]
    local choices = entries and entries[name]
    return choices and #choices > 0 and choices[math.random(#choices)] or nil
end

function methods:AISelectDamage(action, damage, hitgroup)
    if not self:AIHasCapability("reactions") then return end
    local config = self:AIProfile().reactions
    local mapping = config.damage
    if not mapping then return end
    local defaultRegion = mapping.default_region or "body"
    local part = mapping.hitgroups and mapping.hitgroups[hitgroup] or defaultRegion
    local direction = -damage:GetDamageForce()
    local attacker = damage:GetAttacker()
    if IsValid(attacker) and attacker ~= self then direction = attacker:GetPos() - self:GetPos() end
    local front, side = direction:Dot(self:GetForward()), direction:Dot(self:GetRight())
    local facing = math.abs(front) >= math.abs(side) and (front >= 0 and "front" or "back")
        or (side >= 0 and "right" or "left")
    local fallback = mapping.default_family or "any"
    for _, family in ipairs({value(self, config.family, fallback), fallback}) do
        local entries = mapping.families[family]
        entries = entries and entries[action]
        if entries then
            for _, axis in ipairs({facing, mapping.default_facing or "front"}) do
                local regions = entries[axis]
                local choices = regions and (regions[part] or regions[defaultRegion])
                if choices and #choices > 0 then return "vjseq_" .. choices[math.random(#choices)] end
            end
        end
    end
end

function methods:AIReactionReady(now)
    if not self:AIHasCapability("reactions") then return false end
    local config = self:AIProfile().reactions
    return not self.Dead and self:Health() > 0 and not self.VJ_Controlled
        and self.MovementType == VJ_MOVETYPE_GROUND and self:OnGround()
        and self:GetNavType() == NAV_GROUND and not self.AttackType
        and (self:AIProfile().adapter ~= "human" or self:GetWeaponState() ~= VJ.WEP_STATE_RELOADING)
        and not self:IsBusy("Activities") and now >= (self[config.fields.finish] or 0)
        and (not config.allowed or config.allowed(self, now))
end

function methods:AIPlayReaction(kind, sequence, now)
    if not self:AIHasCapability("reactions") or not sequence or self:LookupSequence(sequence) < 0 then return false end
    local config = self:AIProfile().reactions
    local animation, duration = self:PlayAnim("vjseq_" .. sequence, true, false, false, 0, {PlayBackRate = 1})
    if animation == ACT_INVALID or duration <= 0 then return false end
    if config.started then config.started(self, kind, sequence, now, duration) end
    if config.lock_heading ~= false then
        self:ResetTurnTarget()
        self:SetIdealYaw(self:GetAngles().y)
    end
    if config.stop_gesture then config.stop_gesture(self, kind, sequence) end
    local state = config.fields
    self[state.kind], self[state.schedule], self[state.finish] = kind, self.CurrentSchedule, now + duration
    self[state.last] = {kind = kind, sequence = sequence, time = now, duration = duration}
    if config.network then self:SetNW2String(config.network, kind) end
    if config.played then config.played(self, kind, sequence, now, duration) end
    return true
end

function methods:AIUpdateReaction(now)
    local config = self.AIProfile and self:AIProfile().reactions
    if not config then return end
    local state = config.fields
    local kind = self[state.kind]
    if not kind then return end
    local expired = now >= (self[state.finish] or 0)
    if not expired and self:AIHasCapability("reactions") then return end
    local obstacle = self:AIProfile().obstacle
    local action = obstacle and self[obstacle.fields.active]
    if action and action.schedule == self[state.schedule] then self[obstacle.fields.active] = nil end
    self[state.kind], self[state.schedule] = nil, nil
    if not expired then self[state.finish] = now end
    if config.network then self:SetNW2String(config.network, "") end
    if config.finished then config.finished(self, kind, now, expired) end
end

function methods:AIValidateMotion(sequence, minimum, obstacle)
    if not self:AIHasCapability("reactions") then return false end
    local config = self:AIProfile().reactions
    local id = self:LookupSequence(sequence)
    if id < 0 then return false end
    local start, previous = self:GetPos(), self:GetPos()
    local yaw = Angle(0, self:GetAngles().y, 0)
    local mins, maxs = self:GetCollisionBounds()
    local weapon = self.GetActiveWeapon and self:GetActiveWeapon()
    local filter = {self}
    if IsValid(weapon) then filter[#filter + 1] = weapon end
    if IsValid(obstacle) then filter[#filter + 1] = obstacle end
    local movement = 0
    local samples = config.path_samples or 8
    -- Trace each portion of the authored curve, including support below it.
    for step = 1, samples do
        local ok, delta = self:GetSequenceMovement(id, 0, step / samples)
        if not ok then return false end
        delta:Rotate(yaw)
        local position = start + delta
        local trace = util.TraceHull({start = previous + Vector(0, 0, 2), endpos = position + Vector(0, 0, 2),
            mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = filter})
        if trace.StartSolid or trace.AllSolid or trace.Hit then return false end
        local ground = util.TraceHull({start = position + Vector(0, 0, config.ground_up or 18),
            endpos = position - Vector(0, 0, config.ground_down or 24),
            mins = Vector(mins.x, mins.y, 0), maxs = Vector(maxs.x, maxs.y, 2), mask = MASK_NPCSOLID, filter = filter})
        if ground.StartSolid or ground.AllSolid or not ground.Hit or ground.HitNormal.z < (config.ground_normal or 0.7) then return false end
        movement = movement + previous:Distance(position)
        previous = position
    end
    return movement >= (minimum or config.minimum_motion or 24)
end

function methods:AITryEvade(now, cooldown, kind)
    if not self:AIHasCapability("evasion") or not self:AIHasCapability("reactions") then return false end
    local config = self:AIProfile().evasion
    local state = config.fields
    local reactions = value(self, config.choices, {})
    local first = math.random(2) == 1 and "left" or "right"
    for _, side in ipairs({first, first == "left" and "right" or "left"}) do
        local choices = reactions["evade_" .. side] or {}
        local offset = #choices > 0 and math.random(#choices) or 1
        for i = 1, #choices do
            local sequence = choices[(i + offset - 2) % #choices + 1]
            local clear = config.validate_path and config.validate_path(self, sequence)
            if not config.validate_path then clear = self:AIValidateMotion(sequence) end
            local played
            if clear then
                if config.play then played = config.play(self, kind or "aim_evade", sequence, now)
                else played = self:AIPlayReaction(kind or "aim_evade", sequence, now) end
            end
            if played then
                local finish = self[self:AIProfile().reactions.fields.finish] or now
                self[state.next_evade] = finish + (cooldown or value(self, config.cooldown, 4))
                self[state.aim_started] = {}
                self[state.count] = (self[state.count] or 0) + 1
                if config.network then self:SetNW2Int(config.network, self[state.count]) end
                return true
            end
        end
    end
    self[state.next_evade] = now + (config.failed_delay or 0.5)
    return false
end

local function playerAim(now)
    local cache = VJAI.AimCache
    if now < cache.next_sample and now >= cache.last_sample then return cache.samples end
    cache.next_sample, cache.last_sample, cache.samples = now + 0.1, now, {}
    local ignored = GetConVar("ai_ignoreplayers")
    if ignored and ignored:GetBool() then return cache.samples end
    for _, ply in ipairs(player.GetAll()) do
        local weapon = ply:GetActiveWeapon()
        if ply:Alive() and not ply:IsFlagSet(FL_NOTARGET) and IsValid(weapon)
            and not ignoredWeapons[weapon:GetClass()] then
            local start = ply:GetShootPos()
            local trace = util.TraceLine({start = start, endpos = start + ply:GetAimVector() * 32768,
                mask = MASK_SHOT, filter = {ply, weapon}})
            cache.samples[#cache.samples + 1] = {player = ply, target = trace.Entity, origin = start}
        end
    end
    return cache.samples
end

function methods:AIAimThreat(now)
    if not self:AIHasCapability("evasion") then return end
    local config = self:AIProfile().evasion
    local state = config.fields
    local started, aiming = self[state.aim_started] or {}, {}
    local threat
    for _, sample in ipairs(playerAim(now)) do
        local ply = sample.player
        if sample.target == self and IsValid(ply) and self:Disposition(ply) == D_HT then
            local offset = sample.origin - self:WorldSpaceCenter()
            local distance = offset:Length()
            if distance >= value(self, config.minimum_distance, 128) and distance <= value(self, config.range, 2400)
                and self:GetForward():Dot(offset:GetNormalized()) >= math.cos(math.rad(value(self, config.fov, 160) * 0.5))
                and self:Visible(ply) then
                aiming[ply] = started[ply] or now
                if now - aiming[ply] >= value(self, config.aim_time, 0.75) then threat = ply end
            end
        end
    end
    self[state.aim_started] = aiming
    return threat
end

function actions.RecordGunfire(attacker, origin, finish)
    if not IsValid(attacker) or not (attacker:IsNPC() or attacker:IsNextBot())
        or attacker:Health() <= 0 or not origin or not finish then return end
    local now = CurTime()
    local previous = VJAI.Gunfire[attacker]
    if previous and now >= previous.time and now - previous.time < 0.1 then return end
    local delta = finish - origin
    local distance = delta:Length()
    if distance <= 0 then return end
    VJAI.Gunfire[attacker] = {origin = Vector(origin), direction = delta:GetNormalized(), distance = distance, time = now}
end

function actions.ObserveBullet(emitter, bullet)
    local trace = bullet.Trace
    if not trace or trace.StartSolid then return end
    local attacker = bullet.Attacker
    if not IsValid(attacker) or not (attacker:IsNPC() or attacker:IsNextBot()) then
        attacker = emitter
        if IsValid(emitter) and not (emitter:IsNPC() or emitter:IsNextBot()) then attacker = emitter:GetOwner() end
    end
    actions.RecordGunfire(attacker, trace.StartPos, trace.HitPos)
end

function methods:AIGunfireThreat(now)
    if not self:AIHasCapability("evasion") then return end
    local config = self:AIProfile().evasion
    local state = config.fields
    local settings = value(self, config.gunfire, false)
    if not settings or settings.enabled == false or now < (self[state.next_gunfire] or 0) then return end
    local center = self:WorldSpaceCenter()
    for attacker, shot in pairs(VJAI.Gunfire) do
        if not IsValid(attacker) or now - shot.time > 0.35 or attacker:Health() <= 0 then
            VJAI.Gunfire[attacker] = nil
        elseif attacker ~= self and self:Disposition(attacker) == D_HT and not attacker:IsFlagSet(FL_NOTARGET) then
            local offset = shot.origin - center
            local distance = offset:Length()
            local along = -offset:Dot(shot.direction)
            local point = shot.origin + shot.direction * math.Clamp(along, 0, shot.distance)
            if along > 0 and distance >= value(self, config.minimum_distance, 128) and distance <= value(self, config.range, 2400)
                and self:GetForward():Dot(offset:GetNormalized()) >= math.cos(math.rad(value(self, config.fov, 160) * 0.5))
                and self:NearestPoint(point):Distance(point) <= settings.proximity and self:Visible(attacker) then
                local weapon = attacker.GetActiveWeapon and attacker:GetActiveWeapon()
                local trace = util.TraceLine({start = shot.origin, endpos = center, mask = MASK_SHOT,
                    filter = IsValid(weapon) and {attacker, weapon} or attacker})
                if not trace.StartSolid and (not trace.Hit or trace.Entity == self) then
                    -- One probability trial per cooldown, not per pellet.
                    self[state.next_gunfire] = now + settings.delay
                    self[state.last_gunfire] = {attacker = attacker:EntIndex(), class = attacker:GetClass(), time = now}
                    return attacker
                end
            end
        end
    end
end

function methods:AIObstacleOptions(prop)
    if not self:AIHasCapability("obstacle") then return end
    local config = self:AIProfile().obstacle
    local push, damage = value(self, config.push, false), value(self, config.damage, false)
    if not push and not damage then return end
    local convar = GetConVar("vj_npc_melee_propint")
    local mode = convar and convar:GetInt() or 1
    if mode == 0 or not IsValid(prop) or not prop.VJ_ID_Attackable or prop.VJ_ID_Living
        or prop.VJ_ID_Grenade or prop.VJ_ID_Danger or prop:IsVehicle() or prop:IsNPC() or prop:IsPlayer()
        or prop:IsNextBot() or prop:GetMoveType() ~= MOVETYPE_VPHYSICS or IsValid(prop:GetParent())
        or prop:IsPlayerHolding() then return end
    local physics = prop:GetPhysicsObject()
    if not IsValid(physics) or not physics:IsMotionEnabled() or constraint.HasConstraints(prop) then return end
    local mins, maxs = self:GetCollisionBounds()
    local span = prop:OBBMaxs() - prop:OBBMins()
    local size = math.max(span.x, span.y, span.z)
    -- Clearance is relative to the actor hull; species policy supplies eligibility.
    if size <= math.max(maxs.x - mins.x, maxs.y - mins.y) * (config.minimum_width or 0.5) or size > (maxs.z - mins.z) * (config.maximum_height or 1) then return end
    local mine = self:GetPhysicsObject()
    if physics:GetMass() > value(self, config.maximum_mass, IsValid(mine) and mine:GetMass() or 200) then return end
    push = push and mode ~= 2
    damage = damage and mode ~= 3 and prop:Health() > 0
    if push or damage then return physics, push, damage end
end

function methods:AITryObstacle(now, failed)
    if not self:AIHasCapability("obstacle") or not self:AIHasCapability("reactions") then return end
    local config, reaction = self:AIProfile().obstacle, self:AIProfile().reactions
    local fields = config.fields
    if now < (self[fields.next_attempt] or 0) or (not failed and now < (self[fields.next_check] or 0)) then return end
    self[fields.next_check] = now + (config.check_interval or 0.5)
    if not self.HasMeleeAttack or self.PauseAttacks or self.Flinching or self.IsGuard or self.IsFollowing
        or self.DisableChasingEnemy or not self.CurrentSchedule
        or (config.allowed and not config.allowed(self, now)) or not self:AIReactionReady(now) then return end
    if not value(self, config.push, false) and not value(self, config.damage, false) then return end
    local origin = self:GetPos()
    local delta
    if self:IsGoalActive() then
        delta = self:GetCurWaypointPos() - origin
    elseif failed and self[fields.move_intent] and now - (self[fields.move_time] or -1) < (config.intent_age or 0.25) then
        delta = Vector(self[fields.move_intent]) * self.MeleeAttackDamageDistance
    else return end
    delta.z = 0
    if delta:Length() < (config.minimum_route or 8) then return end
    local direction = delta:GetNormalized()
    if self:GetForward():Dot(direction) < (config.heading_dot or 0.866) then return end
    local mins, maxs = self:GetCollisionBounds()
    local weapon = (self.GetActiveWeapon and self:GetActiveWeapon())
    local filter = IsValid(weapon) and {self, weapon} or {self}
    local trace = util.TraceHull({start = origin + Vector(0, 0, 2),
        endpos = origin + direction * math.min(delta:Length(), self.MeleeAttackDamageDistance) + Vector(0, 0, 2),
        mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = filter})
    local prop = trace.Entity
    if trace.StartSolid or trace.AllSolid or not trace.Hit or not self:AIObstacleOptions(prop) then return end
    local side = (prop:WorldSpaceCenter() - origin):Dot(self:GetRight()) > 0 and "right" or "left"
    for _, name in ipairs({side, side == "left" and "right" or "left"}) do
        local sequence = self:AISelectAction((config.action_prefix or "smash_") .. name)
        if sequence and self:AIValidateMotion(sequence, 0, prop) and self:AIPlayReaction(config.reaction_kind or "obstacle_smash", sequence, now) then
            self[fields.active] = {target = prop, weapon = weapon, sequence = self:LookupSequence(sequence),
                schedule = self.CurrentSchedule, side = side == "right" and 1 or -1}
            self[fields.next_attempt] = self[reaction.fields.finish] + (config.cooldown or 2)
            return true
        end
    end
end

function methods:AIObstacleHit()
    if not self:AIHasCapability("obstacle") or not self:AIHasCapability("reactions") then return end
    local config, reaction = self:AIProfile().obstacle, self:AIProfile().reactions
    local fields = config.fields
    local action = self[fields.active]
    if not action or action.hit or self.Dead or self:Health() <= 0 or self.VJ_Controlled or self.Flinching
        or not self.HasMeleeAttack or CurTime() >= (self[reaction.fields.finish] or 0) or self[reaction.fields.kind] ~= (config.reaction_kind or "obstacle_smash")
        or self.CurrentSchedule ~= action.schedule or self:GetSequence() ~= action.sequence
        or (self.GetActiveWeapon and self:GetActiveWeapon()) ~= action.weapon then return end
    local physics, push, damage = self:AIObstacleOptions(action.target)
    if not physics then return end
    -- PlayAnim pauses ordinary attacks. Permit only this synchronous, scoped
    -- VJ melee call from the owned impact event; no attack/reset timers added.
    local state, pause = self.AttackState, self.PauseAttacks
    local knockback, disabled = self.HasMeleeAttackKnockBack, self.DisableDefaultMeleeAttackDamageCode
    self[fields.context] = {action = action, push = push}
    self.AttackState, self.PauseAttacks = VJ.ATTACK_STATE_STARTED, false
    self.HasMeleeAttackKnockBack, self.DisableDefaultMeleeAttackDamageCode = false, not damage
    local ok, message = xpcall(function() self:ExecuteMeleeAttack() end, debug.traceback)
    self[fields.context] = nil
    self.HasMeleeAttackKnockBack, self.DisableDefaultMeleeAttackDamageCode = knockback, disabled
    if not self.Dead then self.AttackState, self.PauseAttacks = state, pause end
    if not ok then ErrorNoHalt("VJ AI obstacle melee: " .. message .. "\n") end
end

function methods:AIObstacleMelee(status, ent)
    local config = self.AIProfile and self:AIProfile().obstacle
    if not config then return end
    local fields = config.fields
    local context = self[fields.context]
    if not context or status ~= "PreDamage" then return end
    if not self:AIHasCapability("obstacle") then return true end
    local action = context.action
    if ent ~= action.target or action.hit then return true end
    local physics = self:AIObstacleOptions(ent)
    if not physics then return true end
    local origin = self:WorldSpaceCenter()
    local point = ent:NearestPoint(origin)
    local trace = util.TraceLine({start = origin, endpos = point, mask = MASK_SHOT, filter = {self, action.weapon}})
    if point:Distance(origin) > self.MeleeAttackDamageDistance or trace.StartSolid
        or (trace.Hit and trace.Entity ~= ent) then return true end
    action.hit = true
    if context.push then
        -- VJ's Human knockback uses Entity:SetVelocity. Physics props need the
        -- impulse on their PhysObj; reuse VJ speed, direct it out of the route.
        local velocity = self:MeleeAttackKnockbackVelocity(ent)
        physics:Wake()
        physics:AddVelocity(self:GetRight() * action.side * velocity:Length2D() + self:GetUp() * velocity.z)
    end
    self[fields.count] = (self[fields.count] or 0) + 1
end

function methods:AIObstacleTraceOrigin()
    local config = self.AIProfile and self:AIProfile().obstacle
    if config and self[config.fields.context] then return self:WorldSpaceCenter() end
    return self:AIBaseCall("MeleeAttackTraceOrigin")
end

function methods:AIObstacleTraceDirection()
    local config = self.AIProfile and self:AIProfile().obstacle
    if config and self[config.fields.context] then return self:GetForward() end
    return self:AIBaseCall("MeleeAttackTraceDirection")
end

return actions
