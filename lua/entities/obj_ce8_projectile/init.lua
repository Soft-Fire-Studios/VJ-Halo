AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")
local effects = include("campaign_evolved/weapon_fx.lua")
local ballistics = include("campaign_evolved/ballistics.lua")

ENT.Model = "models/Items/AR2_Grenade.mdl"
ENT.DoesDirectDamage = true
ENT.DoesRadiusDamage = false
ENT.CollisionDecal = false
ENT.HasStartupSounds = false
ENT.HasIdleSounds = false
ENT.HasOnCollideSounds = false
ENT.CE8CollisionRadius = 1

function ENT:PreInit()
    local data = self.CE8Data
    if not data then self:Remove() return end
    local owner = self:GetOwner()
    -- Preserve NPC attribution for the global damage hook if its owner is
    -- removed before a delayed explosion or supercombine resolves.
    self.CE8NPCDamage = IsValid(owner) and owner.IsCE8SNPC == true
    self.DirectDamage = self.CE8Damage or 0
    if IsValid(owner) and owner.ScaleByDifficulty then
        self.DirectDamage = owner:ScaleByDifficulty(self.DirectDamage)
    end
    if data.needle then
        self.CE8BurstScale = IsValid(owner) and owner.ScaleByDifficulty and owner:ScaleByDifficulty(1) or 1
    end
    self.DirectDamageType = data.damage.category == "plasma" and DMG_ENERGYBEAM or DMG_BULLET
    if data.explosion then
        self.DoesRadiusDamage = true
        self.RadiusDamage = math.Rand(data.explosion.amount[1], data.explosion.amount[2])
        self.RadiusDamageRadius = data.explosion.radius[2]
        self.RadiusDamageType = DMG_BLAST
    end
    self.ProjectileType = VJ.PROJ_TYPE_LINEAR
    self.CE8Expires = CurTime() + (data.grenade and 30 or ballistics.Lifetime(data, self.CE8Flight and self.CE8Flight.scale))
    if data.grenade then
        self.Model = data.model
        self.DoesDirectDamage = false
        self.CollisionFilter = false
        self.VJ_ID_Grenade = true
        self.VJ_ID_Grabbable = false
        self.CE8ArmedAt = CurTime() + data.arming
        self:SetNW2Bool("CE8Grenade", true)
    else
        self.VJ_ID_Danger = true
    end
    if data.projectile_model then
        self.Model = data.projectile_model
        self:SetNW2Bool("CE8ProjectileMesh", true)
        self:SetColor(Color(255, 255, 255)) -- The native material supplies its color.
    else
        self:SetColor(Color(data.color[1], data.color[2], data.color[3]))
    end
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
end

function ENT:InitPhys()
    if not self.CE8Data.grenade then self:PhysicsInitSphere(self.CE8CollisionRadius, "metal") end
    local physics = self:GetPhysicsObject()
    if IsValid(physics) then
        physics:Wake()
        physics:SetMass(1)
        physics:EnableGravity(false)
        physics:EnableDrag(false)
        physics:SetBuoyancyRatio(0)
        if self.CE8Data.grenade then physics:SetMaterial("metal") end
    end
    return true
end

function ENT:Init()
    if self.CE8Sounds then self.CE8AudioPosition = Vector(self:GetPos()) end
    if self.CE8Data.flight then
        self.CE8TravelPosition = self:GetPos()
        self.CE8TravelDistance = 0
        self.CE8Flight = self.CE8Flight or ballistics.State(self.CE8Data, 1, "normal", false, nil, self:GetForward())
    end
    local particleFlight = effects.Flight(self, self.CE8Data, self.CE8ChargedShot == true)
    self:SetNW2Bool("CE8ParticleFlight", particleFlight)
    if not particleFlight then self:CE8StartNeedleFX() end
    if self.CE8Data.grenade then self:CE8GrenadeSound("armed") end
end

