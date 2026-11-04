-- Shared CE8 actor resources, lifecycle and rendering for Human/Creature hosts.
-- VJ retains navigation, combat scheduling and possession.
local Host = {}
-- Weapon users share Human scheduling. Cover/retreat are independent choices.
Host.Roster = {
    elite = {adapter = "human", squad = true}, grunt = {adapter = "human", squad = true},
    jackal = {adapter = "human", squad = true},
    brute = {adapter = "human", squad = true, flee = false, unarmed_flee = false},
    hunter = {adapter = "human", cover = false, reload_cover = false, flee = false,
        retreat_distance = 0, unarmed_flee = false, crouch_fire = false, occlusion_delay = false},
    flood_combat_human = {adapter = "human", cover = false, reload_cover = false, flee = false,
        retreat_distance = 0, unarmed_flee = false, crouch_fire = false, occlusion_delay = false, strafe = false, generic_weapons = true},
    flood_combat_elite = {adapter = "human", cover = false, reload_cover = false, flee = false,
        retreat_distance = 0, unarmed_flee = false, crouch_fire = false, occlusion_delay = false, strafe = false, generic_weapons = true},
    flood_tank = {adapter = "creature"}, flood_infection = {adapter = "creature"},
    flood_carrier = {adapter = "creature"}
}
function Host.Option(data, name, fallback)
    local overrides = data.behavior or {}
    if overrides[name] ~= nil then return overrides[name] end
    local preset = Host.Roster[data.owner] or {}
    if preset[name] ~= nil then return preset[name] end
    return fallback
end
local barrier = SERVER and include("campaign_evolved/barrier.lua")
local heads
if SERVER then
    CE8 = CE8 or {}
    CE8.HeadProfiles = CE8.HeadProfiles or include("campaign_evolved/heads.lua")
    heads = CE8.HeadProfiles
end

function Host.Weapons(ENT, data)
    if SERVER then AddCSLuaFile("vj_ai/weapons.lua") end
    local pickup = Host.Option(data, "generic_weapons", false)
    include("vj_ai/weapons.lua").Attach(ENT, {
        mount = {attachment = "right_hand", pos = Vector(), ang = Angle(0, 90, 180),
            model_angle = Angle(0, 0, 180)},
        native = function(weapon) return weapon.CE8Attach ~= nil end,
        accepts = function(weapon) return not weapon.CE8Attach or data.weapon_sets[weapon.CE8WeaponName] ~= nil end,
        pickup = pickup and {radius = 512, reach = 80, interval = 2, timeout = 6, enemy_distance = 128} or nil,
        allowed = function(self)
            return not self.CE8Rising and not (self.AIAnatomy and self.AIAnatomy.disarmed)
        end
    })
end

