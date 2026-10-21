-- Normal Sandbox models use the preview's depth and lighting passes.
-- Entity models, physics, poses and bodygroups stay under Sandbox's control.
if SERVER then return end
CE8=CE8 or {}
CE8.ModelDepthEntities=CE8.ModelDepthEntities or setmetatable({},{__mode="k"})
local tracked=CE8.ModelDepthEntities
CE8.SpawnedModelDefinitions=CE8.SpawnedModelDefinitions or {}
local definitions=CE8.SpawnedModelDefinitions

function CE8.RefreshSpawnedModelDefinitions()
    local catalog=util.JSONToTable(file.Read("lua/campaign_evolved/ce8_assemblies.json","GAME") or "{}") or {}
    for model in pairs(definitions) do definitions[model]=nil end
    for character,entry in pairs(catalog.characters or {}) do
        for rank,definition in pairs(entry.variants or {}) do
            if definition.geometry_layout=="whole_atlas" or definition.geometry_layout=="whole_material_sets" or definition.geometry_layout=="bodygroups_compact_material_pages" then
                local model=string.lower(definition.parent_model)
                if not definitions[model] or rank==entry.default_rank then
                    definitions[model]={definition=definition,character=character,rank=rank}
                end
            end
        end
    end
    local ragdolls=util.JSONToTable(file.Read("lua/campaign_evolved/ce8_ragdolls.json","GAME") or "{}") or {}
    for character,ranks in pairs(ragdolls.characters or {}) do
        local entry=(catalog.characters or {})[character]
        for rank,model in pairs(ranks) do
            local definition=entry and entry.variants and entry.variants[rank]
            if definition and (not definitions[string.lower(model)] or rank==entry.default_rank) then
                definitions[string.lower(model)]={definition=definition,character=character,rank=rank}
            end
        end
    end
end

local function supported(ent)
    local model=string.lower((ent:GetModel() or ""):gsub("\\","/"))
    return model:find("models/campaign_evolved/ce8/atlas/",1,true)==1
        or model:find("models/campaign_evolved/ce8/material_sets/",1,true)==1
        or model:find("models/campaign_evolved/ce8/ragdolls/",1,true)==1
end

local noDecalModels=setmetatable({}, {__mode="k"})
local noDecalMaterials={}
local function disableMaterialDecals(material,name)
    name=name or material:GetName()
    if noDecalMaterials[name] or string.lower(name):find("models/campaign_evolved/ce8/",1,true)~=1 then return end
    if material:IsError() then return end
    material:SetInt("$flags",bit.bor(material:GetInt("$flags") or 0,67108864)) -- $nodecal
    noDecalMaterials[name]=true
end
local function disableDecals(ent)
    if noDecalModels[ent]==ent:GetModel() or not supported(ent) then return end
    local names=ent:GetMaterials()
    if #names==0 then return end -- Retry after the networked material table arrives.
    for _,name in ipairs(names) do
        if string.lower(name):find("models/campaign_evolved/ce8/",1,true)==1 and not noDecalMaterials[name] then
            -- Update already cached materials without reloading their textures.
            -- The persistent VMT flag also covers every material not loaded yet.
            local material=Material(name)
            disableMaterialDecals(material,name)
        end
    end
    for _,bound in ipairs({ent.CE8OverrideMaterials or {},ent.CE8LightMaterials or {}}) do
        for _,material in pairs(bound) do disableMaterialDecals(material) end
    end
    ent:RemoveAllDecals()
    noDecalModels[ent]=ent:GetModel()
end

function CE8.DrawModelWithDepth(ent,flags,previous)
    local function draw()
        if previous then previous(ent,flags) else ent:DrawModel(flags) end
    end
    local depth=bit.bor(STUDIO_SHADOWDEPTHTEXTURE or 0,STUDIO_SSAODEPTHTEXTURE or 0)
    if not supported(ent) or (flags and bit.band(flags,depth)~=0) then draw() return end
    local ok,message=xpcall(function()
        render.OverrideDepthEnable(true,true)
        draw()
    end,debug.traceback)
    render.OverrideDepthEnable(false,false)
    if not ok and ent.CE8DepthDrawError~=message then
        ErrorNoHalt("CE8 model depth draw: "..tostring(message).."\n")
    end
    ent.CE8DepthDrawError=not ok and message or nil
end

function CE8.ApplyModelDepth(ent)
    if not IsValid(ent) then return false end
    if ent:GetNoDraw() then return false end
    disableDecals(ent)
    local state=tracked[ent]
    local info=definitions[string.lower((ent:GetModel() or ""):gsub("\\","/"))]
    if info and CE8.BindCharacter then
        if ent.CE8NormalSpawnModel==ent:GetModel() and ent.RenderOverride==ent.CE8NormalSpawnRenderer then return true end
        if not ent.CE8CharacterDefinition or ent.CE8NormalSpawnModel then
            -- Newly networked entities can announce their model before the
            -- client has its material table. Discovery retries after it loads.
            if #ent:GetMaterials()==0 then return false end
            local position,angles=ent:GetPos(),ent:GetAngles()
            local model,bodygroups=ent:GetModel(),{}
            for _,group in ipairs(ent:GetBodyGroups()) do bodygroups[group.id]=ent:GetBodygroup(group.id) end
            -- The entity is already a posed model/ragdoll. Bind lighting and
            -- draw passes without AssemblePreview, SetModel or SetSubMaterial.
            CE8.BindCharacter(ent,info.definition,true,true)
            ent.CE8CharacterName,ent.CE8CharacterRank=info.character,ent.CE8Rank or info.rank
            ent.CE8NormalSpawnModel,ent.CE8NormalSpawnRenderer=model,ent.RenderOverride
            assert(ent:GetModel()==model and ent:GetPos()==position and ent:GetAngles()==angles,
                "Normal CE8 draw binding changed the entity setup")
            for index,value in pairs(bodygroups) do assert(ent:GetBodygroup(index)==value,"Normal CE8 draw binding changed a bodygroup") end
            tracked[ent]=nil
            return true
        end
    end
    -- The dedicated preview renderer already scopes both base and light passes.
    if not supported(ent) or (ent.CE8CharacterDefinition and ent.CE8Draft) then
        if state and ent.RenderOverride==state.wrapper then ent.RenderOverride=state.previous end
        tracked[ent]=nil
        return false
    end
    if state and ent.RenderOverride==state.wrapper then return true end
    state={previous=ent.RenderOverride}
    state.wrapper=function(self,flags) CE8.DrawModelWithDepth(self,flags,state.previous) end
    tracked[ent]=state
    ent.RenderOverride=state.wrapper
    return true
end

local function discover()
    -- Existing actors reuse their bindings. Only newly recognized, drawable
    -- actors initialize materials; discovery never spawns a character.
    for _,ent in ipairs(ents.GetAll()) do CE8.ApplyModelDepth(ent) end
end
local function created(ent) timer.Simple(0,function() CE8.ApplyModelDepth(ent) end) end
hook.Add("OnEntityCreated","CE8ModelDepth",created)
hook.Add("NetworkEntityCreated","CE8ModelDepth",created)
hook.Add("NotifyShouldTransmit","CE8ModelDepth",function(ent,visible) if visible then CE8.ApplyModelDepth(ent) end end)
hook.Add("InitPostEntity","CE8ModelDepth",discover)
-- Handle late model assignment, effect children, model swaps and Lua reloads.
timer.Create("CE8ModelDepthDiscovery",1,0,discover)
CE8.RefreshSpawnedModelDefinitions()
timer.Simple(0,discover)
