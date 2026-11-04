AddCSLuaFile()
SWEP.Base = "weapon_vj_base"
SWEP.PrintName = "Hunter Arm Cannon"
SWEP.Author = "VJ-Halo"
SWEP.Category = "Halo - Campaign Evolved"
SWEP.Spawnable, SWEP.MadeForNPCsOnly = false, true
SWEP.HoldType = "ar2"
SWEP.CE8WeaponName = "cannon"
-- VJ needs a weapon entity, but the visible cannon belongs to the Hunter mesh.
SWEP.WorldModel = "models/weapons/w_bugbait.mdl"
SWEP.WorldModelOffsetParams = {Enabled = false}
SWEP.NPC_TimeUntilFire = 0
SWEP.NPC_NextPrimaryFire = 0.05
SWEP.NPC_FiringCone = 0.5
SWEP.HasDeploySound, SWEP.HasDryFireSound, SWEP.NPC_HasReloadSound = false, false, false
SWEP.Primary.ClipSize, SWEP.Primary.DefaultClip, SWEP.Primary.TakeAmmo = 1, 1, 0
SWEP.Primary.Ammo, SWEP.Primary.Automatic = "none", true
SWEP.Primary.Delay, SWEP.Primary.Damage = 0.05, 100
SWEP.Primary.DisableBulletCode, SWEP.Primary.HasDistantSound = true, false
SWEP.Primary.Sound = false
SWEP.PrimaryEffects_MuzzleFlash, SWEP.PrimaryEffects_MuzzleParticles = false, false
SWEP.PrimaryEffects_SpawnShells, SWEP.PrimaryEffects_SpawnDynamicLight = false, false

local character = include("campaign_evolved/hunter_anims.lua")
local data = character.cannon
local sounds = include("campaign_evolved/sounds/hunter_cannon.lua")
local difficulty = include("campaign_evolved/difficulty.lua")
local ballistics = include("campaign_evolved/ballistics.lua")
local effects = include("campaign_evolved/weapon_fx.lua")
SWEP.CE8Data = data
SWEP.NPC_FiringDistanceMax = data.max_range
effects.Load(data)

function SWEP:OnDrawWorldModel() return false end

function SWEP:CE8Flaps(owner, amount)
    if IsValid(owner) and owner.CE8UnitLabel == "hunter" and owner.CE8GunFlaps ~= amount then
        owner.CE8GunFlaps = amount
        owner:SetPoseParameter("gun_flaps", amount)
    end
end

function SWEP:CE8CancelCharge()
    if self.CE8Charge then self:CE8Flaps(self.CE8Charge.owner, 0) end
    self.CE8Charge = nil
end

function SWEP:CE8Attach(owner)
    if not IsValid(owner) or owner.CE8UnitLabel ~= "hunter" then return false end
    local attachment = owner:LookupAttachment(data.muzzle)
    if attachment <= 0 then return false end
    self:RemoveEffects(EF_BONEMERGE)
    self:AddEffects(EF_PARENT_ANIMATES)
    self:SetParent(owner, attachment)
    self:SetLocalPos(Vector())
    self:SetLocalAngles(Angle())
    self:SetSolid(SOLID_NONE)
    self:SetNoDraw(true)
    self:SetDrawWorldModel(false)
    return true
end

function SWEP:OnEquip(owner)
    self:CE8CancelCharge()
    self.CE8NextCharge = nil
    self:CE8Attach(owner)
end

function SWEP:OnGetBulletPos()
    local owner = self:GetOwner()
    if IsValid(owner) and owner.CE8CannonPosition then return owner:CE8CannonPosition() end
end

