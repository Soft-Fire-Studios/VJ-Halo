-- One immutable roster table, shared by all character profiles. An explicit
-- autorun reload replaces it once so existing actors can refresh their bindings.
if SERVER then
    CE8 = CE8 or {}
    CE8.HeadProfiles = include("campaign_evolved/heads.lua")
    CE8.ControlProfiles = include("campaign_evolved/possession.lua").owners
end
if SERVER then
    AddCSLuaFile("campaign_evolved/hud.lua")
    AddCSLuaFile("autorun/client/ce8_hud.lua")
else
    include("autorun/client/ce8_hud.lua")
end
local covenantWeapons = include("campaign_evolved/weapons.lua")
local difficulty = include("campaign_evolved/difficulty.lua")
difficulty.Setup()
if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("campaign_evolved/elite_anims.lua")
    AddCSLuaFile("campaign_evolved/human.lua")
    AddCSLuaFile("campaign_evolved/actor.lua")
    AddCSLuaFile("campaign_evolved/flood_gib_models.lua")
    AddCSLuaFile("campaign_evolved/armor_parts.lua")
    AddCSLuaFile("campaign_evolved/collision.lua")
    AddCSLuaFile("campaign_evolved/hunter_colliders.lua")
    AddCSLuaFile("campaign_evolved/jackal_colliders.lua")
    AddCSLuaFile("campaign_evolved/jackal_collision.lua")
    AddCSLuaFile("campaign_evolved/sounds/elite.lua")
    AddCSLuaFile("campaign_evolved/sounds/elite_shield.lua")
    AddCSLuaFile("campaign_evolved/weapons.lua")
    AddCSLuaFile("campaign_evolved/weapon.lua")
    -- Custom-directory renderer helpers are not sent with client autoruns.
    -- A joining client needs the whole include chain, even without local Lua.
    AddCSLuaFile("campaign_evolved/ce8_assembly.lua")
    AddCSLuaFile("campaign_evolved/ce8_lighting.lua")
    AddCSLuaFile("campaign_evolved/ce8_map_lights.lua")
    AddCSLuaFile("campaign_evolved/ce8_scene.lua")
    AddCSLuaFile("campaign_evolved/ce8_hunter.lua")
    AddCSLuaFile("campaign_evolved/ce8_live_details.lua")
    AddCSLuaFile("campaign_evolved/ce8_blade.lua")
    AddCSLuaFile("campaign_evolved/ce8_gauge.lua")
    AddCSLuaFile("campaign_evolved/ce8_shield.lua")
    AddCSLuaFile("campaign_evolved/weapon_fx.lua")
    AddCSLuaFile("campaign_evolved/ballistics.lua")
    AddCSLuaFile("campaign_evolved/difficulty.lua")
    AddCSLuaFile("campaign_evolved/ce8_bloom.lua")
    for name in pairs(covenantWeapons) do
        AddCSLuaFile("weapons/weapon_vj_ce8_" .. name .. ".lua")
        AddCSLuaFile("campaign_evolved/sounds/" .. name .. ".lua")
    end
    AddCSLuaFile("entities/obj_ce8_projectile/shared.lua")
    AddCSLuaFile("entities/obj_ce8_projectile/cl_init.lua")
end

if not VJ or not VJ.AddNPC_HUMAN then
    ErrorNoHalt("Campaign Evolved NPCs require VJ Base.\n")
    return
end

include("campaign_evolved/collision.lua")

