-- Server-only infection transactions. Real NPC deaths and server corpses own
-- conversion; no live host removal, automatic resurrection or weapon copying.
CE8 = CE8 or {}
local Infection = CE8.FloodInfection or {}
CE8.FloodInfection = Infection
local function weak() return setmetatable({}, {__mode = "k"}) end
Infection.jobs, Infection.claims = Infection.jobs or weak(), Infection.claims or weak()
Infection.bodies, Infection.deaths = Infection.bodies or weak(), Infection.deaths or weak()
Infection.forms = Infection.forms or {}
Infection.damage = Infection.damage or weak()
local difficulty = include("campaign_evolved/difficulty.lua")
local human = {npc_citizen = true, npc_combine_s = true, npc_metropolice = true}
local machines = {npc_turret_floor = true, npc_turret_ceiling = true, npc_manhack = true,
    npc_rollermine = true, npc_cscanner = true, npc_clawscanner = true, npc_strider = true,
    npc_combinedropship = true, npc_combinegunship = true, npc_helicopter = true}
local timers = {"NextChaseTime", "NextIdleTime", "NextDoAnyAttackT", "AttackAnimTime", "AnimLockTime"}
local function bodyPoint(body)
    local physics = body:GetPhysicsObject()
    return IsValid(physics) and physics:GetPos() or body:WorldSpaceCenter()
end
local function bodyContact(actor, body)
    local start = actor:WorldSpaceCenter()
    local trace = util.TraceLine({start = start, endpos = bodyPoint(body), mask = MASK_SHOT, filter = actor})
    if trace.Entity == body and trace.HitPos and start:DistToSqr(trace.HitPos) <= actor:CE8Data().infection.reach ^ 2 then
        return trace
    end
end
local function usableBody(body)
    return IsValid(body) and body:GetClass() == "prop_ragdoll" and not body.IsVJBaseCorpse_Gib and not body.CE8BodyDestroyed
        and not (body.IsOnFire and body:IsOnFire())
        and not (body.IsFlagSet and FL_DISSOLVING and body:IsFlagSet(FL_DISSOLVING))
end
local function enabled(actor)
    local cv = GetConVar("ai_disabled")
    local config = IsValid(actor) and actor.CE8Data and actor:CE8Data().infection
    return config and config.enabled ~= false and not actor.Dead and actor:Health() > 0
        and not actor.VJ_Controlled and not (cv and cv:GetBool()) and actor:GetState() ~= VJ_STATE_FREEZE
end
local function shielded(host)
    return (tonumber(host.CE8Shield) or 0) > 0 or (tonumber(host.AIShield) or 0) > 0
        or (host:IsPlayer() and host:Armor() > 0)
end
local function kind(host, dead)
    if host.CE8BodyDestroyed then return end
    if not IsValid(host) or host:IsPlayer() or not host:IsNPC() then return end
    local label, class = host.CE8UnitLabel, host:GetClass()
    if label == "flood_combat_human" or label == "flood_combat_elite" then
        return dead and label or nil
    end
    if (label and label:find("flood", 1, true)) or class:find("flood", 1, true) then return end
    if label == "elite" or class == "npc_vortigaunt" then return "flood_combat_elite" end
    if human[class] then return "flood_combat_human" end
    if machines[class] or host.IsVJBaseSNPC_Tank or (host.GetBloodColor and host:GetBloodColor() == DONT_BLEED)
        or (VJ.BLOOD_COLOR_OIL and host.BloodColor == VJ.BLOOD_COLOR_OIL) then return end
    -- Rig compatibility is a Source policy for otherwise unknown organic NPCs.
    for _, bone in ipairs({"ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Head1"}) do
        local index = host:LookupBone(bone)
        if index == nil or index < 0 then return end
    end
    return "flood_combat_human"
end
local function descriptor(host, dead)
    local owner = kind(host, dead)
    local form = owner and Infection.forms[owner]
    if not form then return end
    local count = host.CE8Resurrections or 0
    local wasFlood = host.CE8UnitLabel == owner
    if wasFlood and count >= form.resurrection.limit then return end
    return {owner = owner, wasFlood = wasFlood, count = count, dead = dead,
        creator = host:GetCreator(), snapshot = host.AIAnatomySnapshot and host:AIAnatomySnapshot(),
        position = Vector(host:GetPos()), yaw = host:GetAngles().y, time = CurTime()}
