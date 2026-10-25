-- Native weapon audio; shared media and authored cue layers.
return {
    ["contact"] = {
        ["expire"] = {
            ["children"] = {
                {
                    ["avoid"] = 1,
                    ["children"] = {
                        {
                            ["file"] = "campaign_evolved/ce8/weapons/needle_rifle/pop_03.ogg",
                        },
                        {
                            ["file"] = "campaign_evolved/ce8/weapons/needle_rifle/pop_01.ogg",
                        },
                        {
                            ["file"] = "campaign_evolved/ce8/weapons/needle_rifle/pop_02.ogg",
                        },
                        {
                            ["file"] = "campaign_evolved/ce8/weapons/needle_rifle/pop_05.ogg",
                        },
                        {
                            ["file"] = "campaign_evolved/ce8/weapons/needle_rifle/pop_04.ogg",
                        },
                    },
                    ["gain"] = {
                        -15.0,
                        -15.0,
                    },
                    ["random"] = true,
                    ["shuffle"] = false,
                    ["weights"] = {
                        50000,
                        50000,
                        50000,
                        50000,
                        50000,
                    },
                },
            },
        },
        ["flyby"] = {
            ["event"] = {
                ["children"] = {
                    {
                        ["avoid"] = 1,
                        ["children"] = {
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_14.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_12.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_05.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_06.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_03.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_16.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_01.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_13.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_02.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_04.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_15.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_08.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_11.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_10.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_07.ogg",
                            },
                            {
                                ["file"] = "campaign_evolved/ce8/weapons/needler/flyby_09.ogg",
                            },
                        },
                        ["gain"] = {
                            -10.0,
                            -10.0,
                        },
                        ["random"] = true,
                        ["shuffle"] = false,
                        ["weights"] = {
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                            100000,
                        },
                    },
                },
            },
            ["level"] = 75,
            ["radius"] = 1200,
        },
        ["impact"] = {
            ["concrete"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_13.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_03.ogg",
                                    },
                                    {
                                        ["avoid"] = 1,
                                        ["children"] = {
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_01.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_06.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_16.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_02.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_08.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_10.ogg",
                                            },
                                        },
                                        ["gain"] = {
                                            -10.0,
                                            -10.0,
                                        },
                                        ["random"] = true,
                                        ["shuffle"] = false,
                                        ["weights"] = {
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_11.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_14.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_18.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_17.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_09.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_07.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_12.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_15.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -24.0,
                                    -24.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    20000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["default"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/default_19.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/default_09.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/default_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/default_16.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/default_11.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/default_05.ogg",
                                    },
                                    {
                                        ["avoid"] = 1,
                                        ["children"] = {
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/default_04.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/default_08.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/default_07.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/default_20.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/default_10.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/default_17.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/default_15.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/default_12.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/default_18.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/default_13.ogg",
                                            },
                                        },
                                        ["gain"] = {
                                            -10.0,
                                            -10.0,
                                        },
                                        ["random"] = true,
                                        ["shuffle"] = false,
                                        ["weights"] = {
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/default_14.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/default_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/default_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/default_06.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -22.0,
                                    -22.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    50000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    20000,
                                    100000,
                                    50000,
                                    50000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["dirt"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_08.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_20.ogg",
                                    },
                                    {
                                        ["avoid"] = 1,
                                        ["children"] = {
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_07.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_03.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_01.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_12.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_09.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_05.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_19.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_10.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_17.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_16.ogg",
                                            },
                                        },
                                        ["gain"] = {
                                            -10.0,
                                            -10.0,
                                        },
                                        ["random"] = true,
                                        ["shuffle"] = false,
                                        ["weights"] = {
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_15.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_18.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_11.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_14.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_13.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -24.0,
                                    -24.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    50000,
                                    50000,
                                    50000,
                                    20000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["energy"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/energy_02.ogg",
                                        ["gain"] = {
                                            2.0,
                                            2.0,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/energy_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/energy_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/energy_03.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -21.0,
                                    -21.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["flesh_elite"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_elite_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_elite_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_elite_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_elite_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_elite_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_elite_04.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -20.0,
                                    -20.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["flesh_flood"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_flood_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_flood_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_flood_10.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_flood_07.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_flood_09.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_flood_08.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_flood_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_flood_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_flood_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_flood_02.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -20.0,
                                    -20.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["flesh_grunt"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_grunt_10.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_grunt_08.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_grunt_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_elite_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_grunt_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_grunt_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_grunt_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_grunt_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_grunt_09.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_grunt_01.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -20.0,
                                    -20.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["flesh_human"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_14.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_13.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_12.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_10.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_08.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_07.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_09.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_human_11.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -20.0,
                                    -20.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["flesh_hunter"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_hunter_07.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_elite_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_hunter_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_hunter_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_hunter_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_grunt_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_hunter_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_hunter_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_hunter_01.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -12.0,
                                    -12.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["flesh_jackal"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_jackal_09.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_jackal_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_jackal_07.ogg",
                                        ["gain"] = {
                                            -3.0,
                                            -3.0,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_jackal_10.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_jackal_08.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_jackal_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_jackal_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_jackal_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_jackal_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/flesh_jackal_05.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -20.0,
                                    -20.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["glass"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_24.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_23.ogg",
                                        ["gain"] = {
                                            -5.0,
                                            -5.0,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_20.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_29.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_21.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_15.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_18.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_27.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_17.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_13.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_25.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_28.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_10.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_07.ogg",
                                    },
                                    {
                                        ["avoid"] = 1,
                                        ["children"] = {
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_22.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_11.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_09.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_02.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_19.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_08.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_30.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_14.ogg",
                                            },
                                        },
                                        ["gain"] = {
                                            -10.0,
                                            -10.0,
                                        },
                                        ["random"] = true,
                                        ["shuffle"] = false,
                                        ["weights"] = {
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_16.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_12.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/glass_26.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -21.0,
                                    -21.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    50000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["grass"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_15.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_13.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_11.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_14.ogg",
                                    },
                                    {
                                        ["avoid"] = 1,
                                        ["children"] = {
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_03.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_19.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_12.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_16.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_07.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_05.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_10.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_01.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_09.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_17.ogg",
                                            },
                                        },
                                        ["gain"] = {
                                            -10.0,
                                            -10.0,
                                        },
                                        ["random"] = true,
                                        ["shuffle"] = false,
                                        ["weights"] = {
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_20.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_18.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_08.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_06.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -24.0,
                                    -24.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    50000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    20000,
                                    50000,
                                    100000,
                                    50000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["ice"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/ice_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/ice_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/ice_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/ice_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/ice_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/ice_02.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -24.0,
                                    -24.0,
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
                },
            },
            ["metal"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_10.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_30.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_09.ogg",
                                    },
                                    {
                                        ["avoid"] = 1,
                                        ["children"] = {
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_17.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_22.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_26.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_23.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_15.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_16.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_18.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_19.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_25.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_04.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_08.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_20.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_32.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_31.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_27.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_13.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_02.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_05.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_03.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_07.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_24.ogg",
                                            },
                                        },
                                        ["random"] = true,
                                        ["shuffle"] = false,
                                        ["weights"] = {
                                            100000,
                                            100000,
                                            10000,
                                            100000,
                                            100000,
                                            10000,
                                            100000,
                                            10000,
                                            10000,
                                            10000,
                                            100000,
                                            10000,
                                            10000,
                                            10000,
                                            10000,
                                            100000,
                                            100000,
                                            10000,
                                            100000,
                                            10000,
                                            100000,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_28.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_21.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_29.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_14.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_12.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/metal_11.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -19.0,
                                    -19.0,
                                },
                                ["pitch"] = {
                                    25.0,
                                    25.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    20000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["sand"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_18.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_11.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_13.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_14.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_15.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_08.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_06.ogg",
                                    },
                                    {
                                        ["avoid"] = 1,
                                        ["children"] = {
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_03.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_19.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_16.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_10.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_05.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_09.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_01.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_17.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_12.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_07.ogg",
                                            },
                                        },
                                        ["gain"] = {
                                            -10.0,
                                            -10.0,
                                        },
                                        ["random"] = true,
                                        ["shuffle"] = false,
                                        ["weights"] = {
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_20.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_02.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -24.0,
                                    -24.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    50000,
                                    100000,
                                    20000,
                                    100000,
                                    50000,
                                    50000,
                                },
                            },
                        },
                    },
                },
            },
            ["shield_elite"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/elite/shield/impact_01.ogg",
                                        ["gain"] = {
                                            -3.0,
                                            -3.0,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/elite/shield/impact_02.ogg",
                                        ["gain"] = {
                                            -3.0,
                                            -3.0,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/elite/shield/impact_03.ogg",
                                        ["gain"] = {
                                            -3.0,
                                            -3.0,
                                        },
                                    },
                                },
                                ["gain"] = {
                                    -16.0,
                                    -16.0,
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
            },
            ["shield_jackal"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["children"] = {
                                    {
                                        ["avoid"] = 1,
                                        ["children"] = {
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_11.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_07.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_05.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_08.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_02.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_01.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_04.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_12.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_17.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_14.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_18.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_15.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_09.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_10.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_03.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_06.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_16.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_19.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_jackal_13.ogg",
                                            },
                                        },
                                        ["gain"] = {
                                            -20.0,
                                            -20.0,
                                        },
                                        ["random"] = true,
                                        ["shuffle"] = false,
                                        ["weights"] = {
                                            1000,
                                            20000,
                                            60000,
                                            50000,
                                            10000,
                                            20000,
                                            75000,
                                            75000,
                                            5000,
                                            2000,
                                            10000,
                                            20000,
                                            75000,
                                            75000,
                                            2000,
                                            60000,
                                            5000,
                                            75000,
                                            60000,
                                        },
                                    },
                                },
                                ["gain"] = {
                                    2.0,
                                    2.0,
                                },
                            },
                        },
                    },
                },
            },
            ["shield_spartan"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_spartan_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_spartan_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_spartan_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/shield_spartan_04.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -15.0,
                                    -15.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    50000,
                                    50000,
                                    50000,
                                    50000,
                                },
                            },
                        },
                    },
                },
            },
            ["snow"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_08.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_20.ogg",
                                    },
                                    {
                                        ["avoid"] = 1,
                                        ["children"] = {
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_07.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_03.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_01.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_12.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_09.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_05.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_19.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_10.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_17.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_16.ogg",
                                            },
                                        },
                                        ["gain"] = {
                                            -10.0,
                                            -10.0,
                                        },
                                        ["random"] = true,
                                        ["shuffle"] = false,
                                        ["weights"] = {
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_15.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_18.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_11.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_14.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/dirt_13.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -24.0,
                                    -24.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    50000,
                                    50000,
                                    50000,
                                    20000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["stone"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_13.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_12.ogg",
                                    },
                                    {
                                        ["avoid"] = 1,
                                        ["children"] = {
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_08.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_02.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_06.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_01.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_16.ogg",
                                            },
                                            {
                                                ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_10.ogg",
                                            },
                                        },
                                        ["gain"] = {
                                            -10.0,
                                            -10.0,
                                        },
                                        ["random"] = true,
                                        ["shuffle"] = false,
                                        ["weights"] = {
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                            100000,
                                        },
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_18.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_09.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_15.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_07.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_11.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_17.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/concrete_14.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -24.0,
                                    -24.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    20000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["water"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/water_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/water_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/water_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/water_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/water_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/water_03.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -24.0,
                                    -24.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    19999,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
            ["wood"] = {
                ["children"] = {
                    {
                        ["children"] = {
                            {
                                ["avoid"] = 1,
                                ["children"] = {
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_12.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_08.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_09.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_13.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_18.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_15.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_07.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_11.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_03.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_20.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_10.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_01.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_17.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_04.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_14.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_02.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_16.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_21.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_05.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_06.ogg",
                                    },
                                    {
                                        ["file"] = "campaign_evolved/ce8/weapons/impacts/wood_19.ogg",
                                    },
                                },
                                ["gain"] = {
                                    -24.0,
                                    -24.0,
                                },
                                ["random"] = true,
                                ["shuffle"] = false,
                                ["weights"] = {
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                    100000,
                                },
                            },
                        },
                    },
                },
            },
        },
        ["level"] = 75,
    },
    ["fire"] = {
        "campaign_evolved/ce8/weapons/needle_rifle/fire_01.ogg",
        "campaign_evolved/ce8/weapons/needle_rifle/fire_02.ogg",
        "campaign_evolved/ce8/weapons/needle_rifle/fire_03.ogg",
    },
    ["tail"] = {
        "campaign_evolved/ce8/weapons/needle_rifle/tail_01.ogg",
        "campaign_evolved/ce8/weapons/needle_rifle/tail_02.ogg",
        "campaign_evolved/ce8/weapons/needle_rifle/tail_05.ogg",
    },
    ["tail_variants"] = {
        {
            "campaign_evolved/ce8/weapons/needle_rifle/tail_01.ogg",
            "campaign_evolved/ce8/weapons/needle_rifle/tail_02.ogg",
            "campaign_evolved/ce8/weapons/needle_rifle/tail_05.ogg",
        },
        {
            "campaign_evolved/ce8/weapons/needle_rifle/tail_03.ogg",
            "campaign_evolved/ce8/weapons/needle_rifle/tail_04.ogg",
            "campaign_evolved/ce8/weapons/needle_rifle/tail_06.ogg",
        },
    },
}
