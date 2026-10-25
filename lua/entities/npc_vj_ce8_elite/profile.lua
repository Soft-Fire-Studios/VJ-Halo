-- Elite resources and policies bind to character-neutral VJ AI services.
-- Core state bindings retain existing weapon, particle and report integration.
local data = ENT:CE8Data()
local sounds = include("campaign_evolved/sounds/elite.lua")
local shieldSounds = include("campaign_evolved/sounds/elite_shield.lua")
local observedDialogue = {}
for _, voice in pairs(sounds.dialogue) do
    for _, path in ipairs(voice.seefoe or {}) do observedDialogue[path] = "seefoe" end
end

local footMaterials = {
    [MAT_CONCRETE] = "stone", [MAT_DIRT] = "dirt", [MAT_GRASS] = "grass",
    [MAT_SAND] = "sand", [MAT_SNOW] = "snow", [MAT_SLOSH] = "mud",
    [MAT_METAL] = "metal_thick", [MAT_GRATE] = "metal_thin", [MAT_VENT] = "metal_thin",
    [MAT_COMPUTER] = "metal_thin", [MAT_WOOD] = "wood", [MAT_GLASS] = "glass",
    [MAT_TILE] = "brittle", [MAT_PLASTIC] = "rubber", [MAT_FOLIAGE] = "soft_organic",
    [MAT_FLESH] = "flesh", [MAT_BLOODYFLESH] = "flesh", [MAT_ALIENFLESH] = "flesh",
    [MAT_ANTLION] = "flesh", [MAT_WARPSHIELD] = "energy"
}
-- Source surface properties distinguish materials that share one MAT_* value.
local footProperties = {
    {"ice", "ice"}, {"snow", "snow"}, {"gravel", "gravel"}, {"mud", "mud"},
    {"sand", "sand"}, {"grass", "grass"}, {"dirt", "dirt"},
    {"rubber", "rubber"}, {"glass", "glass"}, {"wood", "wood"},
    {"pottery", "brittle"}, {"porcelain", "brittle"}, {"ceramic", "brittle"},
    {"grate", "metal_thin"}, {"vent", "metal_thin"}, {"sheet", "metal_thin"},
    {"metalpanel", "metal_thin"}, {"metal_box", "metal_thin"}, {"metal_barrel", "metal_thin"}
}