end
local function vulnerable(actor, host, afterDamage)
    if not IsValid(host) or host:IsPlayer() or shielded(host) or host.VJ_Controlled then return false end
    if host.Dead or host:Health() <= 0 then return true end
    local maximum = math.max(1, host:GetMaxHealth())
    return host:Health() - (afterDamage or 0) <= maximum * actor:CE8Data().infection.vulnerability
end
local function available(target)
    local job = Infection.claims[target]
    if job and (not IsValid(job.actor) or Infection.jobs[job.actor] ~= job) then Infection.claims[target] = nil return true end
    return job == nil
end
local function jobCount()
    local count = 0
    for other in pairs(Infection.jobs) do if IsValid(other) then count = count + 1 else Infection.jobs[other] = nil end end
    return count
end
local function reserve(actor, target, record, phase)
    if Infection.jobs[actor] or not available(target) then return end
    if jobCount() >= actor:CE8Data().infection.max_jobs then return end
    local job = {actor = actor, target = target, record = record, phase = phase, targets = {[target] = true},
        deadline = CurTime() + 0.5, timers = {}, seed = CurTime()}
    Infection.claims[target], Infection.jobs[actor] = job, job
    return job
end
local function lock(actor, job, finish)
    for _, key in ipairs(timers) do
        local current = actor[key] or 0
        if current == job.lock_until or current < finish then
            if job.timers[key] == nil then job.timers[key] = current end
            actor[key] = finish
        end
    end
    job.lock_until = finish
end
local function detach(job)
    local actor = job.actor
    if job.parented and IsValid(actor) then
        local position, angles = actor:GetPos(), actor:GetAngles()
        actor:SetParent(NULL) actor:SetMoveType(job.move_type)
        actor:SetPos(position) actor:SetAngles(angles)
    end
    job.parented = nil
end
function Infection.Cancel(actor, reason)
    local job = Infection.jobs[actor]
    if not job then return end
    Infection.jobs[actor] = nil
    for target in pairs(job.targets) do if Infection.claims[target] == job then Infection.claims[target] = nil end end
    if not IsValid(actor) then return end
    detach(job)
    if job.schedule and actor.CurrentSchedule == job.schedule then actor:StopCurrentSchedule() end
    if actor.AttackType == VJ.ATTACK_TYPE_CUSTOM and actor.AttackSeed == job.seed then
        actor.AttackType, actor.AttackState, actor.AttackSeed = VJ.ATTACK_TYPE_NONE, VJ.ATTACK_STATE_DONE, 0
    end
    for key, previous in pairs(job.timers) do
        if actor[key] == job.lock_until then actor[key] = math.max(CurTime(), previous) end
    end
    actor.CE8InfectionRetry = CurTime() + actor:CE8Data().infection.retry
    actor.CE8LastInfection = {reason = reason, time = CurTime(), phase = job.phase}
end

-- A committed gib/destruction event invalidates both the registration and any
-- infector already attached to this body. Detach before the corpse is removed.
function Infection.DestroyBody(target)
    if not target then return false end
    if IsValid(target) then target.CE8BodyDestroyed = true end
    local claim = Infection.claims[target]
    if claim then Infection.Cancel(claim.actor, "destroyed_body") end
    if Infection.jobs[target] then Infection.Cancel(target, "destroyed_body") end
    Infection.bodies[target], Infection.deaths[target] = nil, nil
    return true
