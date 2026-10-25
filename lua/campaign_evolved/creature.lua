-- Integrated cannon/melee host. Shared actor services own resources and motion;
-- VJ's Creature base owns attack timers, navigation and possession controls.
local Actor = include("campaign_evolved/actor.lua")
local difficulty = include("campaign_evolved/difficulty.lua")
local ballistics = include("campaign_evolved/ballistics.lua")
local effects = include("campaign_evolved/weapon_fx.lua")
local Host = {}

function Host.Server(ENT, profile)
    Actor.Server(ENT, profile)
    local data = ENT:CE8Data()
    local cannon, melee = data.cannon, data.melee
    local sounds = include("campaign_evolved/sounds/" .. data.owner .. "_cannon.lua")
    local initialize, event, think = ENT.Init, ENT.OnAnimEvent, ENT.OnThink
    ENT.BloodColor = VJ.BLOOD_COLOR_ORANGE
    ENT.HasRangeAttack = true
    ENT.RangeAttackProjectiles = "obj_ce8_projectile"
    -- Recoil is additive and starts when the shot leaves, not at charge start.
    ENT.AnimTbl_RangeAttack = ACT_RANGE_ATTACK1
    ENT.TimeUntilRangeAttackProjectileRelease = cannon.charge
    ENT.NextAnyAttackTime_Range = cannon.recovery
    ENT.NextRangeAttackTime = cannon.interval
    ENT.RangeAttackMinDistance, ENT.RangeAttackMaxDistance = cannon.min_range, cannon.max_range
    ENT.RangeAttackAngleRadius = 60
    ENT.RangeAttackAnimationFaceEnemy = true
    ENT.HasMeleeAttack = true
    ENT.AnimTbl_MeleeAttack = "vjseq_" .. melee.attacks[1].sequence
    ENT.TimeUntilMeleeAttackDamage = false
    ENT.MeleeAttackDistance, ENT.MeleeAttackDamageDistance = melee.range, melee.hit_range
    ENT.MeleeAttackDamage = melee.attacks[1].damage
    ENT.MeleeAttackDamageType = DMG_CLUB
    ENT.MeleeAttackAngleRadius, ENT.MeleeAttackDamageAngleRadius = 60, 90
    ENT.NextMeleeAttackTime = melee.cooldown
    ENT.MeleeAttackAnimationFaceEnemy = false -- Preserve authored heading/root motion.
    ENT.HasMeleeAttackKnockBack = true
    ENT.HasMeleeAttackSounds, ENT.HasExtraMeleeAttackSounds, ENT.HasMeleeAttackMissSounds = false, false, false
    ENT.SoundTbl_MeleeAttack, ENT.SoundTbl_MeleeAttackExtra, ENT.SoundTbl_MeleeAttackMiss = false, false, false
    ENT.SoundTbl_BeforeRangeAttack, ENT.SoundTbl_RangeAttack = false, false
    ENT.CanFlinch = false -- Heavy damage reactions need their own authored motion selection.
    ENT.HasDeathAnimation = false

    function ENT:Init()
        initialize(self)
        self.SoundTbl_BeforeMeleeAttack = profile.sounds.dialogue[data.owner].melee
        self.SoundTbl_AllyDeath = profile.sounds.dialogue[data.owner].lmnt
        self.CE8ChargeStart, self.CE8ChargeEnd = nil, nil
        self:SetPoseParameter("gun_flaps", 0)
        effects.Load(cannon)
    end

    function ENT:CE8CannonPosition()
        local index = self:LookupAttachment(cannon.muzzle)
        local marker = index > 0 and self:GetAttachment(index)
        return marker and marker.Pos or self:GetPos() + Vector(0, 0, data.hull.gun)
    end

    function ENT:OnRangeAttack(status, enemy)
        if status == "PreInit" then
            if not IsValid(enemy) or not self:Visible(enemy) then return true end
        elseif status == "Init" then
            local now = CurTime()
            local started = self.EnemyData and self.EnemyData.TimeAcquired or now
            self.CE8ShotProfile, self.CE8ShotState = difficulty.Select(cannon, self, self, now, started)
            local separation = self.CE8ShotProfile.separation
            -- One charged bolt per attack; native accuracy controls the pause
            -- and spread. Do not copy the handheld Fuel Rod's automatic burst.
            self.NextRangeAttackTime = math.max(cannon.interval - cannon.charge,
                math.Rand(separation[1], separation[2]), cannon.recovery)
            self.CE8ChargeStart, self.CE8ChargeEnd = now, now + cannon.charge / math.max(self.AnimPlaybackRate or 1, 0.01)
            self:StopMoving()
            self:SetTurnTarget("Enemy", cannon.charge, false)
            effects.Sound(sounds.charge, self:CE8CannonPosition(), 80)
        end
    end

    function ENT:RangeAttackProjPos() return self:CE8CannonPosition() end

    function ENT:OnRangeAttackExecute(status, enemy, projectile)
        if status == "Init" then
            self.CE8ChargeStart, self.CE8ChargeEnd = nil, nil
            -- A lost target cancels this shot. VJ still owns recovery/reset.
            if self.Dead or not IsValid(enemy) or not self:Visible(enemy) then return true end
        elseif status == "PreSpawn" then
            local level = difficulty.Level(self)
            local ai = not self.VJ_Controlled
            local scale = ballistics.Scale(cannon, level, ai)
            local origin = projectile:GetPos()
            local target = self:GetAimPosition(enemy, origin, 0)
            local velocity = ai and VJ.GetMoveVelocity(enemy) * cannon.leading or Vector()
            local direction = ballistics.Aim(cannon, origin, target, velocity,
                physenv.GetGravity(), engine.TickInterval(), scale)
            if direction:LengthSqr() < 0.001 then direction = self:GetForward() end
            if ai and self.CE8ShotProfile then
                local error = math.tan(self.CE8ShotProfile.projectile_error)
                    * (self.CE8ShotState and self.CE8ShotState.error_scale or 1)
                direction = (direction + VectorRand() * error):GetNormalized()
            end
            projectile.CE8Data, projectile.CE8Sounds = cannon, sounds
            projectile.CE8WeaponName, projectile.CE8Weapon = data.owner .. "_cannon", self
            projectile.CE8Damage = math.Rand(cannon.damage.amount[1], cannon.damage.amount[2])
            projectile.CE8Flight = ballistics.State(cannon, scale, level, ai, nil, direction)
            projectile.CE8LaunchVelocity = direction * cannon.speed * scale
            projectile:SetAngles(direction:Angle())
        elseif status == "PostSpawn" then
            effects.Muzzle(self, cannon)
            effects.Sound(sounds.fire, projectile:GetPos(), 90)
            local sequence = self:LookupSequence(data.weapon_sets.cannon.sequences.fire)
            if sequence >= 0 then
                if self.CE8Recoil and self:IsValidLayer(self.CE8Recoil) then self:RemoveLayer(self.CE8Recoil) end
                local layer = self:AddGestureSequence(sequence, true)
                if layer >= 0 then
                    self:SetLayerPriority(layer, 1)
                    self:SetLayerPlaybackRate(layer, self.AnimPlaybackRate or 1)
                    self.CE8Recoil = layer
                end
            end
        end
    end

    function ENT:RangeAttackProjVel(projectile)
        return projectile.CE8LaunchVelocity or self:GetForward() * cannon.speed
    end

    function ENT:OnThink()
        think(self)
        local start, finish = self.CE8ChargeStart, self.CE8ChargeEnd
        if start and (self.Dead or self.AttackType ~= VJ.ATTACK_TYPE_RANGE or CurTime() > finish + 0.2) then
            self.CE8ChargeStart, self.CE8ChargeEnd = nil, nil
            start = nil
        end
        local amount = start and math.Clamp((CurTime() - start) / math.max(0.01, finish - start), 0, 1) or 0
        if self.CE8GunFlaps ~= amount then
            self.CE8GunFlaps = amount
            self:SetPoseParameter("gun_flaps", amount)
        end
    end

    function ENT:OnMeleeAttack(status, enemy)
        if status == "PreInit" then
            local attacks = melee.attacks
            local close = not IsValid(enemy) or self:GetPos():DistToSqr(enemy:GetPos()) < 200 * 200
            local attack = attacks[close and 1 or math.random(#attacks)]
            -- Validate the world route. Ignore only the intended victim here;
            -- VJ AutoMovement still collides with it while applying walkframes.
            if not self:AIValidateMotion(attack.sequence, 0, enemy) then return true end
            self.CE8MeleeAttack = attack
            self.AnimTbl_MeleeAttack = "vjseq_" .. attack.sequence
        elseif status == "Init" then
            self.CE8MeleeVictims = {}
            self.CE8ChargeStart, self.CE8ChargeEnd = nil, nil
            self:ResetTurnTarget()
            self:SetIdealYaw(self:GetAngles().y)
        end
    end

    function ENT:OnMeleeAttackExecute(status, victim)
        if status ~= "PreDamage" then return end
        local victims = self.CE8MeleeVictims
        if not victims or victims[victim] then return true end
        victims[victim] = true
    end

    function ENT:MeleeAttackTraceDirection() return self:GetForward() end

    function ENT:OnAnimEvent(id, ...)
        event(self, id, ...)
        if id ~= 4002 or self.AttackType ~= VJ.ATTACK_TYPE_MELEE or self.Dead then return end
        local attack = self.CE8MeleeAttack
        if not attack or self:GetSequenceName(self:GetSequence()) ~= attack.sequence then return end
        local options = select(4, ...)
        local name = type(options) == "string" and options:match("([^/]+)$")
        local amount = name and attack.impacts[name]
        if not amount then return end
        -- Repeated authored contact events extend the hit window without
        -- multiplying full damage on a victim already hit by this swing.
        self.MeleeAttackDamage = amount
        self:ExecuteMeleeAttack()
    end

    function ENT:OnTraceAttack(damage, direction, trace)
        if self.Dead or damage:GetDamage() <= 0 or damage:IsDamageType(DMG_BLAST) then return end
        local region = self:CE8RankSettings().hit_regions[(trace.HitBox or -2) + 1]
        local multiplier = region and data.armor[region]
        if multiplier == nil then return end
        if multiplier == 0 and not self.GodMode then
            local attacker = damage:GetAttacker()
            if IsValid(attacker) and attacker ~= self and self:CheckRelationship(attacker) == D_HT
                and not self.VJ_Controlled then
                -- Physical shield hits must still alert the Hunter even when
                -- VJ's normal damage callback receives a fully blocked hit.
                self:UpdateEnemyMemory(attacker, attacker:GetPos())
                self:MarkTookDamageFromEnemy(attacker)
                if not IsValid(self:GetEnemy()) then self:ForceSetEnemy(attacker, false) end
            end
        end
        damage:ScaleDamage(multiplier)
    end
end

return Host
