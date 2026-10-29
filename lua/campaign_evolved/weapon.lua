-- Shared VJ setup; native values are kept in weapons.lua.
return function(SWEP, name)
local data = include("campaign_evolved/weapons.lua")[name]
local sounds = include("campaign_evolved/sounds/" .. name .. ".lua")
local layers = sounds.layers or {sounds.fire, sounds.tail}
local effects = include("campaign_evolved/weapon_fx.lua")
local ballistics = include("campaign_evolved/ballistics.lua")
local difficulty = include("campaign_evolved/difficulty.lua")
effects.Load(data)
SWEP.PrintName = data.name
SWEP.Author = "VJ-Halo"
SWEP.Category = "Halo - Campaign Evolved"
SWEP.Spawnable = false
SWEP.MadeForNPCsOnly = true
SWEP.HoldType = data.hold_type
SWEP.CE8WeaponName = name
SWEP.CE8Data = data
SWEP.WorldModel = data.model
SWEP.CE8Grip = data.grip
SWEP.CE8GripType = data.grip_type
SWEP.CE8AnimationClass = data.elite_class
SWEP.WorldModelOffsetParams = {Enabled = false, Bone = "wrist_r", Pos = Vector(), Ang = Angle()}
SWEP.NPC_BulletSpawnAttachment = data.attack_origin or data.muzzle
SWEP.NPC_NextPrimaryFire = data.interval
SWEP.NPC_TimeUntilFire = 0
SWEP.NPC_FiringDistanceMax = data.max_range
SWEP.NPC_FiringCone = 0.70710678
SWEP.NPC_HasReloadSound = false
SWEP.HasDeploySound = false
SWEP.HasDryFireSound = false
SWEP.Primary.ClipSize = data.clip > 0 and data.clip or 1
SWEP.Primary.TakeAmmo = data.clip > 0 and 1 or 0
SWEP.Primary.Ammo = data.ammo
SWEP.Primary.Automatic = data.automatic
SWEP.Primary.Delay = data.interval
SWEP.Primary.Damage = data.damage.amount[1]
SWEP.Primary.Force = 2
SWEP.Primary.TracerType = data.tracer or "AR2Tracer"
SWEP.Primary.NumberOfShots = data.projectiles_per_shot or 1
SWEP.Primary.Sound = layers[1] or {}
SWEP.Primary.HasDistantSound = false
SWEP.Primary.SoundPitch = VJ.SET(100, 100)
SWEP.Primary.DisableBulletCode = data.projectile
SWEP.IsMeleeWeapon = data.melee
-- VJ adds 20 units to melee-weapon damage reach. Keep the effective sword
-- reach at the authored depth and its attack start inside that reach.
SWEP.MeleeWeaponDistance = data.melee and math.max(0, data.melee_range - 20) or data.melee_range
SWEP.MeleeWeaponDamageType = DMG_SLASH
SWEP.PrimaryEffects_MuzzleFlash = data.source_effects and data.source_effects.muzzle ~= nil or false
SWEP.PrimaryEffects_MuzzleAttachment = data.muzzle
SWEP.PrimaryEffects_MuzzleParticles = false
SWEP.PrimaryEffects_SpawnShells = false
SWEP.PrimaryEffects_DynamicLightColor = Color(data.color[1], data.color[2], data.color[3])

local function vector(values) return Vector(values[1], values[2], values[3]) end
local function angle(values) return Angle(values[1], values[2], values[3]) end

function SWEP:CE8Attach(owner)
    if not IsValid(owner) or not (owner.IsCE8SNPC or owner.IsCE8Elite) then return false end
    local mount = owner.CE8WeaponMount and owner:CE8WeaponMount(self) or data.parent_offset
    local id = owner:LookupAttachment(data.parent_attachment)
    if id <= 0 then return false end
    self:RemoveEffects(EF_BONEMERGE)
    self:AddEffects(EF_PARENT_ANIMATES)
    self:SetParent(owner, id)
    self:SetLocalPos(vector(mount.pos))
    self:SetLocalAngles(angle(mount.ang))
    self:SetSolid(SOLID_NONE)
    self:SetNoDraw(false)
    if CLIENT then self:InvalidateBoneCache() end
    self.CE8Attached = true
    return true
end