local function permitted(weapon, owner)
    if not IsValid(owner) or owner.CE8UnitLabel ~= "hunter" or owner:GetActiveWeapon() ~= weapon
        or owner.Dead or owner:Health() <= 0 or owner.PauseAttacks or owner.Flinching or owner.AttackType
        or owner:GetState() == VJ_STATE_FREEZE then return false end
    local disabled = GetConVar("ai_disabled")
    if disabled and disabled:GetBool() then return false end
    local enemy = owner:GetEnemy()
    if not IsValid(enemy) or (owner.CE8WeaponShotReady and not owner:CE8WeaponShotReady(CurTime())) then return false end
    if not owner.VJ_Controlled and not owner:Visible(enemy) then
        local point = owner:AISuppressionPoint(weapon, enemy)
        if not point or not owner:CanFireWeapon(false, false) then return false end
        -- Reuse VJ's range/cone/stance check against remembered coordinates.
        -- Never update enemy memory or consult the hidden target's live position.
        local cached, state = owner.EnemyData, owner.WeaponAttackState
        owner.EnemyData = setmetatable({Distance = owner:GetPos():Distance(point)}, {__index = cached})
        owner.WeaponAttackState = VJ.WEP_ATTACK_STATE_FIRE_STAND
        local ok, result = pcall(baseclass.Get("weapon_vj_base").NPC_CanFire, weapon, nil, owner)
        owner.EnemyData, owner.WeaponAttackState = cached, state
        if not ok then ErrorNoHalt("CE8 Hunter suppression: " .. tostring(result) .. "\n") return false end
        return result == true
    end
    return baseclass.Get("weapon_vj_base").NPC_CanFire(weapon, nil, owner) == true
end

function SWEP:OnThink()
    if not SERVER then return end
    local owner, now = self:GetOwner(), CurTime()
    if not permitted(self, owner) then self:CE8CancelCharge() return end
    local enemy = owner:GetEnemy()
    local point = owner:AISuppressionPoint(self, enemy)
    local charge = self.CE8Charge
    if charge and (charge.owner ~= owner or charge.enemy ~= enemy or charge.point ~= point) then self:CE8CancelCharge() charge = nil end
    if now < (self.CE8NextCharge or 0) then return end
    if not charge then
        local acquired = owner.EnemyData and owner.EnemyData.TimeAcquired or now
        local profile, state = difficulty.Select(data, owner, self, now, acquired)
        charge = {owner = owner, enemy = enemy, start = now, finish = now + data.charge,
            profile = profile, state = state, point = point}
        self.CE8Charge = charge
        effects.EntitySound(sounds.charge, self, 80)
    end
    self:CE8Flaps(owner, math.Clamp((now - charge.start) / data.charge, 0, 1))
    if point and now >= charge.finish and now > (self.NPC_NextPrimaryFireT or 0) then
        -- Like shared weapon suppression, this finite exception calls VJ's
        -- PrimaryAttack after all native checks; ordinary firing stays in VJ.
        self:PrimaryAttack()
        self.NPC_NextPrimaryFireT = now + self.NPC_NextPrimaryFire
    end
end

function SWEP:NPC_CanFire(_, owner)
    owner = owner or self:GetOwner()
    local charge = self.CE8Charge
    return IsValid(owner) and charge ~= nil and charge.owner == owner and charge.enemy == owner:GetEnemy()
        and CurTime() >= charge.finish and permitted(self, owner)
end

