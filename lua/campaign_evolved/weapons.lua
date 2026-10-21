-- Native Covenant weapon values; explicit Source motion adapters are named separately.
return {
    ["beam_rifle"] = {
        ["accuracy"] = {
            ["heroic"] = {
                ["bounds"] = {
                    0.2,
                    0.6,
                },
                ["time"] = 4.5,
            },
            ["legendary"] = {
                ["bounds"] = {
                    0.35,
                    0.8,
                },
                ["time"] = 3.75,
            },
            ["normal"] = {
                ["bounds"] = {
                    0.0,
                    0.2,
                },
                ["time"] = 6.0,
            },
        },
        ["ammo"] = "AR2",
        ["automatic"] = false,
        ["clip"] = -1,
        ["color"] = {
            120,
            110,
            255,
        },
        ["damage"] = {
            ["amount"] = {
                90.0,
                90.0,
            },
            ["category"] = "plasma",
            ["core"] = 0.0,
            ["minimum"] = 90.0,
            ["radius"] = {
                0.0,
                0.0,
            },
            ["tag"] = "objects/weapons/rifle/beam_rifle/damage_effects/beam_rifle_impact",
        },
        ["elite_class"] = "rifle",
        ["first_delay"] = {
            0.75,
            1.0,
        },
        ["gravity"] = 0.0,
        ["grip"] = 12,
        ["grip_sequence"] = "combat_rifle_csr_grip",
        ["grip_type"] = "combat:rifle:csr:grip",
        ["heat"] = {
            ["loss"] = 0.574999988079071,
            ["overheated_loss"] = 0.4000000059604645,
            ["per_shot"] = 0.6499999761581421,
            ["recovery"] = 0.10000000149011612,
            ["threshold"] = 1.0,
        },
        ["hold_type"] = "ar2",
        ["interval"] = 0.4000000059604645,
        ["left_attachment"] = "left_hand_elite",
        ["max_range"] = 5400.0,
        ["melee"] = false,
        ["melee_range"] = 72.00000286102295,
        ["model"] = "models/campaign_evolved/ce8/material_sets/weapons/weapon_beam_rifle.mdl",
        ["muzzle"] = "muzzle",
        ["name"] = "Beam Rifle",
        ["native_class"] = "rifle",
        ["native_name"] = "csr",
        ["parent_attachment"] = "primary_weapon",
        ["parent_offset"] = {
            ["ang"] = {
                1.2066519402111384e-05,
                90.00001366038161,
                90.0000000000053,
            },
            ["pos"] = {
                -1.088609835770091,
                0.2150988242560262,
                1.8804536011522212e-08,
            },
        },
        ["profiles"] = {
            {
                ["duration"] = {
                    0.5,
                    0.5,
                },
                ["projectile_error"] = 0.05235987529158592,
                ["rate"] = 1.0,
                ["separation"] = {
                    2.0,
                    4.0,
                },
            },
            {
                ["duration"] = {
                    1.0,
                    1.0,
                },
                ["projectile_error"] = 0.05235987529158592,
                ["rate"] = 1.0,
                ["separation"] = {
                    2.0,
                    4.0,
                },
            },
        },
        ["projectile"] = false,
        ["rate"] = {
            30.0,
            30.0,
        },
        ["right_attachment"] = "right_hand_elite",
        ["speed"] = 144000.0,
        ["unit_classes"] = {
        },
        ["unit_holds"] = {
        },
    },
    ["energy_sword"] = {
        ["accuracy"] = {
            ["heroic"] = {
                ["bounds"] = {
                    0.2,
                    0.6,
                },
                ["time"] = 4.5,
            },
            ["legendary"] = {
                ["bounds"] = {
                    0.3,
                    1.0,
                },
                ["time"] = 3.0,
            },
            ["normal"] = {
                ["bounds"] = {
                    0.0,
                    0.2,
                },
                ["time"] = 6.0,
            },
        },
        ["ammo"] = "none",
        ["attack_origin"] = "fx_bladebase",
        ["automatic"] = false,
        ["clip"] = -1,
        ["color"] = {
            120,
            200,
            255,
        },
        ["damage"] = {
            ["amount"] = {
                250.0,
                250.0,
            },
            ["category"] = "melee",
            ["core"] = 0.0,
            ["minimum"] = 250.0,
            ["radius"] = {
                0.0,
                0.0,
            },
            ["tag"] = "globals/damage_effects/dash_sword_melee",
        },
        ["elite_class"] = "sword",
        ["first_delay"] = {
            0.0,
            0.0,
        },
        ["gravity"] = 0,
        ["grip"] = 17,
        ["grip_sequence"] = "combat_sword_eb_grip",
        ["grip_type"] = "combat:sword:eb:grip",
        ["heat"] = {
            ["loss"] = 0.0,
            ["overheated_loss"] = 0.0,
            ["per_shot"] = 0,
            ["recovery"] = 0.0,
            ["threshold"] = 0.0,
        },
        ["hold_type"] = "melee2",
        ["interval"] = 0.5,
        ["left_attachment"] = "left_hand",
        ["max_range"] = 1200.0,
        ["melee"] = true,
        ["melee_range"] = 120.0,
        ["model"] = "models/campaign_evolved/ce8/material_sets/weapons/weapon_energy_sword.mdl",
        ["muzzle"] = false,
        ["name"] = "Energy Sword",
        ["native_class"] = "sword",
        ["native_name"] = "eb",
        ["parent_attachment"] = "primary_weapon",
        ["parent_offset"] = {
            ["ang"] = {
                1.2066519402111384e-05,
                90.00001366038161,
                90.0000000000053,
            },
            ["pos"] = {
                0.39370078294295857,
                -0.4295986888697656,
                0.42959860073901235,
            },
        },
        ["profiles"] = {
            {
                ["duration"] = {
                    0.0,
                    0.0,
                },
                ["projectile_error"] = 0.0,
                ["rate"] = 0.0,
                ["separation"] = {
                    0.5,
                    0.5,
                },
            },
        },
        ["projectile"] = false,
        ["rate"] = {
            0,
            0,
        },
        ["right_attachment"] = "right_hand_elite",
        ["speed"] = 0,
        ["unit_classes"] = {
        },
        ["unit_holds"] = {
        },
    },
    ["flak_cannon"] = {
        ["accuracy"] = {
            ["heroic"] = {
                ["bounds"] = {
                    0.2,
                    0.6,
                },
                ["time"] = 4.5,
            },
            ["legendary"] = {
                ["bounds"] = {
                    0.35,
                    0.8,
                },
                ["time"] = 3.75,
            },
            ["normal"] = {
                ["bounds"] = {
                    0.0,
                    0.2,
                },
                ["time"] = 4.5,
            },
        },
        ["ammo"] = "RPG_Round",
        ["automatic"] = false,
        ["clip"] = 5,
        ["color"] = {
            130,
            255,
            60,
        },
        ["damage"] = {
            ["amount"] = {
                100.0,
                100.0,
            },
            ["category"] = "high explosive",
            ["core"] = 0.0,
            ["minimum"] = 0.0,
            ["radius"] = {
                0.0,
                0.0,
            },
            ["tag"] = "objects/weapons/support_high/flak_cannon/projectiles/damage_effects/flak_bolt_impact",
        },
        ["effects"] = {
            ["files"] = {
                "particles/halo/halo_beam.pcf",
                "particles/halo/main_effects.pcf",
            },
            ["muzzle_angles"] = {
                0,
                0,
                0,
            },
            ["muzzle_attachment"] = "flash",
            ["normal"] = {
                ["flight"] = "hcea_hunter_frnade_nade",
                ["impact"] = "hcea_hunter_frnade_hit",
                ["muzzle"] = "hcea_hunter_plasma_pistol_fire",
            },
        },
        ["elite_class"] = "missile",
        ["explosion"] = {
            ["amount"] = {
                100.0,
                100.0,
            },
            ["category"] = "high explosive",
            ["core"] = 60.0,
            ["minimum"] = 20.0,
            ["radius"] = {
                60.0,
                270.0,
            },
            ["tag"] = "objects/weapons/support_high/flak_cannon/projectiles/damage_effects/flak_bolt_explosion",
        },
        ["first_delay"] = {
            1.0,
            1.25,
        },
        ["flight"] = {
            ["acceleration_inverse"] = 0.0027777778605620066,
            ["acceleration_range"] = {
                360.0,
                720.0,
            },
            ["ai_speed"] = {
                ["heroic"] = 0.800000011920929,
                ["legendary"] = 1.0,
                ["normal"] = 0.6000000238418579,
            },
            ["final_speed"] = 1320.0,
            ["orient"] = true,
            ["range"] = 9600.0,
        },
        ["gravity"] = 0.02500000037252903,
        ["grip"] = 1,
        ["grip_sequence"] = "combat_missile_fc_grip",
        ["grip_type"] = "combat:missile:fc:grip",
        ["heat"] = {
            ["loss"] = 0.0,
            ["overheated_loss"] = 0.0,
            ["per_shot"] = 0.0,
            ["recovery"] = 0.0,
            ["threshold"] = 0.0,
        },
        ["hold_type"] = "rpg",
        ["interval"] = 0.5,
        ["left_attachment"] = "left_hand_elite",
        ["max_range"] = 1800.0,
        ["melee"] = false,
        ["melee_range"] = 72.00000286102295,
        ["model"] = "models/campaign_evolved/ce8/material_sets/weapons/weapon_flak_cannon.mdl",
        ["muzzle"] = "muzzle",
        ["name"] = "Fuel Rod Gun",
        ["native_class"] = "missile",
        ["native_name"] = "fc",
        ["parent_attachment"] = "primary_weapon",
        ["parent_offset"] = {
            ["ang"] = {
                15.250872760262888,
                96.52689384014295,
                93.25831314585949,
            },
            ["pos"] = {
                -0.6867905279430204,
                -0.06817489440215653,
                0.03790297701102416,
            },
        },
        ["profiles"] = {
            {
                ["duration"] = {
                    0.75,
                    0.9,
                },
                ["projectile_error"] = 0.05235987529158592,
                ["rate"] = 1.5,
                ["separation"] = {
                    1.5,
                    3.0,
                },
            },
            {
                ["duration"] = {
                    0.75,
                    0.9,
                },
                ["projectile_error"] = 0.02617993764579296,
                ["rate"] = 2.5,
                ["separation"] = {
                    1.25,
                    2.5,
                },
            },
            {
                ["duration"] = {
                    0.75,
                    1.0,
                },
                ["projectile_error"] = 0.01308996882289648,
                ["rate"] = 2.5,
                ["separation"] = {
                    1.5,
                    3.0,
                },
            },
            {
                ["duration"] = {
                    1.12,
                    1.5,
                },
                ["projectile_error"] = 0.05235987529158592,
                ["rate"] = 2.5,
                ["separation"] = {
                    0.75,
                    1.5,
                },
            },
        },
        ["projectile"] = true,
        ["rate"] = {
            30.0,
            30.0,
        },
        ["ricochet"] = {
            ["angle_degrees"] = {
                0.0,
                30.00000139811449,
            },
            ["chance"] = 1.0,
            ["never_units"] = true,
            ["only_units"] = false,
            ["speed"] = {
                1800.0,
                2400.0,
            },
        },
        ["right_attachment"] = "right_hand_elite",
        ["speed"] = 2160.0,
        ["unit_classes"] = {
        },
        ["unit_holds"] = {
        },
    },
    ["needle_rifle"] = {
        ["accuracy"] = {
            ["heroic"] = {
                ["bounds"] = {
                    0.3,
                    0.6,
                },
                ["time"] = 4.5,
            },
            ["legendary"] = {
                ["bounds"] = {
                    0.35,
                    0.8,
                },
                ["time"] = 3.75,
            },
            ["normal"] = {
                ["bounds"] = {
                    0.0,
                    0.2,
                },
                ["time"] = 6.0,
            },
        },
        ["ammo"] = "AR2",
        ["automatic"] = true,
        ["clip"] = 21,
        ["color"] = {
            200,
            65,
            255,
        },
        ["damage"] = {
            ["amount"] = {
                18.0,
                18.0,
            },
            ["category"] = "bullet",
            ["core"] = 0.0,
            ["minimum"] = 18.0,
            ["radius"] = {
                0.0,
                0.0,
            },
            ["tag"] = "objects/weapons/rifle/needle_rifle/projectiles/damage_effects/needle_rifle_shard_impact",
        },
        ["effects"] = {
            ["file"] = "particles/halo/main_effects.pcf",
            ["normal"] = {
            },
            ["supercombine"] = {
                ["impact"] = "hcea_hunter_shade_cannon_explode_air",
            },
        },
        ["elite_class"] = "rifle",
        ["first_delay"] = {
            0.75,
            1.0,
        },
        ["gravity"] = 0.0,
        ["grip"] = 10,
        ["grip_sequence"] = "combat_rifle_cb_grip",
        ["grip_type"] = "combat:rifle:cb:grip",
        ["heat"] = {
            ["loss"] = 0.0,
            ["overheated_loss"] = 0.0,
            ["per_shot"] = 0.0,
            ["recovery"] = 0.0,
            ["threshold"] = 0.0,
        },
        ["hold_type"] = "ar2",
        ["interval"] = 0.25,
        ["left_attachment"] = "left_hand_elite",
        ["max_range"] = 2400.0,
        ["melee"] = false,
        ["melee_range"] = 72.00000286102295,
        ["model"] = "models/campaign_evolved/ce8/material_sets/weapons/weapon_needle_rifle.mdl",
        ["muzzle"] = "muzzle",
        ["name"] = "Needle Rifle",
        ["native_class"] = "rifle",
        ["native_name"] = "cb",
        ["needle"] = {
            ["blast"] = {
                ["amount"] = {
                    235.0,
                    235.0,
                },
                ["core"] = 36.000001430511475,
                ["falloff_power"] = 5,
                ["minimum"] = 40,
                ["radius"] = 150.0,
            },
            ["count"] = 3,
            ["delay"] = 0.05000000074505806,
            ["group"] = "objects/weapons/rifle/needle_rifle/projectiles/needle_rifle_shard",
            ["lifetime"] = 4.0,
            ["sounds"] = {
                {
                    "campaign_evolved/ce8/weapons/needle/super_09.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_08.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_02.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_05.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_03.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_06.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_04.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_01.ogg",
                },
                {
                    "campaign_evolved/ce8/weapons/needle/super_07.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_11.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_10.ogg",
                },
            },
        },
        ["parent_attachment"] = "primary_weapon",
        ["parent_offset"] = {
            ["ang"] = {
                0.46620134498561894,
                84.3359709758616,
                90.0001177966786,
            },
            ["pos"] = {
                0.10262290446134144,
                1.0347215769475087,
                -0.008460761616378962,
            },
        },
        ["profiles"] = {
            {
                ["duration"] = {
                    0.66,
                    0.9,
                },
                ["projectile_error"] = 0.01308996882289648,
                ["rate"] = 1.5,
                ["separation"] = {
                    1.25,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    1.2,
                    1.4,
                },
                ["projectile_error"] = 0.004363323096185923,
                ["rate"] = 3.749999761581421,
                ["separation"] = {
                    0.75,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    1.2,
                    1.4,
                },
                ["projectile_error"] = 0.0021816615480929613,
                ["rate"] = 5.0,
                ["separation"] = {
                    0.75,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    1.2,
                    1.8,
                },
                ["projectile_error"] = 0.01308996882289648,
                ["rate"] = 5.0,
                ["separation"] = {
                    0.75,
                    1.5,
                },
            },
        },
        ["projectile"] = false,
        ["projectile_model"] = "models/campaign_evolved/ce8/material_sets/weapons/weapon_needle.mdl",
        ["rate"] = {
            4.0,
            4.0,
        },
        ["right_attachment"] = "right_hand_elite",
        ["speed"] = 180000.0,
        ["unit_classes"] = {
        },
        ["unit_holds"] = {
        },
    },
    ["needler"] = {
        ["accuracy"] = {
            ["heroic"] = {
                ["bounds"] = {
                    0.2,
                    0.75,
                },
                ["time"] = 4.0,
            },
            ["legendary"] = {
                ["bounds"] = {
                    0.35,
                    0.8,
                },
                ["time"] = 3.75,
            },
            ["normal"] = {
                ["bounds"] = {
                    0.0,
                    0.33,
                },
                ["time"] = 6.0,
            },
        },
        ["ammo"] = "SMG1",
        ["automatic"] = true,
        ["clip"] = 24,
        ["color"] = {
            220,
            100,
            255,
        },
        ["damage"] = {
            ["amount"] = {
                6.0,
                6.0,
            },
            ["category"] = "needle",
            ["core"] = 0.0,
            ["minimum"] = 6.0,
            ["radius"] = {
                0.0,
                0.0,
            },
            ["tag"] = "objects/weapons/pistol/needler/projectiles/damage_effects/needler_shard_impact",
        },
        ["effects"] = {
            ["file"] = "particles/halo/main_effects.pcf",
            ["normal"] = {
            },
            ["supercombine"] = {
                ["impact"] = "hcea_hunter_shade_cannon_explode_air",
            },
        },
        ["elite_class"] = "pistol",
        ["first_delay"] = {
            0.75,
            1.0,
        },
        ["flight"] = {
            ["acceleration_inverse"] = 0.004166666666666667,
            ["acceleration_range"] = {
                240.0,
                480.0,
            },
            ["ai_speed"] = {
                ["heroic"] = 0.44999998807907104,
                ["legendary"] = 0.6000000238418579,
                ["normal"] = 0.4000000059604645,
            },
            ["final_speed"] = 960.0,
            ["guidance"] = {
                ["ai_turn"] = {
                    ["heroic"] = 0.15000000596046448,
                    ["legendary"] = 0.15000000596046448,
                    ["normal"] = 0.15000000596046448,
                },
                ["behind"] = false,
                ["error"] = 60.0,
                ["leading"] = 1.0,
                ["player_scale"] = {
                    ["heroic"] = 0.75,
                    ["legendary"] = 1.0,
                    ["normal"] = 0.5,
                },
                ["rate"] = {
                    1.3089969158172607,
                    1.5707963705062866,
                },
                ["rest"] = 1.3089969158172607,
                ["source_motion"] = {
                    ["turn_scale"] = 0.4,
                    ["weave_fraction"] = 0.05,
                    ["weave_radius"] = 240,
                    ["weave_rate"] = 6.5,
                },
            },
            ["orient"] = true,
            ["range"] = 3120.0,
        },
        ["gravity"] = 0.0,
        ["grip"] = 5,
        ["grip_sequence"] = "combat_pistol_ne_grip",
        ["grip_type"] = "combat:pistol:ne:grip",
        ["heat"] = {
            ["loss"] = 0.0,
            ["overheated_loss"] = 0.0,
            ["per_shot"] = 0.0,
            ["recovery"] = 0.0,
            ["threshold"] = 0.0,
        },
        ["hold_type"] = "pistol",
        ["interval"] = 0.1,
        ["left_attachment"] = "left_hand_elite",
        ["max_range"] = 1560.0,
        ["melee"] = false,
        ["melee_range"] = 72.00000286102295,
        ["model"] = "models/campaign_evolved/ce8/material_sets/weapons/weapon_needler.mdl",
        ["muzzle"] = "muzzle",
        ["name"] = "Needler",
        ["native_class"] = "pistol",
        ["native_name"] = "ne",
        ["needle"] = {
            ["blast"] = {
                ["amount"] = {
                    240.0,
                    240.0,
                },
                ["core"] = 36.000001430511475,
                ["falloff_power"] = 5,
                ["minimum"] = 40,
                ["radius"] = 150.0,
            },
            ["count"] = 6,
            ["delay"] = 0.3499999940395355,
            ["group"] = "objects/weapons/pistol/needler/projectiles/needler_shard",
            ["lifetime"] = 4.0,
            ["sounds"] = {
                {
                    "campaign_evolved/ce8/weapons/needle/super_09.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_08.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_02.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_05.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_03.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_06.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_04.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_01.ogg",
                },
                {
                    "campaign_evolved/ce8/weapons/needle/super_07.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_11.ogg",
                    "campaign_evolved/ce8/weapons/needle/super_10.ogg",
                },
            },
        },
        ["parent_attachment"] = "primary_weapon",
        ["parent_offset"] = {
            ["ang"] = {
                6.267960924582377,
                91.29143404522375,
                99.42637112994758,
            },
            ["pos"] = {
                1.585317596207912,
                1.8519240119273404,
                -0.47111423341479114,
            },
        },
        ["profiles"] = {
            {
                ["duration"] = {
                    0.75,
                    1.1,
                },
                ["projectile_error"] = 0.03490658476948738,
                ["rate"] = 2.5,
                ["separation"] = {
                    1.0,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    0.8,
                    1.3,
                },
                ["projectile_error"] = 0.008726646192371845,
                ["rate"] = 3.749999761581421,
                ["separation"] = {
                    1.0,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    0.8,
                    1.3,
                },
                ["projectile_error"] = 0.004363323096185923,
                ["rate"] = 3.749999761581421,
                ["separation"] = {
                    0.75,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    1.0,
                    1.5,
                },
                ["projectile_error"] = 0.03490658476948738,
                ["rate"] = 3.749999761581421,
                ["separation"] = {
                    0.5,
                    1.5,
                },
            },
        },
        ["projectile"] = true,
        ["projectile_model"] = "models/campaign_evolved/ce8/material_sets/weapons/weapon_needle.mdl",
        ["rate"] = {
            7.0,
            10.0,
        },
        ["right_attachment"] = "right_hand_elite",
        ["speed"] = 960.0,
        ["unit_classes"] = {
        },
        ["unit_holds"] = {
        },
    },
    ["plasma_pistol"] = {
        ["accuracy"] = {
            ["heroic"] = {
                ["bounds"] = {
                    0.2,
                    0.5,
                },
                ["time"] = 4.5,
            },
            ["legendary"] = {
                ["bounds"] = {
                    0.35,
                    0.8,
                },
                ["time"] = 3.75,
            },
            ["normal"] = {
                ["bounds"] = {
                    0.0,
                    0.2,
                },
                ["time"] = 6.0,
            },
        },
        ["ammo"] = "AR2",
        ["automatic"] = false,
        ["clip"] = -1,
        ["color"] = {
            100,
            255,
            90,
        },
        ["damage"] = {
            ["amount"] = {
                16.0,
                16.0,
            },
            ["category"] = "plasma",
            ["core"] = 0.0,
            ["minimum"] = 16.0,
            ["radius"] = {
                0.0,
                0.0,
            },
            ["tag"] = "objects/weapons/pistol/plasma_pistol/projectiles/damage_effects/plasma_pistol_bolt",
        },
        ["effects"] = {
            ["charged"] = {
                ["flight"] = "hcea_t25p_tracer_charged",
                ["impact"] = "hcea_t25p_hit",
                ["muzzle"] = "hcea_t25p_muzzle_charged",
            },
            ["file"] = "particles/halo/halo_beam.pcf",
            ["muzzle_angles"] = {
                0,
                0,
                0,
            },
            ["normal"] = {
                ["flight"] = "hcea_t25p_tracer",
                ["muzzle"] = "hcea_t25p_muzzle",
            },
        },
        ["elite_class"] = "pistol",
        ["first_delay"] = {
            0.75,
            1.0,
        },
        ["flight"] = {
            ["acceleration_inverse"] = 0.008333333333333333,
            ["acceleration_range"] = {
                0.0,
                0.0,
            },
            ["ai_speed"] = {
                ["heroic"] = 0.75,
                ["legendary"] = 1.0,
                ["normal"] = 0.6000000238418579,
            },
            ["final_speed"] = 3600.0,
            ["orient"] = false,
            ["range"] = 4800.0,
        },
        ["gravity"] = 0.0,
        ["grip"] = 6,
        ["grip_sequence"] = "combat_pistol_pp_grip",
        ["grip_type"] = "combat:pistol:pp:grip",
        ["heat"] = {
            ["loss"] = 0.699999988079071,
            ["overheated_loss"] = 0.5,
            ["per_shot"] = 0.18000000715255737,
            ["recovery"] = 0.10000000149011612,
            ["threshold"] = 1.0,
        },
        ["hold_type"] = "pistol",
        ["interval"] = 0.07999999821186066,
        ["left_attachment"] = "left_hand_elite",
        ["max_range"] = 1560.0,
        ["melee"] = false,
        ["melee_range"] = 72.00000286102295,
        ["model"] = "models/campaign_evolved/ce8/material_sets/weapons/weapon_plasma_pistol.mdl",
        ["muzzle"] = "muzzle",
        ["name"] = "Plasma Pistol",
        ["native_class"] = "pistol",
        ["native_name"] = "pp",
        ["parent_attachment"] = "primary_weapon",
        ["parent_offset"] = {
            ["ang"] = {
                6.267960924582377,
                91.29143404522375,
                99.42637112994758,
            },
            ["pos"] = {
                1.9254770644870078,
                0.008502483996103828,
                -0.31771121960600807,
            },
        },
        ["profiles"] = {
            {
                ["duration"] = {
                    0.6,
                    0.85,
                },
                ["projectile_error"] = 0.04363323003053665,
                ["rate"] = 3.0,
                ["separation"] = {
                    0.75,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    0.6,
                    0.9,
                },
                ["projectile_error"] = 0.0,
                ["rate"] = 5.5,
                ["separation"] = {
                    0.75,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    0.75,
                    1.1,
                },
                ["projectile_error"] = 0.004363323096185923,
                ["rate"] = 7.499999523162842,
                ["separation"] = {
                    0.75,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    1.12,
                    1.7,
                },
                ["projectile_error"] = 0.04363323003053665,
                ["rate"] = 7.499999523162842,
                ["separation"] = {
                    0.5,
                    1.5,
                },
            },
        },
        ["projectile"] = true,
        ["rate"] = {
            30.0,
            30.0,
        },
        ["right_attachment"] = "right_hand_elite",
        ["speed"] = 2400.0,
        ["unit_classes"] = {
        },
        ["unit_holds"] = {
        },
    },
    ["plasma_rifle"] = {
        ["accuracy"] = {
            ["heroic"] = {
                ["bounds"] = {
                    0.2,
                    0.75,
                },
                ["time"] = 4.0,
            },
            ["legendary"] = {
                ["bounds"] = {
                    0.35,
                    0.8,
                },
                ["time"] = 3.75,
            },
            ["normal"] = {
                ["bounds"] = {
                    0.0,
                    0.2,
                },
                ["time"] = 6.0,
            },
        },
        ["ammo"] = "AR2",
        ["automatic"] = true,
        ["clip"] = -1,
        ["color"] = {
            80,
            160,
            255,
        },
        ["damage"] = {
            ["amount"] = {
                11.0,
                11.0,
            },
            ["category"] = "plasma",
            ["core"] = 0.0,
            ["minimum"] = 7.0,
            ["radius"] = {
                0.0,
                0.0,
            },
            ["tag"] = "objects/weapons/rifle/plasma_rifle/projectiles/plasma_rifle_bolt",
        },
        ["effects"] = {
            ["file"] = "particles/halo/halo_beam.pcf",
            ["muzzle_angles"] = {
                0,
                0,
                0,
            },
            ["muzzle_attachment"] = "fx_muzzleflash",
            ["normal"] = {
                ["flight"] = "hcea_t25r_tracer",
                ["muzzle"] = "hcea_t25r_muzzle",
            },
        },
        ["elite_class"] = "pistol",
        ["first_delay"] = {
            0.75,
            1.0,
        },
        ["flight"] = {
            ["acceleration_inverse"] = 0.008333333333333333,
            ["acceleration_range"] = {
                0.0,
                0.0,
            },
            ["ai_speed"] = {
                ["heroic"] = 0.6000000238418579,
                ["legendary"] = 1.0,
                ["normal"] = 0.5,
            },
            ["final_speed"] = 3000.0,
            ["orient"] = false,
            ["range"] = 4800.0,
        },
        ["gravity"] = 0.0,
        ["grip"] = 6,
        ["grip_sequence"] = "combat_pistol_pp_grip",
        ["grip_type"] = "combat:pistol:pp:grip",
        ["heat"] = {
            ["loss"] = 0.8525000214576721,
            ["overheated_loss"] = 0.3499999940395355,
            ["per_shot"] = 0.125,
            ["recovery"] = 0.10000000149011612,
            ["threshold"] = 1.0,
        },
        ["hold_type"] = "pistol",
        ["interval"] = 0.1,
        ["left_attachment"] = "left_hand",
        ["max_range"] = 1800.0,
        ["melee"] = false,
        ["melee_range"] = 72.00000286102295,
        ["model"] = "models/campaign_evolved/ce8/material_sets/weapons/weapon_plasma_rifle.mdl",
        ["muzzle"] = "muzzle",
        ["name"] = "Plasma Rifle",
        ["native_class"] = "pistol",
        ["native_name"] = "pr",
        ["parent_attachment"] = "primary_weapon",
        ["parent_offset"] = {
            ["ang"] = {
                1.2066519402111384e-05,
                90.00001366038161,
                90.0000000000053,
            },
            ["pos"] = {
                3.827991507024558e-32,
                5.465309584585532e-23,
                -6.251584646260482e-16,
            },
        },
        ["profiles"] = {
            {
                ["duration"] = {
                    0.56,
                    0.85,
                },
                ["projectile_error"] = 0.03490658476948738,
                ["rate"] = 3.3333332538604736,
                ["separation"] = {
                    0.75,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    0.7,
                    1.0,
                },
                ["projectile_error"] = 0.008726646192371845,
                ["rate"] = 7.499999523162842,
                ["separation"] = {
                    0.75,
                    1.75,
                },
            },
            {
                ["duration"] = {
                    0.75,
                    1.1,
                },
                ["projectile_error"] = 0.001745329238474369,
                ["rate"] = 7.499999523162842,
                ["separation"] = {
                    0.75,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    0.9,
                    1.32,
                },
                ["projectile_error"] = 0.008726646192371845,
                ["rate"] = 7.499999523162842,
                ["separation"] = {
                    0.75,
                    1.8,
                },
            },
        },
        ["projectile"] = true,
        ["rate"] = {
            5.0,
            10.0,
        },
        ["right_attachment"] = "right_hand_elite",
        ["speed"] = 3000.0,
        ["unit_classes"] = {
        },
        ["unit_holds"] = {
        },
    },
    ["spike_rifle"] = {
        ["accuracy"] = {
            ["heroic"] = {
                ["bounds"] = {
                    0.2,
                    0.6,
                },
                ["time"] = 4.5,
            },
            ["legendary"] = {
                ["bounds"] = {
                    0.35,
                    0.8,
                },
                ["time"] = 3.75,
            },
            ["normal"] = {
                ["bounds"] = {
                    0.0,
                    0.2,
                },
                ["time"] = 6.0,
            },
        },
        ["ammo"] = "SMG1",
        ["automatic"] = true,
        ["clip"] = 40,
        ["color"] = {
            255,
            160,
            60,
        },
        ["damage"] = {
            ["amount"] = {
                14.0,
                14.0,
            },
            ["category"] = "bullet",
            ["core"] = 0.0,
            ["minimum"] = 14.0,
            ["radius"] = {
                0.0,
                0.0,
            },
            ["tag"] = "objects/weapons/rifle/spike_rifle/projectiles/spike_rifle_shard",
        },
        ["elite_class"] = "rifle",
        ["first_delay"] = {
            0.75,
            1.0,
        },
        ["flight"] = {
            ["acceleration_inverse"] = 0.0013888889302810033,
            ["acceleration_range"] = {
                240.0,
                960.0,
            },
            ["ai_speed"] = {
                ["heroic"] = 0.75,
                ["legendary"] = 1.0,
                ["normal"] = 0.6600000262260437,
            },
            ["final_speed"] = 3000.0,
            ["orient"] = true,
            ["range"] = 8400.0,
        },
        ["gravity"] = 0.20000000298023224,
        ["grip"] = 7,
        ["grip_sequence"] = "combat_pistol_spr_grip",
        ["grip_type"] = "combat:pistol:spr:grip",
        ["heat"] = {
            ["loss"] = 0.125,
            ["overheated_loss"] = 1.0,
            ["per_shot"] = 0.03500000014901161,
            ["recovery"] = 1.0,
            ["threshold"] = 0.8999999761581421,
        },
        ["hold_type"] = "ar2",
        ["interval"] = 0.125,
        ["left_attachment"] = "left_hand_elite",
        ["max_range"] = 1800.0,
        ["melee"] = false,
        ["melee_range"] = 72.00000286102295,
        ["model"] = "models/campaign_evolved/ce8/material_sets/weapons/weapon_spike_rifle.mdl",
        ["muzzle"] = "muzzle",
        ["name"] = "Spiker",
        ["native_class"] = "rifle",
        ["native_name"] = "spr",
        ["parent_attachment"] = "primary_weapon",
        ["parent_offset"] = {
            ["ang"] = {
                -1.3660381596913497e-05,
                90.00001366038158,
                89.9999999999951,
            },
            ["pos"] = {
                3.4093462773348844e-16,
                -6.952586348672279e-32,
                6.777972494813291e-17,
            },
        },
        ["profiles"] = {
            {
                ["duration"] = {
                    0.56,
                    0.75,
                },
                ["projectile_error"] = 0.03490658476948738,
                ["rate"] = 3.3333332538604736,
                ["separation"] = {
                    0.75,
                    1.5,
                },
            },
            {
                ["duration"] = {
                    0.8,
                    1.2,
                },
                ["projectile_error"] = 0.004363323096185923,
                ["rate"] = 7.499999523162842,
                ["separation"] = {
                    0.75,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    0.8,
                    1.2,
                },
                ["projectile_error"] = 0.008726646192371845,
                ["rate"] = 7.499999523162842,
                ["separation"] = {
                    0.75,
                    2.25,
                },
            },
            {
                ["duration"] = {
                    1.12,
                    1.5,
                },
                ["projectile_error"] = 0.03490658476948738,
                ["rate"] = 7.499999523162842,
                ["separation"] = {
                    0.5,
                    0.9,
                },
            },
        },
        ["projectile"] = true,
        ["rate"] = {
            8.0,
            8.0,
        },
        ["right_attachment"] = "right_hand_elite",
        ["speed"] = 4200.0,
        ["unit_classes"] = {
            ["brute"] = "pistol",
        },
        ["unit_holds"] = {
            ["brute"] = "pistol",
        },
    },
}
