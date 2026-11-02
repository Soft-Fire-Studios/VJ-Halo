-- Jackal policy on PRP's shared rigid groups. No attached shield render model.
local J={}

function J.ShieldProxy(entity)
    if not IsValid(entity) or not entity.IsPRPCollider then return false end
    local actor=entity:GetOwner()
    return IsValid(actor) and actor.CE8UnitLabel=="jackal"
        and (entity.ColliderSurface or entity:GetNW2String("prp_surface"))=="default_silent"
end

-- MW fires penetration continuations inside its impact callback. Preserve its
-- damage/effects, absorbing only nested shots from an actual shield contact.
local absorbing={}
hook.Add("EntityFireBullets","CE8BarrierMW",function(shooter,bullet)
    if absorbing[shooter] then return false end
    if not bullet.Callback or not shooter.GetActiveWeapon then return end
    local weapon=shooter:GetActiveWeapon()
    if not IsValid(weapon) or not weapons.IsBasedOn(weapon:GetClass(),"mg_base") then return end
    if bullet.CE8BarrierCallback==bullet.Callback then return true end
    local callback=bullet.Callback
    bullet.Callback=function(attacker,trace,damage)
        if not J.ShieldProxy(trace.Entity) and not (IsValid(trace.Entity) and trace.Entity.IsCE8Barrier) then
            return callback(attacker,trace,damage)
        end
        local previous=absorbing[shooter];absorbing[shooter]=true
        local ok,result=pcall(callback,attacker,trace,damage)
        absorbing[shooter]=previous
        if not ok then error(result,0) end
        return result
    end
    bullet.CE8BarrierCallback=bullet.Callback
    return true
end)

function J.SetBarrier(actor,value)
    if not IsValid(actor) then return end
    local id=actor:FindBodygroupByName("barrier")
    -- OnRemove can retain the Lua entity after its studio data is unavailable.
    if id==nil or id<0 then return end
    local current=actor:GetBodygroup(id)
    if current~=nil and current~=value then actor:SetBodygroup(id,value) end
end

if CLIENT then return J end
function J.Update(actor)
    local C=include("prp/colliders.lua")
    C.Equip(actor)
    local rank,weapon=actor:CE8RankSettings(),actor:GetActiveWeapon()
    local equipped=rank.shield_model and IsValid(weapon)
        and (weapon.CE8WeaponName=="plasma_pistol" or weapon.CE8WeaponName=="needler")
    local variant=rank.bodygroups.emitter or 1
    local emitter=actor:FindBodygroupByName("emitter")
    if emitter and emitter>=0 then actor:SetBodygroup(emitter,equipped and variant or 0) end
    J.SetBarrier(actor,equipped and not actor.CE8BarrierDown and (actor.CE8BarrierMax or 0)>0 and variant or 0)
end

function J.Attach(ENT)
    local initialize,damaged=ENT.Init,ENT.OnDamaged
    function ENT:Init()
        initialize(self)
        self:CE8UpdateEquipment()
    end
    function ENT:OnTraceAttack(damage,direction,trace)
        if trace.ColliderRegion=="shield" and not self.GodMode then
            CE8.Barrier.DamageActor(self,damage,trace.HitGroup)
        end
    end
    function ENT:OnDamaged(damage,hitgroup,status)
        -- PRP dispatches body hits normally. Direct radius damage is evaluated
        -- once on the actor; surface carriers never multiply an explosion.
        if status=="Init" and not self.Dead and not self.GodMode and damage:GetDamage()>0
            and not include("prp/colliders.lua").IsForwarded(self,damage) then
            local hit=CE8.Collision.DamageContact(self,damage)
            if hit then
                if hit.region=="shield" then CE8.Barrier.DamageActor(self,damage,hit.hitgroup)
                elseif not damage:IsDamageType(DMG_BLAST) then
                    damage:ScaleDamage(hit.damage_scale or 1)
                    self:SetSaveValue("m_LastHitGroup",hit.hitgroup)
                end
            elseif damage:IsDamageType(DMG_BULLET) or damage:IsDamageType(DMG_BLAST) then
                damage:SetDamage(0)
            end
        end
        return damaged(self,damage,hitgroup,status)
    end
end
return J
