-- Shared CE8 actor resources, lifecycle and rendering for Human/Creature hosts.
-- VJ retains navigation, combat scheduling and possession.
local Host = {}
local barrier = SERVER and include("campaign_evolved/barrier.lua")

function Host.Shared(ENT, owner, adapter)
    adapter = adapter or "human"
    local data = include("campaign_evolved/" .. owner .. "_anims.lua")
    function ENT:CE8Data() return data end
    function ENT:CE8RankSettings() return data.ranks[self.CE8Rank or "minor"] end
    function ENT:CE8WeaponMount(weapon)
        local set = data.weapon_sets[weapon.CE8WeaponName]
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
        adapter = adapter, capabilities = {movement = true, aim = true, grip = adapter == "human"},
        sets = data.weapon_sets, default_set = data.default_weapon,
        weapon_key = function(self, weapon) return weapon.CE8WeaponName end,
        track_without_firing = true,
        aim_allowed = function(self) return not self.AIFlee end,
        crouch_allowed = function(self) return not self.AIFlee end,
        grip = {parameter = "grip", minimum = 0, maximum = data.grip_max, default = 0}
    })
    function ENT:CE8ApplyGrip(amount) return self:AIApplyGrip(amount) end
    function ENT:FireAnimationEvent(pos, ang, event)
        if event >= 4001 and event <= 4007 then return true end
    end
end

