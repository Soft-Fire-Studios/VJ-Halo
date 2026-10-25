-- Jackal resource bindings for the shared shield service and collision helper.
if CLIENT then return end
CE8 = CE8 or {}
local B = {}
CE8.Barrier = B
CE8.Barriers = CE8.Barriers or {}
local collision = include("vj_ai/barrier.lua")
local difficulty = include("campaign_evolved/difficulty.lua")
local mesh
local function triangles()
    if not mesh then mesh = collision.Prepare(include("campaign_evolved/jackal_barrier.lua")) end
    return mesh
end

function B.ApplyStats(actor, initialize)
    local maximum = (actor:CE8RankSettings().native_shield or 0) * difficulty.Multiplier("shield")
    local old = actor.CE8BarrierMax or maximum
    local fraction = old > 0 and math.Clamp((actor.AIShield or old) / old, 0, 1) or 0
    actor.CE8BarrierMax = maximum
    if initialize or actor.AIShield == nil then
        actor.CE8BarrierDown = false
    else
        actor.AIShield = maximum * fraction
        -- Restoring a disabled shield must recharge it, not create free capacity.
        if maximum > 0 and actor.AIShield <= 0 then actor.CE8BarrierDown = true end
    end
    actor:SetNW2Float("ce8_barrier_max", maximum)
    actor:SetNW2Float("ce8_barrier_value", actor.AIShield or maximum)
    actor:SetNW2Bool("ce8_barrier_down", actor.CE8BarrierDown == true or maximum <= 0)
end

function B.Profile(sounds)
    local fx = include("campaign_evolved/weapon_fx.lua")
    local impact = include("campaign_evolved/sounds/needle_rifle.lua").contact.impact.shield_jackal.children[1]
    return {
        maximum = function(self) return self.CE8BarrierMax or 0 end,
        recharge_delay = function(self) return self:CE8RankSettings().recharge_delay end,
        recharge_time = function(self) return self:CE8RankSettings().recharge_time end,
        resistance = function() return difficulty.Multiplier("shield_resistance") end,
        network = {value = "ce8_barrier_value", maximum = "ce8_barrier_max", hit = "ce8_barrier_hit"},
        accept_damage = function(self) return B.Active(self.CE8Barrier) end,
        depleted = function(self, damage, now)
            self.CE8BarrierDown = true
            self:SetNW2Bool("ce8_barrier_down", true)
            self.CE8FleeRequest = {reason = "shield_lost", time = now}
        end,
        regenerated = function(self, now)
            if self.CE8BarrierDown and self.AIShield >= self.CE8BarrierMax then
                self.CE8BarrierDown = false
                self:SetNW2Bool("ce8_barrier_down", false)
                self:SetNW2Float("ce8_barrier_restored", now)
            end
        end,
        sound = function(self, kind)
            if self.HasSounds == false then return end
            local prop = self.CE8ShieldProp
            local pos = IsValid(prop) and prop:GetPos() or self:WorldSpaceCenter()
            if kind == "impact" then fx.Sound(impact, pos, 75)
            elseif kind == "pop" then fx.Sound(sounds.effects.jackal_shield_death, pos, 80) end
        end,
        after_damage = function(self, damage, hitgroup, now)
            local disabled = GetConVar("ai_disabled")
            if (disabled and disabled:GetBool()) or self.VJ_Controlled or self:GetState() == VJ_STATE_FREEZE then return end
            local attacker = damage:GetAttacker()
            if IsValid(attacker) and attacker ~= self and (attacker:IsNPC() or attacker:IsPlayer() or attacker:IsNextBot()) then
                local disposition = self:CheckRelationship(attacker)
                if disposition == D_HT or disposition == D_NU then
                    self:UpdateEnemyMemory(attacker, attacker:GetPos())
                    self:MarkTookDamageFromEnemy(attacker)
                    local enemy = self:GetEnemy()
                    if not IsValid(enemy) or enemy == attacker or enemy:Health() <= 0 then self:ForceSetEnemy(attacker, false) end
                end
            end
            if self.CanFlinch then self:Flinch(damage, hitgroup) end
        end
    }
end

function B.Active(entity)
    if not IsValid(entity) then return false end
    local actor = entity:GetOwner()
    return IsValid(actor) and not actor.Dead and actor:Health() > 0
        and actor:AIHasCapability("shield") and IsValid(actor.CE8ShieldProp)
        and not actor.CE8BarrierDown and (actor.AIShield or 0) > 0