end
local function start(actor, job, contact)
    local settings = actor:CE8Data().infection
    local dead = job.record.dead
    local sequence = settings.sequences[job.record.owner]
    if dead then sequence = settings.corpse_sequence end
    local index = sequence and actor:LookupSequence(sequence)
    if not index or index < 0 then Infection.Cancel(actor, "missing_animation") return false end
    -- Corpse infection plays the complete authored clip and its existing events.
    -- Paired struggles and their native variable duration belong to live hosts.
    local duration = dead and actor:SequenceDuration(index) or math.Rand(settings.wrestle[1], settings.wrestle[2])
    if duration <= 0 then Infection.Cancel(actor, "missing_animation") return false end
    actor:AIEndLeap(CurTime(), "infection") actor:AISuspendActions(CurTime())
    actor:StopCurrentSchedule()
    if actor.CurrentSchedule then Infection.Cancel(actor, "replacement_schedule") return false end
    actor:StopMoving() actor:ClearGoal()
    if contact then
        -- This is a short, collision-verified contact, not an OBB edge. Put
        -- the authored infection clip at the body before parenting it.
        local direction = bodyPoint(job.body) - actor:GetPos()
        actor:SetAngles(Angle(0, direction:Angle().y, 0))
        actor:SetPos(contact.HitPos + contact.HitNormal * 2)
    end
    job.finish, job.deadline, job.phase = CurTime() + duration, CurTime() + duration + settings.corpse_wait, dead and "infect" or "wrestle"
    job.sequence = index
    local result = actor:PlayAnim("vjseq_" .. sequence, "LetAttacks", duration, false, 0, {
        PlayBackRate = 1,
        OnFinish = function(interrupted)
            if Infection.jobs[actor] ~= job then return end
            if not interrupted then job.animation_complete = true
            elseif not job.animation_complete then job.animation_interrupted = true end
        end
    })
    if result == ACT_INVALID then Infection.Cancel(actor, "missing_animation") return false end
    job.schedule = actor.CurrentSchedule
    if job.schedule then
        local previous = job.schedule.RunCode_OnFinish
        job.schedule.RunCode_OnFinish = function()
            if previous then previous() end
            -- VJ finishes a sequence when IsSequenceFinished becomes true,
            -- which can precede the duration timer by an AI tick. That is
            -- successful completion, not a replacement schedule.
            if Infection.jobs[actor] == job and actor:GetSequence() == index
                and (actor:IsSequenceFinished() or CurTime() >= job.finish) then job.animation_complete = true end
        end
    end
    lock(actor, job, job.deadline)
    actor.AttackType, actor.AttackState, actor.AttackSeed = VJ.ATTACK_TYPE_CUSTOM, VJ.ATTACK_STATE_STARTED, job.seed
    local target = IsValid(job.body) and job.body or IsValid(job.host) and not job.record.dead and job.host
    if IsValid(target) then
        local position, angles = actor:GetPos(), actor:GetAngles()
        job.move_type, job.parented = actor:GetMoveType(), true
        actor:SetMoveType(MOVETYPE_NONE) actor:SetParent(target)
        actor:SetPos(position) actor:SetAngles(angles)
    end
    return true
end
function Infection.PrepareBite(actor, host, rawDamage)
    if not enabled(actor) or not IsValid(host) or host:IsPlayer() or actor:CheckRelationship(host) ~= D_HT
        or CurTime() < (actor.CE8InfectionRetry or 0) then return end
    local predicted = math.max(0, rawDamage or 0) * difficulty.Multiplier("damage")
    if host.IsCE8SNPC then predicted = predicted / difficulty.Multiplier("resistance") end
    if not vulnerable(actor, host, predicted) then return end
    local record = descriptor(host, false)
    if not record then return end
    local job = reserve(actor, host, record, "bite")
    if not job then return end
    job.host = host
    -- Only this accepted, vulnerable host gets a server-ragdoll request.
    host:SetShouldServerRagdoll(true)
    return job
end
function Infection.FinishBite(actor, host, ticket)
    local job = ticket or Infection.jobs[actor]
    if not job or job ~= Infection.jobs[actor] or job.host ~= host then return false end
    if not enabled(actor) or (IsValid(host) and not vulnerable(actor, host))
        or (not IsValid(host) and not job.record.dead) then Infection.Cancel(actor, "bite_not_eligible") return false end
    return start(actor, job)
end
function Infection.TryInfect(actor, host)
    local ticket = Infection.PrepareBite(actor, host, 0)
    return ticket and Infection.FinishBite(actor, host, ticket) or false
end
local function trim(registry, limit)
    local count, oldest, time = 0, nil, math.huge
    for entity, record in pairs(registry) do
        if not IsValid(entity) or CurTime() - record.time > 180 then registry[entity] = nil
        else
            count = count + 1
            if available(entity) and record.time < time then oldest, time = entity, record.time end
        end
    end
    if count >= limit and oldest then registry[oldest] = nil end
end
function Infection.RecordDeath(host)
    if host.CE8BodyDestroyed then Infection.DestroyBody(host) return end
    local job = Infection.claims[host]
    if job then detach(job) end -- Parent removal must not consume its infector.
    local damage = Infection.damage[host]
    if (host.IsOnFire and host:IsOnFire()) or (damage and damage.blocked and CurTime() - damage.time < 0.1) then
        if job then Infection.Cancel(job.actor, "destroyed_host") end
        return
    end
    local record = job and job.record or descriptor(host, true)
    if not record then return end
    record.dead, record.time = true, CurTime()
    if host.AIAnatomySnapshot then record.snapshot = host:AIAnatomySnapshot() end
    trim(Infection.deaths, 128)
    Infection.deaths[host] = record