function SWEP:OnEquip(owner)
    self.NPC_BulletSpawnAttachment = data.attack_origin or data.muzzle
    local label = IsValid(owner) and owner.CE8UnitLabel
    self.CE8AnimationClass = data.unit_classes[label] or data.native_class
    self.HoldType = data.unit_holds[label] or data.hold_type
    if self.SetHoldType then self:SetHoldType(self.HoldType) end
    self.CE8Grip = owner.CE8WeaponGrip and owner:CE8WeaponGrip(self) or data.grip
    self:CE8Attach(owner)
    self.CE8Burst = nil
    self.CE8Trigger, self.CE8NextTriggerT = nil, nil
    self.NPC_FiringDistanceMax = difficulty.Unit(data, owner).max_range or data.max_range
    self.CE8FireEnemy = nil
    self.CE8NextBurstT = nil
    self.CE8FireOwner = nil
    self.CE8FireReady = nil
    self.CE8AccuracyStarted = nil
    self.CE8FireState = nil
    self.CE8ShotProfile = nil
    self.CE8MeleeSwing, self.CE8MeleeEventOwner = nil, nil
end

local function sample(range) return math.Rand(range[1], range[2]) end

-- A heat event carries its cooling slope. Clients interpolate without polling
-- or networking a new material value every frame. No per-weapon render targets.
function SWEP:CE8SyncGaugeAmmo()
    if not SERVER or (name~="needler" and name~="needle_rifle") or not self.SetNW2Int then return end
    local rounds=self:Clip1()
    if rounds~=self.CE8GaugeAmmo then
        self.CE8GaugeAmmo=rounds
        self:SetNW2Int("ce8_weapon_ammo",rounds)
    end
end

function SWEP:CE8SyncHeat(now)
    if not SERVER or data.heat.threshold<=0 or not self.SetNW2Vector then return end
    local loss=self.CE8Overheated and data.heat.overheated_loss or data.heat.loss
    self:SetNW2Vector("ce8_weapon_heat",Vector(self.CE8Heat or 0,now,loss))
    self.CE8HeatNetworked=true
end

function SWEP:CE8UpdateHeat(now)
    local elapsed = math.max(0, now - (self.CE8HeatClock or now))
    self.CE8HeatClock = now
    local loss = self.CE8Overheated and data.heat.overheated_loss or data.heat.loss
    self.CE8Heat = math.max(0, (self.CE8Heat or 0) - elapsed * loss)
    local recovered=self.CE8Overheated and self.CE8Heat<=data.heat.recovery
    if recovered then self.CE8Overheated=nil end
    if recovered or not self.CE8HeatNetworked then self:CE8SyncHeat(now) end
end

function SWEP:CE8UpdateFireContext(owner, now)
    local enemy = owner:GetEnemy()
    local reloading = owner.GetWeaponState and owner:GetWeaponState() == VJ.WEP_STATE_RELOADING
    local active = not owner.GetActiveWeapon or owner:GetActiveWeapon() == self
    local visible = false
    if IsValid(enemy) then
        local cached = owner.EnemyData
        if cached and cached.Target == enemy and cached.Visible ~= nil then
            visible = cached.Visible
        else
            visible = not owner.Visible or owner:Visible(enemy)
        end
    end
    local ready = visible and active and not reloading or false
    local blind, corpse
    if owner.CE8BlindFirePoint and (not visible or (owner.CE8PostCombat and owner.CE8PostCombat.firing)) then
        blind, corpse = owner:CE8BlindFirePoint(self, enemy)
    end
    if corpse then enemy, visible = corpse, false end
    self.CE8CorpseTarget = corpse
    ready = ready or (blind ~= nil and active and not reloading)
    if owner ~= self.CE8FireOwner or enemy ~= self.CE8FireEnemy or ready ~= self.CE8FireReady or blind ~= self.CE8BlindAim then
        self.CE8BlindAim = blind
        self.CE8FireOwner = owner
        self.CE8FireEnemy = enemy
        self.CE8FireReady = ready
        self.CE8Burst = nil
        self.CE8Trigger, self.CE8NextTriggerT = nil, nil
        self.CE8NextBurstT = ready and now + sample(difficulty.Unit(data, owner).first_delay or data.first_delay) or nil
        self.CE8AccuracyStarted = ready and now or nil
        self.CE8ShotProfile = nil
        self.CE8FireState = nil
    end
end