-- Temporary flight visibility until the needle particle system is ported.
-- Engine sprites stay outside the custom mesh shader's depth/light passes.
function ENT:CE8StartNeedleFX()
    local data = self.CE8Data
    if self.CE8NeedleFXStarted or self.CE8NeedleTarget or self.Dead
        or not data.needle or not data.projectile then return end
    self.CE8NeedleFXStarted = true
    local tint = Color(data.color[1], data.color[2], data.color[3], 190)
    local trail = util.SpriteTrail(self, 0, tint, true, 3, 0, 0.12, 1 / 6, "sprites/laserbeam.vmt")
    if IsValid(trail) then
        self.CE8NeedleTrail = trail
        self:DeleteOnRemove(trail)
    end
    local glow = ents.Create("env_sprite")
    if IsValid(glow) then
        glow:SetKeyValue("model", "sprites/light_glow02_add.vmt")
        glow:SetKeyValue("rendermode", "5") -- Additive, depth tested.
        glow:SetKeyValue("renderamt", "190")
        glow:SetKeyValue("rendercolor", string.format("%d %d %d", tint.r, tint.g, tint.b))
        glow:SetKeyValue("scale", "0.12")
        glow:SetKeyValue("spawnflags", "1")
        glow:SetPos(self:GetPos())
        glow:SetParent(self)
        glow:Spawn()
        glow:Activate()
        self.CE8NeedleGlow = glow
        self:DeleteOnRemove(glow)
    end
end

function ENT:CE8StopNeedleFX()
    if IsValid(self.CE8NeedleTrail) then self.CE8NeedleTrail:Remove() end
    if IsValid(self.CE8NeedleGlow) then self.CE8NeedleGlow:Remove() end
    self.CE8NeedleTrail, self.CE8NeedleGlow = nil, nil
end

