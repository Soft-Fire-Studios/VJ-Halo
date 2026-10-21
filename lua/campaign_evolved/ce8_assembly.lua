-- Regional CE models share one posed parent and independent material tables.
if SERVER then return end
CE8 = CE8 or {}

function CE8.GetAssembly(character, permutation)
    if not CE8.Assemblies then
        CE8.Assemblies = util.JSONToTable(file.Read("lua/campaign_evolved/ce8_assemblies.json", "GAME") or "{}") or {}
    end
    local entry = (CE8.Assemblies.characters or {})[string.lower(character or "")]
    if not entry then return end
    permutation = string.lower(permutation or entry.default_rank or "minor")
    permutation = (entry.aliases or {})[permutation] or permutation
    return (entry.variants or {})[permutation]
end

function CE8.MaterialOwner(ent)
    return IsValid(ent) and IsValid(ent.CE8MaterialOwner) and ent.CE8MaterialOwner or ent
end

function CE8.ActiveCharacterMaterials(ent)
    local definition=ent.CE8CharacterDefinition
    if not definition or not definition.shared_bodygroup_model then
        return ent.CE8OverrideMaterials,ent.CE8LightMaterials,ent.CE8AllOverrideSlots
    end
    local layout=ent.CE8BodygroupLayout
    if not layout then layout=ent:GetBodyGroups();ent.CE8BodygroupLayout=layout end
    local key=0
    for _,group in ipairs(layout) do key=key*group.num+ent:GetBodygroup(group.id) end
    local cache=ent.CE8BodygroupDrawCache
    if not cache or cache.key~=key then
        local values={}
        for _,group in ipairs(layout) do values[group.name]=ent:GetBodygroup(group.id) end
        local slots={}
        local options=definition.parts[1].bodygroup_options
        for name,value in pairs(values) do
            local option=options[name] and options[name][value+1]
            for _,slot in ipairs(option and option.materials or {}) do slots[slot]=true end
        end
        local base,lights={},{}
        for slot in pairs(slots) do
            base[slot]=ent.CE8OverrideMaterials[slot]
            lights[slot]=(ent.CE8LightMaterials or {})[slot]
        end
        local function matches(name)
            local preset=(definition.bodygroup_presets or {})[name]
            if not preset then return false end
            local match=true
            for group,value in pairs(preset) do if values[group]~=value then match=false;break end end
            return match
        end
        local rank=ent.CE8CharacterRank
        if not rank or not matches(rank) then
            rank="mixed"
            for _,name in ipairs(definition.rank_order or {}) do if matches(name) then rank=name;break end end
        end
        ent.CE8CharacterRank=rank
        cache={key=key,base=base,lights=next(lights) and lights or nil,slots=slots}
        ent.CE8BodygroupDrawCache=cache
    end
    ent.CE8ActiveLightMaterials=cache.lights
    return cache.base,cache.lights,cache.slots
end

function CE8.LightPosition(ent)
    ent = CE8.MaterialOwner(ent)
    return ent.CE8LightingCenter and ent:LocalToWorld(ent.CE8LightingCenter) or ent:WorldSpaceCenter()
end

function CE8.LightRadius(ent)
    ent = CE8.MaterialOwner(ent)
    return ent.CE8LightingRadius or ent:BoundingRadius()
end

local sharedFields = {"CE8Draft", "CE8Parameters", "CE8EnvironmentTint", "CE8OverallColor", "CampaignPortColor", "CampaignPortColor2", "CampaignPortColor3", "CampaignPortColor4"}
local function appearance(parent, part)
    for _, name in ipairs(sharedFields) do part[name] = parent[name] end
    part:SetColor(parent:GetColor())
end

local function rememberGroups(ent, values)
    for _, group in ipairs(ent:GetBodyGroups()) do values[group.name] = ent:GetBodygroup(group.id) end
end

local function restoreGroups(ent, values)
    for _, group in ipairs(ent:GetBodyGroups()) do
        local value = values[group.name]
        if value ~= nil then ent:SetBodygroup(group.id, math.Clamp(value, 0, math.max(group.num - 1, 0))) end
    end
end

function CE8.RemoveAssemblyParts(ent)
    for _, part in pairs(ent.CE8AssemblyParts or {}) do if IsValid(part) then part:Remove() end end
    ent.CE8AssemblyParts = {}
end

