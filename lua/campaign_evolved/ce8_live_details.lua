-- Baked base maps with named color/emission controls and cached scene parameters.
-- No mesh rebuilding or per-frame texture baking. Changed parameter sheets use
-- one bounded scene target shared by material defaults and editable overrides.
if SERVER then return end
CE8 = CE8 or {}
if CE8.LiveDetailsVersion=="scene_numeric_parameters_v2" then
    -- Rebind the parent transport after a surface-proxy Lua refresh without
    -- rebuilding parameter sheets or discarding live rank/entity overrides.
    local function initializeLive(...) return CE8.InitializeLiveDetails(...) end
    local function bindLive(...) return CE8.BindLiveDetails(...) end
    CE8.RegisterSurfaceVariant("CE8LiveSurface",false,initializeLive,bindLive)
    CE8.RegisterSurfaceVariant("CE8LiveLight",true,initializeLive,bindLive)
    return
end
CE8.LiveDetailError=nil
local descriptor=util.JSONToTable(file.Read("lua/campaign_evolved/ce8_live_details.json","GAME") or "{}") or {}
local materials=descriptor.materials or {}
local state=CE8.LiveDetailState or {entityOverrides=setmetatable({}, {__mode="k"}),rankOverrides={},
    slots={},pending={},queued={},generation=0}
CE8.LiveDetailState=state
if state.format~="scene_v1" then
    state.slots={};state.pending={};state.queued={};state.format="scene_v1"
end
state.programs=state.programs or {};state.shaderUpdates={};state.pending={};state.queued={}
local entityOverrides,rankOverrides=state.entityOverrides,state.rankOverrides
state.generation=state.generation+1
local textureAliases=descriptor.texture_aliases or {}
local emissionFields={emissionmode=true,emissioncolor=true,emissioncolor1=true,
    emissioncolor2=true,emissioncolor3=true,emissionexposure=true,emissiontintbydiffuse=true,
    emissionthreshold=true,emissiongamma=true,emissioncontrast=true}

local function normalize(values)
    if values~=nil and type(values)~="table" then return nil,"Expected a table of emission controls" end
    local result={}
    for name,value in pairs(values or {}) do
        local key=string.lower(tostring(name))
        if not emissionFields[key] then return nil,"Unknown emission control: "..key end
        if type(value)=="number" and (value~=value or math.abs(value)>65504) then
            return nil,"Emission value must be finite and within -65504..65504: "..key
        end
        result[key]=value
    end
    return result
end
local function copyRows(source)
    local result={}
    for i,row in ipairs(source) do result[i]={row[1],row[2],row[3],row[4]} end
    return result
end
local function numeric(value,default)
    if value==true then return 1 elseif value==false then return 0 end
    value=tonumber(value)
    return value and value==value and math.abs(value)~=math.huge and value or default
