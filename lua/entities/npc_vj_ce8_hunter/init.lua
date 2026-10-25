AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")
include("campaign_evolved/creature.lua").Server(ENT, include("profile.lua"))
