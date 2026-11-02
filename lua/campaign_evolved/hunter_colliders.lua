-- Numbered groups match data_static/colliders/npc_vj_ce8_hunter_collision.json.
return {
    {
        groups = {1, 3, 6, 18, 19, 21, 22, 23},
        surface = "metal", damage_scale = 0, hitgroup = HITGROUP_GEAR,
        region = "armor", part = "armor",
        bodygroups = {armor_2 = {0, 1}},
    },
    {
        groups = {2},
        surface = "metal", damage_scale = 0, hitgroup = HITGROUP_GEAR,
        region = "armor", part = "topplate",
        bodygroups = {topplate = {0, 1}},
    },
    {
        groups = {4, 5, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17},
        surface = "metal", damage_scale = 0, hitgroup = HITGROUP_GEAR,
        region = "armor", part = "armor",
        bodygroups = {armor = {0, 1}},
    },
    {
        groups = {7},
        surface = "metal", damage_scale = 0, hitgroup = HITGROUP_GEAR,
        region = "armor", part = "backplate",
        bodygroups = {backplate = {0, 1}},
    },
    {
        groups = {20},
        surface = "metal", damage_scale = 0, hitgroup = HITGROUP_GEAR,
        region = "armor", part = "armor",
        bodygroups = {armor_3 = {0, 1}},
    },
    {
        groups = {24, 25},
        surface = "flesh", damage_scale = 1, hitgroup = HITGROUP_STOMACH,
        region = "body", part = "body",
        bodygroups = {body = {0, 1}, body_2 = {0, 1}},
    },
    {
        groups = {26, 28},
        surface = "flesh", damage_scale = 1, hitgroup = HITGROUP_RIGHTLEG,
        region = "body", part = "body",
        bodygroups = {body = {0, 1}, body_2 = {0, 1}},
    },
    {
        groups = {27, 29},
        surface = "flesh", damage_scale = 1, hitgroup = HITGROUP_LEFTLEG,
        region = "body", part = "body",
        bodygroups = {body = {0, 1}, body_2 = {0, 1}},
    },
    {
        groups = {30},
        surface = "flesh", damage_scale = 1, hitgroup = HITGROUP_HEAD,
        region = "body", part = "body",
        bodygroups = {body = {0, 1}, body_2 = {0, 1}},
    },
    {
        groups = {31},
        surface = "flesh", damage_scale = 1, hitgroup = HITGROUP_RIGHTARM,
        region = "body", part = "body",
        bodygroups = {body = {0, 1}, body_2 = {0, 1}},
    },
    {
        groups = {32, 33},
        surface = "flesh", damage_scale = 1, hitgroup = HITGROUP_LEFTARM,
        region = "body", part = "body",
        bodygroups = {body = {0, 1}, body_2 = {0, 1}},
    },
    {
        groups = {34},
        surface = "metal", damage_scale = 0, hitgroup = HITGROUP_GEAR,
        region = "shield", part = "shield",
        bodygroups = {shield = {0, 1}},
    },
    {
        groups = {35},
        surface = "flesh", damage_scale = 2.5, hitgroup = HITGROUP_STOMACH,
        region = "weakspot", part = "weakspot",
        bodygroups = {weakspot = {0}},
    },
    {
        groups = {36},
        surface = "metal", damage_scale = 1, hitgroup = HITGROUP_GEAR,
        region = "weakspot_shell", part = "weakspot_shell",
        bodygroups = {weakspot_shell = {0, 1}},
    },
}