local function finishKnownBurst(action, corpse)
    if not action then return end
    action.bursts_fired = (action.bursts_fired or 0) + 1
    if corpse then
        action.burst_done = action.bursts_fired >= (action.burst_limit or 1)
    end -- Suppression retains normal bursts until its action deadline.
end

function SWEP:CE8FireKnownPosition(owner, now)
    if not self.CE8BlindAim then return end
    local action = self.CE8CorpseTarget and owner.CE8PostCombat or owner.CE8Search
    -- Count an interrupted burst once, preserving its ordinary separation.
    -- The next burst keeps its normal pause; corpse fire also has a count cap.
    if self.CE8Burst and now >= self.CE8Burst.finish then
        local burst = self.CE8Burst
        self.CE8NextBurstT = math.max(self.CE8NextBurstT or 0,
            burst.finish + sample(burst.profile.separation))
        self.CE8Burst = nil
        finishKnownBurst(action, self.CE8CorpseTarget)
        return
    end
    if now <= (self.NPC_NextPrimaryFireT or 0) or not owner:CanFireWeapon(false, false) then return end
    local origin, target = self:GetBulletPos(), self.CE8BlindAim
    local trace = util.TraceHull({start = origin, endpos = target, mins = Vector(-12,-12,-12),
        maxs = Vector(12,12,12), mask = MASK_SHOT, filter = {owner, self}})
    if trace.StartSolid or (trace.Hit and trace.HitPos:Distance(origin) < 72)
        or (IsValid(trace.Entity) and owner:Disposition(trace.Entity) == D_LI)
        or (self.CE8CorpseTarget and trace.Hit and trace.Entity ~= self.CE8CorpseTarget) then return end
    -- Human Base clears its firing state when sight is lost. Supply it only
    -- around this explicit shot check; do not change normal enemy visibility.
    local state = owner.WeaponAttackState
    owner.WeaponAttackState = VJ.WEP_ATTACK_STATE_FIRE_STAND
    owner:UpdatePoseParamTracking()
    local allowed = self:NPC_CanFire()
    owner.WeaponAttackState = state
    if not allowed then return end
    -- NPCShoot_Primary intentionally requires live visibility. Reuse VJ's
    -- actual PrimaryAttack after its CanFire checks for this bounded exception.
    local previous = self.CE8LastShotT
    self:PrimaryAttack()
    if self.CE8LastShotT ~= previous then
        owner.WeaponLastShotTime = now
        self.NPC_NextPrimaryFireT = now + self.NPC_NextPrimaryFire
        if self.CE8CorpseTarget and owner.AINotifyCorpseShot then owner:AINotifyCorpseShot(self, now) end
        if not self.CE8Burst then finishKnownBurst(action, self.CE8CorpseTarget) end
    end
end

function SWEP:CE8FireCorpse(owner, now)
    local point, corpse = owner:CE8CorpseFirePoint(self)
    if not point or corpse ~= self.CE8CorpseTarget then return end
    -- VJ's native checks/PrimaryAttack require an enemy entity. Supply the
    -- actual corpse only during this synchronous call; never add it to enemy
    -- memory or let the NPC's regular combat scheduler pursue it.
    local previous, cached, state = owner:GetEnemy(), owner.EnemyData, owner.WeaponAttackState
    local context = setmetatable({Target = corpse, Visible = false,
        Distance = owner:GetPos():Distance(point)}, {__index = cached})
    owner.CE8CorpseShot = corpse
    owner:SetEnemy(corpse)
    owner.EnemyData = context
    local ok, failure = xpcall(function() self:CE8FireKnownPosition(owner, now) end, debug.traceback)
    if IsValid(owner) then
        owner.CE8CorpseShot = nil
        if owner:GetEnemy() == corpse then owner:SetEnemy(IsValid(previous) and previous or NULL) end
        if owner.EnemyData == context then owner.EnemyData = cached end
        if owner.WeaponAttackState == VJ.WEP_ATTACK_STATE_FIRE_STAND then owner.WeaponAttackState = state end
        if not ok then
            owner:CE8EndCorpseFire(now)
            owner.CE8PostCombat = nil
            ErrorNoHalt("CE8 corpse firing: " .. tostring(failure) .. "\n")
        end
    end
end

-- Elite sword damage belongs to the authored contact event, not VJ's
-- animation-start firing timer. Other hosts retain their existing dispatch.
local function eventMelee(owner)
    return data.melee and IsValid(owner) and owner.IsCE8Elite