-- Register explicitly as well as supporting GMod's normal entity loader. This
-- lets lua_openscript load the new classes into an already running local map.
local previousENT, previousSWEP = ENT, SWEP
local eliteData
local rosterData = {}
local ok, message = xpcall(function()
    ENT = {}
    include("entities/obj_prp_collider.lua")
    scripted_ents.Register(ENT, "obj_prp_collider")
    ENT = {}
    include("entities/obj_ce8_armor.lua")
    scripted_ents.Register(ENT, "obj_ce8_armor")
    ENT = {}
    include("entities/obj_ce8_barrier.lua")
    scripted_ents.Register(ENT, "obj_ce8_barrier")
    ENT = {}
    include("entities/obj_ce8_infection_fountain.lua")
    scripted_ents.Register(ENT, "obj_ce8_infection_fountain")
    ENT = {}
    include("entities/obj_ce8_projectile/" .. (SERVER and "init.lua" or "cl_init.lua"))
    scripted_ents.Register(ENT, "obj_ce8_projectile")
    ENT = {}
    include("entities/npc_vj_ce8_elite/" .. (SERVER and "init.lua" or "cl_init.lua"))
    scripted_ents.Register(ENT, "npc_vj_ce8_elite")
    eliteData = ENT:CE8Data()
    for _, rank in ipairs(eliteData.rank_order) do
        if rank ~= "minor" then
            local path = "entities/" .. eliteData.ranks[rank].class_name .. ".lua"
            if SERVER then AddCSLuaFile(path) end
            ENT = {}
            include(path)
            scripted_ents.Register(ENT, eliteData.ranks[rank].class_name)
        end
    end
    for _, owner in ipairs({"grunt", "jackal", "brute", "hunter", "flood_combat_human", "flood_combat_elite",
        "flood_tank", "flood_infection", "flood_carrier"}) do
        ENT = {}
        if owner:sub(1, 6) == "flood_" then
            local path = "entities/npc_vj_ce8_" .. owner .. ".lua"
            if SERVER then AddCSLuaFile(path) end
            include(path)
        else
            include("entities/npc_vj_ce8_" .. owner .. "/" .. (SERVER and "init.lua" or "cl_init.lua"))
        end
        scripted_ents.Register(ENT, "npc_vj_ce8_" .. owner)
        local data = ENT:CE8Data()
        rosterData[owner] = data
        if data.builtin_weapon then
            local path = "weapons/" .. data.builtin_weapon .. ".lua"
            if SERVER then
                AddCSLuaFile(path)
                AddCSLuaFile("campaign_evolved/sounds/" .. owner .. "_cannon.lua")
            end
            SWEP = {Primary = {}, Secondary = {}}
            include(path)
            weapons.Register(SWEP, data.builtin_weapon)
        end
        for _, rank in ipairs(data.rank_order) do
            if rank ~= "minor" then
                local path = "entities/" .. data.ranks[rank].class_name .. ".lua"
                if SERVER then AddCSLuaFile(path) end
                ENT = {}
                include(path)
                scripted_ents.Register(ENT, data.ranks[rank].class_name)
            end
        end
    end
    for name in pairs(covenantWeapons) do
        SWEP = {Primary = {}, Secondary = {}}
        include("weapons/weapon_vj_ce8_" .. name .. ".lua")
        weapons.Register(SWEP, "weapon_vj_ce8_" .. name)
    end
end, debug.traceback)
ENT, SWEP = previousENT, previousSWEP
if not ok then ErrorNoHalt("Campaign Evolved NPC registration: " .. message .. "\n") return end
if CLIENT and CE8 and CE8.RefreshSpawnedModelDefinitions then CE8.RefreshSpawnedModelDefinitions() end
-- Register replaces class definitions but merges existing entity tables.
-- Retire the old per-entity resource clone in both realms after rebinding getters.
for _, actor in ipairs(ents.FindByClass("npc_vj_ce8_elite*")) do
    actor.CE8AnimationData = nil
end
-- Refresh only Infection movement on explicit reload. The rest of the roster
-- retains its native movement policy; PRP owns the separate damage carriers.
for _, actor in ipairs(ents.FindByClass("npc_vj_ce8_flood_infection")) do
    if SERVER then actor:SetCollisionGroup(COLLISION_GROUP_NPC) end
    actor:SetCustomCollisionCheck(true)
    actor:CollisionRulesChanged()
end

