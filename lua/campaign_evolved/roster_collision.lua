-- Roster policy on PRP's shared collision implementation; no per-frame work.
local R = {}
local owners = {elite=true, grunt=true, brute=true, flood_tank=true,
    flood_combat_human=true, flood_combat_elite=true, flood_carrier=true, flood_infection=true}

function R.Shared(ENT, owner)
    if not owners[owner] then return end
    local path = "campaign_evolved/" .. owner .. "_colliders.lua"
    if SERVER then AddCSLuaFile("campaign_evolved/roster_collision.lua") AddCSLuaFile(path) end
    ENT.ColliderFile = "npc_vj_ce8_" .. owner .. "_collision.json"
    ENT.ColliderBodies = include(path)
    -- Include flight between the carrier's 10 Hz position updates, while
    -- keeping swarm broad-phase bounds smaller than the Hunter defaults.
    if owner == "flood_infection" then
        ENT.ColliderBounds = {Vector(-96,-96,-96),Vector(96,96,144)}
    end
end

function R.Attach(ENT, owner)
    if not owners[owner] then return end
    local C = include("prp/colliders.lua")
    local init, death, remove, damaged = ENT.Init, ENT.OnDeath, ENT.CustomOnRemove, ENT.OnDamaged
    function ENT:Init(...)
        init(self, ...)
        C.Equip(self)
    end
    function ENT:OnDeath(damage, hitgroup, status)
        if status == "Init" then C.Remove(self) end
        return death(self, damage, hitgroup, status)
    end
    function ENT:CustomOnRemove(...)
        C.Remove(self)
        return remove(self, ...)
    end
    function ENT:OnDamaged(damage, hitgroup, status)
        if status == "Init" and not self.Dead and not self.GodMode and damage:GetDamage()>0
            and not C.IsForwarded(self,damage)
            and (damage:IsDamageType(DMG_BULLET) or damage:IsDamageType(DMG_BLAST)) then
            -- Proxy bullets already carry a precise trace. Radius damage visits
            -- the owner once; resolve one exposed surface for anatomical damage.
            local hit = CE8.Collision.DamageContact(self,damage)
            if hit then
                damage:ScaleDamage(hit.damage_scale or 1)
                local direction = damage:GetDamageForce():GetNormalized()
                local trace = C.TraceRecord(self,hit,direction)
                trace.ColliderScaled = true
                if self.OnTraceAttack then self:OnTraceAttack(damage,direction,trace) end
                self:SetSaveValue("m_LastHitGroup",hit.hitgroup)
                hitgroup = hit.hitgroup
            end
        end
        return damaged(self,damage,hitgroup,status)
    end
end
return R