end

function B.Trace(entity, start, delta)
    if not B.Active(entity) then return end
    local actor = entity:GetOwner()
    local attachment = actor:GetAttachment(actor:LookupAttachment("shield"))
    if not attachment then return end
    local localStart = WorldToLocal(start, angle_zero, attachment.Pos, attachment.Ang)
    local localEnd = WorldToLocal(start + delta, angle_zero, attachment.Pos, attachment.Ang)
    local direction = localEnd - localStart
    -- The emitter faces local +X. Do not intercept its owner's outgoing shots.
    if direction.x >= -0.00001 then return end
    local fraction, normal = collision.Trace(triangles(), localStart, direction)
    if not fraction then return end
    normal = Vector(normal)
    normal:Rotate(attachment.Ang)
    return {Fraction = fraction, HitPos = start + delta * fraction, Normal = normal}
end

function B.Damage(entity, damage)
    if not B.Active(entity) then return end
    local actor, attacker = entity:GetOwner(), damage:GetAttacker()
    if attacker == actor then return end
    if IsValid(attacker) and attacker:IsNPC() and attacker:Disposition(actor) == D_LI then return end
    actor:AIShieldDamage(damage, HITGROUP_LEFTARM, CurTime())
    -- This hit touched the barrier, which may lie outside the body. Never send
    -- overflow damage to the actor without a second body intersection.
    damage:SetDamage(0)
end

-- Physical CE8 shots also sweep the small native mesh. This catches fast shots
-- independently of VPhysics/anim-entity contact support; no global Think hook.
function B.ProjectileHit(projectile, start, finish)
    if not start or not next(CE8.Barriers) then return end
    local nearest, target
    for entity in pairs(CE8.Barriers) do
        if not IsValid(entity) then CE8.Barriers[entity] = nil
        elseif entity:GetOwner() ~= projectile:GetOwner() then
            local hit = B.Trace(entity, start, finish - start)
            if hit and (not nearest or hit.Fraction < nearest.Fraction) then nearest, target = hit, entity end
        end
    end
    if not nearest then return end
    -- Walls and ordinary props still win if they occur before the barrier.
    local obstruction = util.TraceLine({start = start, endpos = nearest.HitPos,
        mask = MASK_SHOT, filter = function(ent) return ent ~= projectile and ent ~= projectile:GetOwner() and not ent.IsCE8Barrier end})
    if obstruction.Hit and obstruction.Fraction < 0.999 then return end
    return {HitEntity = target, HitPos = nearest.HitPos, HitNormal = nearest.Normal,
        TheirSurfaceProps = util.GetSurfaceIndex("default_silent"), TheirOldVelocity = vector_origin,
        DeltaTime = engine.TickInterval(), CE8BarrierHit = true}
end

function B.Sweep(projectile, physics)
    local finish = projectile:GetPos()
    local start = projectile.CE8BarrierPosition or finish
    projectile.CE8BarrierPosition = Vector(finish)
    if projectile.CE8Data.grenade then return false end
    local hit = B.ProjectileHit(projectile, start, finish)
    if not hit then return false end
    hit.OurOldVelocity = physics:GetVelocity()
    hit.Speed, hit.HitSpeed = hit.OurOldVelocity:Length(), hit.OurOldVelocity:Length()
    projectile.CE8BarrierPending = true
    timer.Simple(0, function()
        if not IsValid(projectile) or projectile.Dead then return end
        projectile.CE8BarrierPending = nil
        if not IsValid(hit.HitEntity) then return end
        projectile:SetPos(hit.HitPos)
        projectile:PhysicsCollide(hit, physics)
    end)
    return true
end

function B.Redirect(projectile, contact)
    if projectile.CE8Data.grenade or contact.CE8BarrierHit or (IsValid(contact.HitEntity) and contact.HitEntity.IsCE8Barrier) then return end
    local hit = B.ProjectileHit(projectile, projectile.CE8BarrierPosition, contact.HitPos)
    if hit then
        contact.HitEntity, contact.HitPos, contact.HitNormal = hit.HitEntity, hit.HitPos, hit.HitNormal
        contact.TheirSurfaceProps = hit.TheirSurfaceProps
        contact.SurfaceProps = hit.TheirSurfaceProps
        contact.CE8BarrierHit = true
    end
end

return B
