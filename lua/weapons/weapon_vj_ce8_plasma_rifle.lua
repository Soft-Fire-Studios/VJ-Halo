AddCSLuaFile()
SWEP.Base = "weapon_vj_base"
SWEP.RenderGroup = RENDERGROUP_BOTH -- Opaque body and engine-sorted heat glyph.
include("campaign_evolved/weapon.lua")(SWEP, "plasma_rifle")