end

local function meleeReady(weapon, owner, swing)
    if not swing or swing.owner ~= owner or not IsValid(owner) or weapon:GetOwner() ~= owner
        or owner:GetActiveWeapon() ~= weapon or owner.Dead or owner:Health() <= 0
        or owner.PauseAttacks or owner.Flinching or owner.AttackType or owner.CE8Reaction
        or owner:GetState() == VJ_STATE_FREEZE or owner:GetSequence() ~= swing.sequence then return false end
    local disabled = GetConVar("ai_disabled")
    return not (disabled and disabled:GetBool()) and owner:GetCycle() >= swing.cycle
end

function SWEP:CE8BeginMeleeSwing(owner, sequence)
    if not SERVER or not eventMelee(owner) then return end
    self.CE8MeleeSwing = {owner = owner, sequence = sequence, cycle = 0}
    self.CE8MeleeEventOwner = nil
    -- Retire a pre-refresh ranged-style burst without inheriting its pause.
    self.CE8Burst, self.CE8NextBurstT = nil, nil
end

function SWEP:OnHolster()
    self.CE8MeleeSwing, self.CE8MeleeEventOwner = nil, nil
end

function SWEP:CE8MeleeEvent(owner)
    if not SERVER or not eventMelee(owner) then return false end
    local swing = self.CE8MeleeSwing
    self.CE8MeleeSwing = nil -- A miss also consumes this swing's contact.
    if not meleeReady(self, owner, swing) then return false end
    self.CE8MeleeEventOwner = owner
    -- Reuse VJ's melee damage, range, relationship and hit/miss sound handling.
    -- Its swing-start timer stays blocked, even if it runs after this event.
    local ok, message = xpcall(function() self:PrimaryAttack() end, debug.traceback)
    self.CE8MeleeEventOwner = nil
    if not ok then ErrorNoHalt("CE8 melee event: " .. tostring(message) .. "\n") end
    return ok
end

function SWEP:NPC_CanFire(selfData, owner)
    owner = owner or self:GetOwner()
    if eventMelee(owner) then return false end
    if IsValid(owner) and owner.CE8WeaponShotReady and not owner:CE8WeaponShotReady(CurTime()) then return false end
    if self.CE8Overheated or CurTime() < (self.CE8NextBurstT or 0)
        or CurTime() < (self.CE8NextTriggerT or 0) then return false end
    return baseclass.Get("weapon_vj_base").NPC_CanFire(self, selfData, owner)
end

function SWEP:CE8BeginShot(owner, now)
    if owner.CE8WeaponShotReady and not owner:CE8WeaponShotReady(now) then return false end
    self:CE8UpdateHeat(now)
    self:CE8UpdateFireContext(owner, now)
    if not self.CE8FireReady or self.CE8Overheated or now < (self.CE8NextBurstT or 0)
        or now < (self.CE8NextTriggerT or 0) then return false end
    local burst = self.CE8Burst
    if burst and not self.CE8Trigger and now >= burst.finish then
        self.CE8NextBurstT = burst.finish + sample(burst.profile.separation)
        self.CE8Burst = nil
        if now < self.CE8NextBurstT then return false end
        burst = nil
    end
    if not burst then
        local profile, state = difficulty.Select(data, owner, self, now, self.CE8AccuracyStarted)
        local interval = math.max(data.interval, profile.rate > 0 and 1 / profile.rate or data.interval)
        burst = {start = now, finish = now + sample(profile.duration), profile = profile,
            pattern = state.pattern, state = state, interval = interval, shots = 0}
        self.CE8Burst = burst
    end
    self.CE8ShotProfile = burst.profile
    self.CE8FireState = burst.state
    self.NPC_NextPrimaryFire = data.trigger_burst and data.trigger_burst.interval or burst.interval
    self.Primary.Damage = sample(data.damage.amount)
    return true
end

function SWEP:CE8ShotSpread(owner)
    local profile = self.CE8ShotProfile
    if not profile then return data.conical_spread and math.tan(data.conical_spread.angle) or nil end
    local scale = self.CE8FireState and self.CE8FireState.error_scale
        or tonumber(difficulty.Get("ce8_projectile_error_scale"))
    local aim = math.tan(profile.projectile_error) * scale * math.max(0, owner.Weapon_Accuracy or 1)
        * math.max(0, self.NPC_CustomSpread or 1)
    -- The native shotgun cone is mechanical spread, independent of AI aim.
    return aim + (data.conical_spread and math.tan(data.conical_spread.angle) or 0)
