-- Compatibility for the existing CE8 debug toggle; implementation is in PRP.
if not CLIENT then return end
include("autorun/client/prp_collision_debug.lua")
local old=CreateClientConVar("ce8_collision_debug","0",false,false,"Alias of prp_collision_debug",0,1)
cvars.RemoveChangeCallback("ce8_collision_debug","CE8CollisionDebug")
cvars.AddChangeCallback("ce8_collision_debug",function(_,_,value)
    GetConVar("prp_collision_debug"):SetInt(tonumber(value) or 0)
end,"CE8CollisionDebug")
if old:GetBool() then GetConVar("prp_collision_debug"):SetInt(1) end