local weaponPools = {}
for _, name in ipairs(eliteData.rank_order) do
    local rank = eliteData.ranks[name]
    local pool = weaponPools[rank.profile]
    if not pool then
        pool = {}
        for _, choice in ipairs(eliteData.rank_profiles[rank.profile].loadout) do
            for _ = 1, choice.weight do pool[#pool + 1] = choice.weapon end
        end
        weaponPools[rank.profile] = pool
    end
    VJ.AddNPC_HUMAN(rank.name, rank.class_name, pool, "Halo - Campaign Evolved")
end
for _, data in pairs(rosterData) do
    for _, name in ipairs(data.rank_order) do
        local rank = data.ranks[name]
        if data.adapter == "creature" then
            VJ.AddNPC(rank.name, rank.class_name, "Halo - Campaign Evolved")
        else
            VJ.AddNPC_HUMAN(rank.name, rank.class_name, rank.loadout, "Halo - Campaign Evolved")
        end
    end
end
local listed = {}
for _, entry in ipairs(list.Get("NPCUsableWeapons") or {}) do
    listed[entry.class] = true
end
for name, data in pairs(covenantWeapons) do
    local class = "weapon_vj_ce8_" .. name
    if not listed[class] then VJ.AddNPCWeapon(data.name, class, "Halo - Campaign Evolved") end
end

if SERVER then
    CE8 = CE8 or {}
    -- Share one recent shot per shooter; the reusable service owns the cache.
    local core = include("vj_ai/core.lua")
    CE8.Gunfire = core.Gunfire
    CE8.RecordGunfire = core.RecordGunfire
    hook.Add("PostEntityFireBullets", "CE8Gunfire", core.ObserveBullet)
    hook.Add("CreateEntityRagdoll", "CE8PostCombatCorpse", function(victim, corpse)
        local actor = IsValid(victim) and victim.CE8CorpseObserver
        local config = IsValid(actor) and actor.AIProfile and actor:AIProfile().postcombat
        local action = config and actor[config.fields.active]
        if action and action.victim == victim and IsValid(corpse) then action.corpse = corpse end
    end)
    concommand.Add("ce8_weapon_report", function(ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local target = ply:GetEyeTrace().Entity
        local weapon = IsValid(target) and target.IsCE8Elite and target:GetActiveWeapon() or target
        if not IsValid(weapon) or not weapon.CE8WeaponName then ply:ChatPrint("Aim at a CE8 weapon or its Elite.") return end
        local report = {class = weapon:GetClass(), weapon = weapon.CE8WeaponName, clip = weapon:Clip1(),
            hold_type = weapon:GetHoldType(), animation_class = weapon.CE8AnimationClass,
            grip = weapon.CE8Grip, grip_type = weapon.CE8GripType,
            raw_damage = weapon.CE8Data.damage, firing_state = weapon.CE8FireState,
            active_profile = weapon.CE8ShotProfile,
            difficulty = difficulty.Get("ce8_difficulty"),
            native_profiles = weapon.CE8Data.profiles, next_burst = weapon.CE8NextBurstT,
            heat = weapon.CE8Heat, overheated = weapon.CE8Overheated}
        file.CreateDir("campaign_evolved")
        file.Write("campaign_evolved/weapon_fire.json", util.TableToJSON(report, true))
        print("CE8 weapon firing report saved: " .. weapon.CE8WeaponName)
    end)
    -- Refresh supported Human profiles on explicit reload, preserving health,
    -- shield damage, grenade counts and active berserk state.
    for _, actor in ipairs(ents.FindByClass("npc_vj_ce8_*")) do
        -- Retire native head control on existing Human and Creature actors too.
        if actor.AIPrepareGaze then actor:AIPrepareGaze() end
        if actor.AIConfigureWeapon then actor:AIConfigureWeapon(actor:GetActiveWeapon()) end
        if actor.IsCE8Elite or actor.CE8UnitLabel == "grunt" or actor.CE8UnitLabel == "jackal" or actor.CE8UnitLabel == "brute" then
            actor.ConstantlyFaceEnemy = false
            actor.SoundTbl_GrenadeSight = actor.SoundTbl_DangerSight
            local footsteps = GetConVar("vj_npc_snd_footstep")
            actor.HasFootstepSounds = not footsteps or footsteps:GetBool()
            actor.DisableFootStepSoundTimer = true
            actor.CE8FootAttachments = nil
            actor.CE8FootstepLast = nil
            if actor.CE8ApplyStats then actor:CE8ApplyStats(false) end
            actor.CE8ActivitySets = nil
            if actor.AIMotionProfile then
                local fields = actor:AIMotionProfile().fields
                actor[fields.activity_sets], actor[fields.activities] = nil, nil
            end
            if actor.CE8ConfigureAI then
                actor:CE8ConfigureAI()
                if actor.JumpParams and actor.JumpParams.Enabled then actor:CapabilitiesAdd(CAP_MOVE_JUMP) end
            end
            local weapon = actor.GetActiveWeapon and actor:GetActiveWeapon()
            local settings = IsValid(weapon) and covenantWeapons[weapon.CE8WeaponName]
            if settings then
                weapon.CE8Data = settings
                weapon.CE8Grip = settings.grip
                weapon.CE8GripType = settings.grip_type
                if weapon.OnEquip then weapon:OnEquip(actor) end
                if actor.OnWeaponChange then actor:OnWeaponChange(weapon) end
            end
            local facing = actor.CurrentSchedule and actor.CurrentSchedule.TurnData
            if facing and (facing.Type == VJ.FACE_ENEMY or facing.Type == VJ.FACE_ENEMY_VISIBLE)
                and IsValid(actor:GetEnemy()) then
                actor:SetTurnTarget("Enemy", -1, false, facing.Type == VJ.FACE_ENEMY_VISIBLE)
                actor.TurnData.IsSchedule = true
            end
        end
    end
    concommand.Add("ce8_squad_report", function(ply, _, args)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local actor = ply:GetEyeTrace().Entity
        if IsValid(actor) and (actor.IsCE8Barrier or actor.IsPRPCollider) then actor = actor:GetOwner() end
        if not IsValid(actor) or not actor.AISquadReport then
            ply:ChatPrint("Aim at a Campaign Evolved NPC.") return
        end
        local report = actor:AISquadReport()
        local profile = actor:AIProfile()
        local defense = profile.defense and actor[profile.defense.fields.active]
        local search = profile.search and actor[profile.search.fields.active]
        if profile.defense then
            report.defense = defense and {crouched=defense.crouched,pressure=defense.pressure,
                weight=defense.weight,yaw=defense.yaw} or false
            report.cover_obstacle = search and IsValid(search.break_target) and search.break_target:EntIndex() or false
        end
        if actor.ColliderParts then
            report.collision={last=actor.ColliderLastHit,proxies=table.Count(actor.ColliderParts),parts={}}
            for _,name in ipairs({"shield","backplate","topplate","weakspot_shell"}) do
                report.collision.parts[name]=CE8.Collision.Active(actor,name)
            end
        end
        if args and args[1] == "shield" and actor.CE8MergedBarrier then
            report.shield={merged=true,value=actor.AIShield,maximum=actor.CE8BarrierMax,
                down=actor.CE8BarrierDown,active=CE8.Barrier.ActorActive(actor),
                bodygroup=actor:GetBodygroup(actor:FindBodygroupByName("barrier")),
                last=actor.ColliderLastHit}
        elseif args and args[1] == "shield" then
            local part = actor.CE8Barrier
            if not IsValid(part) then ply:ChatPrint("This NPC has no active shield entity.") return end
            local frame = part:CE8AttachmentFrame()
            local physics = part:GetPhysicsObject()
            report.shield = {entity = part:EntIndex(), model = part:GetModel(),
                value = actor.AIShield, maximum = actor.CE8BarrierMax, down = actor.CE8BarrierDown,
                active = CE8.Barrier.Active(part), position = part:GetPos(), angles = part:GetAngles(),
                frame = frame, solid = part:GetSolid(), flags = part:GetSolidFlags(),
                collision_group = part:GetCollisionGroup(), move_type = part:GetMoveType(),
                parent = IsValid(part:GetParent()), physics = IsValid(physics), rays = {}}
            if IsValid(physics) then
                report.shield.physics_position, report.shield.physics_angles = physics:GetPos(), physics:GetAngles()
            end
            if frame then
                for _, height in ipairs({0, 10, -10}) do
                    local start = LocalToWorld(Vector(60, 0, height), angle_zero, frame.Pos, frame.Ang)
                    local finish = LocalToWorld(Vector(-60, 0, height), angle_zero, frame.Pos, frame.Ang)
                    local hit = util.TraceLine({start = start, endpos = finish, mask = MASK_SHOT,
                        filter = function(ent) return ent == part end})
                    local native = CE8.Barrier.Trace(part, start, finish - start)
                    report.shield.rays[#report.shield.rays + 1] = {height = height,
                        engine_hit = hit.Entity == part, engine_entity = IsValid(hit.Entity) and hit.Entity:GetClass(),
                        position = hit.HitPos, native_hit = native ~= nil, native_position = native and native.HitPos}
                end
            end
        end
        local timerName = "CE8SquadReport" .. ply:EntIndex()
        timer.Remove(timerName)
        hook.Remove("PostEntityFireBullets", timerName)
        hook.Remove("PostEntityTakeDamage", timerName)
        local function save()
            file.CreateDir("campaign_evolved")
            file.Write("campaign_evolved/squad.json", util.TableToJSON(report, true))
            local latest = report.samples and report.samples[#report.samples].squad or report
            print(string.format("CE8 squad: %d members, leader %s. Report saved%s.",
                #(latest.members or {}), tostring(latest.leader or "none"),
                report.samples and (" (" .. #report.samples .. " samples)") or ""))
        end
        local mode = args and args[1]
        if mode == "shield" then
            local part = actor.CE8MergedBarrier and actor.ColliderParts and actor.ColliderParts.default_silent or actor.CE8Barrier
            local weapon = ply:GetActiveWeapon()
            report.shield.player_weapon = IsValid(weapon) and weapon:GetClass()
            report.shield.health_before = actor:Health()
            report.shield.shots, report.shield.damage = {}, {}
            hook.Add("PostEntityFireBullets", timerName, function(shooter, bullet)
                if shooter ~= ply or #report.shield.shots >= 32 then return end
                local trace = bullet.Trace
                local firedWeapon = shooter:GetActiveWeapon()
                report.shield.shots[#report.shield.shots + 1] = {entity = IsValid(trace.Entity) and trace.Entity:GetClass(),
                    hit = trace.HitPos, shield = trace.Entity == part, actor = trace.Entity == actor,
                    time = CurTime(), weapon = IsValid(firedWeapon) and firedWeapon:GetClass()}
            end)
            hook.Add("PostEntityTakeDamage", timerName, function(target, damage, accepted)
                if (target ~= part and target ~= actor) or #report.shield.damage >= 32 then return end
                report.shield.damage[#report.shield.damage + 1] = {shield = target == part,
                    amount = damage:GetDamage(), accepted = accepted, value = actor.AIShield,
                    health = IsValid(actor) and actor:Health()}
            end)
            ply:ChatPrint("CE8 shield: recording 10 seconds. Close the console and shoot the shield.")
            timer.Create(timerName, 10, 1, function()
                hook.Remove("PostEntityFireBullets", timerName)
                hook.Remove("PostEntityTakeDamage", timerName)
                report.shield.health_after = IsValid(actor) and actor:Health()
                report.shield.value_after = IsValid(actor) and actor.AIShield
                save()
            end)
            return
        end
        if mode ~= "watch" and mode ~= "motion" then save() return end
        report = {mode = mode, started = CurTime(), samples = {{elapsed = 0, squad = report}}}
        local count = mode == "motion" and 240 or 24
        ply:ChatPrint(mode == "motion" and "CE8: recording this NPC for 12 seconds. Close the console and reproduce the movement snap."
            or "CE8 squad: recording for 12 seconds. Close the console and break line of sight.")
        timer.Create(timerName, 12 / count, count, function()
            if not IsValid(actor) or not IsValid(ply) then
                timer.Remove(timerName)
                report.stopped = "actor_or_player_removed"
                save() return
            end
            local sample = {elapsed = CurTime() - report.started, squad = actor:AISquadReport()}
            if mode == "motion" then
                local sequence = actor:GetSequence()
                local fields = actor:AIMotionProfile().fields
                local turn = actor[fields.aim_turn]
                local motion = {entity = actor:EntIndex(), model = actor:GetModel(), position = actor:GetPos(),
                    angles = actor:GetAngles(), velocity = actor:GetMoveVelocity(), moving = actor:IsMoving(),
                    sequence = actor:GetSequenceName(sequence), cycle = actor:GetCycle(),
                    activity = actor:GetActivity(), sequence_activity = actor:GetSequenceActivity(sequence),
                    move_direction = actor[fields.move_direction], facing_direction = actor[fields.facing_direction],
                    move_intent = actor[fields.move_intent], schedule = actor.CurrentSchedule and actor.CurrentSchedule.Name,
                    goal_type = actor:GetCurGoalType(), ideal_yaw = actor:GetIdealYaw(),
                    schedule_moving = actor.CurrentSchedule and actor.CurrentSchedule.HasMovement,
                    schedule_firing = actor.CurrentSchedule and actor.CurrentSchedule.CanShootWhenMoving,
                    turn_type = actor.TurnData and actor.TurnData.Type,
                    turn_schedule = actor.TurnData and actor.TurnData.IsSchedule,
                    turn_stop_on_face = actor.TurnData and actor.TurnData.StopOnFace,
                    attack = actor.AttackType, flinching = actor.Flinching, busy = actor:IsBusy("Activities"),
                    controlled = actor.VJ_Controlled, poses = {}, attachments = {}, layers = {}}
                for _, name in ipairs({"aim_yaw", "aim_pitch", "head_yaw", "head_pitch"}) do
                    if actor:LookupPoseParameter(name) >= 0 then motion.poses[name] = actor:GetPoseParameter(name) end
                end
                -- Read engine attachments; do not rebuild/cache/manipulate bones
                -- or write any pose, facing, sequence or navigation state.
                for _, name in ipairs({"forward", "head_forward", "chest"}) do
                    local id = actor:LookupAttachment(name)
                    if id > 0 then motion.attachments[name] = actor:GetAttachment(id) end
                end
                for layer = 0, 14 do
                    if actor:IsValidLayer(layer) then
                        motion.layers[#motion.layers + 1] = {id = layer,
                            sequence = actor:GetSequenceName(actor:GetLayerSequence(layer)),
                            cycle = actor:GetLayerCycle(layer), aim_turn = turn and turn.layer == layer or false}
                    end
                end
                sample.motion = motion
            end
            report.samples[#report.samples + 1] = sample
            if #report.samples >= count + 1 then save() end
        end)
    end)
    concommand.Add("ce8_elite_ai_report", function(ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local actor = ply:GetEyeTrace().Entity
        if not IsValid(actor) or not actor.IsCE8Elite then ply:ChatPrint("Aim at a Campaign Evolved Elite NPC.") return end
        local now = CurTime()
        local _, profile = actor:CE8RankSettings()
        local weapon, enemy = actor:GetActiveWeapon(), actor:GetEnemy()
        local function remaining(time) return math.max(0, (time or 0) - now) end
        local engagement = {time = now, initialized = actor.IsInitialized,
            enemy = IsValid(enemy) and enemy:GetClass() or false,
            visible = IsValid(enemy) and actor:Visible(enemy) or false,
            acquired_ago = actor.EnemyData and now - (actor.EnemyData.TimeAcquired or now),
            attack_state = actor.WeaponAttackState, weapon_state = actor:GetWeaponState(),
            pause_attacks = actor.PauseAttacks, attack_type = actor.AttackType,
            busy = actor:IsBusy("Activities"), move_delay = math.max(0, actor:GetMoveDelay()),
            next_attack = remaining(actor.NextDoAnyAttackT), next_chase = remaining(actor.NextChaseTime),
            weapon_attack = remaining(actor.NextWeaponAttackT), fire_animation = remaining(actor.NextWeaponAttackT_Base),
            animation_lock = remaining(actor.AnimLockTime), attack_animation = remaining(actor.AttackAnimTime),
            reaction = remaining(actor.CE8ReactionEnd), taking_cover = remaining(actor.TakingCoverT),
            requested_activity = actor:GetActivity(), sequence_activity = actor:GetSequenceActivity(actor:GetSequence())}
        engagement.body_yaw = actor:GetAngles().y
        engagement.poses = {aim_yaw = actor:GetPoseParameter("aim_yaw"), head_yaw = actor:GetPoseParameter("head_yaw"),
            aim_pitch = actor:GetPoseParameter("aim_pitch"), head_pitch = actor:GetPoseParameter("head_pitch")}
        engagement.pose_names = {}
        for _, axis in ipairs({"pitch", "yaw", "roll"}) do
            local names = {}
            for _, name in ipairs((actor.PoseParameterLooking_Names or {})[axis] or {}) do names[#names + 1] = name end
            engagement.pose_names[axis] = names
        end
        if IsValid(enemy) then
            engagement.target_yaw = math.AngleDifference((enemy:GetPos() - actor:GetPos()):Angle().y, actor:GetAngles().y)
            engagement.distance = actor:GetPos():Distance(enemy:GetPos())
            local direction = actor:GetAimPosition(enemy, actor:GetPos(), 0) - actor:GetPos()
            local sight = actor:AIHeadDirection()
            direction.z, sight.z = 0, 0
            direction:Normalize(); sight:Normalize()
            engagement.aim_dot = sight:Dot(direction)
        end
        if IsValid(weapon) then
            engagement.weapon = {name = weapon.CE8WeaponName or weapon:GetClass(),
                ready = weapon.CE8FireReady, burst_wait = remaining(weapon.CE8NextBurstT),
                primary_wait = remaining(weapon.NPC_NextPrimaryFireT), overheated = weapon.CE8Overheated,
                cone = weapon.NPC_FiringCone, clip = weapon:Clip1()}
        end
        local report = {engagement = engagement, squad = actor:AISquadReport(), rank = actor.CE8Rank, health = actor:Health(), shield = actor.CE8Shield, shield_max = actor.CE8ShieldMax,
            behavior_profile = profile.behavior, grenades = actor.CE8Grenades,
            combat_multipliers = difficulty.Combat(),
            base_health = profile.health, base_shield = profile.shield,
            cover = actor.CE8Cover and actor.CE8Cover.phase,
            charging = actor.CE8Charge ~= nil, berserk_remaining = math.max(0, (actor.CE8BerserkUntil or 0) - now),
            perception = actor.CE8PerceptionMode, search_mode = actor.CE8Search and actor.CE8Search.mode,
            search_action = actor.CE8Search and actor.CE8Search.action,
            search_action_remaining = actor.CE8Search and actor.CE8Search.action_until
                and math.max(0, actor.CE8Search.action_until - now),
            suppression_bursts = actor.CE8Search and actor.CE8Search.bursts_fired or 0,
            search_remaining = actor.CE8Search and math.max(0, actor.CE8Search.deadline - now),
            shield_breaks = actor.CE8ShieldBreaks, evades = actor.CE8Evades,
            shield_break_pending = actor.CE8PendingShieldBreak == true,
            shield_particles_loaded = CE8.ShieldParticlesReady == true,
            shield_effects = actor.CE8ShieldFXCounts or {},
            shield_sounds = actor.CE8ShieldSoundCounts or {},
            dialogue_counts = actor.CE8DialogueCounts or {}, last_dialogue = actor.CE8LastDialogue,
            last_footstep = actor.CE8LastFootstep,
            gunfire_evades = actor.CE8GunfireEvades or 0, last_gunfire_threat = actor.CE8LastGunfire,
            obstacle_smashes = actor.CE8Smashes or 0,
            coordinated_openings = actor.CE8CoordinatedOpenings or 0,
            opening_ready_in = actor.CE8Opening and math.max(0, actor.CE8Opening.ready_at - now),
            last_opening = actor.CE8LastOpening,
            last_spacing_recovery = actor.CE8LastSpacing,
            acquire_remaining = math.max(0, (actor.CE8AcquireAt or 0) - now),
            movement_schedule = actor.CurrentSchedule and actor.CurrentSchedule.Name,
            corpse_firing = actor.CE8PostCombat and actor.CE8PostCombat.firing == true,
            corpse_bursts = actor.CE8PostCombat and actor.CE8PostCombat.bursts_fired,
            corpse_burst_limit = actor.CE8PostCombat and actor.CE8PostCombat.burst_limit,
            recharge_in = math.max(0, (actor.CE8ShieldRechargeAt or now) - now),
            reaction = actor.CE8Reaction, last_reaction = actor.CE8LastReaction,
            sequence = actor:GetSequenceName(actor:GetSequence()),
            constantly_face_enemy = actor.ConstantlyFaceEnemy,
            aim_time = actor.CE8AimEvadeTime, evade_cooldown = actor.CE8AimEvadeCooldown,
            aiming_players = {}, native_reactions = {}}
        for player, start in pairs(actor.CE8AimStarted or {}) do
            if IsValid(player) then report.aiming_players[#report.aiming_players + 1] = {entity = player:EntIndex(), seconds = now - start} end
        end
        for name, value in pairs(actor:CE8ReactionSet()) do
            report.native_reactions[name] = {}
            for _, sequence in ipairs(istable(value) and value or {value}) do
                local id = actor:LookupSequence(sequence)
                local ok, movement = actor:GetSequenceMovement(id, 0, 1)
                report.native_reactions[name][#report.native_reactions[name] + 1] = {
                    sequence = sequence, index = id, duration = actor:SequenceDuration(id),
                    root_motion = ok, movement = movement and {movement.x, movement.y, movement.z}}
            end
        end
        file.CreateDir("campaign_evolved")
        file.Write("campaign_evolved/elite_ai.json", util.TableToJSON(report, true))
        print(string.format("CE8 AI: shield %.1f/%.1f, health %.1f, shield breaks %d, aim evades %d. Report saved.",
            actor.CE8Shield or 0, actor.CE8ShieldMax, actor:Health(), actor.CE8ShieldBreaks or 0, actor.CE8Evades or 0))
    end)
end