end
function Infection.RecordCorpse(host, body)
    if host.CE8BodyDestroyed then Infection.DestroyBody(body) return end
    if not usableBody(body) then return end
    local record = Infection.deaths[host]
    if not record or not record.dead then return end
    Infection.deaths[host] = nil
    record.snapshot = body.AIAnatomySnapshotData or record.snapshot
    trim(Infection.bodies, 128)
    Infection.bodies[body] = record
    local job = Infection.claims[host]
    if job then
        job.body, job.targets[body], Infection.claims[body] = body, true, job
    end
end
local function placement(actor, body, record)
    local form = Infection.forms[record.owner]
    local radius, height = form.hull.radius, form.hull.height
    local center = body:WorldSpaceCenter()
    -- Five grounded alternatives, no retries or unbounded nav search.
    for _, delta in ipairs({Vector(), Vector(48,0,0), Vector(-48,0,0), Vector(0,48,0), Vector(0,-48,0)}) do
        local above = center + delta + Vector(0,0,48)
        local floor = util.TraceLine({start = above, endpos = above - Vector(0,0,192),
            mask = MASK_NPCSOLID, filter = {actor, body}})
        if floor.Hit and not floor.StartSolid and not floor.HitSky and floor.HitNormal.z >= 0.7 then
            local position = floor.HitPos + Vector(0,0,2)
            local route = util.TraceLine({start = center, endpos = position + Vector(0,0,height * 0.5),
                mask = MASK_NPCSOLID, filter = {actor,body}})
            local room = util.TraceHull({start = position, endpos = position, mins = Vector(-radius,-radius,0),
                maxs = Vector(radius,radius,height), mask = MASK_NPCSOLID, filter = {actor,body}})
            if not route.Hit and not route.StartSolid and not room.Hit and not room.StartSolid and not room.AllSolid
                and bit.band(util.PointContents(position), CONTENTS_WATER) == 0 then return position end
        end
    end
end
local function complete(actor, job)
    local body, record = job.body, job.record
    if not IsValid(body) or Infection.bodies[body] ~= record or not record.dead then return false end
    if not usableBody(body) then Infection.Cancel(actor, "destroyed_body") return false end
    local position = placement(actor, body, record)
    if not position then Infection.Cancel(actor, "blocked_successor") return false end
    local successor = ents.Create("npc_vj_ce8_" .. record.owner)
    if not IsValid(successor) then Infection.Cancel(actor, "spawn_failed") return false end
    successor:SetPos(position) successor:SetAngles(Angle(0, record.yaw, 0))
    if IsValid(record.creator) then successor:SetCreator(record.creator) end
    successor:SetKeyValue("additionalequipment", "")
    successor.WeaponInventory_AntiArmorList, successor.WeaponInventory_MeleeList = false, false
    successor.CE8Resurrections = record.count + (record.wasFlood and 1 or 0)
    successor:Spawn() successor:Activate()
    if not IsValid(successor) or successor:Health() <= 0 then
        if IsValid(successor) then successor:Remove() end
        Infection.Cancel(actor, "spawn_failed") return false
    end
    if record.snapshot and successor.AIAnatomyRestore then successor:AIAnatomyRestore(record.snapshot, {reset = {infection = true}}) end
    local form = Infection.forms[record.owner]
    local rising, reason
    if successor.CE8BeginResurrection then
        -- Both entities disappear on commit. Neither may obstruct the
        -- successor's authored get-up path while that commit is being checked.
        rising, reason = successor:CE8BeginResurrection(form.resurrection.sequence, {body, actor})
    end
    if not rising then
        successor:Remove() Infection.Cancel(actor, reason or "missing_resurrection") return false
    end
    local enemy = actor:GetEnemy()
    if IsValid(enemy) and enemy ~= job.host and enemy:Health() > 0 and successor:CheckRelationship(enemy) == D_HT then
        successor:ForceSetEnemy(enemy, false)
    end
    -- VJ's corpse removal callback deletes ChildEnts. Keep its dropped weapon;
    -- the successor starts unarmed and never copies/gives that weapon again.
    for i = #(body.ChildEnts or {}), 1, -1 do
        local child = body.ChildEnts[i]
        if IsValid(child) and child:IsWeapon() then table.remove(body.ChildEnts, i) end
    end
    undo.ReplaceEntity(body, successor) cleanup.ReplaceEntity(body, successor)
    if IsValid(job.host) then undo.ReplaceEntity(job.host, successor) cleanup.ReplaceEntity(job.host, successor) end
    Infection.bodies[body] = nil
    Infection.Cancel(actor, "completed")
    body:Remove()
    actor:Remove() -- Consumed infection form, after successful replacement only.
    return true