function Host.Shared(ENT, owner, adapter)
    include("campaign_evolved/roster_collision.lua").Shared(ENT, owner)
    if owner=="jackal" then
        ENT.CE8MergedBarrier=true
        ENT.ColliderFile="npc_vj_ce8_jackal_collision.json"
        ENT.ColliderBodies=include("campaign_evolved/jackal_colliders.lua")
        function ENT:OnColliderImpactTrace(proxy)
            if (proxy.ColliderSurface or proxy:GetNW2String("prp_surface"))=="default_silent" then return true end
        end
        if SERVER then
            AddCSLuaFile("campaign_evolved/jackal_colliders.lua")
            AddCSLuaFile("campaign_evolved/jackal_collision.lua")
        end
    end
    local data = include("campaign_evolved/" .. owner .. "_anims.lua")
    adapter = adapter or Host.Option(data, "adapter", "human")
    function ENT:CE8Data() return data end
    function ENT:CE8RankSettings() return data.ranks[self.CE8Rank or "minor"] end
    function ENT:CE8WeaponMount(weapon)
        local set = IsValid(weapon) and data.weapon_sets[weapon.CE8WeaponName]
        return set and set.mount
    end
    function ENT:CE8WeaponGrip(weapon)
        local set = IsValid(weapon) and data.weapon_sets[weapon.CE8WeaponName]
        return set and set.grip or 0
    end
    if SERVER then
        AddCSLuaFile("campaign_evolved/actor.lua")
        AddCSLuaFile("campaign_evolved/" .. owner .. "_anims.lua")
        AddCSLuaFile("vj_ai/motion.lua")
    end
    include("vj_ai/motion.lua").Attach(ENT, {
        adapter = adapter, capabilities = {movement = true, aim = data.aim ~= false, grip = (data.grip_max or 0) > 0},
        forward_only = data.forward_only,
        sets = data.weapon_sets, default_set = data.default_weapon,
        weapon_key = function(self, weapon)
            if data.weapon_sets[weapon.CE8WeaponName] then return weapon.CE8WeaponName end
            return Host.Option(data, "generic_weapons", false) and "any" or nil
        end,
        track_without_firing = true,
        blind_point = function(self, target)
            if not SERVER or not self.AICorpseFirePoint then return end
            local weapon = self:GetActiveWeapon()
            return self:AICorpseFirePoint(weapon) or self:AISuppressionPoint(weapon, target)
        end,
        aim_allowed = function(self) return not self.AIFlee and not self.AIKamikaze end,
        crouch_allowed = function(self) return not self.AIFlee and not self.AIKamikaze end,
        grip = {parameter = "grip", minimum = 0, maximum = data.grip_max, default = 0}
    })
    if adapter == "human" then Host.Weapons(ENT, data) end
    function ENT:CE8ApplyGrip(amount) return self:AIApplyGrip(amount) end
    function ENT:FireAnimationEvent(pos, ang, event)
        if event >= 4001 and event <= 4007 then return true end
    end
end

function Host.Tactics(profile, data, owner)
    owner = owner or data.owner
    profile.capabilities.threat = profile.adapter == "human"
    -- These are Source pressure units, not Halo's undocumented danger score.
    local thresholds = {grunt = 0.25, jackal = 0.4, elite = 0.65, brute = 0.85}
    profile.threat = {
        interval = 0.5, cover_pressure = thresholds[owner] or 0.5,
        policy = function(self)
            local rank = self.CE8RankSettings and self:CE8RankSettings()
            if rank and rank.tactics then return rank.tactics end
            local defensive = owner == "elite" or owner == "brute"
            return {cover = defensive, pressure = defensive, dangerous = defensive,
                unreachable = defensive, ineffective = defensive}
        end,
        allowed = function(self)
            return not self.CE8BerserkUntil and not self.CE8PendingShieldBreak and not self.CE8PendingBerserk
        end
    }
    if profile.squad then
        profile.squad.positioning = {spacing = 96, lane_width = 48, interval = 3, cooldown = 5, radius = 192, route_time = 4}
    end
    return profile
end