return {
    adapter = "human",
    capabilities = {controller = true, investigation = true, obstacle = true, idle = true, postcombat = true, shield = true, dialogue = true, footsteps = true, reactions = true, evasion = true, cover = true, perception = true, flank = true, search = true, opening = true, charge = true},
    sounds = sounds,
    shield_sounds = shieldSounds,
    lifecycle = {
        grip = function(self) return self:GetNW2Int("ce8_grip", data.weapon.grip) end,
        shutdown = function(self)
            self.CE8BerserkUntil, self.CE8PendingShieldBreak = nil, nil
            self.CE8PendingBerserk, self.CE8BerserkRequestExpires = nil, nil
        end,
        alert = function(self, enemy, now, found, mode)
            self.CE8SeenEnemies = self.CE8SeenEnemies or setmetatable({}, {__mode = "k"})
            if IsValid(enemy) then self.CE8SeenEnemies[enemy] = true end
            if found and IsValid(enemy) and self:Visible(enemy) and self.HasAlertSounds ~= false then
                self:CE8QueueDialogue("foundfoe", now, enemy)
                -- DoEnemyAlert plays generic Alert after the hook; the specific
                -- reacquisition line (including its native skip) owns this window.
                self.NextAlertSoundT = math.max(self.NextAlertSoundT or 0, now + data.dialogue_rules.foundfoe.queue)
            end
            local perception = self:CE8BehaviorSettings().perception
            local hit = self.CE8LastHit
            local surprised = self:CE8BehaviorSettings().charge.surprise
            local offset = IsValid(enemy) and (enemy:GetPos() - self:GetPos())
            if surprised and mode == "idle" and offset and offset:Length() < perception.idle.surprise
                and offset:Dot(self:GetForward()) < 0 then
                self.CE8PendingBerserk, self.CE8BerserkRequestExpires = "surprise", now + 3
            end
            -- VJ has already acquired this enemy. Halo perception time drives
            -- acknowledgement buildup, not another delay after acquisition.
            -- Share the weapon's existing first-shot deadline with coordinated
            -- openings instead of sampling or stacking a second timer.
            self.CE8AcquireAt = now
            local weapon = self:GetActiveWeapon()
            if IsValid(weapon) and weapon.CE8UpdateFireContext and not weapon.IsMeleeWeapon then
                weapon:CE8UpdateFireContext(self, now)
                if weapon.CE8FireReady and weapon.CE8FireEnemy == enemy
                    and not (hit and now - hit.time < 0.5) then
                    self.CE8AcquireAt = math.max(now, weapon.CE8NextBurstT or now)
                end
            end
        end
    },

    controller = {
        fields = {next_sample = "CE8NextAimCheck", next_tactic = "CE8NextTactic",
            spacing = "CE8Spacing", last_spacing = "CE8LastSpacing"},
        spacing = {distance = 300, progress = 8, stall_time = 1.2, retry_delay = 2},
        initialize = function(self) self:CE8InitAI() end,
        can_react = function(self, now) return self:CE8CanReact(now) end,
        priority_reaction = function(self, now) return self:CE8TryBerserk(now) end,
        evasion_allowed = function(self) return not self.CE8PendingShieldBreak end,
        before_tactics = function(self, now)
            if self.CE8BerserkUntil and now >= self.CE8BerserkUntil then self.CE8BerserkUntil = nil end
        end,
        cover_requested = function(self, now)
            local settings = self:CE8BehaviorSettings().cover
            local shieldLow = self:AIHasCapability("shield") and self.CE8Shield < self.CE8ShieldMax * settings.shield
            -- Recovery cannot heal old wounds; a new hit can request another try.
            local hurt = self:Health() < self:GetMaxHealth() * settings.vitality
                and self.CE8CoveredHit ~= (self.CE8LastHit or false)
            return not self.CE8BerserkUntil and not self.CE8PendingShieldBreak
                and now >= (self.CE8NextCover or 0) and (shieldLow or hurt)
        end
    },
    investigation = {
        fields = {active = "CE8Investigation"},
        timeout = function(self)
            local time = self:CE8BehaviorSettings().search.time
            return math.Rand(time[1], time[2])
        end,
        select = function(self, phase) return self:CE8Action("investigate_" .. phase) end,
        play = function(self, sequence, now) return self:CE8PlayReaction("investigate", sequence, now) end
    },
    obstacle = {
        fields = {active = "CE8Obstacle", context = "CE8SmashContext", count = "CE8Smashes",
            next_attempt = "CE8NextSmash", next_check = "CE8NextObstacleCheck",
            move_intent = "CE8MoveIntent", move_time = "CE8MoveIntentTime"},
        push = function(self)
            local settings = self:CE8BehaviorSettings().obstacle
            return settings and settings.smash and settings.size > settings.ignore
        end,
        damage = function(self)
            local settings = self:CE8BehaviorSettings().obstacle
            return settings and settings.destroy and settings.size > settings.ignore
        end,
        allowed = function(self) return not self.CE8Cover and not self.CE8Charge end
    },
    idle = {
        fields = {active = "CE8IdlePose", next_pose = "CE8NextIdlePose"},
        settings = function(self) return self:CE8BehaviorSettings().idle end,
        select = function(self) return self:CE8Action("idle_pose") end,
        validate_path = function(self, sequence) return self:CE8EvadePath(sequence, 0) end
    },
    postcombat = {
        fields = {active = "CE8PostCombat", transient_target = "CE8CorpseShot"},
        settings = function(self) return self:CE8BehaviorSettings().postcombat end,
        timeout = function(self) return self:CE8BehaviorSettings().idle.pose[2] end,
        can_react = function(self, now) return self:CE8CanReact(now) end,
        fire_allowed = function(self) return not self.CE8Cover and not self.CE8Search end,
        weapon_allowed = function(self, weapon)
            local values = weapon.CE8Data
            return values and not values.melee and not weapon.IsMeleeWeapon
                and not weapon.CE8Overheated and weapon:Clip1() > 0
                and values.damage.radius[2] == 0 and (not values.explosion or values.explosion.radius[2] == 0)
        end,
        fire_activity = function(self, weapon) return self:CE8CacheActivities(weapon).combat_idle end,
        burst_count = function(self) return math.random(1, 2) end,
        fired = function(self, action, now)
            if self.HasKilledEnemySounds ~= false then self:CE8QueueDialogue("shotfoebdy", now, action) end
        end,
        started = function(self, action, now)
            action.victim.CE8CorpseObserver = self -- Existing server ragdoll hook.
            self:CE8EndCharge(now)
            self:CE8EndSearchAction(now)
            self.CE8Search, self.CE8Charge, self.CE8BerserkUntil = nil, nil, nil
        end,
        finished = function(self, action, now)
            local sequence = self:CE8Action("taunt") or self:CE8Action("warn")
            if sequence then self:CE8PlayReaction("postcombat", sequence, now) end
        end
    },
    charge = {
        fields = {active = "CE8Charge", next_attempt = "CE8NextCharge"},
        settings = function(self) return self:CE8BehaviorSettings().charge end,
        forced = function(self) return self.CE8BerserkUntil ~= nil end,
        can_react = function(self, now) return self:CE8CanReact(now) end,
        started = function(self, charge, now, forced)
            if not forced then self:CE8QueueDialogue("charge", now, charge) end
        end
    },
    opening = {
        fields = {active = "CE8Opening", last = "CE8LastOpening", count = "CE8CoordinatedOpenings"},
        acquire_at = function(self) return self.CE8AcquireAt end,
        hit = function(self) return self.CE8LastHit end,
        window = function(self)
            local weapon = self:GetActiveWeapon()
            local delay = IsValid(weapon) and weapon.CE8Data and weapon.CE8Data.first_delay
            return delay and delay[2] or 0
        end,
        can_react = function(self, now) return self:CE8CanReact(now) end,
        allowed = function(self, now)
            return self:CE8BehaviorSettings().squad and not self.CE8Cover and not self.CE8Charge
                and not self.CE8PendingShieldBreak and not self.CE8PendingBerserk
                and now >= (self.CE8BerserkUntil or 0)
        end,
        weapon_allowed = function(self, weapon)
            return weapon.CE8Data and not weapon.IsMeleeWeapon and not weapon.CE8Overheated and weapon:Clip1() > 0
        end
    },
    search = {
        fields = {active = "CE8Search", seen = "CE8SeenAim"},
        settings = function(self) return self:CE8BehaviorSettings().search end,
        squad = function(self) return self:CE8BehaviorSettings().squad end,
        -- Native task attitude/explicit stimuli select overrides. Source has no
        -- Halo mission task; use authored base properties unless explicitly set.
        default_mode = "normal",
        mode = function(self) return self.CE8Stimulus or "normal" end,
        can_react = function(self, now) return self:CE8CanReact(now) end,
        suppression_allowed = function(self) return not self.CE8Cover and not self.CE8Charge end,
        suppress_eligible = function(self, weapon)
            local values = weapon.CE8Data
            return values and not values.melee and values.gravity == 0 and values.damage.radius[2] == 0
                and not weapon.CE8Overheated and weapon:Clip1() > 0
        end,
        suppress_activity = function(self, weapon) return self:CE8CacheActivities(weapon).combat_idle end,
        investigate = function(self, phase, now)
            local sequence = self:CE8Action("investigate_" .. phase)
            if sequence then
                self:CE8PlayReaction("investigate", sequence, now)
                return (self.CE8ReactionEnd or now) - now
            end
        end,
        started = function(self, search, now) self:CE8QueueDialogue("searching", now, search) end,
        reacquired = function(self, enemy, now)
            if self.HasAlertSounds ~= false then self:CE8QueueDialogue("foundfoe", now, enemy) end
        end,
        finished = function(self, search, now, expired)
            self:AICancelDialogue(search)
            if expired then self:CE8QueueDialogue("invsgt_fail", now) end
        end
    },
    perception = {
        fields = {mode = "CE8PerceptionMode", heard = "CE8HeardSounds"},
        modes = function(self) return self:CE8BehaviorSettings().perception end,
        allowed = function(self) return not self.CE8Cover and not self.CE8Investigation end,
        before_investigate = function(self, source, position, now)
            self:CE8CancelIdlePose()
            self:CE8EndCorpseFire(now)
            self.CE8Search, self.CE8PostCombat = nil, nil
        end
    },
    flank = {
        fields = {next_check = "CE8NextFlank", enemy = "CE8FlankEnemy", finish = "CE8FlankUntil"},
        chance = function(self) return self:CE8BehaviorSettings().flank end
    },
    cover = {
        fields = {active = "CE8Cover", next_attempt = "CE8NextCover"},
        head_height = function(self)
            local weapon = self:GetActiveWeapon()
            local kind = IsValid(weapon) and weapon.CE8AnimationClass or "rifle"
            local stance = data.cover_height and data.cover_height[self.CE8Rank or "minor"]
            return stance and (stance[kind] or stance.rifle)
        end,
        hide_time = function(self)
            local time = self:CE8BehaviorSettings().cover.time
            return math.Rand(time[1], time[2])
        end,
        maximum_hold = function(self)
            local recovery = self:AIHasCapability("shield") and (self.CE8ShieldRechargeDelay + self.CE8ShieldRechargeTime) or 0
            return recovery + self:CE8BehaviorSettings().cover.time[2]
        end,
        recovered = function(self) return not self:AIHasCapability("shield") or self.CE8Shield >= self.CE8ShieldMax * self:CE8BehaviorSettings().cover.emerge end,
        validate = function(self, ...) return self:CE8CoverPoint(...) end,
        find = function(self, ...) return self:CE8FindCover(...) end,
        route = function(self, ...) return self:CE8CoverRoute(...) end,
        can_react = function(self, now) return self:CE8CanReact(now) end,
        play = function(self, phase, now)
            local sequence = self:CE8Action("cover_" .. phase)
            if sequence then return self:CE8PlayReaction(phase == "idle" and "cover_hold" or "cover_" .. phase, sequence, now) end
        end,
        started = function(self, cover, now) self:CE8QueueDialogue("move_cvr", now, cover) end,
        finished = function(self) self.CE8CoveredHit = self.CE8LastHit or false end
    },
    reactions = {
        family = function(self)
            local weapon = self:GetActiveWeapon()
            return IsValid(weapon) and weapon.CE8AnimationClass or nil
        end,
        actions = {families = data.actions, default_family = "rifle"},
        damage = {families = data.damage_reactions, default_family = "any", default_region = "gut",
            hitgroups = {[HITGROUP_HEAD] = "head", [HITGROUP_LEFTARM] = "l_arm", [HITGROUP_RIGHTARM] = "r_arm",
                [HITGROUP_LEFTLEG] = "l_leg", [HITGROUP_RIGHTLEG] = "r_leg"}},
        fields = {kind = "CE8Reaction", finish = "CE8ReactionEnd", schedule = "CE8ReactionSchedule", last = "CE8LastReaction"},
        network = "ce8_reaction",
        started = function(self, kind, sequence, now)
            self.CE8IdlePose, self.CE8NextIdlePose = nil, nil
            self:CE8EndCharge(now)
        end,
        stop_gesture = function(self)
            local weapon = self:CE8WeaponSet()
            if weapon.sequences.fire then
                local fire = self:GetSequenceActivity(self:LookupSequence(weapon.sequences.fire))
                if fire >= 0 then self:RemoveGesture(fire) end
            end
        end,
        played = function(self, kind, sequence, now)
            local cue = ({shield_break = "brsrk", grenade_dive = "dive", danger_dive = "dive",
                danger_evade = "dodge", gunfire_evade = "dodge"})[kind]
            if cue and not data.reaction_dialogue[sequence] then self:CE8PlayDialogue(cue, now) end
        end
    },
    evasion = {
        fields = {next_evade = "CE8NextEvade", aim_started = "CE8AimStarted", count = "CE8Evades", gunfire_count = "CE8GunfireEvades",
            next_gunfire = "CE8NextGunfireCheck", last_gunfire = "CE8LastGunfire"},
        network = "ce8_evades",
        choices = function(self) return self:CE8ReactionSet() end,
        validate_path = function(self, sequence) return self:CE8EvadePath(sequence) end,
        play = function(self, ...) return self:CE8PlayReaction(...) end,
        cooldown = function(self) return self.CE8AimEvadeCooldown end,
        minimum_distance = function(self) return self.CE8AimEvadeMinDistance end,
        range = function(self) return self.CE8AimEvadeRange end,
        fov = function(self) return self.CE8AimEvadeFOV end,
        aim_time = function(self) return self.CE8AimEvadeTime end,
        gunfire = function(self) return self:CE8BehaviorSettings().evade end
    },
    shield = {
        maximum = function(self) return self.CE8ShieldMax end,
        resistance = function() return CE8.Difficulty.Multiplier("shield_resistance") end,
        recharge_delay = function(self) return self.CE8ShieldRechargeDelay end,
        recharge_time = function(self) return self.CE8ShieldRechargeTime end,
        impact_interval = function(self) return self.CE8ShieldImpactInterval end,
        impact_sound_interval = function(self) return self.CE8ShieldImpactSoundInterval end,
        fields = {
            value = "CE8Shield", clock = "CE8ShieldClock", recharge_at = "CE8ShieldRechargeAt",
            breaks = "CE8ShieldBreaks", recharging = "CE8ShieldRecharging", recharge_sound = "CE8ShieldRechargeSound",
            impact_at = "CE8NextShieldImpact", impact_sound_at = "CE8NextShieldImpactSound"
        },
        network = {maximum = "ce8_shield_max", value = "ce8_shield", hit = "ce8_shield_hit", breaks = "ce8_shield_breaks"},
        effect = function(self, ...) return self:CE8ShieldEffect(...) end,
        sound = function(self, kind) return self:CE8PlayShieldSound(kind) end,
        depleted = function(self)
            self.CE8PendingShieldBreak = self:CE8BehaviorSettings().charge.shield_break or nil
        end,
        regenerated = function(self) self.CE8PendingShieldBreak = nil end,
        accept_damage = function(self, damage)
            return not (damage:IsDamageType(DMG_FALL) or damage:IsDamageType(DMG_DROWN)
                or damage:IsDamageType(DMG_DROWNRECOVER) or damage:IsDamageType(DMG_CRUSH))
        end,
        before_damage = function(self, damage, hitgroup, now, previous, amount)
            self.CE8LastHit = {time = now, amount = amount, shielded = previous > 0}
            local attacker = damage:GetAttacker()
            if IsValid(attacker) and attacker ~= self and (attacker:IsNPC() or attacker:IsPlayer() or attacker:IsNextBot())
                and self:CheckRelationship(attacker) == D_HT and (damage:IsDamageType(DMG_BULLET)
                or damage:IsDamageType(DMG_ENERGYBEAM) or damage:IsDamageType(DMG_BLAST)) then
                self:CE8QueueDialogue("undr_fire", now, attacker)
            end
        end,
        after_damage = function(self, damage, hitgroup, now, previous, amount, absorbed)
            local attacker = damage:GetAttacker()
            -- Fully absorbed hits exit VJ before its health-damage awareness code.
            local disabled = GetConVar("ai_disabled")
            if (disabled and disabled:GetBool()) or self.VJ_Controlled or self:GetState() == VJ_STATE_FREEZE then return end
            if IsValid(attacker) and attacker ~= self and (attacker:IsNPC() or attacker:IsPlayer() or attacker:IsNextBot()) then
                -- Potential enemies are D_VJ_INTEREST until VJ sees them. Its
                -- relationship API resolves that state and respects notarget,
                -- ignoreplayers, dead targets and allies before we acquire them.
                local disposition = self:CheckRelationship(attacker)
                if disposition == D_HT or disposition == D_NU then
                    self:UpdateEnemyMemory(attacker, attacker:GetPos())
                    self:MarkTookDamageFromEnemy(attacker)
                    local enemy = self:GetEnemy()
                    if not IsValid(enemy) or enemy == attacker or enemy:Health() <= 0 then
                        self:ForceSetEnemy(attacker, false)
                    end
                end
            end
            -- VJ exits early for fully absorbed hits; still use its flinch pipeline.
            if amount <= absorbed and self.CanFlinch and not self.CE8PendingShieldBreak then self:Flinch(damage, hitgroup) end
        end
    },
    dialogue = {
        -- Established campaign allegiance, independent of temporary VJ hostility.
        -- Other species may share this key; player-allied profiles use another.
        domain = "ce8_enemy",
        bank = function(self) return sounds.dialogue[self.CE8Voice or "newelite1"] end,
        rules = data.dialogue_rules,
        responses = data.dialogue_responses,
        friend_responses = data.dialogue_friends,
        relevance = function(self)
            return self:AIDialogueRelevance(player.GetAll(), data.dialogue_player_distance)
        end,
        fallbacks = data.dialogue_fallbacks,
        observed = observedDialogue,
        listeners = function(self)
            return self:Allies_Check(self.CallForHelpDistance or 2000)
        end,
        can_respond = function(self, spoken, cue)
            local speaker, target = spoken.speaker, spoken.context
            if not self.IsCE8Elite or not speaker.IsCE8Elite
                or self:Disposition(speaker) ~= D_LI or speaker:Disposition(self) ~= D_LI
                or not self:Visible(speaker)
                or self:GetPos():DistToSqr(speaker:GetPos()) > (speaker.CallForHelpDistance or 2000)^2 then return false end
            if cue == "prs" then
                -- The native kill-confirmation reply comes from a friend, not
                -- necessarily an ally sharing the dead target as its enemy.
                return self.HasKilledEnemySounds ~= false and speaker.HasKilledEnemySounds ~= false
                    and type(target) == "table" and target.victim ~= nil
                    and (not IsValid(target.victim) or target.victim.Dead or target.victim:Health() <= 0)
                    and not self.CE8PendingShieldBreak and not self.CE8BerserkUntil
            end
            if (cue ~= "foundfoe_re" and cue ~= "seefoe_ack")
                or self.HasAlertSounds == false or speaker.HasAlertSounds == false
                or not IsValid(target) or target:Health() <= 0 or self:Disposition(target) ~= D_HT
                or self:GetEnemy() ~= target or speaker:GetEnemy() ~= target
                or not speaker:Visible(target) then return false end
            if cue == "seefoe_ack" then return self:Visible(target) end
            -- The native found-unit reply caps combat status at "certain", below clear LOS.
            -- Source mapping: a searching ally, not one already exchanging fire.
            return not self:Visible(target) and not self.AttackType and not self.CE8Cover
                and not self.CE8PendingShieldBreak and not self.CE8BerserkUntil
        end,
        fields = {pending = "CE8PendingDialogue", queue = "CE8DialogueQueue", dispatch = "CE8DialogueDispatch",
            repeats = "CE8DialogueRepeat", speech_until = "CE8SpeechUntil",
            last = "CE8LastDialogue", counts = "CE8DialogueCounts", takes = "CE8DialogueTakes", spoken = "CE8SpokenDialogue"},
        play = function(self, cue, now, context) return self:CE8PlayDialogue(cue, now, context) end,
        played = function(self, cue, now, finish)
            if cue == "panic_plsmgrnd" then
                self.NextDangerSightSoundT = math.max(self.NextDangerSightSoundT or 0, finish)
            end
        end,
        can_interrupt = function(self, cue, context, speech)
            if cue ~= "panic_plsmgrnd" or not speech then return false end
            -- Native queued screams may replace priority <= 11. Involuntary
            -- dive/dodge cries (12) and other screams (13) keep their turn.
            if speech == self.CE8DangerSpeech then return true end -- warn_incmn, 9
            local spoken = self.CE8SpokenDialogue
            local rule = spoken and data.dialogue_rules[spoken.cue]
            return spoken and spoken.handle == speech and rule and rule.priority <= 11 or false
        end,
        valid_context = function(self, cue, context, now)
            local enemy = self:GetEnemy()
            local cancelled = ((cue == "chr_kllfoe" or cue == "chr" or cue == "prs") and (self.HasKilledEnemySounds == false
                    or not context or context.victim == nil
                    or (IsValid(context.victim) and not context.victim.Dead and context.victim:Health() > 0)
                    or self.CE8PendingShieldBreak or self.CE8BerserkUntil))
                or (cue == "shotfoebdy" and (self.HasKilledEnemySounds == false
                    or not context or not context.shot_notified
                    or (self.CE8PostCombat and self.CE8PostCombat ~= context)
                    or self.IsGuard or self.IsFollowing or self.CE8PendingShieldBreak or self.CE8BerserkUntil
                    or not IsValid(context.corpse)
                    or (IsValid(context.victim) and context.victim:IsPlayer() and context.victim:Alive())
                    or (IsValid(enemy) and enemy ~= self.CE8CorpseShot and enemy:Health() > 0)))
                or (cue == "reloading" and (self.HasWeaponReloadSounds == false
                    or not context or not IsValid(context.weapon) or self:GetActiveWeapon() ~= context.weapon
                    or self:GetWeaponState() ~= VJ.WEP_STATE_RELOADING or self.WeaponReloadSeed ~= context.seed
                    or not IsValid(enemy) or enemy:Health() <= 0))
                or (cue == "move_cvr" and (self.CE8Cover ~= context or context.failed or context.phase ~= "seek"))
                or (cue == "searching" and self.CE8Search ~= context)
                or (cue == "invsgt_fail" and (self.CE8Search or (IsValid(enemy) and self:Visible(enemy))))
                or (cue == "charge" and (self.CE8Charge ~= context or self.CE8BerserkUntil))
                or (cue == "overheated" and (not IsValid(context) or self:GetActiveWeapon() ~= context or not context.CE8Overheated))
                or (cue == "undr_fire" and (not IsValid(context) or context:Health() <= 0 or self:Disposition(context) ~= D_HT))
                or ((cue == "morefoe" or cue == "foundfoe") and (self.HasAlertSounds == false
                    or not IsValid(context) or context:Health() <= 0 or self:Disposition(context) ~= D_HT
                    or not self:Visible(context) or (cue == "foundfoe" and enemy ~= context)))
                or (cue == "lmnt_deadally" and (self.HasAllyDeathSounds == false
                    or (IsValid(context) and not context.Dead and context:Health() > 0)))
                or (cue == "panic_plsmgrnd" and (self.HasDangerSightSounds == false
                    or not IsValid(context) or context:GetParent() ~= self or context.Dead
                    or now >= (context.CE8DetonateAt or math.huge)))
            return not cancelled
        end
    },
    footsteps = {
        bank = sounds.footsteps,
        attachments = {left = "left_foot", right = "right_foot"},
        materials = footMaterials, properties = footProperties,
        default_surface = "stone", water_surface = "water",
        fields = {attachments = "CE8FootAttachments", last_choices = "CE8FootstepLast", last = "CE8LastFootstep"},
        action = function(self)
            local sequence = "_" .. self:GetSequenceName(self:GetSequence()) .. "_"
            if string.find(sequence, "_walk_", 1, true) then return "walk" end
            if string.find(sequence, "_move_", 1, true) or string.find(sequence, "_run_", 1, true) then return "run" end
            return "shuffle"
        end
    }
}