end
function Infection.Update(actor)
    local job = Infection.jobs[actor]
    if not job then return false end
    local now = CurTime()
    if not enabled(actor) then Infection.Cancel(actor, "disabled") return false end
    if now >= job.deadline then Infection.Cancel(actor, "deadline") return false end
    if job.body and not usableBody(job.body) then Infection.Cancel(actor, "destroyed_body") return false end
    if job.phase == "bite" then return true end
    if job.phase == "approach" then
        if not IsValid(job.body) then Infection.Cancel(actor, "destroyed_body") return false end
        if now < (job.contact_at or 0) then return true end
        job.contact_at = now + 0.1
        local contact = bodyContact(actor, job.body)
        if contact then return start(actor, job, contact) end
        if actor.CurrentSchedule ~= job.schedule then Infection.Cancel(actor, "route_ended") return false end
        return true
    end
    if actor.AttackType ~= VJ.ATTACK_TYPE_CUSTOM or actor.AttackSeed ~= job.seed
        or (IsValid(job.host) and shielded(job.host)) then Infection.Cancel(actor, "attack_interrupted") return false end
    if job.animation_interrupted then Infection.Cancel(actor, "animation_interrupted") return false end
    if not job.animation_complete and now < job.finish then
        if actor.CurrentSchedule ~= job.schedule then Infection.Cancel(actor, "animation_replaced") return false end
        return true
    end
    if not job.record.dead then
        if not IsValid(job.host) or not vulnerable(actor, job.host) then Infection.Cancel(actor, "host_recovered") return false end
        if not placement(actor, job.host, job.record) then Infection.Cancel(actor, "blocked_successor") return false end
        job.phase = "await_corpse"
        local damage = DamageInfo()
        damage:SetAttacker(actor) damage:SetInflictor(actor) damage:SetDamageType(DMG_SLASH)
        local outgoing = difficulty.Multiplier("damage")
        if outgoing <= 0 then Infection.Cancel(actor, "damage_disabled") return false end
        local resistance = job.host.IsCE8SNPC and difficulty.Multiplier("resistance") or 1
        damage:SetDamage((job.host:Health() * resistance + 1) / outgoing)
        damage:SetDamagePosition(job.host:WorldSpaceCenter())
        job.host:TakeDamageInfo(damage)
        -- A godmode/filter/special death handler may reject lethal damage.
        if not job.record.dead then Infection.Cancel(actor, "host_survived") return false end
    end
    if IsValid(job.body) then return complete(actor, job) end
    job.phase = "await_corpse"
    return true
end
function Infection.Search(actor)
    if Infection.jobs[actor] then return true end
    local now, settings = CurTime(), actor:CE8Data().infection
    if not enabled(actor) or actor.AttackType or actor:IsBusy("Activities") or not actor:OnGround()
        or actor.IsGuard or actor.IsFollowing or actor.DisableChasingEnemy
        or now < (actor.CE8InfectionRetry or 0) or now < (actor.CE8NextCorpseSearch or 0) then return false end
    if jobCount() >= settings.max_jobs then return false end
    local budget = Infection.searchBudget
    if not budget or now >= budget.until_time then budget = {until_time = now + 0.25, scans = 4, traces = 8} Infection.searchBudget = budget end
    if budget.scans <= 0 or budget.traces <= 0 then
        actor.CE8NextCorpseSearch = budget.until_time + (actor:EntIndex() % 8) * 0.025
        return false
    end
    budget.scans = budget.scans - 1
    actor.CE8NextCorpseSearch = now + settings.search_interval + (actor:EntIndex() % 8) * 0.025
    trim(Infection.bodies, 128)
    local chosen, record, candidates = nil, nil, {}
    for body, candidate in pairs(Infection.bodies) do
        local delta = actor:GetPos():DistToSqr(bodyPoint(body))
        local minimumAge = candidate.wasFlood and Infection.forms[candidate.owner].resurrection.minimum_age or 0
        if available(body) and now - candidate.time >= minimumAge and delta <= settings.search_radius ^ 2
            and usableBody(body) then
            local at = #candidates + 1
            for i, row in ipairs(candidates) do if delta < row.distance then at = i break end end
            if at <= 6 then
                table.insert(candidates, at, {body = body, record = candidate, distance = delta})
                if #candidates > 6 then table.remove(candidates) end
            end
        end
    end
    for _, row in ipairs(candidates) do
        if budget.traces <= 0 then break end
        budget.traces = budget.traces - 1
        if actor:Visible(row.body) then chosen, record = row.body, row.record break end
    end
    if not chosen then return false end
    local job = reserve(actor, chosen, record, "approach")
    if not job then return false end
    job.body, job.deadline = chosen, now + settings.approach_timeout
    actor:AISuspendActions(now) actor:StopCurrentSchedule()
    if actor.CurrentSchedule then Infection.Cancel(actor, "replacement_schedule") return false end
    -- Corpse acquisition takes priority over a live enemy without forgetting
    -- that enemy. VJ's own timers protect this finite route from chase/attacks.
    lock(actor, job, job.deadline)
    actor:SetLastPosition(bodyPoint(chosen))
    actor:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH", function(schedule)
        job.schedule = schedule
        schedule.CanShootWhenMoving = false
        schedule.RunCode_OnFail = function() if Infection.jobs[actor] == job then Infection.Cancel(actor, "path_failed") end end
    end)
    return true
