if SERVER then AddCSLuaFile() end
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "CE8 attached armor"
ENT.Spawnable = false
ENT.DisableDuplicator = true
ENT.PhysgunDisabled = true
ENT.VJ_ID_Grabbable = false

function ENT:PhysgunPickup() return false end
function ENT:GravGunPickupAllowed() return false end

local frames = {}
if CLIENT then
    for _, pieces in pairs(include("campaign_evolved/armor_parts.lua")) do
        for _, piece in pairs(pieces) do
            frames[piece.model] = {attachment = piece.attachment, bone = piece.bone,
                pose_attachment = piece.pose_attachment}
        end
    end
end

function ENT:CE8AttachmentFrame()
    local actor = self:GetOwner()
    if not IsValid(actor) then return end
    local definition = CLIENT and frames[self:GetModel()]
    local socket = self.CE8Socket or definition and definition.attachment
    if socket then
        local index = actor:LookupAttachment(socket)
        return index > 0 and actor:GetAttachment(index) or nil
    end
    local bone = self.CE8Bone or definition and definition.bone
    if not bone then return end
    -- Hunter parts can draw before their owner. GetBoneMatrix alone can still
    -- contain the previous pose. A native socket on this bone requests Source's
    -- current attachment pose; keep the bone frame, not the socket's offset.
    if definition and definition.pose_attachment then
        local socketIndex = actor:LookupAttachment(definition.pose_attachment)
        if socketIndex > 0 then actor:GetAttachment(socketIndex) end
    end
    local index = actor:LookupBone(bone)
    local matrix = index and actor:GetBoneMatrix(index)
    if matrix then return {Pos = matrix:GetTranslation(), Ang = matrix:GetAngles()} end
end

if CLIENT then
    include("campaign_evolved/actor.lua").Client(ENT)
    function ENT:CE8UpdateRenderFrame()
        -- Use the owner's interpolated pose, not a second interpolated stream
        -- of world positions. Server collision remains on this same entity.
        local frame = self:CE8AttachmentFrame()
        self:SetRenderOrigin(frame and frame.Pos or nil)
        self:SetRenderAngles(frame and frame.Ang or nil)
    end
    function ENT:Initialize() self:CE8BindRenderer() end
    function ENT:Think()
        self:CE8UpdateRenderFrame()
        self:CE8BindRenderer()
        self:SetNextClientThink(CurTime())
        return true
    end
    return
end

function ENT:Initialize()
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    local physics = self:GetPhysicsObject()
    if IsValid(physics) then physics:EnableMotion(false) end
    self:SetHealth(1)
    self:SetSaveValue("m_takedamage", 2)
    self:Think()
end

function ENT:Think()
    local actor = self:GetOwner()
    if not IsValid(actor) or actor.Dead and not self.CE8AwaitCorpse then self:Remove() return end
    local frame = self:CE8AttachmentFrame()
    if frame then
        self:SetPos(frame.Pos)
        self:SetAngles(frame.Ang)
        local physics = self:GetPhysicsObject()
        if IsValid(physics) then physics:SetPos(frame.Pos) physics:SetAngles(frame.Ang) end
    end
    self:NextThink(CurTime())
    return true
end

function ENT:OnTakeDamage(damage)
    local actor = self:GetOwner()
    if not IsValid(actor) or not actor.IsCE8SNPC or actor.Dead or damage:GetAttacker() == actor then return end
    -- Splash already reaches the Hunter body through Source's blast trace.
    -- Transferring the same explosion from both attached pieces would triple it.
    if damage:IsDamageType(DMG_BLAST) then return end
    local attacker = damage:GetAttacker()
    if IsValid(attacker) and actor:CheckRelationship(attacker) == D_HT and not actor.VJ_Controlled then
        actor:UpdateEnemyMemory(attacker, attacker:GetPos())
        actor:MarkTookDamageFromEnemy(attacker)
        if not IsValid(actor:GetEnemy()) then actor:ForceSetEnemy(attacker, false) end
    end
    local multiplier = self.CE8ArmorScale or 0
    if multiplier > 0 then
        damage:ScaleDamage(multiplier)
        -- The incoming hit has already passed the global outgoing multiplier.
        actor.CE8ForwardedArmorDamage = damage
        local ok, message = pcall(actor.TakeDamageInfo, actor, damage)
        actor.CE8ForwardedArmorDamage = nil
        if not ok then ErrorNoHalt("CE8 armor damage: " .. tostring(message) .. "\n") end
    end
    damage:SetDamage(0)
end
