if SERVER then AddCSLuaFile() end
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Flood Infection Fountain"
ENT.Category = "Halo - Campaign Evolved"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.DisableDuplicator = true
ENT.PhysgunDisabled = true
ENT.VJ_ID_Grabbable = false
function ENT:Draw() self:DrawModel() end
if CLIENT then return end

local Flood = include("campaign_evolved/flood.lua")
local launch = include("campaign_evolved/flood_carrier_anims.lua").burst.launch
local CLASS = "obj_ce8_infection_fountain"
local LOW, HIGH = Vector(-12, -12, 0), Vector(12, 12, 24.12)

local function validCount(count)
    return count and count >= 1 and count <= 256 and count == math.floor(count)
        and bit.band(count, count - 1) == 0
end

function ENT:Initialize()
    self:SetModel("models/props_junk/garbage_metalcan001a.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-12, -12, -16), Vector(12, 12, 16))
    self:SetCollisionGroup(COLLISION_GROUP_DEBRIS_TRIGGER)
    self:AddFlags(FL_NOTARGET)
    self.Total = validCount(self.Total) and self.Total or 32
    self.Emitted = 0
    self.EmitPoint = self:GetPos() + Vector(0, 0, 40)
    self.EmitTimer = "ce8_infection_fountain_" .. self:EntIndex()
    local timerName = self.EmitTimer
    timer.Create(timerName, 0.125, self.Total, function()
        if not IsValid(self) then timer.Remove(timerName) return end
        self:EmitInfection()
    end)
end

function ENT:EmitInfection()
    if self.Emitted >= self.Total then timer.Remove(self.EmitTimer) return end
    local point = self.EmitPoint -- Every form starts at this exact point.
    local clear = util.TraceHull({start = point, endpos = point, mins = LOW, maxs = HIGH,
        mask = MASK_NPCSOLID_BRUSHONLY, filter = self})
    local child
    if not clear.Hit and not clear.StartSolid and not clear.AllSolid and util.IsInWorld(point)
        and bit.band(util.PointContents(point), CONTENTS_WATER) == 0 then
        child = Flood.LaunchInfection(self, point, math.Rand(0, 360), launch)
    end
    if not IsValid(child) then
        timer.Remove(self.EmitTimer)
        local creator = self:GetCreator()
        if IsValid(creator) then creator:ChatPrint("Infection fountain stopped: release point blocked or NPC creation failed.") end
        return
    end
    self.Emitted = self.Emitted + 1
    self:DeleteOnRemove(child) -- Undo/removing the fountain cleans up its batch.
    if self.Emitted >= self.Total then timer.Remove(self.EmitTimer) end
end

function ENT:OnRemove()
    if self.EmitTimer then timer.Remove(self.EmitTimer) end
end
function ENT:PhysgunPickup() return false end
function ENT:GravGunPickupAllowed() return false end

local function spawn(ply, trace, count)
    if not trace.Hit or trace.HitSky then return end
    local entity = ents.Create(CLASS)
    if not IsValid(entity) then return end
    entity.Total = count or 32
    entity:SetPos(trace.HitPos + trace.HitNormal * 16)
    entity:SetCreator(ply)
    entity:Spawn()
    entity:Activate()
    return entity
end

function ENT:SpawnFunction(ply, trace)
    return spawn(ply, trace, trace.CE8FountainCount or 32)
end

concommand.Add("ce8_infection_fountain", function(ply, _, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local count = args[1] == nil and 32 or tonumber(args[1])
    if not validCount(count) then
        ply:ChatPrint("Use ce8_infection_fountain [1, 2, 4, 8, 16, 32, 64, 128 or 256]. Default: 32.")
        return
    end
    if not Spawn_SENT then ply:ChatPrint("Use the Infection fountain in Sandbox.") return end
    local trace = ply:GetEyeTrace()
    trace.CE8FountainCount = count
    Spawn_SENT(ply, CLASS, trace) -- Sandbox supplies limits, spawn hooks, undo and cleanup.
end)