end

function SWEP:CE8SpawnProjectile(owner)
    local projectile = ents.Create("obj_ce8_projectile")
    if not IsValid(projectile) then return end
    local level = difficulty.Level(owner, self)
    local ai = owner:IsNPC() or owner:IsNextBot()
    local scale = ballistics.Scale(data, level, ai)
    local origin = self:GetBulletPos()
    local enemy = owner:GetEnemy()
    local target = owner.GetAimPosition and owner:GetAimPosition(enemy, origin, 0)
        or (IsValid(enemy) and enemy:WorldSpaceCenter() or origin + owner:GetForward() * data.max_range)
    local direction = (target - origin):GetNormalized()
    if direction:LengthSqr() == 0 then direction = owner:GetForward() end
    if data.gravity > 0 or (data.flight and data.flight.final_speed ~= data.speed) then
        local targetVelocity = Vector()
        if IsValid(enemy) and (not owner.Visible or owner:Visible(enemy)) then
            targetVelocity = VJ.GetMoveVelocity(enemy)
        end
        direction = ballistics.Aim(data, origin, target, targetVelocity,
            physenv.GetGravity(), engine.TickInterval(), scale)
        if direction:LengthSqr() == 0 then direction = owner:GetForward() end

    end
    local spread = self:CE8ShotSpread(owner)
    if spread then
        if spread > 0 then
            local axis = math.abs(direction.z) < 0.99 and Vector(0, 0, 1) or Vector(0, 1, 0)
            local right = direction:Cross(axis):GetNormalized()
            local up = right:Cross(direction)
            local turn = math.Rand(0, math.pi * 2)
            local radius = math.sqrt(math.Rand(0, 1)) * spread
            direction = (direction + (right * math.cos(turn) + up * math.sin(turn)) * radius):GetNormalized()
        end
    else
        spread = owner.GetAimSpread and owner:GetAimSpread(enemy, target, self.NPC_CustomSpread or 1) or 0
        if spread > 0 then direction = (direction + VectorRand() * spread):GetNormalized() end
    end
    projectile.CE8Data = data
    projectile.CE8Sounds = sounds
    projectile.CE8WeaponName = name
    projectile.CE8Weapon = self
    projectile.CE8Target = data.flight and data.flight.guidance and not self.CE8BlindAim and enemy or nil
    projectile.CE8Flight = ballistics.State(data, scale, level, ai, nil, direction)
    projectile.CE8Damage = self.Primary.Damage
    projectile:SetOwner(owner)
    projectile:SetPos(origin)
    projectile:SetAngles(direction:Angle())
    projectile:Spawn()
    projectile:Activate()
    local physics = projectile:GetPhysicsObject()
    if IsValid(physics) then physics:SetVelocityInstantaneous(direction * data.speed * scale) end
    -- Preserve the initial shot-direction threat for plasma/needles; guidance
    -- can change their later flight. Gravity shots use projectile danger instead.
    if data.gravity == 0 and CE8 and CE8.RecordGunfire then
        CE8.RecordGunfire(owner, origin, origin + direction * data.max_range)
    end
end

function SWEP:CE8FinishShot(now)
    local burst = self.CE8Burst
    if not burst then return end
    self.CE8LastShotT = now
    burst.shots = burst.shots + 1
    self.CE8Heat = (self.CE8Heat or 0) + data.heat.per_shot
    if data.heat.threshold > 0 and self.CE8Heat >= data.heat.threshold and not self.CE8Overheated then
        self.CE8Overheated = true
        local owner = self:GetOwner()
        if IsValid(owner) and owner.CE8QueueDialogue then owner:CE8QueueDialogue("overheated", now, self) end
    end
    self:CE8SyncHeat(now)
    self:CE8SyncGaugeAmmo()
    local trigger = data.trigger_burst
    if trigger then
        local state = self.CE8Trigger or {shots = 0}
        state.shots = state.shots + 1
        if state.shots < trigger.rounds and self:Clip1() > 0 then
            self.CE8Trigger = state
            self.CE8NextTriggerT = now + trigger.interval
            self.NPC_NextPrimaryFire = trigger.interval
            return
        end
        self.CE8Trigger = nil
        self.CE8NextTriggerT = now + math.max(trigger.recovery, burst.interval)
        self.NPC_NextPrimaryFire = self.CE8NextTriggerT - now
    end
    if now + burst.interval >= burst.finish - 0.00001 then
        self.CE8NextBurstT = math.max(now + burst.interval, self.CE8NextTriggerT or 0, burst.finish + sample(burst.profile.separation))
        -- VJ writes this delay after PrimaryAttack returns. Set it here so a
        -- held attack respects the full pause without extra firing timers.
        self.NPC_NextPrimaryFire = self.CE8NextBurstT - now
        self.CE8Burst = nil
    end
