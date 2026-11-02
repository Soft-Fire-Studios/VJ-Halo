-- Halo damage-origin adaptation; geometry, proxies and hit dispatch belong to PRP.
CE8=CE8 or {}
local core=include("prp/colliders.lua")
local C=setmetatable({}, {__index=core})
CE8.Collision=C
C.Model="models/campaign_evolved/ce8/material_sets/hunter.mdl"
local definition=core.Definition("npc_vj_ce8_hunter_collision.json",include("campaign_evolved/hunter_colliders.lua"))
C.Shapes=definition and definition.shapes or {}
function C.DamageContact(actor,damage)
    local position=damage:GetDamagePosition()
    if damage:IsDamageType(DMG_BLAST) then
        local inflictor=damage:GetInflictor()
        local reported=damage:GetReportedPosition()
        -- VJ writes the victim's nearest point into DamagePosition. Our shots
        -- expose the actual blast center during DealDamage; ordinary projectile
        -- entities and Source's reported blast position supply the other cases.
        if IsValid(inflictor) and inflictor.CE8BlastOrigin then position=inflictor.CE8BlastOrigin
        elseif reported~=vector_origin then position=reported
        elseif IsValid(inflictor) and inflictor~=actor and not inflictor:IsWorld()
            and not inflictor:IsPlayer() and not inflictor:IsWeapon() then position=inflictor:GetPos() end
        return C.BlastContact(actor,position,inflictor)
    end
    local direction=damage:GetDamageForce()
    if direction:LengthSqr()>.00001 then
        direction=direction:GetNormalized()
        return C.Trace(actor,nil,position-direction*8,direction*16,false)
    end
    -- Unlocated/scripted damage must not bypass the armor or reuse a stale hit.
end


if SERVER then
    hook.Add("ShouldCollide","CE8CollisionShots",function(a,b)
        local actor,shot
        if a.ColliderParts then actor,shot=a,b elseif b.ColliderParts then actor,shot=b,a end
        if actor and shot:GetClass()=="obj_ce8_projectile" and shot.CE8Data and not shot.CE8Data.grenade then return false end
    end)
    function C.Equip(actor)
        for _,part in pairs(actor.CE8ArmorParts or {}) do if IsValid(part) then part:Remove() end end
        actor.CE8ArmorParts=nil
        return core.Equip(actor)
    end
end
return C
