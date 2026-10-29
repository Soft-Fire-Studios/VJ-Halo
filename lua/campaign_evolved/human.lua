-- Weapon and wrist-equipment integration for CE8 Human NPCs.
local Actor = include("campaign_evolved/actor.lua")
local Host = {Shared = Actor.Shared, Profile = Actor.Profile, Client = Actor.Client}
function Host.Server(ENT, profile)
    Actor.Server(ENT, profile)
    local data = ENT:CE8Data()
    ENT.Weapon_CanMoveFire, ENT.Weapon_Strafe = true, Actor.Option(data, "strafe", true)
    ENT.Weapon_StrafeCooldown = VJ.SET(2, 4)
    ENT.Weapon_CanCrouchAttack = Actor.Option(data, "crouch_fire", true)
    ENT.Weapon_CanSecondaryFire = false
    ENT.Weapon_FindCoverOnReload = Actor.Option(data, "reload_cover", false)
    ENT.Weapon_RetreatDistance = Actor.Option(data, "retreat_distance", data.owner == "grunt" and 90 or 150)
    ENT.Weapon_UnarmedBehavior = Actor.Option(data, "unarmed_flee", true)
    ENT.Weapon_OcclusionDelay = Actor.Option(data, "occlusion_delay", true)
    ENT.Weapon_MinDistance, ENT.Weapon_MaxDistance = 40, Actor.Option(data, "weapon_max_distance", 2400)
    ENT.Weapon_AimTurnDiff = 0.70710678
    ENT.AnimTbl_WeaponAttack, ENT.AnimTbl_WeaponAttackCrouch = ACT_IDLE_ANGRY, ACT_COVER_LOW
    ENT.HasMeleeAttack = false
    function ENT:SetAnimationTranslations(hold, weapon)
        self:AISetAnimationTranslations(hold, weapon)
        if not self:AIHasCapability("cover") then
            self.AnimTbl_TakingCover = false
            self.AnimTbl_WeaponReloadCovered = false
        end
    end
    function ENT:OnWeaponChange(weapon)
        self:SetAnimationTranslations(IsValid(weapon) and weapon:GetHoldType() or "pistol", weapon)
        local grip = self:CE8WeaponGrip(weapon)
        self:AIApplyGrip(grip)
        self:SetNW2Int("ce8_grip", grip)
        if IsValid(weapon) and weapon.CE8Attach then weapon:CE8Attach(self) end
        self:CE8UpdateEquipment()
    end
    function ENT:CE8WeaponShotReady(now)
        return not self.AIFlee and not self.Dead and not self:AIChargeBlocksWeapon(self:GetActiveWeapon(), now)
    end
    -- Gate VJ's firing stance as well as the SWEP; otherwise a standing shot
    -- replaces the chase schedule while the actor is committed to melee.
    function ENT:OnWeaponCanFire()
        if self:AIChargeBlocksWeapon(self:GetActiveWeapon(), CurTime()) then return false end
    end
    Host.Equipment(ENT)
end

-- Keep the visual wrist prop parented. Its invisible trace detector follows
-- separately because Source makes parented entities nonsolid to bullet traces.
function Host.Equipment(ENT)
    function ENT:CE8RemoveEquipment()
        if IsValid(self.CE8Barrier) then self.CE8Barrier:Remove() end
        self.CE8Barrier = nil
        if IsValid(self.CE8ShieldProp) then self.CE8ShieldProp:Remove() end
        self.CE8ShieldProp = nil
    end
    function ENT:CE8UpdateEquipment()
        local rank, weapon = self:CE8RankSettings(), self:GetActiveWeapon()
        local equipped = rank.shield_model and IsValid(weapon)
            and (weapon.CE8WeaponName == "plasma_pistol" or weapon.CE8WeaponName == "needler")
        if not equipped then self:CE8RemoveEquipment() return end
        if IsValid(self.CE8ShieldProp) and IsValid(self.CE8Barrier) then return end
        self:CE8RemoveEquipment()
        local attachment = self:LookupAttachment("shield")
        if attachment <= 0 then return end
        local prop = ents.Create("prop_dynamic")
        if not IsValid(prop) then return end
        prop:SetModel(rank.shield_model)
        prop:SetKeyValue("DisableBoneFollowers", "1")
        prop:SetOwner(self)
        prop:SetPos(self:GetPos())
        prop:Spawn()
        prop:SetSolid(SOLID_NONE)
        prop:SetMoveType(MOVETYPE_NONE)
        prop:AddEffects(EF_PARENT_ANIMATES)
        prop:SetParent(self, attachment)
        prop:SetLocalPos(Vector())
        prop:SetLocalAngles(Angle())
        self:DeleteOnRemove(prop)
        self.CE8ShieldProp = prop
        prop:SetNW2Entity("ce8_barrier_owner", self)
        local detector = ents.Create("obj_ce8_barrier")
        if IsValid(detector) then
            detector:SetModel(rank.shield_model)
            detector:SetOwner(self)
            self.CE8Barrier = detector
            detector:Spawn()
            self:DeleteOnRemove(detector)
        end
    end
end

return Host
