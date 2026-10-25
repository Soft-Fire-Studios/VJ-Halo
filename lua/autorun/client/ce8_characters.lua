-- Shared character renderer and current model/material controls.
if SERVER then return end
CE8 = CE8 or {}
if include and file and file.Exists and not CE8.SupportsOverallPaint
    and file.Exists("lua/autorun/client/ce8_surface.lua","GAME") then
    include("autorun/client/ce8_surface.lua")
end
CE8.Assemblies = nil
if include then include("campaign_evolved/ce8_assembly.lua") end

-- Native props can be classified as opaque even when a custom shader supplies
-- a translucent section. Remember only props actually submitted in this view;
-- the translucent-stage fallback never redraws their body or direct lights.
local pendingEmissive={}
if hook then
    hook.Add("PreDrawOpaqueRenderables","CE8EmissiveView",function(depth)
        if not depth then pendingEmissive={} end
    end)
    hook.Add("PostDrawTranslucentRenderables","CE8EmissiveProps",function(depth)
        if depth then return end
        local queued=pendingEmissive;pendingEmissive={}
        local ordered={}
        local eye=EyePos()
        for ent in pairs(queued) do
            if IsValid(ent) and not ent:GetNoDraw() and ent.CE8EmissiveMaterials then
                ordered[#ordered+1]={ent=ent,distance=ent:GetPos():DistToSqr(eye)}
            end
        end
        table.sort(ordered,function(a,b) return a.distance>b.distance end)
        for _,row in ipairs(ordered) do CE8.DrawEmissiveModel(row.ent,STUDIO_RENDER or 1) end
    end)
end

-- Draw only after opaque scene depth is complete. A native translucent callback
-- consumes the queued fallback, so each section is drawn once per view.
function CE8.DrawEmissiveModel(ent, flags)
    pendingEmissive[ent]=nil
    local materials=ent.CE8EmissiveMaterials
    if not ent.CE8Draft or not materials then return end
    local previous=ent.CE8DrawingEmissive
    ent.CE8DrawingEmissive=true
    local ok,message=xpcall(function()
        render.OverrideDepthEnable(true,false)
        render.OverrideBlend(true,BLEND_SRC_ALPHA,ent.CE8EmissiveAdditive and BLEND_ONE or BLEND_ONE_MINUS_SRC_ALPHA,BLENDFUNC_ADD)
        for slot,material in pairs(materials) do render.MaterialOverrideByIndex(slot,material) end
        -- Indexed overrides isolate the energy mesh. The Jackal prop must submit
        -- all submodels: STUDIO_TWOPASS filters out its barrier before shading.
        local drawFlags=ent.CE8EmissiveAllSubmodels and (STUDIO_RENDER or 1)
            or bit.bor(flags or STUDIO_RENDER or 1,STUDIO_TWOPASS or 8)
        ent:DrawModel(drawFlags)
    end,debug.traceback)
    ent.CE8DrawingEmissive=previous
    render.OverrideBlend(false)
    render.OverrideDepthEnable(false,false)
    for slot in pairs(materials) do render.MaterialOverrideByIndex(slot,nil) end
    ent.CE8DrawError=not ok and message or nil
    if not ok then ErrorNoHalt("CE8 emissive draw: "..tostring(message).."\n") end
end

function CE8.BindCharacter(ent, definition, custom, normalSpawn)
    if definition.ce8_only then custom = true end
    local bindings = definition.material_bindings or definition
    ent.CE8Draft = custom == nil and ent.CE8Draft or custom
    ent.CE8Parameters = ent.CE8Parameters or {}
    ent.CE8CharacterDefinition = definition
    ent.CE8BodygroupDrawCache=nil;ent.CE8BodygroupLayout=nil;ent.CE8ActiveLightMaterials=nil
    if not normalSpawn then
        local assembly = definition.assembly or definition
        CE8.AssemblePreview(ent, assembly, function(part) CE8.BindCharacter(part, definition, ent.CE8Draft) end)
        ent:SetSubMaterial()
    end
    ent.CE8OverrideMaterials, ent.CE8LightMaterials, ent.CE8AllOverrideSlots = {},nil,{}
    if ent.CE8Draft and ent.AddEffects and EF_NOFLASHLIGHT then ent:AddEffects(EF_NOFLASHLIGHT) end
    ent.CE8EmissiveMaterials=nil
    ent.CE8EmissiveAdditive=bindings.emissive_blend=="additive"
    ent.CE8EmissiveAllSubmodels=bindings.emissive_submodels=="all"
    ent.CE8ShadowHiddenMaterials={}
    local emissive=bindings.emissive_materials or {}
    if ent.CE8Draft and next(emissive) then ent.CE8EmissiveMaterials={} end
    for index, original in ipairs(ent:GetMaterials()) do
        local slot, name = index-1, string.lower(original)
        local replacement = (bindings.stock_materials or {})[name]
        if ent.CE8Draft then replacement = (bindings.materials or {})[name] or (bindings.glows or {})[name] or replacement end
        if ent.CE8EmissiveMaterials then
            local hidden=assert(bindings.light_hidden_material,"Emissive slots require a hidden material")
            ent.CE8EmissiveMaterials[slot]=Material(emissive[name] or hidden)
            ent.CE8AllOverrideSlots[slot]=true
            if emissive[name] then
                replacement=hidden
                ent.CE8ShadowHiddenMaterials[slot]=Material(hidden)
            end
        end
        if replacement then
            assert(slot<32,"CE8 region exceeds the indexed material override limit")
            ent.CE8OverrideMaterials[slot] = Material(replacement)
            if CE8.RefreshMaterialTextures then CE8.RefreshMaterialTextures(ent.CE8OverrideMaterials[slot]) end
            ent.CE8AllOverrideSlots[slot] = true
        end

    end
    ent.RenderOverride = function(self, flags)
        if self.CE8DrawingEmissive then self:DrawModel(flags) return end
        local depth = bit.bor(STUDIO_SHADOWDEPTHTEXTURE or 0,STUDIO_SSAODEPTHTEXTURE or 0)
        if flags and bit.band(flags,depth)~=0 then
            -- CE's plasma surface casts no shadow or SSAO depth. Keep the
            -- physical handle in those passes and restore indexed overrides.
            local hidden=self.CE8ShadowHiddenMaterials
            for slot,material in pairs(hidden) do render.MaterialOverrideByIndex(slot,material) end
            local ok,message=xpcall(function() self:DrawModel(flags) end,debug.traceback)
            for slot in pairs(hidden) do render.MaterialOverrideByIndex(slot,nil) end
            if not ok then ErrorNoHalt("CE8 shadow draw: "..tostring(message).."\n") end
            CE8.DrawAssemblyParts(self,flags)
            return
        end
        if self.CE8EmissiveMaterials and flags and
            bit.band(flags,STUDIO_DRAWTRANSLUCENTSUBMODELS or 4)~=0 then
            CE8.DrawEmissiveModel(self,flags)
            return
        end
        if self.CE8EmissiveMaterials and not self.DrawWorldModelTranslucent then
            pendingEmissive[self]=true
        end
        local baseMaterials,_,activeSlots=CE8.ActiveCharacterMaterials(self)
        -- GetColor creates a Lua Color table. All material/light binds inside
        -- this model submission share the same entity modulation. Scope it to
        -- this draw only so another view or same-frame SetColor stays current.
        local previousColor=self.CE8BoundRenderColor
        self.CE8BoundRenderColor=self.GetColor and self:GetColor() or nil
        local ok,message = xpcall(function()
            for slot,material in pairs(baseMaterials) do render.MaterialOverrideByIndex(slot,material) end
            if self.CE8Draft then render.OverrideDepthEnable(true,true) end
            self:DrawModel(flags)
            render.OverrideDepthEnable(false,false)
            self.CE8LightPasses=0
        end,debug.traceback)
        self.CE8BoundRenderColor=previousColor
        render.OverrideDepthEnable(false,false)
        render.OverrideBlend(false)
        for slot in pairs(activeSlots) do render.MaterialOverrideByIndex(slot,nil) end
        self.CE8DrawError = not ok and message or nil
        if ok then self.CE8Draws = (self.CE8Draws or 0)+1 else ErrorNoHalt("CE8 character draw: "..tostring(message).."\n") end
        CE8.DrawAssemblyParts(self,flags)
    end
    ent.CE8ApplyError = nil
    return ent
end

function CE8.AttachCharacter(ent, character, permutation, custom)
    local definition = CE8.GetAssembly(character,permutation)
    assert(definition,"CE8 character/permutation is absent from the assembly catalog")
    if custom == nil then custom = next((definition.material_bindings or {}).materials or {})~=nil end
    return CE8.BindCharacter(ent,definition,custom)
end

function CE8.SpawnCharacterPreview(character, permutation)
    character=string.lower(character or "")
    permutation=permutation and string.lower(permutation)
    local definition = CE8.GetAssembly(character,permutation)
    assert(definition,"Unknown CE8 character/permutation; use ce8_character_list")
    local entry=(CE8.Assemblies or {}).characters and CE8.Assemblies.characters[character]
    permutation=permutation or (entry and entry.default_rank) or "minor"
    local player = LocalPlayer()
    if not IsValid(player) then return end
    local trace = player:GetEyeTrace()
    local position = trace.HitPos+Vector(0,0,1)
    if trace.Hit == false then position = player:EyePos()+player:GetAimVector()*200 end
    local angles = Angle(0,player:EyeAngles().y+180,0)
    local entities = {}
    local ent = ClientsideModel(definition.parent_model,RENDERGROUP_BOTH)
    if IsValid(ent) then
        ent:SetNoDraw(true)
        ent:SetPos(position);ent:SetAngles(angles)
        ent:SetSequence("bind_pose");ent:SetPlaybackRate(0)
        ent.CE8Draft=true;ent.CE8Parameters={}
        ent.CE8CharacterName,ent.CE8CharacterRank = character,permutation
        local ok,message=xpcall(function() CE8.BindCharacter(ent,definition,true) end,debug.traceback)
        if ok then
            ent:SetPos(position);ent:SetAngles(angles)
            ent.CE8SpawnPosition,ent.CE8SpawnAngles=position,angles
            ent:SetNoDraw(false)
            entities[#entities+1]=ent
        else ent:Remove();ErrorNoHalt("CE8 character setup: "..tostring(message).."\n") end
    end
    return entities
end

if not concommand then return end
CE8CharacterPreviewEntities = CE8CharacterPreviewEntities or {}
local preview = CE8CharacterPreviewEntities
local function remove(character)
    for index=#preview,1,-1 do
        local ent=preview[index]
        if not IsValid(ent) or not character or ent.CE8CharacterName==character then
            if IsValid(ent) then ent:Remove() end
            table.remove(preview,index)
        end
    end
end
local function status()
    local report={entities={}}
    for _,ent in ipairs(preview) do
        if IsValid(ent) then
            local p=ent:GetPos()
            report.entities[#report.entities+1]={character=ent.CE8CharacterName,rank=ent.CE8CharacterRank,
                custom=ent.CE8Draft,position={p.x,p.y,p.z},parts=CE8.AssemblyStatus(ent),
                spawn_position_error=ent.CE8SpawnPosition and p:Distance(ent.CE8SpawnPosition)}
        end
    end
    PrintTable(report)
    return report
end
concommand.Add("ce8_character_list",function()
    CE8.GetAssembly("elite","minor")
    for character,entry in pairs((CE8.Assemblies or {}).characters or {}) do
        print(character..": "..table.concat(table.GetKeys(entry.variants),", "))
    end
end)
local function spawn(character,permutation)
    character=string.lower(character or "")
    if not CE8.GetAssembly(character,permutation) then print("Unknown CE8 character/permutation; use ce8_character_list");return end
    remove(character)
    local entities=CE8.SpawnCharacterPreview(character,permutation)
    for _,ent in ipairs(entities or {}) do preview[#preview+1]=ent end
end
concommand.Add("ce8_character_preview",function(_,_,args)
    spawn(args[1] or "elite",args[2])
end)
local function parameter(_,_,args)
    local name,value=string.lower(args[1] or ""),tonumber(args[2])
    local schema=(CE8.Controls or {})[name]
    if not schema or (args[2]~="default" and (not value or value~=value or math.abs(value)==math.huge)) then
        print("ce8_character_param <named parameter> <value|default>");return
    end
    for _,ent in ipairs(preview) do
        if IsValid(ent) and ent.CE8Draft and (not args[3] or ent.CE8CharacterName==args[3]) then
            ent.CE8Parameters[name]=value and math.Clamp(value,schema.min,schema.max) or nil
        end
    end
end
concommand.Add("ce8_character_param",parameter)
local function parameters()
    for _,info in SortedPairs(CE8.Controls or {}) do
        print(info.name.." ("..info.min..".."..info.max..", default "..info.default..")")
    end
end
concommand.Add("ce8_character_params",parameters)
local function environmentTint(_,_,args)
    for _,ent in ipairs(preview) do
        if IsValid(ent) then
            ent.CE8EnvironmentTint=args[1]~="default" and Vector(math.max(tonumber(args[1]) or 1,0),
                math.max(tonumber(args[2]) or 1,0),math.max(tonumber(args[3]) or 1,0)) or nil
        end
    end
end
concommand.Add("ce8_character_envtint",environmentTint)
local function palette(_,_,args)
    local region=math.Clamp(math.floor(tonumber(args[1]) or 1),1,4)
    local field="CampaignPortColor"..(region==1 and "" or region)
    local indexedReset=tonumber(args[1])~=nil and args[2]=="default"
    local indexed=indexedReset or (#args>=4 and tonumber(args[4])~=nil)
    local scope
    if indexedReset then scope=args[3]
    elseif indexed then scope=args[5]
    elseif args[1]=="default" then scope=args[2]
    else scope=args[4] end
    for _,ent in ipairs(preview) do
        if IsValid(ent) and (not scope or ent.CE8CharacterName==scope) then
            if indexed then
                -- Channel controls are shared by the entire character. They
                -- never address individual armor materials or atlas cells.
                if isvector(ent.CE8OverallColor) then
                    for index=1,4 do ent["CampaignPortColor"..(index==1 and "" or index)]=ent.CE8OverallColor end
                    ent.CE8OverallColor=nil
                end
                ent[field]=args[2]~="default" and Vector(math.Clamp(tonumber(args[2]) or 255,0,255)/255,
                    math.Clamp(tonumber(args[3]) or 255,0,255)/255,math.Clamp(tonumber(args[4]) or 255,0,255)/255) or nil
            else
                ent.CE8OverallColor=args[1]~="default" and Vector(math.Clamp(tonumber(args[1]) or 255,0,255)/255,
                    math.Clamp(tonumber(args[2]) or 255,0,255)/255,math.Clamp(tonumber(args[3]) or 255,0,255)/255) or nil
                for index=1,4 do
                    ent["CampaignPortColor"..(index==1 and "" or index)]=
                        (ent.CE8CharacterDefinition or {}).color_mode~="overall" and ent.CE8OverallColor or nil
                end
            end
        end
    end
end
concommand.Add("ce8_character_color",palette)
concommand.Add("ce8_character_bodygroup",function(_,_,args)
    local name,value=args[1] or "armor",math.floor(tonumber(args[2]) or 0)
    for _,ent in ipairs(preview) do
        if IsValid(ent) then
            local parts={ent}
            for _,part in pairs(ent.CE8AssemblyParts or {}) do parts[#parts+1]=part end
            for _,part in ipairs(parts) do
                for _,group in ipairs(part:GetBodyGroups()) do
                    if group.name==name or group.name:match("^"..name.."_%d+$") then
                        part:SetBodygroup(group.id,math.Clamp(value,0,group.num-1))
                    end
                end
            end
        end
    end
end)
concommand.Add("ce8_character_status",status)
concommand.Add("ce8_character_remove",function(_,_,args) remove(args and args[1]) end)
hook.Add("ShutDown","CE8CharacterCleanup",remove)
for _,ent in ipairs(preview) do
    if IsValid(ent) and ent.CE8CharacterName then
        local definition=CE8.GetAssembly(ent.CE8CharacterName,ent.CE8CharacterRank)
        if definition then CE8.BindCharacter(ent,definition,ent.CE8Draft) end
    end
end
