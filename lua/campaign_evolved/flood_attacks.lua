-- Unarmed Combat Flood use VJ's ordinary melee scheduler and contact window.
-- Root walkframes move the actor; marker directions are relative to its start.
local Attacks = {}

function Attacks.Attach(ENT, data)
    local settings = data.combat and data.combat.attacks
    if not settings then return end
    local melee, event = ENT.OnMeleeAttack, ENT.OnAnimEvent
    local direction, knockback = ENT.MeleeAttackTraceDirection, ENT.MeleeAttackKnockbackVelocity
    local translations, initialize, attack = ENT.SetAnimationTranslations, ENT.Init, ENT.OnThinkAttack
    local tackle, rear = settings.tackle, settings.rear

    local function admission(actor, enemy, weapon)
        -- VJ also uses these fields to STOP pursuing. Only expose the range
        -- of a swing that can actually start at the target's current bearing.
        actor.MeleeAttackDistance, actor.MeleeAttackAngleRadius = data.melee.range, data.melee.angle
        if not IsValid(enemy) then return end
        local delta = enemy:GetPos() - actor:GetPos()
        delta.z = 0
        local facing = actor:GetForward():Dot(delta:GetNormalized())
        local distance = VJ.GetNearestDistance(actor, enemy, true)
        local _, key = actor:AIAnimationSet(weapon)
        if key == "unarmed" and not actor.MeleeAttack_IsPropAttack then
            if rear.enabled ~= false and facing <= -math.cos(math.rad(rear.angle))
                and distance <= data.melee.hit_range then
                actor.MeleeAttackDistance, actor.MeleeAttackAngleRadius = data.melee.hit_range, 180
                return rear
            elseif facing >= math.cos(math.rad(tackle.angle))
                and distance > math.max(data.melee.range, tackle.advance)
                and distance <= data.melee.range + tackle.advance then
                actor.MeleeAttackDistance, actor.MeleeAttackAngleRadius = data.melee.range + tackle.advance, tackle.angle
                return tackle
            end
        end
        if distance > data.melee.range or (not actor.VJ_Controlled
            and facing < math.cos(math.rad(data.melee.angle))) then
            actor.MeleeAttackDistance = 0
        end
    end
    function ENT:SetAnimationTranslations(hold, weapon)
        local result = translations(self, hold, weapon)
        admission(self, nil, weapon)
        return result
    end
    function ENT:Init()
        initialize(self)
        admission(self)
    end
    function ENT:OnThinkAttack(isAttacking, enemy)
        if attack then attack(self, isAttacking, enemy) end
        admission(self, enemy)
    end
    function ENT:OnMeleeAttack(status, enemy)
        if status == "PreInit" then
            self.CE8CombatStrike, self.CE8CombatDirection, self.CE8CombatHeading = nil, nil, nil
            self.CE8CombatStrikeSeed = nil
            if self:AIIsReloading() then return true end
            local strike = admission(self, enemy)
            if strike then
                if not self:AIPrepareAttackTurn(strike.sequence, enemy) then return true end
                if not self:AIValidateMotion(strike.sequence, 0, enemy) then
                    self.MeleeAttackDistance = 0 -- Let VJ approach/turn instead of idling on a rejected attack.
                    return true
                end
                self.CE8CombatStrike = strike
                self.CE8ContactSequence = strike.sequence
                self.AnimTbl_MeleeAttack = "vjseq_" .. strike.sequence
                return
            end
            if self.MeleeAttackDistance == 0 then return true end
        elseif status == "PostInit" and self.CE8CombatStrike then
            return -- The committed clip owns its starting heading.
        end
        local result = melee(self, status, enemy)
        if status == "PreInit" and result == true then self.MeleeAttackDistance = 0 end
        if status == "Init" and self.CE8CombatStrike then
            self.CE8CombatHeading, self.CE8CombatStrikeSeed = self:GetAngles().y, self.AttackSeed
            self:ResetTurnTarget()
            self:SetIdealYaw(self.CE8CombatHeading)
        end
        return result
    end
    function ENT:OnAnimEvent(id, eventTime, cycle, eventType, options)
        local strike = self.CE8CombatStrike
        if strike and id == 4001 and options == "primary keyframe"
            and self:GetSequenceName(self:GetSequence()) == strike.sequence then
            if self.AttackType ~= VJ.ATTACK_TYPE_MELEE or self.AttackSeed ~= self.CE8CombatStrikeSeed
                or self.CE8CombatHeading == nil or type(cycle) ~= "number" then return end
            local frame = math.floor(cycle * (strike.frames - 1) + 0.5)
            local heading
            for i, contact in ipairs(strike.contacts) do
                if frame == contact then heading = strike.directions[i] break end
            end
            if heading == nil then return end
            self.CE8CombatDirection = Angle(0, self.CE8CombatHeading + heading, 0):Forward()
        end
        return event(self, id, eventTime, cycle, eventType, options)
    end
    function ENT:MeleeAttackTraceDirection()
        if self.AttackType == VJ.ATTACK_TYPE_MELEE and self.AttackSeed == self.CE8CombatStrikeSeed
            and self.CE8CombatDirection then return self.CE8CombatDirection end
        return direction(self)
    end
    function ENT:MeleeAttackKnockbackVelocity(victim)
        local velocity = knockback and knockback(self, victim) or self:AIBaseCall("MeleeAttackKnockbackVelocity", victim)
        if self.AttackType == VJ.ATTACK_TYPE_MELEE and self.AttackSeed == self.CE8CombatStrikeSeed
            and self.CE8CombatDirection then
            local forward = self:GetForward()
            return velocity + (self.CE8CombatDirection - forward) * velocity:Dot(forward)
        end
        return velocity
    end
end

return Attacks