function CE8.AssemblePreview(ent, definition, bindPart)
    if ent.CE8AssemblyPart or not definition then return end
    local parentModel = definition.parent_model or definition.body_model
    assert(parentModel and definition.parts, "CE8 assembly requires a parent model and regional parts")
    local originalPosition, originalAngles = ent:GetPos(), ent:GetAngles()
    local position = Vector(originalPosition.x, originalPosition.y, originalPosition.z)
    local angles = Angle(originalAngles.p, originalAngles.y, originalAngles.r)
    local values = ent.CE8AssemblyBodygroups or {}
    rememberGroups(ent, values)
    for _, part in pairs(ent.CE8AssemblyParts or {}) do
        if IsValid(part) then rememberGroups(part, values) end
    end
    ent.CE8AssemblyBodygroups = values
    if not ent.CE8LightingCenter then
        local bounds = definition.model_bounds
        if ent:GetModel() == parentModel and bounds then
            local low, high = bounds.min, bounds.max
            ent.CE8LightingCenter = Vector((low[1]+high[1])*.5,(low[2]+high[2])*.5,(low[3]+high[3])*.5)
            ent.CE8LightingRadius = math.sqrt((high[1]-low[1])^2+(high[2]-low[2])^2+(high[3]-low[3])^2)*.5
        else
            ent.CE8LightingCenter = ent:WorldToLocal(ent:WorldSpaceCenter())
            ent.CE8LightingRadius = ent:BoundingRadius()
        end
    end
    if ent:GetModel() ~= parentModel then
        local noDraw = ent:GetNoDraw()
        local sequence = ent:GetSequenceName(ent:GetSequence())
        local cycle, rate, scale = ent:GetCycle(), ent:GetPlaybackRate(), ent:GetModelScale()
        local bones = {}
        for index = 0, ent:GetBoneCount() - 1 do
            bones[ent:GetBoneName(index)] = {ent:GetManipulateBonePosition(index),
                ent:GetManipulateBoneAngles(index), ent:GetManipulateBoneScale(index)}
        end
        ent:SetModel(parentModel)
        ent:SetPos(position)
        ent:SetAngles(angles)
        ent:SetNoDraw(noDraw)
        ent:SetModelScale(scale, 0)
        local selected = ent:LookupSequence(sequence or "bind_pose")
        ent:SetSequence(selected and selected >= 0 and selected or 0)
        ent:SetCycle(cycle)
        ent:SetPlaybackRate(rate)
        for name, pose in pairs(bones) do
            local index = ent:LookupBone(name)
            if index then
                ent:ManipulateBonePosition(index, pose[1])
                ent:ManipulateBoneAngles(index, pose[2])
                ent:ManipulateBoneScale(index, pose[3])
            end
        end
    end
    restoreGroups(ent, values)
    if definition.bodygroup_defaults and ent.CE8BodygroupPreset~=definition then
        restoreGroups(ent,definition.bodygroup_defaults)
        if definition.hitbox_set and ent.SetHitboxSet then ent:SetHitboxSet(definition.hitbox_set) end
        ent.CE8BodygroupPreset=definition
    end
    local bounds = definition.model_bounds or definition.render_bounds
    if bounds then ent:SetRenderBounds(Vector(unpack(bounds.min)), Vector(unpack(bounds.max))) end
    local parts = ent.CE8AssemblyParts or {}
    ent.CE8AssemblyParts = parts
    local retained = {}
    for _, info in ipairs(definition.parts) do
        local key = info.component or info.region
        if info.model ~= parentModel then
            local part = parts[key]
            if IsValid(part) and part:GetModel() ~= info.model then part:Remove(); part = nil end
            if not IsValid(part) then
                part = ClientsideModel(info.model, RENDERGROUP_BOTH)
                assert(IsValid(part), "CE8 could not create regional model " .. info.model)
                parts[key] = part
                part:SetParent(ent)
                part:SetLocalPos(vector_origin)
                part:SetLocalAngles(angle_zero)
                part:AddEffects(bit.bor(EF_BONEMERGE, EF_BONEMERGE_FASTCULL))
                part:SetNoDraw(true)
                part:SetSequence("bind_pose")
                part:SetPlaybackRate(0)
            end
            retained[key] = true
            part.CE8AssemblyPart = true
            part.CE8AssemblyRegion = info.region
            part.CE8AssemblyComponent = key
            part.CE8MaterialOwner = ent
            appearance(ent, part)
            restoreGroups(part, values)
            bindPart(part)
        else
            ent.CE8AssemblyRegion = info.region
            ent.CE8AssemblyComponent = key
        end
    end
    for region, part in pairs(parts) do
        if not retained[region] then if IsValid(part) then part:Remove() end; parts[region] = nil end
    end
    ent.CE8AssemblyDefinition = definition
    ent:CallOnRemove("CE8AssemblyCleanup", function(removed) CE8.RemoveAssemblyParts(removed) end)
    -- Apply the copied world transform after every model/bone/child setup step.
    ent:SetPos(position)
    ent:SetAngles(angles)
end

function CE8.DrawAssemblyParts(ent, flags)
    if ent.CE8AssemblyPart then return end
    for _, part in pairs(ent.CE8AssemblyParts or {}) do
        if IsValid(part) then
            appearance(ent, part)
            part:SetupBones()
            if part.RenderOverride then part:RenderOverride(flags) else part:DrawModel(flags) end
        end
    end
end

function CE8.AssemblyStatus(ent)
    local rows = {}
    local function add(part)
        local row = {region = part.CE8AssemblyRegion, component = part.CE8AssemblyComponent, model = part:GetModel(),
            parent = part == ent, material_count = #part:GetMaterials(), materials = {},
            apply_error = part.CE8ApplyError, draw_error = part.CE8DrawError,
            draws = part.CE8Draws or 0, direct_light_passes = part.CE8LightPasses or 0}
        for index, name in ipairs(part:GetMaterials()) do
            local bound = (part.CE8OverrideMaterials or {})[index - 1]
            row.materials[#row.materials + 1] = {slot = index - 1, original = name,
                draw_override = bound and bound:GetName()}
        end
        rows[#rows + 1] = row
    end
    add(ent)
    for _, part in pairs(ent.CE8AssemblyParts or {}) do if IsValid(part) then add(part) end end
    return rows
end
