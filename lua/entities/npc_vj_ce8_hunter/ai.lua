-- Hunter-specific melee and physical armor on the shared Human host.
local Host = {}
function Host.Server(ENT, profile)
    include("campaign_evolved/human.lua").Server(ENT, profile)
    local data = ENT:CE8Data()
    local cannon, melee = data.cannon, data.melee
    local initialize, event = ENT.Init, ENT.OnAnimEvent
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
    ENT.CanFlinch = false
    ENT.HasDeathAnimation = false

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
            local weapon = self:GetActiveWeapon()
            if IsValid(weapon) and weapon.CE8CancelCharge then weapon:CE8CancelCharge() end
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
