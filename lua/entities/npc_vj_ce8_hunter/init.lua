AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")
include("ai.lua").Server(ENT, include("profile.lua"))