-- Possession publishes a small snapshot only while controlled; VJ supplies
-- health, weapon identity and ammunition through its existing controller.
function Host.Possession(owner)
    CE8 = CE8 or {}
    CE8.ControlProfiles = CE8.ControlProfiles or include("campaign_evolved/possession.lua").owners
    return {
        settings = CE8.ControlProfiles[owner],
        ignore = function(self) return self.ColliderParts or self.CE8ArmorParts end,
        started = function(self, state)
            state.controller.VJC_Player_DrawHUD = false
            state.controller:SetHUDEnabled(false)
            state.controller:SetNW2Bool("ce8_hud", true)
        end,
        stopped = function(self, state)
            state.controller:SetNW2Bool("ce8_hud", false)
            state.controller:SetHUDEnabled(state.hud ~= false)
        end,
        changed = function(self, state)
            if IsValid(state.controller) then state.controller:SetNW2Bool("ce8_crouched", state.crouched) end
        end,
        update = function(self, state, now)
            local controller, shield, maximum = state.controller, 0, 0
            local _, stance = self:AIAnimationSet()
            local controls = self:AIProfile().possession.settings
            controller:SetNW2Bool("ce8_crouch_supported", controls.crouch.enabled and controls.crouch.sets[stance] == true)
            local profile = self:AIProfile().shield
            if profile and self:AIHasCapability("shield") then
                shield = self[profile.fields.value] or 0
                maximum = profile.maximum
                if type(maximum) == "function" then maximum = maximum(self) end
                maximum = tonumber(maximum) or 0
            end
            controller:SetNW2Vector("ce8_vitals", Vector(shield, maximum, self.CE8Grenades or 0))
            controller:SetNW2Float("ce8_max_health", self:GetMaxHealth())
            local weapon = self.GetActiveWeapon and self:GetActiveWeapon()
            local heat, charge, clip = 0, 0, 0
            if IsValid(weapon) then
                local values = weapon.CE8Data
                local threshold = values and values.heat and values.heat.threshold or 0
                heat = threshold > 0 and math.Clamp((weapon.CE8Heat or 0) / threshold, 0, 1) or 0
                local charging = weapon.CE8Charge
                if type(charging) == "table" and charging.finish and charging.start then
                    charge = math.Clamp((now - charging.start) / math.max(0.001, charging.finish - charging.start), 0, 1)
                end
                clip = weapon.Primary and weapon.Primary.ClipSize or 0
            end
            controller:SetNW2Vector("ce8_weapon_state", Vector(heat, charge, clip))
        end
    }
end

