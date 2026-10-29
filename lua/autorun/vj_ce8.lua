-- One immutable roster table, shared by all character profiles. An explicit
-- autorun reload replaces it once so existing actors can refresh their bindings.
if SERVER then
    CE8 = CE8 or {}
    CE8.HeadProfiles = include("campaign_evolved/heads.lua")
end
local covenantWeapons = include("campaign_evolved/weapons.lua")
local difficulty = include("campaign_evolved/difficulty.lua")
difficulty.Setup()
if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("campaign_evolved/elite_anims.lua")
    AddCSLuaFile("campaign_evolved/human.lua")
    AddCSLuaFile("campaign_evolved/actor.lua")
    AddCSLuaFile("campaign_evolved/sounds/elite.lua")
    AddCSLuaFile("campaign_evolved/sounds/elite_shield.lua")
    AddCSLuaFile("campaign_evolved/weapons.lua")
    AddCSLuaFile("campaign_evolved/weapon.lua")
    AddCSLuaFile("campaign_evolved/ce8_gauge.lua")
    AddCSLuaFile("campaign_evolved/ce8_shield.lua")
    AddCSLuaFile("campaign_evolved/weapon_fx.lua")
    AddCSLuaFile("campaign_evolved/ballistics.lua")
    AddCSLuaFile("campaign_evolved/difficulty.lua")
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

-- Register explicitly as well as supporting GMod's normal entity loader. This
-- lets lua_openscript load the new classes into an already running local map.
local previousENT, previousSWEP = ENT, SWEP
local eliteData
local rosterData = {}
local ok, message = xpcall(function()
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
    for _, owner in ipairs({"grunt", "jackal", "hunter", "flood_combat_human", "flood_combat_elite",
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
        local action = IsValid(actor) and actor.CE8PostCombat
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
    -- Apply the facing correction to existing NPCs on explicit Lua reload.
    for _, actor in ipairs(ents.FindByClass("npc_vj_ce8_elite*")) do
        actor.ConstantlyFaceEnemy = false
        actor.SoundTbl_GrenadeSight = actor.SoundTbl_DangerSight
        local footsteps = GetConVar("vj_npc_snd_footstep")
        actor.HasFootstepSounds = not footsteps or footsteps:GetBool()
        actor.DisableFootStepSoundTimer = true
        actor.CE8FootAttachments = nil
        actor.CE8FootstepLast = nil
        if actor.CE8ApplyStats then actor:CE8ApplyStats(false) end
        actor.CE8ActivitySets = nil
        if actor.CE8ConfigureAI then
            actor:CE8ConfigureAI()
            if actor.JumpParams.Enabled then actor:CapabilitiesAdd(CAP_MOVE_JUMP) end
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
            local sight = actor:GetHeadDirection()
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
        local report = {engagement = engagement, rank = actor.CE8Rank, health = actor:Health(), shield = actor.CE8Shield, shield_max = actor.CE8ShieldMax,
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
