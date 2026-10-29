AddCSLuaFile()
SWEP.Base = "weapon_vj_base"
SWEP.RenderGroup = RENDERGROUP_BOTH -- Opaque body and engine-sorted emissive parts.
include("campaign_evolved/weapon.lua")(SWEP, "plasma_rifle")
