if SERVER then AddCSLuaFile() end
ENT.Base = "npc_vj_human_base"
ENT.Type = "ai"
ENT.PrintName = "Flood Combat Human"
ENT.Category = "Halo - Campaign Evolved"
ENT.Author = "VJ-Halo"
ENT.IsCE8SNPC = true
ENT.CE8UnitLabel = "flood_combat_human"
ENT.CE8Rank = "minor"
local Actor = include("campaign_evolved/actor.lua")
Actor.Shared(ENT, "flood_combat_human", "human")
local Flood = include("campaign_evolved/flood.lua")
Flood.Shared(ENT)
if SERVER then Flood.Server(ENT, Actor.Profile(ENT:CE8Data(), "human"))
else Actor.Client(ENT) end