function ENT:CE8GrenadeSound(kind)
    local cues = self.CE8Data.sounds
    for _, choices in ipairs(cues and cues[kind] or {}) do
        if #choices > 0 then
            self:EmitSound(choices[math.random(#choices)], kind == "explode" and 100 or 70, 100, 1, CHAN_AUTO)
        end
    end
end

function ENT:CE8AdvanceVelocity(velocity, dt)
    local flight = self.CE8Data.flight
    if not flight then return velocity end
    local position = self:GetPos()
    local distance = self.CE8TravelDistance or 0
    if self.CE8TravelPosition then
        local delta = position - self.CE8TravelPosition
        local length = delta:Length()
        if flight.range and distance < flight.range and distance + length >= flight.range then
            self.CE8RangePoint = self.CE8TravelPosition + delta * ((flight.range - distance) / length)
        end
        distance = distance + length
    end
    self.CE8TravelDistance, self.CE8TravelPosition = distance, position
    if not dt then return velocity end
    self.CE8Flight = self.CE8Flight or ballistics.State(self.CE8Data, 1, "normal", false, nil, self:GetForward())
    return ballistics.Advance(self.CE8Data, self.CE8Flight, velocity, dt)
end

function ENT:OnCollision(collision, physics)
    if self.CE8NeedlePending or self.CE8NeedleTarget then return true end
    if not self.CE8Data.grenade and not self.CE8RicochetPending and self.CE8Sounds then
        effects.ProjectileFlyby(self, collision.HitPos)
        -- Capture shielding before VJ applies the damage that may break it.
        self.CE8AudioContact = effects.ContactSurface(collision)
    end
    if self.CE8Data.needle then
        local target = collision.HitEntity
        if IsValid(target) and (target:IsNPC() or target:IsPlayer() or target:IsNextBot()) and
            target ~= self:GetOwner() and
            target:Health() > 0 and (target.CE8Shield or 0) <= 0 and
            not (target:IsPlayer() and target:Armor() > 0) then
            self.CE8NeedlePending = target
            self.CE8NeedleHealth = target:Health()
            self.CollisionBehavior = VJ.PROJ_COLLISION_PERSIST
            return -- VJ deals the impact once, then defers OnCollisionPersist.
        end
    end
    if self.CE8Data.grenade then
        if self.CE8StuckTo or self.CE8GrenadePending then return true end
        self.CE8ContactAt = CurTime()
        local target = collision.HitEntity
        if IsValid(target) and (target:IsNPC() or target:IsPlayer() or target:IsNextBot()
            or target:IsVehicle() or target:GetClass() == "prop_ragdoll") and target ~= self:GetOwner() then
            self.CE8GrenadePending = true
            local position = Vector(collision.HitPos)
            -- Parenting/solid changes must happen outside the VPhysics callback.
            timer.Simple(0, function()
                if not IsValid(self) or self.Dead then return end
                self.CE8GrenadePending = nil
                if not IsValid(target) then return end
                local object = self:GetPhysicsObject()
                if IsValid(object) then object:EnableMotion(false) end
                self:SetMoveType(MOVETYPE_NONE)
                self:SetSolid(SOLID_NONE)
                self:SetParent(target)
                self:SetPos(position)
                self.CE8StuckTo = target
                self.CE8DetonateAt = math.max(self.CE8ArmedAt,
                    CurTime() + math.Rand(self.CE8Data.fuse[1], self.CE8Data.fuse[2]))
                self:CE8GrenadeSound("arm")
                local blast = self.CE8Data.attached_explosion
                self.RadiusDamage = math.Rand(blast.amount[1], blast.amount[2])
                self.RadiusDamageRadius = blast.radius[2]
                -- A short fuse can expire before VJ's next danger scan. Notify
                -- only after attachment succeeds, outside the physics callback.
                if target.IsCE8Elite and target.OnDangerDetected then
                    target:OnDangerDetected(VJ.DANGER_TYPE_GRENADE, self)
                end
            end)
        else
            if CurTime() >= (self.CE8NextBounceSound or 0) and collision.OurOldVelocity
                and collision.OurOldVelocity:LengthSqr() > 1600 then
                self:CE8GrenadeSound("bounce")
                self.CE8NextBounceSound = CurTime() + 0.1
            end
            if self.CE8RicochetPending or not IsValid(physics) then return true end
            local response = self.CE8Data.bounce
            local normal, incoming = collision.HitNormal, collision.OurOldVelocity
            if not response or not incoming or not normal or normal:LengthSqr() == 0 then return true end
            local surfaceVelocity = collision.TheirOldVelocity or Vector(0, 0, 0)
            incoming = incoming - surfaceVelocity
            local speed = incoming:Length()
            if speed == 0 then return true end
            normal = normal:GetNormalized()
            local approach = incoming:Dot(normal)
            if approach > 0 then return true end
            -- Native response loses tangent and normal velocity independently.
            -- Work relative to the contacted surface, then restore its motion.
            local normalVelocity = normal * approach
            local reflected = (incoming - normalVelocity) * (1 - response.parallel_friction)
                - normalVelocity * (1 - response.perpendicular_friction) + surfaceVelocity
            self.CE8RicochetPending = true
            timer.Simple(0, function()
                if not IsValid(self) or self.Dead then return end
                self.CE8RicochetPending = nil
                if self.CE8GrenadePending or self.CE8StuckTo then return end
                local object = self:GetPhysicsObject()
                if not IsValid(object) then return end
                -- Keep the mesh's resolved position and let unit attachment
                -- supersede this bounce if both contacts occurred this tick.
                object:Wake()
                object:SetVelocityInstantaneous(reflected)
            end)
        end
        return true -- World contacts bounce/settle, never detonate on impact.
    end
    if self.CE8RicochetPending then return true end
    local response = self.CE8Data.ricochet
    if not response or not IsValid(physics) then return end
    local hit = collision.HitEntity
    local unit = IsValid(hit) and (hit:IsPlayer() or hit:IsNPC() or hit:IsNextBot()
        or hit:IsVehicle() or hit:GetClass() == "prop_ragdoll")
    if (response.never_units and unit) or (response.only_units and not unit) then return end
    local incoming, normal = collision.OurOldVelocity, collision.HitNormal
    if not incoming or not normal or normal:LengthSqr() == 0 then return end
    incoming = self:CE8AdvanceVelocity(incoming)
    local speed = incoming:Length()
    if speed == 0 or speed < response.speed[1] or speed > response.speed[2] then return end
    normal = normal:GetNormalized()
    local approach = incoming:Dot(normal)
    if approach > 0 then return end
    -- Halo's angle is measured from the surface plane: 0 = grazing, 90 = head-on.
    local angle = math.deg(math.asin(math.Clamp(-approach / speed, 0, 1)))
    if angle < response.angle_degrees[1] or angle > response.angle_degrees[2] then return end
    if response.chance < 1 and math.Rand(0, 1) >= response.chance then return end
    local reflected = incoming - normal * (2 * approach)
    local position = collision.HitPos + normal * (self.CE8CollisionRadius + 0.01)
    effects.ContactSound(self.CE8Sounds, collision, self.CE8AudioContact, "ricochet", self.CE8ChargedShot == true)
    self.CE8AudioContact = nil
    self.CE8BounceCount = (self.CE8BounceCount or 0) + 1
    self.CE8RicochetPending = true
    -- Apply after VPhysics finishes its collision callback, so its material
    -- solver cannot replace the native reflection or change collision rules.
    timer.Simple(0, function()
        if not IsValid(self) or self.Dead then return end
        local object = self:GetPhysicsObject()
        if not IsValid(object) then self.CE8RicochetPending = nil return end
        self:SetPos(position)
        self:SetAngles(reflected:Angle())
        if self.CE8Flight then self.CE8Flight.forward = reflected:GetNormalized() end
        self.CE8TravelPosition = position -- separation is not extra flight distance
        if self.CE8AudioPosition then self.CE8AudioPosition = Vector(position) end
        object:Wake()
        object:SetVelocityInstantaneous(reflected)
        self.CE8RicochetPending = nil
    end)
    -- VJ retains its normal damage, explosion and removal path for every
    -- rejected bounce. A successful ricochet does none of those things.
    return true
end

function ENT:CE8ImpactSound(collision)
    if not self.CE8AudioContact or self.CE8ImpactSoundPlayed then return end
    self.CE8ImpactSoundPlayed = true
    effects.ContactSound(self.CE8Sounds, collision, self.CE8AudioContact, "impact", self.CE8ChargedShot == true)
end

function ENT:OnDealDamage(collision, physics, hitEntities)
    self:CE8ImpactSound(collision)
    local target = self.CE8NeedlePending
    if not IsValid(target) or not hitEntities then return end
    for _, hit in ipairs(hitEntities) do
        if hit == target and target:Health() < self.CE8NeedleHealth then
            self.CE8NeedleAccepted = true
            return
        end
    end
end

function ENT:OnCollisionPersist(collision, physics)
    if self.Dead then return end
    local accepted = self.CE8NeedleAccepted
    self.CE8NeedlePending = nil
    self.CE8NeedleAccepted = nil
    self.CE8NeedleHealth = nil
    if not accepted or not self:CE8EmbedNeedle(collision.HitEntity, collision) then
        self:Destroy(collision, physics)
    end
end

function ENT:CE8EmbedNeedle(target, hit)
    if self.Dead or self.CE8NeedleTarget or not self.CE8Data.needle or not IsValid(target)
        or target == self:GetOwner() or target:Health() <= 0 or (target.CE8Shield or 0) > 0
        or (target:IsPlayer() and target:Armor() > 0) then return false end
    if not (target:IsNPC() or target:IsPlayer() or target:IsNextBot()) then return false end
    local direction = hit.OurOldVelocity or hit.Normal or self:GetForward()
    if direction:LengthSqr() == 0 then direction = self:GetForward() end
    direction = direction:GetNormalized()
    -- Physics contacts can contain only a hull hit. Resolve its actual hitbox
    -- along the incoming path; never pick a nearby bone by distance.
    if hit.HitBox == nil then
        local trace = util.TraceLine({start = hit.HitPos - direction * (target:BoundingRadius() * 2 + 8),
            endpos = hit.HitPos + direction * 8, mask = MASK_SHOT,
            filter = function(entity) return entity == target end})
        if trace.Entity == target then hit = trace end
    end
    local bone = hit.HitBox ~= nil and target:GetHitBoxBone(hit.HitBox, hit.HitBoxSet or 0)
    local matrix = bone and bone >= 0 and target:GetBoneParent(bone) >= 0 and
        target:BoneHasFlag(bone, BONE_USED_BY_VERTEX_LOD0) and target:GetBoneMatrix(bone)
    local position, angles = hit.HitPos, direction:Angle()
    local basePos, baseAng = target:GetPos(), target:GetAngles()
    if matrix then basePos, baseAng = matrix:GetTranslation(), matrix:GetAngles() end
    local localPos, localAng = WorldToLocal(position, angles, basePos, baseAng)
    local physics = self:GetPhysicsObject()
    if IsValid(physics) then physics:EnableMotion(false) end
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetTrigger(false)
    self.CollisionBehavior = VJ.PROJ_COLLISION_NONE
    self.DoesDirectDamage = false
    self.DoesRadiusDamage = false
    self.VJ_ID_Danger = false
    self:CE8StopNeedleFX()
    self:StopParticles()
    if matrix then self:FollowBone(target, bone) else self:SetParent(target) end
    self:SetLocalPos(localPos)
    self:SetLocalAngles(localAng)
    self.CE8NeedleTarget = target
    local now = CurTime()
    self.CE8Expires = now + self.CE8Data.needle.lifetime
    -- A shot already in flight during Lua refresh retains its old data table.
    -- Let that shot finish its original attachment lifetime without inventing
    -- missing settings or resetting active projectiles during the reload.
    if not self.CE8Data.needle.blast then return true end
    self.CE8SuperReadyAt = now + self.CE8Data.needle.delay
    target.CE8Needles = target.CE8Needles or {}
    local key = self.CE8Data.needle.group
    local group = target.CE8Needles[key] or {members = {}}
    target.CE8Needles[key] = group
    -- CE refreshes older matching attachments' ordinary expiry, up to the
    -- native count threshold. Their supercombine eligibility keeps its age.
    -- Expired Source entities may await Think; never bring them back to life.
    local refreshed = 0
    for needle in pairs(group.members) do
        local data = IsValid(needle) and needle.CE8Data and needle.CE8Data.needle
        if data and data.group == key and not needle.Dead and
            needle.CE8NeedleTarget == target and needle.CE8Expires > now then
            needle.CE8Expires = now + data.lifetime
            refreshed = refreshed + 1
            if refreshed >= self.CE8Data.needle.count then break end
        end
    end
    group.members[self] = true
    group.checked = nil
    self.CE8NeedleGroup = group
    return true
end

function ENT:CE8CheckNeedles(now)
    local target, group = self.CE8NeedleTarget, self.CE8NeedleGroup
    if not group or group.checked == now then return end
    group.checked = now -- One small target-local scan per tick, not per needle.
    local members, center, trigger = {}, Vector(), nil
    for needle in pairs(group.members) do
        if not IsValid(needle) or needle.Dead or needle.CE8NeedleTarget ~= target then
            group.members[needle] = nil
        elseif now >= needle.CE8Expires then
            needle:Remove()
        else
            members[#members + 1] = needle
            center = center + needle:GetPos()
            if now >= needle.CE8SuperReadyAt and
                (not trigger or needle.CE8SuperReadyAt < trigger.CE8SuperReadyAt) then trigger = needle end
        end
    end
    if #members < self.CE8Data.needle.count or not trigger then return end
    center = center / #members
    -- Consume the whole group before any damage callback can remove the host,
    -- its children, or re-enter a projectile's Think. Other types stay separate.
    target.CE8Needles[self.CE8Data.needle.group] = nil
    if not next(target.CE8Needles) then target.CE8Needles = nil end
    for _, needle in ipairs(members) do
        needle.Dead = true
        needle.CE8NeedleGroup = nil
        needle.CE8NeedleTarget = nil
    end
    group.members = {}
    trigger:SetParent(NULL)
    trigger:SetPos(center)
    for _, needle in ipairs(members) do if needle ~= trigger then needle:Remove() end end
    trigger:CE8Supercombine(center, target)
end

function ENT:CE8Supercombine(position, host)
    if self.CE8Combined then return end
    self.CE8Combined = true
    local blast = self.CE8Data.needle.blast
    local maximum = math.Rand(blast.amount[1], blast.amount[2])
    self.DoesDirectDamage = true
    self.DirectDamageType = DMG_BLAST
    -- VJ's radius helper cannot set this curve or a per-recipient damage value.
    -- Keep its existing DealDamage path for filtering, attribution and special
    -- entities; only the radius, obstruction test and falloff are CE8-specific.
    for _, recipient in ipairs(ents.FindInSphere(position, blast.radius)) do
        if not IsValid(self) then return end
        if IsValid(recipient) and recipient ~= self and not recipient.CE8NeedleTarget then
            local nearest = recipient:NearestPoint(position)
            local distance = position:Distance(nearest)
            if distance <= blast.radius then
                local trace = util.TraceLine({start = position, endpos = nearest,
                    mask = MASK_SHOT, filter = {self, host}})
                if recipient == host or not trace.Hit or trace.Entity == recipient then
                    local taper = math.Clamp((blast.radius - distance) / (blast.radius - blast.core), 0, 1)
                    self.DirectDamage = (blast.minimum + (maximum - blast.minimum) *
                        taper ^ blast.falloff_power) * self.CE8BurstScale
                    self:DealDamage({HitEntity = recipient, HitPos = nearest}, self:GetPhysicsObject())
                end
            end
        end
    end
    if not IsValid(self) then return end
    self.DoesDirectDamage = false
    self:Destroy({HitPos = position, HitNormal = Vector(0, 0, 1)}, self:GetPhysicsObject())
end

function ENT:OnDestroy(collision)
    if self.CE8Combined then
        effects.Supercombine(self.CE8Data, collision.HitPos)
        for _, choices in ipairs(self.CE8Data.needle.sounds or {}) do
            if #choices > 0 then self:EmitSound(choices[math.random(#choices)], 100, 100, 1, CHAN_AUTO) end
        end
        return
    end
    self:CE8ImpactSound(collision)
    local contact = self.CE8Sounds and self.CE8Sounds.contact
    if contact and contact.detonate and collision and collision.HitPos then
        effects.Sound(contact.detonate, collision.HitPos, 100)
    end
    effects.Impact(self, self.CE8Data, self.CE8ChargedShot == true, collision)
    if self.CE8Data.grenade then self:CE8GrenadeSound("explode") end
end

function ENT:CustomOnRemove()
    self:CE8StopNeedleFX()
    -- VJ stops particles on collision; expiry and external removal also have
    -- to stop the continuous flight emitters.
    self:StopParticles()
    local target, group = self.CE8NeedleTarget, self.CE8NeedleGroup
    if group then
        group.members[self] = nil
        if not next(group.members) and IsValid(target) and target.CE8Needles then
            local key = self.CE8Data.needle.group
            if target.CE8Needles[key] == group then target.CE8Needles[key] = nil end
            if not next(target.CE8Needles) then target.CE8Needles = nil end
        end
    end
    self.CE8NeedleTarget, self.CE8NeedleGroup = nil, nil
end

function ENT:PhysicsUpdate(physics)
    if self.Dead or self.CE8RicochetPending or self.CE8GrenadePending or self.CE8StuckTo
        or self.CE8NeedlePending or self.CE8NeedleTarget then return end
    local data = self.CE8Data
    if not data then return end
    local dt = engine.TickInterval()
    if data.flight then
        self.CE8Flight = self.CE8Flight or ballistics.State(data, 1, "normal", false, nil, self:GetForward())
        local velocity = physics:GetVelocity()
        local target = self.CE8Target
        -- VJ's captured attack target supplies the Source entity. A stale/dead
        -- target leaves the shot ballistic; never reacquire another victim.
        if data.flight.guidance and IsValid(target) and target:Health() > 0
            and (target:IsNPC() or target:IsPlayer() or target:IsNextBot()) then
            velocity = ballistics.Steer(data, self.CE8Flight, self:GetPos(), velocity,
                target:WorldSpaceCenter(), VJ.GetMoveVelocity(target), target:IsPlayer(), dt)
        end
        velocity = self:CE8AdvanceVelocity(velocity, dt)
        effects.ProjectileFlyby(self, self.CE8RangePoint or self:GetPos())
        local final = velocity + physenv.GetGravity() * data.gravity * dt
        if data.flight.orient and final:LengthSqr() > 0 then
            self.CE8Flight.forward = final:GetNormalized()
            -- Rotate the simulated body, not the entity's previous transform.
            -- SetAngles on the entity here can rewind the completed physics step.
            physics:SetAngles(final:Angle())
        end
        physics:SetVelocityInstantaneous(velocity)
    end
    if data.gravity > 0 then
        -- ApplyForceCenter takes an impulse (mass * acceleration * seconds),
        -- not acceleration. Apply once per physics tick, independent of FPS.
        physics:ApplyForceCenter(physenv.GetGravity() * data.gravity * physics:GetMass() * dt)
    end
end

function ENT:OnThink()
    if self.Dead then return end
    if CurTime() >= self.CE8Expires then self:Remove() return end
    if self.CE8NeedleTarget then
        if not IsValid(self.CE8NeedleTarget) or self.CE8NeedleTarget:Health() <= 0 then self:Remove()
        else self:CE8CheckNeedles(CurTime()) end
        return
    end
    if self.CE8RicochetPending then return end
    local physics = self:GetPhysicsObject()
    if not IsValid(physics) then return end
    if self.CE8Data.grenade then
        local now = CurTime()
        if not self.CE8DetonateAt and (physics:IsAsleep() or
            (now - (self.CE8ContactAt or -1) < 0.2 and physics:GetVelocity():LengthSqr() < 256)) then
            self.CE8DetonateAt = math.max(self.CE8ArmedAt,
                now + math.Rand(self.CE8Data.fuse[1], self.CE8Data.fuse[2]))
            self:CE8GrenadeSound("arm")
        end
        if self.CE8DetonateAt and now >= self.CE8DetonateAt then
            local collision = {HitPos = self:GetPos(), HitNormal = Vector(0, 0, 1),
                HitEntity = IsValid(self.CE8StuckTo) and self.CE8StuckTo or game.GetWorld()}
            self.Dead = true
            self:DealDamage(collision, physics)
            self:Destroy(collision, physics)
        end
        return
    end
    if self.CE8Data.flight then
        self:CE8AdvanceVelocity(physics:GetVelocity())
        if self.CE8RangePoint then
            self:SetPos(self.CE8RangePoint)
            if self.CE8Data.explosion then
                local collision = {HitPos = self.CE8RangePoint, HitNormal = Vector(0, 0, 1),
                    HitEntity = game.GetWorld()}
                self.Dead = true
                self:DealDamage(collision, physics)
                self:Destroy(collision, physics)
            else
                self:Remove()
            end
        end
    end
end