end

function SWEP:OnThink()
    self:CE8SyncGaugeAmmo()
    local owner = self:GetOwner()
    if IsValid(owner) and (owner.IsCE8SNPC or owner.IsCE8Elite) and (self:GetParent() ~= owner or not self.CE8Attached) then
        self:CE8Attach(owner)
    end
    if SERVER and IsValid(owner) and owner:IsNPC() then
        if eventMelee(owner) then
            local swing = self.CE8MeleeSwing
            if meleeReady(self, owner, swing) then swing.cycle = owner:GetCycle()
            else self.CE8MeleeSwing = nil end
            return
        end
        local now = CurTime()
        self:CE8UpdateHeat(now)
        self:CE8UpdateFireContext(owner, now)
        if self.CE8CorpseTarget then self:CE8FireCorpse(owner, now)
        elseif self.CE8BlindAim then self:CE8FireKnownPosition(owner, now) end
    end
end

function SWEP:OnPrimaryAttack(status)
    local owner = self:GetOwner()
    if status == "Init" and SERVER and IsValid(owner) and owner:IsNPC() then
        if eventMelee(owner) then
            if self.CE8MeleeEventOwner ~= owner then return true end
            self.CE8MeleeEventOwner = nil -- Consume before VJ applies damage.
            self.Primary.Damage = sample(data.damage.amount)
        elseif not self:CE8BeginShot(owner, CurTime()) then return true end
    elseif status == "PostFire" then
        if SERVER then effects.Muzzle(self, data, false) end
        if SERVER and data.projectile and IsValid(owner) then self:CE8SpawnProjectile(owner) end
        for index = 2, #layers do
            local choices = layers[index]
            if choices and #choices > 0 then self:EmitSound(choices[math.random(#choices)], 85, 100, 1, CHAN_AUTO) end
        end
        if SERVER then
            if eventMelee(owner) then
                self.CE8LastShotT = CurTime()
                owner.WeaponLastShotTime = self.CE8LastShotT
            else self:CE8FinishShot(CurTime()) end
        end
    end
end

function SWEP:OnPrimaryAttack_BulletCallback(attacker, trace, damage)
    if SERVER and not data.projectile and data.damage_falloff then
        local falloff = data.damage_falloff
        local distance = trace.StartPos:Distance(trace.HitPos)
        local fraction = math.Clamp((distance - falloff.start) / math.max(0.001, falloff.finish - falloff.start), 0, 1)
        local peak = math.max(0.001, self.Primary.Damage)
        damage:ScaleDamage(1 + (falloff.minimum / peak - 1) * fraction)
    end
    if SERVER and not data.projectile then
        effects.Flyby(sounds, trace.StartPos, trace.HitPos, attacker)
        if trace.Hit and not trace.HitSky then
            effects.ContactSound(sounds, trace, effects.ContactSurface(trace), "impact", false)
        end
    end
    if not SERVER or data.projectile or not data.needle or damage:GetDamage() <= 0 then return end
    local target = trace.Entity
    if target == attacker then return end
    local contact = effects.NeedleContact(target, trace)
    if not contact then return end
    local health = contact == "unit" and target:Health() or nil
    -- The callback runs before Source applies bullet damage. Copy the trace
    -- values now; DamageInfo must not be retained beyond this callback.
    local hit = {HitPos = Vector(trace.HitPos), Normal = Vector(trace.Normal),
        HitBox = trace.HitBox, HitBoxSet = trace.HitBoxSet, PhysicsBone = trace.PhysicsBone,
        MatType = trace.MatType, HitSky = trace.HitSky}
    timer.Simple(0, function()
        if not IsValid(target) or (health and (target:Health() <= 0 or target:Health() >= health)) then return end
        local projectile = ents.Create("obj_ce8_projectile")
        if not IsValid(projectile) then return end
        projectile.CE8Data = data
        projectile.CE8WeaponName = name
        projectile.CE8Sounds = sounds
        projectile.CE8ImpactSoundPlayed = true -- The original trace owns contact audio.
        projectile.CE8Damage = 0 -- The original bullet already dealt the impact.
        if IsValid(attacker) then projectile:SetOwner(attacker) end
        projectile:SetPos(hit.HitPos)
        projectile:SetAngles(hit.Normal:Angle())
        projectile:Spawn()
        if not IsValid(projectile) then return end
        projectile:Activate()
        if not projectile:CE8EmbedNeedle(target, hit) then projectile:Remove() end
    end)