function Host.Profile(data, adapter)
    adapter = adapter or "human"
    local sounds = include("campaign_evolved/sounds/" .. data.owner .. ".lua")
    local materials = {
        [MAT_CONCRETE] = "stone", [MAT_DIRT] = "dirt", [MAT_GRASS] = "grass", [MAT_SAND] = "sand",
        [MAT_SNOW] = "snow", [MAT_SLOSH] = "mud", [MAT_METAL] = "metalthick", [MAT_GRATE] = "metalthin",
        [MAT_VENT] = "metalthin", [MAT_COMPUTER] = "metalthin", [MAT_WOOD] = "wood", [MAT_GLASS] = "glass",
        [MAT_TILE] = "brittle", [MAT_PLASTIC] = "rubber", [MAT_FOLIAGE] = "soft_organic",
        [MAT_FLESH] = "flesh", [MAT_BLOODYFLESH] = "flesh", [MAT_ALIENFLESH] = "flesh", [MAT_WARPSHIELD] = "energy"
    }
    return {
        adapter = adapter, sounds = sounds,
        capabilities = {controller = true, cover = adapter == "human", flee = adapter == "human", dialogue = true,
            footsteps = true, search = true, reactions = true,
            shield = data.owner == "jackal" and function(self) return (self:CE8RankSettings().native_shield or 0) > 0 end or false},
        shield = data.owner == "jackal" and barrier.Profile(sounds) or nil,
        lifecycle = {
            grip = function(self) return self:GetNW2Int("ce8_grip", 0) end,
            shutdown = function(self) if self.CE8RemoveEquipment then self:CE8RemoveEquipment() end end
        },
        controller = {spacing = {distance = 240, progress = 8, stall_time = 1.2, retry_delay = 2}},
        cover = {range = 512, max_objects = 6, head_height = data.hull.height * 0.95},
        flee = {
            settings = function(self) return self:CE8RankSettings().retreat end,
            allowed = function(self)
                local disabled = GetConVar("ai_disabled")
                if (disabled and disabled:GetBool()) or self:GetState() == VJ_STATE_FREEZE then return false end
                return true
            end,
            is_leader = function(self, ally) return ally.AISquadLeader == true end,
            notice_loss = function(self, ally) return self:Disposition(ally) == D_LI and self:Visible(ally) end,
            started = function(self, action)
                self:ResetTurnTarget()
                self:AIPlayDialogue("flee", CurTime(), action)
            end
        },
        reactions = {damage = {families = {any = data.damage_reactions or {}}, default_family = "any",
            default_region = "gut", hitgroups = {[HITGROUP_HEAD] = "head", [HITGROUP_LEFTARM] = "l_arm",
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
            domain = "ce8_enemy", rules = data.dialogue_rules,
            bank = function(self) return sounds.dialogue[self.CE8Voice or data.owner] end
        },
        footsteps = {
            bank = sounds.footsteps, attachments = {left = "left_foot", right = "right_foot"},
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
end

function Host.Server(ENT, profile)
    local data = ENT:CE8Data()
    local sounds = profile.sounds
    local difficulty = include("campaign_evolved/difficulty.lua")
    include("vj_ai/core.lua").Attach(ENT, profile)
    ENT.Model = data.model
    ENT.StartHealth = data.ranks.minor.health
    ENT.HullType = profile.adapter == "creature" and HULL_LARGE or (data.owner == "grunt" and HULL_WIDE_SHORT or HULL_HUMAN)
    ENT.BloodColor = VJ.BLOOD_COLOR_PURPLE
    ENT.VJ_NPC_Class = {"CLASS_COVENANT"}
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
    ENT.HasFootstepSounds = true
    ENT.DisableFootStepSoundTimer = true
    ENT.FootstepSoundPitch = VJ.SET(100, 100)
    ENT.MainSoundPitch, ENT.MainSoundPitchStatic = 100, true
    ENT.CanFlinch = true
    ENT.HasDeathAnimation = false -- Ragdolls until authored death motion gets its own live check.
    ENT.HasPoseParameterLooking = true
    ENT.PoseParameterLooking_InvertPitch = true
    ENT.PoseParameterLooking_Names = {pitch = {}, yaw = {}, roll = {}}
    ENT.PoseParameterLooking_TurningSpeed = 8
    ENT.ControllerParams = {CameraMode = 1, ThirdP_Offset = Vector(), FirstP_Bone = "head_m",
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
        if self.AIFlee then return self:AIMotionBase("GetTurnAngle", angle) end
        return self:AIGetTurnAngle(angle)
    end
    function ENT:OverrideMoveFacing(interval, move)
        if self.AIFlee then return self:AIMotionBase("OverrideMoveFacing", interval, move) end
        return self:AIOverrideMoveFacing(interval, move)
    end
    function ENT:UpdatePoseParamTracking(reset) if not self.AIFlee then return self:AIUpdatePoseTracking(reset) end end
    function ENT:GetHeadDirection() return self:AIHeadDirection() end
    function ENT:GetAimPosition(...) return self:AIMotionAimPosition(...) end
    function ENT:SetTurnTarget(...) return self:AIMotionTurnTarget(...) end
    function ENT:PlayAnim(...) return self:AIMotionPlayAnim(...) end
    function ENT:OnTaskFailed(code, message) self:AITaskFailed(code, message, CurTime()) end
    function ENT:Init()
        local rank, hull = self:CE8RankSettings(), data.hull
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
        self:SetNW2Int("ce8_grip", 0)
        self.CE8Voice = data.owner
        local bank = sounds.dialogue[self.CE8Voice]
        for category, cue in pairs({Idle = "idle", CombatIdle = "thrtn", Alert = "seefoe", Investigate = "invsgt",
            LostEnemy = "lst_cntct", AllyDeath = "lmnt_deadally", Pain = "pain", Death = "dth",
            DangerSight = "warn_incmn", GrenadeSight = "warn_incmn"}) do self["SoundTbl_" .. category] = bank[cue] or false end
        self.EnemyTimeout = data.search.time[2]
        self:AISetAnimationTranslations(data.default_weapon)
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
            damage:SetDamage(damage:GetDamage() / difficulty.Multiplier("resistance"))
        elseif status == "PostDamage" and self:AIHasCapability("flee") and self:Health() > 0
            and self:Health() / self:GetMaxHealth() <= self:CE8RankSettings().retreat.critical_fraction then
            self.CE8FleeRequest = {reason = "wounded", time = CurTime()}
        end
    end
    function ENT:OnFlinch(damage, hitgroup, status)
        if status ~= "Init" then return end
        if self.AIFlee or self.AttackType then return true end
        local sequence = self:AISelectDamage("h_ping", damage, hitgroup)
        if not sequence then return true end
        self.AnimTbl_Flinch = sequence
    end
    function ENT:OnDeath(damage, hitgroup, status) if status == "Init" then self:AIShutdown(CurTime(), "death") end end
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
            if self.HasSounds ~= false and choices and #choices > 0 then self:EmitSound(choices[math.random(#choices)], 70, 100, 1, CHAN_BODY) end
        elseif event == 4003 then self:AIPlayDialogue(options, CurTime())
        elseif event == 4001 and (options == "left foot" or options == "right foot") then
            self:AIFootstep(options == "left foot" and "left" or "right")
        end
    end
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
    self:CE8ApplyGrip(self:GetNW2Int("ce8_grip", (self:CE8Data().weapon or {}).grip or 0))
    self:CE8BindRenderer()
end

function ENT:Think()
    self:CE8ApplyGrip(self:GetNW2Int("ce8_grip", (self:CE8Data().weapon or {}).grip or 0))
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
