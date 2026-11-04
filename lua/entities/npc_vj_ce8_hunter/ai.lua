-- Hunter-specific melee and physical armor on the shared Human host.
local Host = {}
function Host.Server(ENT, profile)
    include("campaign_evolved/human.lua").Server(ENT, profile)
    local data = ENT:CE8Data()
    local cannon, melee = data.cannon, data.melee
    local initialize, event, thinkAttack = ENT.Init, ENT.OnAnimEvent, ENT.OnThinkAttack
    local knockback = ENT.MeleeAttackKnockbackVelocity
    ENT.BloodColor = VJ.BLOOD_COLOR_ORANGE
    ENT.Weapon_MinDistance, ENT.Weapon_MaxDistance = cannon.min_range, cannon.max_range
    ENT.Weapon_CanReload = false -- Integrated cannon has no magazine.
    ENT.DropWeaponOnDeath = false
    ENT.HasMeleeAttack = true
    ENT.AnimTbl_MeleeAttack = "vjseq_" .. melee.attacks[1].sequence
    ENT.TimeUntilMeleeAttackDamage = false
    ENT.MeleeAttackDistance, ENT.MeleeAttackDamageDistance = melee.range, melee.hit_range
    ENT.MeleeAttackDamage = melee.attacks[1].damage
    ENT.MeleeAttackDamageType = DMG_CLUB
    ENT.MeleeAttackAngleRadius, ENT.MeleeAttackDamageAngleRadius = melee.angle, melee.hit_angle
    ENT.NextMeleeAttackTime = melee.cooldown
    ENT.MeleeAttackAnimationFaceEnemy = false
    ENT.HasMeleeAttackKnockBack = true
    ENT.HasMeleeAttackSounds, ENT.HasExtraMeleeAttackSounds, ENT.HasMeleeAttackMissSounds = false, false, false
    ENT.SoundTbl_MeleeAttack, ENT.SoundTbl_MeleeAttackExtra, ENT.SoundTbl_MeleeAttackMiss = false, false, false

    function ENT:Init()
        initialize(self)
        self.SoundTbl_BeforeMeleeAttack = profile.sounds.dialogue[data.owner].melee
        self.SoundTbl_AllyDeath = profile.sounds.dialogue[data.owner].lmnt
        self:SetPoseParameter("gun_flaps", 0)
    end
    function ENT:CE8CannonPosition()
        local index = self:LookupAttachment(cannon.muzzle)
        local marker = index > 0 and self:GetAttachment(index)
        return marker and marker.Pos or self:GetPos() + Vector(0, 0, data.hull.gun)
    end
    local sectors = {"back", "left", "right", "tackle"}
    local function admission(self, enemy)
        -- VJ uses this same range to stop chasing. Expose a side/rear/tackle
        -- range only when an authored attack can reach that bearing.
        self.MeleeAttackDistance, self.MeleeAttackAngleRadius = melee.range, melee.angle
        if self.VJ_Controlled or not IsValid(enemy) then return melee.attacks[1] end
        local delta = enemy:GetPos() - self:GetPos()
        delta.z = 0
        local distance = VJ.GetNearestDistance(self, enemy, true)
        local bearing = math.AngleDifference(delta:Angle().y, self:GetAngles().y)
        if not self.MeleeAttack_IsPropAttack then
            for _, key in ipairs(sectors) do
                local candidate = melee.directional[key]
                if distance > candidate.minimum and distance <= candidate.range
                    and math.abs(math.AngleDifference(bearing, candidate.heading)) <= melee.angle then
                    self.MeleeAttackDistance = candidate.range
                    self.MeleeAttackAngleRadius = key == "tackle" and melee.angle or 180
                    return candidate
                end
            end
        end
        if distance <= melee.range and math.abs(bearing) <= melee.angle then
            return melee.attacks[1]
        end
        self.MeleeAttackDistance = 0
    end
    function ENT:OnThinkAttack(isAttacking, enemy)
        if thinkAttack then thinkAttack(self, isAttacking, enemy) end
        if not isAttacking then admission(self, enemy) end
    end
    function ENT:OnMeleeAttack(status, enemy)
        if status == "PreInit" then
            self.CE8MeleeAttack, self.CE8MeleeDirection, self.CE8MeleeSeed, self.CE8MeleeHeading = nil, nil, nil, nil
            self.MeleeAttackDamageDistance, self.MeleeAttackDamageAngleRadius = melee.hit_range, melee.hit_angle
            if self:AIIsReloading() then return true end
            local attack = admission(self, enemy)
            if not attack then return true end
            if not self:AIPrepareAttackTurn(attack.sequence, enemy) then return true end
            if not self:AIValidateMotion(attack.sequence, 0, enemy) then
                -- Only the two forward variants are interchangeable. Never
                -- turn a blocked side swing into an attack facing elsewhere.
                if attack == melee.attacks[1] and self:AIValidateMotion(melee.attacks[2].sequence, 0, enemy) then
                    attack = melee.attacks[2]
                else
                    self.MeleeAttackDistance = 0
                    return true
                end
            end
            self.CE8MeleeAttack = attack
            self.AnimTbl_MeleeAttack = "vjseq_" .. attack.sequence
        elseif status == "Init" then
            self.CE8MeleeVictims = {}
            self.CE8MeleeHeading, self.CE8MeleeSeed = self:GetAngles().y, self.AttackSeed
            local weapon = self:GetActiveWeapon()
            if IsValid(weapon) and weapon.CE8CancelCharge then weapon:CE8CancelCharge() end
            self:ResetTurnTarget()
            self:SetIdealYaw(self.CE8MeleeHeading)
        end
    end

    function ENT:OnMeleeAttackExecute(status, victim)
        if status ~= "PreDamage" then return end
        if self.AIObstacleContext then return self:AIObstacleMelee(status, victim) end
        local victims = self.CE8MeleeVictims
        if not victims or victims[victim] then return true end
        victims[victim] = true
    end

    function ENT:MeleeAttackTraceDirection()
        if not self.AIObstacleContext and self.AttackType == VJ.ATTACK_TYPE_MELEE
            and self.AttackSeed == self.CE8MeleeSeed and self.CE8MeleeDirection then
            return self.CE8MeleeDirection
        end
        return self:GetForward()
    end
    function ENT:MeleeAttackTraceOrigin() return self:AIObstacleTraceOrigin() end
    function ENT:MeleeAttackKnockbackVelocity(victim)
        local velocity = knockback and knockback(self, victim) or self:AIBaseCall("MeleeAttackKnockbackVelocity", victim)
        if not self.AIObstacleContext and self.AttackType == VJ.ATTACK_TYPE_MELEE
            and self.AttackSeed == self.CE8MeleeSeed and self.CE8MeleeDirection then
            local forward = self:GetForward()
            return velocity + (self.CE8MeleeDirection - forward) * velocity:Dot(forward)
        end
        return velocity
    end

    function ENT:OnAnimEvent(id, eventTime, cycle, eventType, options)
        event(self, id, eventTime, cycle, eventType, options)
        local name = type(options) == "string" and options:match("([^/]+)$")
        if id == 4002 and self.AIObstacle and not self.Dead then
            if name == "melee_swipe_forward_var2" then
                local previous, reach, angle = self.MeleeAttackDamage, self.MeleeAttackDamageDistance, self.MeleeAttackDamageAngleRadius
                self.MeleeAttackDamage = melee.attacks[2].damage
                self.MeleeAttackDamageDistance, self.MeleeAttackDamageAngleRadius = melee.hit_range, melee.hit_angle
                self:AIObstacleHit()
                self.MeleeAttackDamage, self.MeleeAttackDamageDistance, self.MeleeAttackDamageAngleRadius = previous, reach, angle
            end
            return
        end
        if id ~= 4002 or self.AttackType ~= VJ.ATTACK_TYPE_MELEE or self.Dead
            or self.CE8MeleeHeading == nil or self.AttackSeed ~= self.CE8MeleeSeed or type(cycle) ~= "number" then return end
        local attack = self.CE8MeleeAttack
        if not attack or self:GetSequenceName(self:GetSequence()) ~= attack.sequence then return end
        local frame = math.floor(cycle * (attack.frames - 1) + 0.5)
        for _, contact in ipairs(attack.contacts) do
            if frame == contact.frame and name == contact.effect then
                -- Marker orientation includes the authored root turn. Add it
                -- to the starting heading only; the current actor has turned.
                self.CE8MeleeDirection = Angle(0, self.CE8MeleeHeading + contact.heading, 0):Forward()
                self.MeleeAttackDamage = contact.damage
                self.MeleeAttackDamageDistance, self.MeleeAttackDamageAngleRadius = contact.range, contact.angle
                -- Repeated authored contacts extend the window; a victim is
                -- damaged only once per swing by the native VJ damage path.
                self:ExecuteMeleeAttack()
                return
            end
        end
    end

    function ENT:OnTraceAttack(damage, direction, trace)
        if self.Dead or damage:GetDamage() <= 0 and not trace.ColliderScaled then return end
        local region = trace.ColliderRegion
        local multiplier = trace.ColliderDamageScale or (region and data.armor[region])
        if multiplier == nil then multiplier = 0 end
        local part = region and data.anatomy.regions[region]
        if (multiplier == 0 or part and part.health_scale == 0) and not self.GodMode then
            local attacker = damage:GetAttacker()
            if IsValid(attacker) and attacker ~= self and self:CheckRelationship(attacker) == D_HT
                and not self.VJ_Controlled then
                -- Armor and breakable-shell hits still alert the Hunter when
                -- they do not reach body health through VJ's damage callback.
                self:UpdateEnemyMemory(attacker, attacker:GetPos())
                self:MarkTookDamageFromEnemy(attacker)
                if not IsValid(self:GetEnemy()) then self:ForceSetEnemy(attacker, false) end
                -- The collider has already removed health damage. A confirmed
                -- armor impact still counts as one observed hit for pressure.
                if region then self:AIRecordThreatDamage(damage, CurTime(), 1) end
            end
        end
        if not trace.ColliderScaled then damage:ScaleDamage(multiplier) end
    end

    local damaged = ENT.OnDamaged
    function ENT:OnDamaged(damage, hitgroup, status)
        if status == "Init" and not self.Dead and not self.GodMode and damage:GetDamage() > 0
            and not CE8.Collision.IsForwarded(self, damage) then
            -- Radius and untraced damage cannot bypass armor through the NPC hull.
            local collision = CE8.Collision
            local hit = collision.DamageContact(self, damage)
            self:OnTraceAttack(damage, damage:GetDamageForce():GetNormalized(),
                hit and collision.TraceRecord(self, hit, damage:GetDamageForce():GetNormalized()) or {Entity=self})
            self.ColliderLastHit = {region=hit and hit.region or "blocked",part=hit and hit.part,
                surface=hit and hit.surface,damage=damage:GetDamage(),time=CurTime()}
        end
        if damaged then return damaged(self, damage, hitgroup, status) end
    end
    include("vj_ai/anatomy.lua").Attach(ENT, {
        regions = data.anatomy.regions,
        trace_region = function(self, trace) return trace.ColliderRegion end,
        traced_blasts = true
    })
end
return Host