function Host.Profile(data, adapter)
    adapter = adapter or Host.Option(data, "adapter", "human")
    local sounds = include("campaign_evolved/sounds/" .. data.owner .. ".lua")
    local materials = {
        [MAT_CONCRETE] = "stone", [MAT_DIRT] = "dirt", [MAT_GRASS] = "grass", [MAT_SAND] = "sand",
        [MAT_SNOW] = "snow", [MAT_SLOSH] = "mud", [MAT_METAL] = "metalthick", [MAT_GRATE] = "metalthin",
        [MAT_VENT] = "metalthin", [MAT_COMPUTER] = "metalthin", [MAT_WOOD] = "wood", [MAT_GLASS] = "glass",
        [MAT_TILE] = "brittle", [MAT_PLASTIC] = "rubber", [MAT_FOLIAGE] = "soft_organic",
        [MAT_FLESH] = "flesh", [MAT_BLOODYFLESH] = "flesh", [MAT_ALIENFLESH] = "flesh", [MAT_WARPSHIELD] = "energy"
    }
    local profile = {
        adapter = adapter, sounds = sounds,
        possession = Host.Possession(data.owner),
        gaze = {rig = heads[data.owner]},
        capabilities = {gaze = true, squad = Host.Option(data, "squad", false), controller = true, cover = Host.Option(data, "cover", adapter == "human"),
            flee = Host.Option(data, "flee", adapter == "human"), dialogue = Host.Option(data, "dialogue", true),
            footsteps = Host.Option(data, "footsteps", true), search = Host.Option(data, "search", true), reactions = true,
            charge = data.charge ~= nil,
            shield = data.owner == "jackal" and function(self) return (self:CE8RankSettings().native_shield or 0) > 0 end or false},
        shield = data.owner == "jackal" and barrier.Profile(sounds) or nil,
        -- Nearby groups are a Source policy, not Halo mission squad placement.
        squad = Host.Option(data, "squad", false) and {key = "covenant", limit = 8, radius = 900} or nil,
        lifecycle = {
                shutdown = function(self) if self.CE8RemoveEquipment then self:CE8RemoveEquipment() end end
        },
        controller = {spacing = {distance = 240, progress = 8, stall_time = 1.2, retry_delay = 2}},
        charge = data.charge and {settings = data.charge} or nil,
        cover = {range = 512, max_objects = 6, head_height = data.hull.height * 0.95},
        flee = {
            settings = function(self) return self:CE8RankSettings().retreat end,
            allowed = function(self)
                local disabled = GetConVar("ai_disabled")
                if (disabled and disabled:GetBool()) or self:GetState() == VJ_STATE_FREEZE then return false end
                return true
            end,
            is_leader = function(self, ally) return self:AISquadIsLeader(ally) end,
            notice_loss = function(self, ally)
                return (not self:AIHasCapability("squad") or self:AISquadMember(ally))
                    and self:Disposition(ally) == D_LI and self:Visible(ally)
            end,
            started = function(self, action)
                self:ResetTurnTarget()
                self:AIPlayDialogue("flee", CurTime(), action)
            end
        },
        reactions = {family = data.damage_families and function(self) local _, key = self:AIAnimationSet() return key end or nil,
            ignore = function(self) return self.ColliderParts or self.CE8ArmorParts end,
            damage = {families = data.damage_families or {any = data.damage_reactions or {}}, default_family = "any",
            default_region = "gut", hitgroups = {[HITGROUP_HEAD] = "head", [HITGROUP_CHEST] = "chest",
                [HITGROUP_STOMACH] = "gut", [HITGROUP_LEFTARM] = "l_arm",
                [HITGROUP_RIGHTARM] = "r_arm", [HITGROUP_LEFTLEG] = "l_leg", [HITGROUP_RIGHTLEG] = "r_leg"}}},
        search = {
            default_mode = "normal", mode = "normal",
            settings = data.search,
            -- First pass investigates the remembered position. Native suppression
            -- weights remain catalogued; no hidden-target aiming is introduced.
            started = function(self, action, now) self:AIQueueDialogue("searching", now, action) end,
            finished = function(self, action) self:AICancelDialogue(action) end
        },
        dialogue = {
            domain = data.dialogue_domain or "ce8_enemy", rules = data.dialogue_rules,
            bank = function(self) return sounds.dialogue[self.CE8Voice or data.voice or data.owner] end
        },
        footsteps = {
            bank = sounds.footsteps, attachments = data.foot_attachments or {left = "left_foot", right = "right_foot"},
            materials = materials, default_surface = "stone", water_surface = "water",
            properties = {{"ice", "ice"}, {"gravel", "gravel"}, {"mud", "mud"}, {"grate", "metalthin"}, {"vent", "metalthin"}},
            action = function(self)
                local name = "_" .. self:GetSequenceName(self:GetSequence()) .. "_"
                if name:find("_walk_", 1, true) then return "walk" end
                if name:find("_move_", 1, true) then return "run" end
                return "shuffle"
            end
        }
    }
    return Host.Tactics(profile, data)
end

