-- Spawn compiled CE8 ragdolls through the ordinary Sandbox path.
if SERVER then return end
local function spawn(character, rank)
    local catalog=util.JSONToTable(file.Read("lua/campaign_evolved/ce8_ragdolls.json","GAME") or "{}") or {}
    character=string.lower(character or "elite")
    local entry=(catalog.characters or {})[character]
    rank=string.lower(rank or (catalog.default_ranks or {})[character] or "minor")
    rank=((catalog.aliases or {})[character] or {})[rank] or rank
    local model=entry and entry[rank]
    if not model then print("ce8_ragdoll: no compiled physics for this character/rank") return end
    local bodygroups=((catalog.bodygroups or {})[character] or {})[rank]
    if bodygroups then RunConsoleCommand("gm_spawn",model,"0",bodygroups)
    else RunConsoleCommand("gm_spawn",model) end
end
concommand.Add("ce8_ragdoll",function(_,_,args) spawn(args[1],args[2]) end)
concommand.Add("ce8_ragdoll_list",function()
    local catalog=util.JSONToTable(file.Read("lua/campaign_evolved/ce8_ragdolls.json","GAME") or "{}") or {}
    for character,ranks in SortedPairs(catalog.characters or {}) do
        print(character..": "..table.concat(table.GetKeys(ranks),", "))
    end
end)
