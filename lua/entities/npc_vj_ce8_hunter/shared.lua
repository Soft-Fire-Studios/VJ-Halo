ENT.Base = "npc_vj_human_base"
ENT.Type = "ai"
ENT.PrintName = "Hunter"
ENT.Category = "Halo - Campaign Evolved"
ENT.Author = "VJ-Halo"
ENT.IsCE8SNPC = true
ENT.CE8UnitLabel = "hunter"
ENT.CE8Rank = "minor"
include("campaign_evolved/actor.lua").Shared(ENT, "hunter", "human")

ENT.ColliderFile = "npc_vj_ce8_hunter_collision.json"
ENT.ColliderBodies = include("campaign_evolved/hunter_colliders.lua")