function Host.Server(ENT, profile)
    local data = ENT:CE8Data()
    local sounds = profile.sounds
    local difficulty = include("campaign_evolved/difficulty.lua")
    include("vj_ai/core.lua").Attach(ENT, profile)
    ENT.Model = data.model
    ENT.StartHealth = data.ranks.minor.health
    local hulls = {tiny = HULL_TINY, human = HULL_HUMAN, large = HULL_LARGE}
    ENT.HullType = hulls[data.hull.kind] or ((profile.adapter == "creature" or data.hull.radius >= 32) and HULL_LARGE or (data.owner == "grunt" and HULL_WIDE_SHORT or HULL_HUMAN))
    ENT.BloodColor = VJ.BLOOD_COLOR_PURPLE
    ENT.VJ_NPC_Class = {data.faction or "CLASS_COVENANT"}
    ENT.MovementType = VJ_MOVETYPE_GROUND
    ENT.CanTurnWhileMoving = true
    ENT.UsePoseParameterMovement = false
    ENT.ConstantlyFaceEnemy = false
    ENT.TurningSpeed = 30
    ENT.FollowPlayer = false
    ENT.CallForHelp = true
    ENT.AnimTbl_CallForHelp = false
    ENT.AnimTbl_DamageAllyResponse = false
    ENT.HasGrenadeAttack = false
    ENT.CanRedirectGrenades = false
    ENT.JumpParams = {Enabled = false}
    ENT.HasFootstepSounds = Host.Option(data, "footsteps", true)
    ENT.DisableFootStepSoundTimer = true
    ENT.FootstepSoundPitch = VJ.SET(100, 100)
    ENT.MainSoundPitch, ENT.MainSoundPitchStatic = 100, true
    ENT.CombatDamageResponse = profile.capabilities.cover
    ENT.CanFlinch = true
    ENT.HasDeathAnimation = data.deaths ~= nil
    ENT.HasPoseParameterLooking = data.aim ~= false
    ENT.PoseParameterLooking_InvertPitch = true
    ENT.PoseParameterLooking_Names = {pitch = {}, yaw = {}, roll = {}}
    ENT.PoseParameterLooking_TurningSpeed = 8
    ENT.ControllerParams = {CameraMode = 1, ThirdP_Offset = Vector(), FirstP_Bone = data.camera_bone or "head_m",
        FirstP_Offset = Vector(), FirstP_ShrinkBone = true, FirstP_CameraBoneAng = 0, FirstP_CameraBoneAng_Offset = 0}

    function ENT:ScaleByDifficulty(amount) return amount end
    function ENT:CE8ApplyStats(initialize)
        difficulty.ApplyVitality(self, self:CE8RankSettings(), initialize)
        if data.owner == "jackal" then barrier.ApplyStats(self, initialize) end
    end
    function ENT:PreInit() self.StartHealth = self:CE8RankSettings().health end
    function ENT:CE8WeaponSet(weapon) return self:AIAnimationSet(weapon) end
    function ENT:CE8CacheActivities(weapon) return self:AIAnimationActivities(weapon) end
    function ENT:SetAnimationTranslations(hold, weapon) return self:AISetAnimationTranslations(hold, weapon) end
    function ENT:TranslateActivity(act)
        if self.AIKamikaze and self.AIKamikaze.phase == "charge" and data.kamikaze then
            local sequence
            if act == ACT_IDLE or act == ACT_IDLE_ANGRY then sequence = data.kamikaze.idle
            elseif act == ACT_RUN or act == ACT_WALK or act == ACT_RUN_AIM or act == ACT_WALK_AIM or act == ACT_RUN_PROTECTED then
                sequence = data.kamikaze.run
            end
            if sequence then return self:GetSequenceActivity(self:LookupSequence(sequence)) end
        end
        if self.AIFlee then
            local a = self:AIAnimationActivities()
            if self.AIFlee.holding and (act == ACT_IDLE or act == ACT_IDLE_ANGRY) then return a.flee_idle or a.crouch_idle end
            if act == ACT_RUN or act == ACT_WALK or act == ACT_RUN_AIM or act == ACT_WALK_AIM or act == ACT_RUN_PROTECTED then
                return (self.AIFlee.reason == "leader_lost" and a.panic_move) or a.flee_move or a.combat_move_front
            end
        end
        return self:AITranslateActivity(act)
    end
    function ENT:GetTurnAngle(angle)
        if self.AIFlee or self.AIKamikaze then return self:AIMotionBase("GetTurnAngle", angle) end
        return self:AIGetTurnAngle(angle)
    end
    function ENT:OverrideMoveFacing(interval, move)
        if self.AIFlee or self.AIKamikaze then return self:AIMotionBase("OverrideMoveFacing", interval, move) end
        return self:AIOverrideMoveFacing(interval, move)
    end
    function ENT:UpdatePoseParamTracking(reset) if not self.AIFlee and not self.AIKamikaze then return self:AIUpdatePoseTracking(reset) end end
    function ENT:GetAimPosition(...) return self:AIMotionAimPosition(...) end
    function ENT:SetTurnTarget(...) return self:AIMotionTurnTarget(...) end
    function ENT:PlayAnim(...) return self:AIMotionPlayAnim(...) end
    function ENT:OnMeleeAttack(status)
        if status == "PreInit" and self:AIIsReloading() then return true end
    end
    function ENT:TASK_VJ_PLAY_SEQUENCE(status, task)
        local side = type(task.animation) == "string" and task.animation:match("_melee_(%a+)$")
        -- VJ already consumes translating walkframes. Supply its same engine
        -- movement call for stationary directional turns, which VJ skips.
        if (side == "back" or side == "left" or side == "right")
            and status ~= TASKSTATUS_NEW and task.seqID == self:GetSequence()
            and CurTime() <= task.animEndTime and not self:IsSequenceFinished()
            and not self:IsMoving() and self.MovementType == VJ_MOVETYPE_GROUND
            and self:GetSequenceMoveDist(task.seqID) <= 0 then
            self:AutoMovement(self:GetAnimTimeInterval())
        end
        return self:AIBaseCall("TASK_VJ_PLAY_SEQUENCE", status, task)
    end
    function ENT:OnDangerDetected()
        -- VJ's default danger response runs to cover. Species can override this
        -- hook later with an authored brace/dive without enabling fleeing.
        if not self:AIHasCapability("cover") then return true end
    end
    function ENT:OnTaskFailed(code, message) self:AITaskFailed(code, message, CurTime()) end
    function ENT:Init()
        local rank, hull = self:CE8RankSettings(), data.hull
        if rank.flinch then self.FlinchChance = 1 end
        self:CE8ApplyStats(true)
        self:AIInitialize(CurTime())
        self:CapabilitiesAdd(CAP_MOVE_SHOOT)
        self:SetCollisionBounds(Vector(-hull.radius, -hull.radius, 0), Vector(hull.radius, hull.radius, hull.height))
        self:SetSaveValue("m_HackedGunPos", Vector(8, 0, hull.gun))
        for name, value in pairs(rank.bodygroups) do
            local id = self:FindBodygroupByName(name)
            if id >= 0 then self:SetBodygroup(id, value) end
        end
        self:SetHitboxSet(rank.hitbox_set)
        self:SetNW2String("ce8_rank", self.CE8Rank or "minor")
        self:AIApplyGrip(0)
        self:SetNW2Int("ce8_grip", 0)
        self.CE8Voice = data.voices and data.voices[math.random(#data.voices)] or data.voice or data.owner
        local bank = sounds.dialogue[self.CE8Voice] or {}
        for category, cue in pairs({Idle = "idle", CombatIdle = "thrtn", Alert = "seefoe", Investigate = "invsgt",
            LostEnemy = "lst_cntct", AllyDeath = "lmnt_deadally", Pain = "pain", Death = "dth",
            DangerSight = "warn_incmn", GrenadeSight = "warn_incmn"}) do self["SoundTbl_" .. category] = bank[cue] or false end
        self.EnemyTimeout = data.search.time[2]
        self:SetAnimationTranslations(data.default_weapon)
    end
    function ENT:CE8PlayDialogue(cue, now, context) return self:AIPlayDialogue(cue, now or CurTime(), context) end
    function ENT:CE8QueueDialogue(cue, now, context) return self:AIQueueDialogue(cue, now or CurTime(), context) end
    function ENT:OnThink() self:AIUpdate(CurTime()) end
    function ENT:OnThinkActive()
        local request, now = self.CE8FleeRequest, CurTime()
        if request and (now - request.time > 2 or self:AIStartFlee(request.reason, self:GetEnemy(), now)) then self.CE8FleeRequest = nil end
        self:AIThinkActions(now)
    end
    function ENT:OnAlert(enemy) self:AIAlert(enemy, CurTime()) end
    function ENT:OnResetEnemy() self:AIResetEnemy(CurTime()) end
    function ENT:OnAllyKilled(ally) self:AIAllyLost(ally, CurTime()) end
    function ENT:OnCreateSound(sound, path) self:AIObserveDialogue(sound, path, CurTime(), self:GetEnemy()) end
    function ENT:OnDamaged(damage, hitgroup, status)
        if status == "PreDamage" then
            self:AIRecordThreatDamage(damage, CurTime())
            damage:SetDamage(damage:GetDamage() / difficulty.Multiplier("resistance"))
        elseif status == "PostDamage" and self:AIHasCapability("flee") and not self.AIKamikaze and self:Health() > 0
            and self:Health() / self:GetMaxHealth() <= self:CE8RankSettings().retreat.critical_fraction then
            self.CE8FleeRequest = {reason = "wounded", time = CurTime()}
        end
    end
    function ENT:OnFlinch(damage, hitgroup, status)
        if status ~= "Init" then return end
        if self.Dead or self:Health() <= 0 or self.AIFlee or self.AIKamikaze or self.AttackType
            or self.AILeap or self.AISurface or self.CE8BurstPlayed or self.CE8Rising then return true end
        local settings = self:CE8RankSettings().flinch
        local kind = "h_ping"
        if settings then
            local shield = self.CE8ShieldFlinchAmount or damage:GetDamage()
            local threshold = self.CE8ShieldFlinchAmount and settings.threshold or settings.unshielded
            if shield < threshold then
                local soft = self.CE8ShieldFlinchAmount and settings.soft or settings.soft_unshielded
                if soft == nil or shield < soft then return true end
                kind = "s_ping"
            end
            self.FlinchCooldown = kind == "h_ping" and settings.cooldown > 0 and settings.cooldown or false
        end
        -- Let VJ select an explicit hitgroup map after our normal reaction gates.
        for _, entry in ipairs(self.FlinchHitGroupMap or {}) do
            if VJ.HasValue(entry.HitGroup, hitgroup) then return end
        end
        local sequence = self:AISelectDamage(kind, damage, hitgroup)
        if not sequence then return true end
        if data.gesture_reactions and data.gesture_reactions[sequence:sub(7)] then
            sequence = "vjges_" .. sequence:sub(7)
        end
        self.AnimTbl_Flinch = sequence
    end
    function ENT:OnDeath(damage, hitgroup, status)
        if status ~= "Init" then return end
        local grounded = self:OnGround() -- Capture before leap/traversal cleanup.
        self:AIShutdown(CurTime(), "death")
        self.AnimTbl_Death, self.DeathAnimationTime = {}, false
        local setting = GetConVar("vj_npc_anim_death")
        if not self.HasDeathAnimation or not data.deaths or not grounded or self.CE8ImmediateBurst
            or self.CE8BodyDestroyed or (setting and not setting:GetBool())
            or damage:IsDamageType(bit.bor(DMG_BLAST, DMG_DISSOLVE, DMG_REMOVENORAGDOLL)) then
            self.HasDeathAnimation = false
            return
        end
        -- Reuse our existing hard-reaction threshold as a Source selection
        -- policy; this is not a recovered native hard/soft-death decision rule.
        local flinch = self:CE8RankSettings().flinch
        local hard = damage:GetDamage() >= (flinch and flinch.unshielded or math.huge)
        for _, action in ipairs(hard and {"h_kill", "s_kill"} or {"s_kill", "h_kill"}) do
            local animation = self:AISelectDamage(action, damage, hitgroup, data.deaths)
            local name = animation and animation:sub(7)
            local clip = name and data.deaths.clips[name]
            if clip and self:LookupSequence(name) >= 0
                and (not clip.motion or self:AIValidateMotion(name, 0, nil, clip.cycle)) then
                self.AnimTbl_Death, self.DeathAnimationTime = {animation}, clip.time
                return -- VJ owns playback, playback-rate scaling and the ragdoll.
            end
        end
        self.HasDeathAnimation = false -- Missing/blocked deaths retain normal ragdolls.
    end
    function ENT:CustomOnRemove() self:AIShutdown(CurTime(), "remove") end
    function ENT:OnCreateDeathCorpse(damage, hitgroup, corpse)
        if not IsValid(corpse) then return end
        corpse:SetSkin(self:GetSkin())
        for _, group in ipairs(self:GetBodyGroups()) do corpse:SetBodygroup(group.id, self:GetBodygroup(group.id)) end
        corpse:SetHitboxSet(self:CE8RankSettings().hitbox_set)
    end
    function ENT:OnAnimEvent(event, eventTime, cycle, eventType, options)
        if event == 4005 then
            local choices = sounds.events[options]
            if self.HasSounds ~= false and choices and #choices > 0 then VJ.EmitSound(self, choices, 70, 100, 1, CHAN_AUTO) end
        elseif event == 4003 then self:AIPlayDialogue(options, CurTime())
        elseif event == 4001 and (options == "left foot" or options == "right foot") then
            self:AIFootstep(options == "left foot" and "left" or "right")
        end
    end
    include("campaign_evolved/roster_collision.lua").Attach(ENT, data.owner)
end

function Host.Client(ENT)
local rendererToken = {}

function ENT:CE8BindRenderer()
    if not CE8 or not CE8.ApplyModelDepth then return end
    if self.CE8NPCRendererToken ~= rendererToken then
        if self.CE8NPCRenderer then self.CE8NormalSpawnRenderer = false end
        self.CE8NPCRenderer = nil
        self.CE8NPCRendererToken = rendererToken
    end
    CE8.ApplyModelDepth(self)
    if self.CE8RankSettings and self.CE8CharacterDefinition then
        self.CE8CharacterRank = self:CE8RankSettings().hitbox_set
    end
    -- CE8 already renders projected lights. The native projector pass draws
    -- ScreenspaceGeneral's full base shading again instead of light only.
    if self.CE8Draft and not self:IsEffectActive(EF_NOFLASHLIGHT) then
        self:AddEffects(EF_NOFLASHLIGHT)
    end
    if self.RenderOverride ~= self.CE8NPCRenderer then
        local draw = self.RenderOverride
        if not draw then return end
        self.CE8NPCRenderer = function(actor, flags)
            -- A Lua Draw callback can enter RenderOverride again through
            -- DrawModel. Reuse the outer pass's materials/blend/depth state.
            if actor.CE8DrawingModel then actor:DrawModel(flags) return end
            if actor.CE8UpdateRenderFrame then actor:CE8UpdateRenderFrame() end
            local previous = actor.CE8DrawingModel
            actor.CE8DrawingModel = true
            local ok, message = xpcall(function() draw(actor, flags) end, debug.traceback)
            actor.CE8DrawingModel = previous
            if not ok then ErrorNoHalt("CE8 NPC draw: " .. tostring(message) .. "\n") return end
            -- The weapon draws through its own engine/VJ callback after this
            -- scope. A raw weapon DrawModel here bypasses that engine context.
        end
        self.RenderOverride = self.CE8NPCRenderer
        self.CE8NormalSpawnRenderer = self.CE8NPCRenderer
    end
    local weapon = self.GetActiveWeapon and self:GetActiveWeapon()
    if IsValid(weapon) and weapon.CE8BindRenderer then weapon:CE8BindRenderer() end
end

function ENT:Init()
    if self.AIConfigureWeapon then self:AIConfigureWeapon(self:GetActiveWeapon()) end
    self:CE8BindRenderer()
end

function ENT:Think()
    if self.AIConfigureWeapon then self:AIConfigureWeapon(self:GetActiveWeapon()) end
    self:CE8BindRenderer()
end

function ENT:Draw(flags)
    if self.CE8DrawingModel then self:DrawModel(flags) return end
    self:CE8BindRenderer()
    if self.RenderOverride then self:RenderOverride(flags) else self:DrawModel(flags) end
end

function ENT:DrawTranslucent(flags)
    self:Draw(flags)
end

end

return Host
