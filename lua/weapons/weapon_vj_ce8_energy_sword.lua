AddCSLuaFile()
SWEP.Base = "weapon_vj_base"
SWEP.RenderGroup = RENDERGROUP_BOTH -- Opaque handle and engine-sorted translucent blade.
include("campaign_evolved/weapon.lua")(SWEP, "energy_sword")