function SWEP:CE8FireBolt(owner, charge)
    local origin = self:GetBulletPos()
    local level, ai = difficulty.Level(owner, self), not owner.VJ_Controlled
    local scale = ballistics.Scale(data, level, ai)
    local target = charge.point or owner:GetAimPosition(charge.enemy, origin, 0)
    local velocity = ai and not charge.point and VJ.GetMoveVelocity(charge.enemy) * data.leading or Vector()
    local direction, duration, miss, reachable = ballistics.Aim(data, origin, target, velocity,
        physenv.GetGravity(), engine.TickInterval(), scale)
    if direction:LengthSqr() < 0.001 then direction = owner:GetForward() end
    if ai then
        local error = math.tan(charge.profile.projectile_error) * (charge.state.error_scale or 1)
        direction = (direction + VectorRand() * error):GetNormalized()
    end
    if charge.point then
        if not reachable or miss > 16 then return false end
        local filter, previous = {owner, self}, origin
        for _, part in pairs(owner.ColliderParts or owner.CE8ArmorParts or {}) do if IsValid(part) then filter[#filter + 1] = part end end
        for i = 1, 12 do
            local nextPos = origin + ballistics.Predict(data, direction, duration * i / 12,
                physenv.GetGravity() * data.gravity, engine.TickInterval(), scale)
            local trace = util.TraceHull({start = previous, endpos = nextPos, mins = Vector(-4,-4,-4),
                maxs = Vector(4,4,4), mask = MASK_SHOT, filter = filter})
            if trace.StartSolid or trace.AllSolid then return false end
            if trace.Hit then
                if trace.HitPos:Distance(origin) < data.explosion.radius[2] + 64 then return false end
                for _, actor in ipairs(ents.FindInSphere(trace.HitPos, data.explosion.radius[2])) do
                    if actor ~= owner and (actor:IsNPC() or actor:IsPlayer() or actor:IsNextBot())
                        and actor:Health() > 0 and owner:Disposition(actor) == D_LI then return false end
                end
                break
            end
            previous = nextPos
        end
    end
    local projectile = ents.Create("obj_ce8_projectile")
    if not IsValid(projectile) then return false end
    projectile.CE8Data, projectile.CE8Sounds = data, sounds
    projectile.CE8WeaponName, projectile.CE8Weapon = "hunter_cannon", self
    projectile.CE8Damage = math.Rand(data.damage.amount[1], data.damage.amount[2])
    projectile.CE8Flight = ballistics.State(data, scale, level, ai, nil, direction)
    projectile:SetOwner(owner)
    projectile:SetPhysicsAttacker(owner)
    projectile:SetPos(origin)
    projectile:SetAngles(direction:Angle())
    projectile:Spawn()
    projectile:Activate()
    local physics = projectile:GetPhysicsObject()
    if IsValid(physics) then physics:SetVelocityInstantaneous(direction * data.speed * scale) end
    effects.Muzzle(owner, data)
    effects.EntitySound(sounds.fire, self, 90)
    local animations = character.weapon_sets.cannon.sequences
    local crouched = (owner.AIDefenseCrouched and owner:AIDefenseCrouched())
        or (owner.AIControlCrouched and owner:AIControlCrouched())
    local sequence = owner:LookupSequence(crouched and animations.crouch_fire or animations.fire)
    if sequence >= 0 then
        if owner.CE8Recoil and owner:IsValidLayer(owner.CE8Recoil) then owner:RemoveLayer(owner.CE8Recoil) end
        local layer = owner:AddGestureSequence(sequence, true)
        if layer >= 0 then
            owner:SetLayerPriority(layer, 1)
            owner:SetLayerPlaybackRate(layer, owner.AnimPlaybackRate or 1)
            owner.CE8Recoil = layer
        end
    end
    return true
end

function SWEP:OnPrimaryAttack(status)
    if not SERVER then return true end
    if status == "Init" then
        if not self:NPC_CanFire() then return true end
    elseif status == "PostFire" then
        local charge = self.CE8Charge
        if not charge then return end
        local fired = self:CE8FireBolt(charge.owner, charge)
        if charge.point then
            local config = charge.owner:AIProfile().search
            local search = charge.owner[config.fields.active]
            if search and search.aim == charge.point then
                search.burst_done = true
                search.bursts_fired = (search.bursts_fired or 0) + (fired and 1 or 0)
            end
        end
        local separation = charge.profile.separation
        local pause = math.max(data.interval - data.charge, data.recovery, math.Rand(separation[1], separation[2]))
        self.CE8NextCharge = CurTime() + pause
        -- VJ writes its next-shot timer after this callback. Retain its ownership.
        self.NPC_NextPrimaryFire = pause
        self:CE8CancelCharge()
    end
end

function SWEP:OnHolster() self:CE8CancelCharge() end
function SWEP:CustomOnRemove() self:CE8CancelCharge() end
