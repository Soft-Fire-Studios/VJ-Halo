Campaign Evolved whole-rank roster atlas package

One complete MDL per rank; no runtime bone-merge children.
All programs use screenspace_general_8tex and SM3.
Unpainted albedo and all four RGBA mask channels remain separate textures.
Original rank palettes and ordered CE blend modes remain live shader controls.
Color overrides share one palette across the whole character, through its masks.

ce8_character_preview elite minor
ce8_hunter_preview minor
ce8_character_color 255 160 100 elite
ce8_character_color 1 255 160 100 elite
ce8_character_color default elite

Character/rank | base materials before -> after | models before -> after | visible mesh sections before -> after
elite/minor | 24 -> 6 | 3 -> 1 | 30 -> 10
elite/major | 30 -> 5 | 3 -> 1 | 36 -> 8
elite/officer | 30 -> 5 | 3 -> 1 | 36 -> 8
elite/ultra | 20 -> 5 | 3 -> 1 | 23 -> 9
elite/spec_ops | 15 -> 4 | 2 -> 1 | 19 -> 6
elite/general | 27 -> 5 | 3 -> 1 | 31 -> 9
elite/zealot | 27 -> 5 | 3 -> 1 | 31 -> 9
elite/shipmaster | 23 -> 6 | 3 -> 1 | 25 -> 10
elite/sacristan_minor | 20 -> 4 | 3 -> 1 | 32 -> 7
elite/sacristan_major | 20 -> 5 | 3 -> 1 | 32 -> 7
elite/sacristan_zealot | 19 -> 9 | 3 -> 1 | 25 -> 12
elite/sacristan_specops | 14 -> 3 | 3 -> 1 | 26 -> 5
elite/exploded | 35 -> 4 | 3 -> 1 | 35 -> 5
hunter/minor | 23 -> 4 | 5 -> 1 | 29 -> 10
hunter/sacristan | 24 -> 4 | 5 -> 1 | 33 -> 10
jackal/jackal_minor | 34 -> 6 | 2 -> 1 | 36 -> 6
jackal/skirmisher_minor | 25 -> 5 | 1 -> 1 | 25 -> 5
jackal/jackal_sniper | 28 -> 4 | 1 -> 1 | 28 -> 4
jackal/jackal_major | 36 -> 5 | 2 -> 1 | 36 -> 5
jackal/sancristan | 35 -> 9 | 3 -> 1 | 36 -> 10
jackal/sacristan_minor | 47 -> 11 | 4 -> 1 | 47 -> 11
jackal/sacristan_major | 44 -> 11 | 4 -> 1 | 44 -> 11
jackal/sacristan_sniper | 47 -> 10 | 4 -> 1 | 48 -> 10
grunt/minor | 16 -> 4 | 3 -> 1 | 16 -> 6
grunt/major | 22 -> 4 | 3 -> 1 | 22 -> 6
grunt/spec_ops | 17 -> 5 | 3 -> 1 | 17 -> 8
grunt/sacristan_minor | 19 -> 6 | 3 -> 1 | 19 -> 8
grunt/sacristan_major | 30 -> 4 | 3 -> 1 | 30 -> 7
grunt/sacristan_specops | 17 -> 5 | 3 -> 1 | 17 -> 8
grunt/destroyed_minor | 17 -> 4 | 3 -> 1 | 18 -> 8
grunt/destroyed_major | 14 -> 4 | 3 -> 1 | 15 -> 7
grunt/destroyed_spec_ops | 16 -> 4 | 3 -> 1 | 17 -> 8
brute/default | 40 -> 8 | 4 -> 1 | 44 -> 12
flood_carrier/default | 6 -> 2 | 1 -> 1 | 6 -> 2
flood_combat_elite/default | 32 -> 5 | 8 -> 1 | 68 -> 15
flood_combat_elite/major | 39 -> 7 | 6 -> 1 | 64 -> 12
flood_combat_elite/sasquatch | 32 -> 5 | 8 -> 1 | 68 -> 15
flood_combat_human/default | 19 -> 3 | 7 -> 1 | 20 -> 10
flood_infection/default | 1 -> 1 | 1 -> 1 | 1 -> 1
flood_tank/default | 22 -> 3 | 10 -> 1 | 59 -> 17

Surfaces are unique base materials. Each also has a separate direct-light VMT. Visible mesh sections count the default bodygroups and exclude suppressed glow overlays. These are not measured GPU draw calls or a frame-rate benchmark.

Cells use each map's native density; diffuse, normals, ORME and RGBA masks may differ in size.
Pages contain 1, 2, 4, 8 or 16 actual cells, without repeated filler cells. Maximum dimension: 8192.
Periodic sampling margins are cell_size/128 pixels (minimum 1); shader UVs skip these margins.
Independent per-cell mips use explicit isotropic trilinear filtering.
Hunter worms atlas their background maps and retain the original detail/scroll UVs. Plasma keeps its native inputs.
Only bind-pose sequences are prepared; animations and NPC behavior are separate work.
