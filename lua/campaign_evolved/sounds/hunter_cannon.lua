-- Native Hunter cannon one-shots; shared plasma flyby is a Source port choice.
local sounds = {
    ["charge"] = {
        ["children"] = {
            {
                ["avoid"] = 0,
                ["children"] = {
                    {
                        ["file"] = "campaign_evolved/ce8/hunter/cannon/charge_01.ogg",
                    },
                },
                ["gain"] = {
                    -11.0,
                    -11.0,
                },
                ["random"] = true,
                ["shuffle"] = false,
                ["weights"] = {
                    50000,
                },
            },
        },
    },
    ["contact"] = {
        ["detonate"] = {
            ["children"] = {
                {
                    ["avoid"] = 1,
                    ["children"] = {
                        {
                            ["file"] = "campaign_evolved/ce8/hunter/cannon/explode_01.ogg",
                        },
                        {
                            ["file"] = "campaign_evolved/ce8/hunter/cannon/explode_03.ogg",
                        },
                        {
                            ["file"] = "campaign_evolved/ce8/hunter/cannon/explode_02.ogg",
                        },
                    },
                    ["gain"] = {
                        -9.0,
                        -9.0,
                    },
                    ["random"] = true,
                    ["shuffle"] = false,
                    ["weights"] = {
                        50000,
                        50000,
                        50000,
                    },
                },
            },
        },
    },
    ["fire"] = {
        ["children"] = {
            {
                ["avoid"] = 1,
                ["children"] = {
                    {
                        ["file"] = "campaign_evolved/ce8/hunter/cannon/fire_03.ogg",
                    },
                    {
                        ["file"] = "campaign_evolved/ce8/hunter/cannon/fire_05.ogg",
                    },
                    {
                        ["file"] = "campaign_evolved/ce8/hunter/cannon/fire_04.ogg",
                    },
                    {
                        ["file"] = "campaign_evolved/ce8/hunter/cannon/fire_06.ogg",
                    },
                    {
                        ["file"] = "campaign_evolved/ce8/hunter/cannon/fire_02.ogg",
                    },
                    {
                        ["file"] = "campaign_evolved/ce8/hunter/cannon/fire_01.ogg",
                    },
                },
                ["gain"] = {
                    -7.0,
                    -7.0,
                },
                ["random"] = true,
                ["shuffle"] = false,
                ["weights"] = {
                    50000,
                    50000,
                    50000,
                    50000,
                    50000,
                    50000,
                },
            },
        },
    },
}
sounds.contact.flyby = include("campaign_evolved/sounds/flak_cannon.lua").contact.flyby
return sounds
