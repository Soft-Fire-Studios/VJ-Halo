if SERVER then AddCSLuaFile() end
ENT.Base = "npc_vj_creature_base"
ENT.Type = "ai"
ENT.PrintName = "Flood Carrier"
ENT.Category = "Halo - Campaign Evolved"
ENT.Author = "VJ-Halo"
ENT.IsCE8SNPC = true
ENT.CE8UnitLabel = "flood_carrier"
ENT.CE8Rank = "minor"
local Actor = include("campaign_evolved/actor.lua")
Actor.Shared(ENT, "flood_carrier", "creature")
local Flood = include("campaign_evolved/flood.lua")
Flood.Shared(ENT)
if SERVER then Flood.Server(ENT, Actor.Profile(ENT:CE8Data(), "creature"))
else Actor.Client(ENT) end
