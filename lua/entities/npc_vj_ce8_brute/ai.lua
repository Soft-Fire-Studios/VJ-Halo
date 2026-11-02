-- Brute-specific choices; VJ owns attack scheduling, navigation and possession.
local Host = {}
function Host.Server(ENT, profile)
    include("campaign_evolved/human.lua").Server(ENT, profile)
    local data = ENT:CE8Data()
    local initialize, event, changed, damaged = ENT.Init, ENT.OnAnimEvent, ENT.OnWeaponChange, ENT.OnDamaged
    local flinch, configure = ENT.OnFlinch, ENT.CE8ConfigureAI
    ENT.HasMeleeAttack = true
    ENT.HasLeapAttack = false -- Authored phases use the existing shared CUSTOM attack.
    ENT.TimeUntilMeleeAttackDamage = false
    ENT.MeleeAttackDistance, ENT.MeleeAttackDamageDistance = data.melee.range, data.melee.hit_range
    ENT.MeleeAttackAngleRadius, ENT.MeleeAttackDamageAngleRadius = data.melee.angle, data.melee.hit_angle
    ENT.MeleeAttackDamage, ENT.MeleeAttackDamageType = data.melee.damage, DMG_CLUB
    ENT.MeleeAttackAnimationFaceEnemy = true
    ENT.HasMeleeAttackSounds, ENT.HasExtraMeleeAttackSounds, ENT.HasMeleeAttackMissSounds = false, false, false
    ENT.Weapon_RetreatDistance = 0
    function ENT:CE8ConfigureAI()
        configure(self)
        if self:GetNW2Bool("ce8_berserk", false) then self.HasGrenadeAttack = false end
    end

    function ENT:Init()
        self.CE8WeaponProfile = self:CE8RankSettings().native
        initialize(self)
        local rank = self:CE8RankSettings()
        self.NextMeleeAttackTime = rank.melee_delay
        self.FlinchChance, self.FlinchCooldown = 1, rank.flinch.cooldown
        self.SoundTbl_BeforeMeleeAttack = profile.sounds.dialogue[self.CE8Voice].melee_attack or false
        self:SetNW2Bool("ce8_berserk", false)
    end
    function ENT:OnWeaponChange(weapon, ...)
        changed(self, weapon, ...)
        if self:GetNW2Bool("ce8_berserk", false) then
            self:AIApplyGrip(0)
            self:SetNW2Int("ce8_grip", 0)
        end
    end
    function ENT:OnDamaged(damage, hitgroup, status)
        if status == "PreDamage" then
            local blocked = self:AIShieldDamage(damage, hitgroup, CurTime())
            self:AIRecordThreatDamage(damage, CurTime(), blocked)
        end
        return damaged(self, damage, hitgroup, status)
    end
    function ENT:OnFlinch(damage, hitgroup, status)
        if status == "Init" then
            local settings = self:CE8RankSettings().flinch
            local threshold = (self.CE8Shield or 0) > 0 and settings.threshold or settings.unshielded
            if self.CE8PendingBerserk or self:GetNW2Bool("ce8_berserk", false)
                or (self.CE8ShieldFlinchAmount or damage:GetDamage()) < threshold then return true end
        end
        return flinch(self, damage, hitgroup, status)
    end
    function ENT:CE8TryBerserk(now)
        if not self.CE8PendingBerserk or now < (self.CE8BerserkRetry or 0) or not self:AIReactionReady(now) then return false end
        self.CE8BerserkRetry = now + 0.5
        local sequence = self:AISelectAction("go_berserk")
        if not sequence or not self:AIValidateMotion(sequence, 0) then return false end
        self:AISuspendActions(now)
        if not self:AIPlayReaction("berserk", sequence, now) then return false end
        self.CE8PendingBerserk = nil
        self.CE8NextBerserk = now + self:CE8RankSettings().berserk.cooldown
        self:SetNW2Bool("ce8_berserk", true)
        self.CE8Shield = 0
        self:SetNW2Float("ce8_shield", 0)
        self:AIStopShieldRecharge()
        self.HasGrenadeAttack, self.Weapon_Strafe, self.CombatDamageResponse = false, false, false
        local weapon = self:GetActiveWeapon()
        if IsValid(weapon) then self:DropWeapon(weapon, nil, self:GetForward()) end
        self:AIApplyGrip(0)
        self:SetNW2Int("ce8_grip", 0)
        self:SetAnimationTranslations("normal")
        self:AIPlayDialogue("brsrk", now)
        return true
    end
    function ENT:CE8WeaponShotReady(now)
        return not self:GetNW2Bool("ce8_berserk", false)
            and not self.Dead and now >= (self.AIReactionEnd or 0)
            and not self:AIChargeBlocksWeapon(self:GetActiveWeapon(), now)
    end
    function ENT:OnWeaponCanFire()
        if not self:CE8WeaponShotReady(CurTime()) then return false end
    end
    function ENT:OnThinkAttack(isAttacking, enemy) self:AITryLeap(CurTime(), enemy) end
    function ENT:OnMeleeAttack(status, enemy)
        if status == "PreInit" and self:AIIsReloading() then return true end
        if status == "PreInit" then
            local _, key = self:AIAnimationSet()
            local choices = data.melee_by_set[key] or data.melee_by_set.unarmed
            local sequence = choices[math.random(#choices)]
            if not self:AIValidateMotion(sequence, 0, enemy) then return true end
            self.CE8ContactSequence = sequence
            self.AnimTbl_MeleeAttack = "vjseq_" .. sequence
            local rank = self:CE8RankSettings()
            self.NextMeleeAttackTime = key == "berserk" and rank.berserk.melee_delay
                or key == "unarmed" and rank.unarmed_delay or rank.melee_delay
        elseif status == "Init" then
            self:AIEndCharge(CurTime())
            self.CE8MeleeVictims = {}
            self.CE8MeleeTurnTarget = nil
        elseif status == "PostInit" and not self.VJ_Controlled and not self.MeleeAttack_IsPropAttack and IsValid(enemy) then
            if self:SetTurnTarget(enemy, math.min(data.melee.tracking_time, self.AttackAnimDuration), true, true) then
                self.CE8MeleeTurnTarget = enemy
            end
        end
    end
    function ENT:OnMeleeAttackExecute(status, victim)
        if status ~= "PreDamage" then return end
        if not self.CE8MeleeVictims or self.CE8MeleeVictims[victim] then return true end
        self.CE8MeleeVictims[victim] = true
    end
    function ENT:MeleeAttackTraceDirection() return self:GetForward() end
    function ENT:OnAnimEvent(id, eventTime, cycle, eventType, options)
        event(self, id, eventTime, cycle, eventType, options)
        local primary = id == 4001 and options == "primary keyframe"
        if not self.Dead and primary and self:AILeapActive() then
            self:AILeapContact(cycle, eventTime)
            return
        end
        if self.Dead or self.AttackType ~= VJ.ATTACK_TYPE_MELEE
            or self:GetSequenceName(self:GetSequence()) ~= self.CE8ContactSequence then return end
        local contact = primary
        if id == 4002 then
            for _, effect in ipairs(data.melee_events[self.CE8ContactSequence].effects) do
                if effect.options == options then contact = true break end
            end
        end
        if not contact then return end
        if self.CE8MeleeTurnTarget and self.TurnData and self.TurnData.Target == self.CE8MeleeTurnTarget
            and self.TurnData.StopOnFace then self:ResetTurnTarget() self:SetIdealYaw(self:GetAngles().y) end
        self.CE8MeleeTurnTarget = nil
        self:ExecuteMeleeAttack()
    end


end
return Host