end
local function emissionColor(value,default)
    if isvector(value) then value={value.x,value.y,value.z} end
    if type(value)=="string" then
        local parts={}
        for part in value:gmatch("[-+]?[%d%.]+[eE]?[-+]?%d*") do parts[#parts+1]=tonumber(part) end
        value=parts
    end
    if type(value)~="table" then return default end
    return {numeric(value[1],default[1]),numeric(value[2],default[2]),
        numeric(value[3],default[3]),default[4]}
end
local function makeRows(record,values)
    local rows=copyRows(record.default_parameter_rows)
    for i,name in ipairs({"emissioncolor","emissioncolor1","emissioncolor2","emissioncolor3"}) do
        rows[14+i]=emissionColor(values[name],rows[14+i])
    end
    local modes={texture=0,tint=1,tricolor=2}
    local mode=values.emissionmode
    if mode~=nil then
        mode=modes[tostring(mode):lower()] or tonumber(mode)
        if not mode or mode<0 or mode>2 or mode~=math.floor(mode) then return nil,"Unknown emission mode" end
        rows[15][4]=mode
    end
    rows[19][1]=math.Clamp(numeric(values.emissionexposure,rows[19][1]),0,65504)
    rows[19][2]=math.Clamp(numeric(values.emissiontintbydiffuse,rows[19][2]),0,1)
    rows[16][4]=numeric(values.emissionthreshold,rows[16][4])
    rows[17][4]=numeric(values.emissiongamma,rows[17][4])
    rows[18][4]=numeric(values.emissioncontrast,rows[18][4])
    -- GPU rows are float32; JSON/VMT numbers arrive as doubles. Equivalent
    -- author defaults must reuse their shared scene slot.
    for index,row in ipairs(rows) do for component=1,4 do
        local original=record.default_parameter_rows[index][component]
        if math.abs(row[component]-original)<=1e-7*math.max(1,math.abs(original)) then row[component]=original end
    end end
    return rows
end
local function keyFor(record,rows)
    -- Identical numeric data is shared across ranks and material families.
    local parts={}
    for index,row in ipairs(rows) do
        -- The full string is the key: no hash collision can share another actor's state.
        parts[#parts+1]=string.format("%.9g,%.9g,%.9g,%.9g",row[1],row[2],row[3],row[4])
    end
    return table.concat(parts,";")
end
local function requestSheet(record,rows,key,isDefault)
    return CE8.SceneParameters(record,rows,key,isDefault)
end
hook.Remove("PreRender","CE8LiveDetailParameters")
hook.Remove("PostRender","CE8LiveDetailParameters")

local function setMaterialOverrides(ent,material,values)
    if not IsValid(ent) then return false,"Invalid entity" end
    if CE8.MaterialOwner then ent=CE8.MaterialOwner(ent) end
    local normalized,message=normalize(values)
    if not normalized then return false,message end
    entityOverrides[ent]=entityOverrides[ent] or {}
    entityOverrides[ent][string.lower(material)]=normalized
    state.generation=state.generation+1
    return true
end
-- Emission edits share the existing cached parameter sheet.
-- Colors use linear RGB, like native VMT defaults; they are not 0..255 colors.
function CE8.SetMaterialEmission(ent,material,values)
    if not IsValid(ent) then return false,"Invalid entity" end
    if CE8.MaterialOwner then ent=CE8.MaterialOwner(ent) end
    local normalized,message=normalize(values)
    if not normalized then return false,message end
    for name in pairs(normalized) do
        if not emissionFields[name] then return false,"Unknown emission control: "..name end
    end
    local key=string.lower(material)
    local merged=table.Copy(entityOverrides[ent] and entityOverrides[ent][key] or {})
    for name,value in pairs(normalized) do merged[name]=value end
    return setMaterialOverrides(ent,material,merged)
end
function CE8.ClearMaterialEmission(ent,material)
    if CE8.MaterialOwner then ent=CE8.MaterialOwner(ent) end
    if entityOverrides[ent] then
        if material then entityOverrides[ent][string.lower(material)]=nil else entityOverrides[ent]=nil end
    end
    state.generation=state.generation+1
end
function CE8.SetRankEmission(species,rank,material,values)
    local normalized,message=normalize(values)
    if not normalized then return false,message end
    rankOverrides[string.lower(species.."/"..rank.."/"..material)]=normalized
    state.generation=state.generation+1
    return true
end
function CE8.ClearRankEmission(species,rank,material)
    rankOverrides[string.lower(species.."/"..rank.."/"..material)]=nil
    state.generation=state.generation+1
end
function CE8.LiveDetailCacheStats()
    local scene=CE8.SceneState
    return {slots=#scene.parameters,pending=#scene.pending,limit=256,bytes=scene.texture and 16777216 or 0,sharedScene=true}
end

local function initialize(self,material,values)
    self.liveRecord=materials[values.materialset]
    if not self.liveRecord then ErrorNoHalt("CE8: unknown live MaterialSet "..tostring(values.materialset).."\n");return end
    for public,slot in pairs({albedotexture="$basetexture",normaltexture="$texture1",surfacetexture="$texture2",paintmasktexture="$texture3"}) do
        local reference=values[public]
        if reference and textureAliases[reference] then material:SetTexture(slot,CE8.NamedTexture(textureAliases[reference],false)) end
    end
    self.liveDefaults={}
    for key,value in pairs(self.liveRecord.parameters or {}) do
        if emissionFields[string.lower(key)] then self.liveDefaults[string.lower(key)]=value end
    end
    for key,value in pairs(values) do if emissionFields[key] then self.liveDefaults[key]=value end end
    self.liveCache=setmetatable({}, {__mode="k"})
    self.liveDefaultKey=keyFor(self.liveRecord,self.liveRecord.default_parameter_rows)
    requestSheet(self.liveRecord,self.liveRecord.default_parameter_rows,self.liveDefaultKey,true)
end
local function bind(self,material,ent)
    local record=self.liveRecord;if not record then return end
    if CE8.MaterialOwner then ent=CE8.MaterialOwner(ent) end
    local currentRank=IsValid(ent) and ent.CE8CharacterRank or record.rank
    local cache=IsValid(ent) and self.liveCache[ent] or self.liveUnbound
    if not cache or cache.generation~=state.generation or cache.rank~=currentRank then
        local values=table.Copy(self.liveDefaults)
        local species=IsValid(ent) and ent.CE8CharacterName or record.species
        local rankName=currentRank
        local rank=rankOverrides[species.."/"..rankName.."/"..record.alias]
        for key,value in pairs(rank or {}) do values[key]=value end
        local overrides=entityOverrides[ent]
        for _,name in ipairs({record.alias,record.name,record.material}) do
            for key,value in pairs(overrides and overrides[name] or {}) do values[key]=value end
        end
        local rows,message=makeRows(record,values)
        if not rows then ErrorNoHalt("CE8 emission: "..tostring(message).."\n");rows=record.default_parameter_rows end
        local key=keyFor(record,rows)
        local changed=key~=keyFor(record,record.default_parameter_rows)
        cache={generation=state.generation,rank=currentRank,rows=rows,key=key,changed=changed}
        if IsValid(ent) then self.liveCache[ent]=cache else self.liveUnbound=cache end
    end
    local defaults=requestSheet(record,record.default_parameter_rows,self.liveDefaultKey,true)
    local prepared=requestSheet(record,cache.rows,cache.key,cache.key==self.liveDefaultKey)
    local index=prepared or defaults
    local usingScene=CE8.SceneMaterial(material,index~=nil)
    -- Sampler 7 has one meaning: the shared numeric scene. Never restore the
    -- retired packed VTF underneath a material already using the scene shader.
    if CE8.SceneState.texture then material:SetTexture("$texture7",CE8.SceneState.texture) end
    if usingScene and index~=nil then
        self.matrixA:SetField(3,3,((index%2)*512+.5)/1024)
        self.matrixA:SetField(3,4,(64+math.floor(index/2)+.5)/1024)
        material:SetMatrix("$viewprojmat",self.matrixA)
    else
        self.matrixA:SetField(3,3,-1);self.matrixA:SetField(3,4,-1)
        material:SetMatrix("$viewprojmat",self.matrixA)
        return -- Pending data is discarded by the shader, never read as valid.
    end
    self.liveProgram="ce8_scene_live_ps30"
    if CE8.CaptureEmissionBloom then CE8.CaptureEmissionBloom(self,material,ent,"live",cache,usingScene) end

end
CE8.InitializeLiveDetails,CE8.BindLiveDetails=initialize,bind
local function initializeLive(...) return CE8.InitializeLiveDetails(...) end
local function bindLive(...) return CE8.BindLiveDetails(...) end
CE8.RegisterSurfaceVariant("CE8LiveSurface",false,initializeLive,bindLive)
CE8.RegisterSurfaceVariant("CE8LiveLight",true,initializeLive,bindLive)
CE8.SupportsLiveDetails=false
CE8.SupportsBakedDetails=true
CE8.SetMaterialDetails=nil
CE8.ClearMaterialDetails=nil
CE8.SetRankDetails=nil
CE8.ClearRankDetails=nil
CE8.RegisterDetailLibrary=nil
CE8.LiveDetailsVersion="scene_numeric_parameters_v2"