end

function SWEP:OnDrop()
    local pos, ang = self:GetPos(), self:GetAngles()
    baseclass.Get("weapon_vj_base").OnDrop(self)
    self:SetParent(NULL)
    self:RemoveEffects(EF_PARENT_ANIMATES)
    self:SetPos(pos)
    self:SetAngles(ang)
    self.CE8Attached = false
    self.CE8Trigger, self.CE8NextTriggerT = nil, nil
end

if CLIENT then
    local rendererToken = {}
    function SWEP:CE8BindRenderer()
        if not CE8 or not CE8.ApplyModelDepth then return end
        if self.CE8WeaponRendererToken ~= rendererToken then
            if self.CE8WeaponRenderer then self.CE8NormalSpawnRenderer = false end
            self.CE8WeaponRenderer = nil
            self.CE8WeaponRendererToken = rendererToken
        end
        CE8.ApplyModelDepth(self)
        -- Projected lighting is already included in the CE8 surface pass.
        if self.CE8Draft and not self:IsEffectActive(EF_NOFLASHLIGHT) then
            self:AddEffects(EF_NOFLASHLIGHT)
        end
        if self.RenderOverride == self.CE8WeaponRenderer then return end
        local draw = self.RenderOverride
        if not draw then return end
        self.CE8WeaponRenderer = function(weapon, flags)
            local owner = weapon:GetOwner()
            if IsValid(owner) and (owner.IsCE8SNPC or owner.IsCE8Elite) and owner.CE8DrawingModel then return end
            if weapon.CE8DrawingModel then weapon:DrawModel(flags) return end
            local previous = weapon.CE8DrawingModel
            weapon.CE8DrawingModel = true
            local ok, message = xpcall(function() draw(weapon, flags) end, debug.traceback)
            weapon.CE8DrawingModel = previous
            if not ok then ErrorNoHalt("CE8 weapon draw: " .. tostring(message) .. "\n") end
        end
        self.RenderOverride = self.CE8WeaponRenderer
        self.CE8NormalSpawnRenderer = self.CE8WeaponRenderer
    end

    function SWEP:CE8DrawHeld(flags)
        if not self:GetDrawWorldModel() then return end
        self:CE8BindRenderer()
        local previous = self.CE8DrawingHeld
        self.CE8DrawingHeld = true
        local ok, message = xpcall(function()
            if self.RenderOverride then self:RenderOverride(flags) else self:DrawModel(flags) end
        end, debug.traceback)
        self.CE8DrawingHeld = previous
        if not ok then ErrorNoHalt("CE8 held weapon draw: " .. tostring(message) .. "\n") end
    end

    function SWEP:DrawWorldModelTranslucent(flags)
        if not self:GetDrawWorldModel() then return end
        local owner=self:GetOwner()
        if IsValid(owner) and (owner.IsCE8SNPC or owner.IsCE8Elite) and owner.CE8DrawingModel then return end
        self:CE8BindRenderer()
        if CE8 and CE8.DrawEmissiveModel then
            CE8.DrawEmissiveModel(self,bit.bor(flags or 0,STUDIO_RENDER or 1,STUDIO_DRAWTRANSLUCENTSUBMODELS or 4))
        end
    end

    function SWEP:OnDrawWorldModel()
        local owner = self:GetOwner()
        if IsValid(owner) and (owner.IsCE8SNPC or owner.IsCE8Elite) and owner.CE8DrawingModel then return false end
        self:CE8DrawHeld()
        return false
    end
end

end