end
function Infection.Attach(ENT, data)
    if data.resurrection then
        Infection.forms[data.owner] = data
        local ready = ENT.CE8WeaponShotReady
        if ready then
            function ENT:CE8WeaponShotReady(now) return not self.CE8Rising and ready(self, now) end
        end
        function ENT:CE8BeginResurrection(sequence, consumed)
            if self:LookupSequence(sequence) < 0 then return false, "missing_resurrection" end
            if not self:AIValidateMotion(sequence, 0, consumed) then return false, "blocked_resurrection" end
            local animation, duration = self:PlayAnim("vjseq_" .. sequence, "LetAttacks", false, false, 0, {PlayBackRate = 1})
            if animation == ACT_INVALID or duration <= 0 then return false, "resurrection_playback" end
            self.CE8Rising = {finish = CurTime() + duration, seed = CurTime(), schedule = self.CurrentSchedule}
            self.AttackType, self.AttackState, self.AttackSeed = VJ.ATTACK_TYPE_CUSTOM, VJ.ATTACK_STATE_STARTED, self.CE8Rising.seed
            return true
        end
        local think = ENT.OnThink
        function ENT:OnThink()
            local rise = self.CE8Rising
            if rise and (CurTime() >= rise.finish or self.Dead or self.VJ_Controlled or self.CurrentSchedule ~= rise.schedule) then
                self.CE8Rising = nil
                if self.AttackType == VJ.ATTACK_TYPE_CUSTOM and self.AttackSeed == rise.seed then
                    self.AttackType, self.AttackState, self.AttackSeed = VJ.ATTACK_TYPE_NONE, VJ.ATTACK_STATE_DONE, 0
                end
            end
            return think(self)
        end
    end
    if not data.infection then return end
    local think, active, death, remove = ENT.OnThink, ENT.OnThinkActive, ENT.OnDeath, ENT.CustomOnRemove
    function ENT:OnThink()
        Infection.Update(self)
        if IsValid(self) then return think(self) end
    end
    function ENT:OnThinkActive()
        if Infection.Search(self) then return end
        return active(self)
    end
    function ENT:OnDeath(damage, hitgroup, status)
        if status == "Init" then Infection.Cancel(self, "death") end
        return death(self, damage, hitgroup, status)
    end
    function ENT:CustomOnRemove() Infection.Cancel(self, "remove") return remove(self) end
end
hook.Add("OnNPCKilled", "CE8InfectionDeaths", Infection.RecordDeath)
hook.Add("CreateEntityRagdoll", "CE8InfectionCorpses", Infection.RecordCorpse)
hook.Add("EntityTakeDamage", "CE8InfectionDeathFlags", function(victim, damage)
    if not IsValid(victim) or not victim:IsNPC() then return end
    Infection.damage[victim] = {time = CurTime(), blocked = damage:IsDamageType(DMG_BURN)
        or damage:IsDamageType(DMG_SLOWBURN) or damage:IsDamageType(DMG_DISSOLVE)
        or damage:IsDamageType(DMG_REMOVENORAGDOLL)}
end)
hook.Add("PreCleanupMap", "CE8InfectionCleanup", function()
    for actor in pairs(Infection.jobs) do Infection.Cancel(actor, "cleanup") end
    Infection.bodies, Infection.deaths = weak(), weak()
end)
return Infection
