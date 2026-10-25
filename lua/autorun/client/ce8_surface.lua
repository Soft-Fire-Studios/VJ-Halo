-- Named controls for screenspace_general_8tex and its shared lighting transport.
-- Public VMT controls belong inside Proxies { CE8Surface { ... } }.
if SERVER then return end

CE8 = CE8 or {}
-- Existing sessions can still have the previous bytecode cached under these
-- program names. A fresh startup is required before using the new constants.
if CE8.MaterialLODReady == nil then CE8.MaterialLODReady = CE8.Controls == nil end
if include and file.Exists and file.Exists("lua/campaign_evolved/ce8_assembly.lua", "GAME") then
    include("campaign_evolved/ce8_assembly.lua")
end
local descriptor = util.JSONToTable(file.Read("lua/campaign_evolved/ce8_controls.json", "GAME") or "{}") or {}
CE8.Controls = descriptor.controls or {}
local lightHz = CreateClientConVar("ce8_light_hz", "20", true, false,
    "Refresh rate of CE8's six sampled map-light directions.", 1, 120)
local detailDistance = CreateClientConVar("ce8_detail_distance", "1024", true, false,
    "CE8 detail layers stop beyond this camera distance in units; 0 keeps them at all distances.", 0, 32768)
local normalDistance = CreateClientConVar("ce8_normal_distance", "2048", true, false,
    "CE8 normal maps stop beyond this camera distance in units; 0 keeps them at all distances.", 0, 32768)
local specularDistance = CreateClientConVar("ce8_specular_distance", "3072", true, false,
    "CE8 highlights and cubemap reflections stop beyond this camera distance; 0 keeps them at all distances.", 0, 32768)
local states = setmetatable({}, {__mode = "k"})

local function distanceWeight(distance, cutoff)
    if cutoff <= 0 then return 1 end
    local t = math.Clamp((cutoff-distance)/(cutoff*.25), 0, 1)
    return t*t*(3-2*t)
end

-- Called during material/render binding: use the actual view (including cameras
-- and possession), and distance to the model's bounding sphere, not its origin.
function CE8.MaterialLOD(ent)
    if not CE8.MaterialLODReady or not IsValid(ent) or not EyePos then return 1,1,1 end
    local eye = EyePos()
    if not isvector(eye) then return 1,1,1 end
    local d,n,s = detailDistance:GetFloat(),normalDistance:GetFloat(),specularDistance:GetFloat()
    local state = states[ent]
    if not state then state = {}; states[ent] = state end
    local frame = FrameNumber and FrameNumber() or -1
    local lod = state.lod
    if frame >= 0 and lod and lod.frame == frame and lod.x == eye.x and lod.y == eye.y
        and lod.z == eye.z and lod.d == d and lod.n == n and lod.s == s then
        return lod.detail,lod.normal,lod.specular
    end
    local center = ent:WorldSpaceCenter()
    local x,y,z = eye.x-center.x,eye.y-center.y,eye.z-center.z
    local radius = ent.BoundingRadius and ent:BoundingRadius() or 0
    local distance = math.max(0,math.sqrt(x*x+y*y+z*z)-math.max(radius,0))
    lod = {frame=frame,x=eye.x,y=eye.y,z=eye.z,d=d,n=n,s=s,
        detail=distanceWeight(distance,d),normal=distanceWeight(distance,n),specular=distanceWeight(distance,s)}
    state.lod = lod
    return lod.detail,lod.normal,lod.specular
end

-- Carry an 8-bit fade beside a scalar below8 in an existing SM3 constant.
-- Nonnegative values retain the old full-quality contract exactly. Neither
-- textures nor render-target parameter sheets change when the camera moves.
local function lodCarrier(value, weight)
    if weight >= 1 then return value end
    return -(value+8*(1+math.floor(weight*255+.5)))
end
local directions = {Vector(1,0,0), Vector(-1,0,0), Vector(0,1,0),
    Vector(0,-1,0), Vector(0,0,1), Vector(0,0,-1)}
local neutral = {Vector(.25,.25,.25), Vector(.25,.25,.25), Vector(.25,.25,.25),
    Vector(.25,.25,.25), Vector(.25,.25,.25), Vector(.25,.25,.25)}
local blendModes = {multiply = 0, overlay = 1, replace = 2}
local textureSlots = {
    albedotexture = "$basetexture", normaltexture = "$texture1",
    surfacetexture = "$texture2", paintmasktexture = "$texture3",
    emissiontexture = "$texture4", environmenttexture = "$texture5",
    featuretexture = "$texture6", environmentbrdftexture = "$texture7"
}
local textureCache = {}
local environmentTexture = "models/cubemaps/fallout4cube_dithered_grey"

local function number(value, default)
    local result = tonumber(value)
    if not result or result ~= result or result == math.huge or result == -math.huge then return default end
    return result
end

local function color(value)
    local parts = {}
    for part in string.gmatch(tostring(value or "1 1 1"), "[-+]?[%d%.]+[eE]?[-+]?%d*") do
        parts[#parts + 1] = math.max(number(part, 1), 0)
    end
    return Vector(parts[1] or 1, parts[2] or 1, parts[3] or 1)
end

local function linear(component)
    component = math.max(component, 0)
    if component <= .04045 then return component / 12.92 end
    return ((component + .055) / 1.055) ^ 2.4
end

-- Cache the conversion by components, not frame or Vector identity: palettes
-- can be edited in place between two draws of the same shared material.
local function linearColor(ent, key, x, y, z)
    local state = states[ent]
    if not state then state = {}; states[ent] = state end
    local cached = state[key]
    if not cached then cached = {}; state[key] = cached end
    if cached.x ~= x or cached.y ~= y or cached.z ~= z then
        cached.x, cached.y, cached.z = x, y, z
        cached.value = Vector(linear(x), linear(y), linear(z))
    end
    return cached.value
end

local paintFields = {"CampaignPortColor", "CampaignPortColor2", "CampaignPortColor3", "CampaignPortColor4"}
local paintFlags = {"ce_campaign_has_color", "ce_campaign_has_color2", "ce_campaign_has_color3", "ce_campaign_has_color4"}
local paintNetwork = {"ce_campaign_color", "ce_campaign_color2", "ce_campaign_color3", "ce_campaign_color4"}
local function entityPaint(ent, region)
    if not IsValid(ent) then return end
    local value = ent[paintFields[region]]
    if not isvector(value) and ent:GetNW2Bool(paintFlags[region], false) then
        value = ent:GetNW2Vector(paintNetwork[region], vector_origin)
    end
    -- Match the current roster's public palette API: entity colors are sRGB.
    -- Material PaintColor1..4 defaults are already linear and never pass here.
    if isvector(value) then return linearColor(ent, region, value.x, value.y, value.z) end
end

local function lighting(ent)
    if not IsValid(ent) then return neutral end
    local state = states[ent]
    if not state then state = {}; states[ent] = state end
    if not state.lights or RealTime() >= state.nextLight then
        state.nextLight = RealTime() + 1 / math.Clamp(lightHz:GetFloat(), 1, 120)
        state.lights = {}
        local position = CE8.LightPosition and CE8.LightPosition(ent) or ent:WorldSpaceCenter()
        for index, direction in ipairs(directions) do
            local ok, sample = pcall(render.ComputeLighting, position, direction)
            state.lights[index] = ok and isvector(sample) and sample or vector_origin
        end
    end
    return state.lights
end

CE8.AmbientLighting=lighting

local function namedTexture(reference, cube)
    local key = (cube and "ldr-cube:" or "2d:") .. reference
    if textureCache[key] then return textureCache[key] end
    -- Load the named VTF directly, preserving its cube flag and LDR samples.
    local helper = CreateMaterial("ce8_texture_" .. util.CRC(key),
        "UnlitGeneric", {["$basetexture"] = reference})
    local texture = helper:GetTexture("$basetexture")
    if texture and not texture:IsError() then textureCache[key] = texture; return texture end
    ErrorNoHalt("CE8: cannot load named texture " .. reference .. "\n")
end

CE8.NamedTexture=namedTexture

local textureBindings
local refreshedMaterials=setmetatable({}, {__mode="k"})
function CE8.RefreshMaterialTextures(material)
    if not material.GetName or refreshedMaterials[material] then return end
    if not textureBindings then
        local descriptor=util.JSONToTable(file.Read("lua/campaign_evolved/ce8_texture_bindings.json","GAME") or "{}") or {}
        textureBindings=descriptor.materials or {}
    end
    local bindings=textureBindings[string.lower(material:GetName())]
    if type(bindings)=="table" then
        for slot,reference in pairs(bindings) do
            local texture=namedTexture(reference,false)
            if texture then material:SetTexture(slot,texture) end
        end
    end
    refreshedMaterials[material]=true
end

local function meanLighting(samples)
    if samples.meanX then return samples.meanX, samples.meanY, samples.meanZ end
    local x,y,z = 0,0,0
    for _,sample in ipairs(samples) do x=x+sample.x; y=y+sample.y; z=z+sample.z end
    samples.meanX,samples.meanY,samples.meanZ = x/6,y/6,z/6
    return samples.meanX,samples.meanY,samples.meanZ
end

local paintRegisters = {
    {"$c0_x","$c0_y","$c0_z","$c0_w"}, {"$c1_x","$c1_y","$c1_z","$c1_w"},
    {"$c2_x","$c2_y","$c2_z","$c2_w"}, {"$c3_x","$c3_y","$c3_z","$c3_w"}
}
local function writeColor(material, region, value, scalar)
    local fields = paintRegisters[region]
    material:SetFloat(fields[1], value.x)
    material:SetFloat(fields[2], value.y)
    material:SetFloat(fields[3], value.z)
    material:SetFloat(fields[4], scalar)
end

local function overallColor(self,ent)
    if not self.overallPaintMode then return nil end
    local value=IsValid(ent) and ent.CE8OverallColor or nil
    if not isvector(value) and IsValid(ent) and ent.GetColor then
        local rgba=ent.CE8BoundRenderColor or ent:GetColor()
        if rgba.r~=255 or rgba.g~=255 or rgba.b~=255 then
            return linearColor(ent, "overall", rgba.r/255, rgba.g/255, rgba.b/255)
        end
    end
    if isvector(value) then return linearColor(ent, "overall", value.x, value.y, value.z) end
end

local function parameter(self, overrides, key)
    local value = overrides and overrides[key]
    -- Defaults were validated in init. Most draws have no live overrides.
    if value == nil then return self.defaults[key] end
    local schema = CE8.Controls[key]
    return math.Clamp(number(value, self.defaults[key]), schema.min, schema.max)
end

local function writePaint(self, material, ent)
    if CE8.MaterialOwner then ent = CE8.MaterialOwner(ent) end
    local overrides = IsValid(ent) and ent.CE8Parameters or nil
    local colors = self.paintColors
    local sharedColor=overallColor(self,ent)
    for region = 1, 4 do
        colors[region] = (region ~= 1 or not self.lockFirst) and (entityPaint(ent,region) or sharedColor) or nil
        colors[region] = colors[region] or self.colors[region]
    end
    local detail,normal,specular = CE8.MaterialLOD(ent)
    writeColor(material, 1, colors[1], lodCarrier(parameter(self,overrides,"normalstrength")*normal,detail))
    writeColor(material, 2, colors[2], parameter(self,overrides,"roughnessscale"))
    writeColor(material, 3, colors[3], parameter(self,overrides,"roughnessbias"))
    writeColor(material, 4, colors[4], parameter(self,overrides,"metallicscale"))
    return overrides,specular
end

local surfaceProxy = {
    name = "CE8Surface",
    init = function(self, material, values)
        self.defaults, self.colors, self.paintColors = {}, {}, {}
        for key, schema in pairs(CE8.Controls) do
            self.defaults[key] = math.Clamp(number(values[key], schema.default), schema.min, schema.max)
        end
        self.blends = 0
        for region = 1, 4 do
            self.colors[region] = color(values["paintcolor" .. region])
            local mode = string.lower(tostring(values["paintblend" .. region] or "multiply"))
            if not blendModes[mode] then
                ErrorNoHalt("CE8: unknown PaintBlend" .. region .. " " .. mode .. "; using multiply\n")
                mode = "multiply"
            end
            self.blends = self.blends + blendModes[mode] * 4 ^ (region - 1)
        end
        self.lockFirst = number(values.lockpaint1, 0) ~= 0
        self.overallPaintMode = number(values.overallpaintmode,0) ~= 0
        local layoutCodes={["1x1"]=0,["2x1"]=1,["2x2"]=2,["4x2"]=3,["4x4"]=4}
        local columns=math.floor(number(values.atlascolumns,1))
        local rows=math.floor(number(values.atlasrows,1))
        local layout=assert(layoutCodes[columns.."x"..rows],"CE8: unsupported atlas layout")
        local function cellBits(name)
            local size=math.max(number(values[name],32),32)
            local exponent=math.floor(math.log(size)/math.log(2)+.5)-5
            assert(exponent>=0 and exponent<=7 and 2^(exponent+5)==size,"CE8: invalid atlas cell size")
            return exponent
        end
        -- Exact integer transport below 2^24; author controls remain named.
        self.surfaceBits=self.blends+layout*256+cellBits("albedocellpixels")*2048
            +cellBits("normalcellpixels")*16384+cellBits("surfacecellpixels")*131072
            +cellBits("paintmaskcellpixels")*1048576
            +(number(values.emissionfromsurface,0)~=0 and 8388608 or 0)
        self.environmentTint = color(values.environmenttint)
        -- Resolve old cached VMTs through the same shared cube on a Lua reload.
        self.environmentReference = values.environmenttexture
        if not self.environmentReference or self.environmentReference == "env_cubemap" then
            self.environmentReference = environmentTexture
        end
        self.environmentTexture = nil
        self.matrixA, self.matrixB = Matrix(), Matrix()
        for name, slot in pairs(textureSlots) do
            if values[name] and not (self.directPass and name == "environmenttexture") then
                local reference = values[name]
                if name == "environmenttexture" then reference = self.environmentReference end
                local texture = namedTexture(reference, name == "environmenttexture")
                if texture then material:SetTexture(slot, texture) end
            end
        end
    end,
    bind = function(self, material, ent)
        if CE8.MaterialOwner then ent = CE8.MaterialOwner(ent) end
        -- A shared neutral cube supplies reflection detail. Only lighting at
        -- this model controls exposure; map capture brightness is irrelevant.
        if not self.directPass then
            local texture = namedTexture(self.environmentReference or environmentTexture, true)
            if texture and texture ~= self.environmentTexture then
                material:SetTexture("$texture5", texture)
                self.environmentTexture = texture
            end
        end
        local modelSlot=CE8.SceneModel and CE8.SceneModel(ent) or 0
        local scene=CE8.SceneMaterial and CE8.SceneMaterial(material,not self.liveRecord and CE8.SceneState.brdf)
        self.sceneActive=scene
        -- Always reset every field at bind, including unbound/editor draws.
        -- Two entities sharing one VMT cannot inherit each other's palette/state.
        local overrides,specular = writePaint(self, material, ent)
        local lights = lighting(ent)
        local x, nx, y, ny, z, nz = unpack(lights)
        local tint = IsValid(ent) and ent.CE8EnvironmentTint or nil
        if isvector(tint) then tint = linearColor(ent, "environment", tint.x, tint.y, tint.z)
        else tint = self.environmentTint end
        local influence = parameter(self,overrides,"environmentlightinfluence")
        local strength = parameter(self,overrides,"environmentstrength")
        local meanX,meanY,meanZ=meanLighting(lights)
        local exposureX = math.Clamp(meanX,0,1)
        local exposureY = math.Clamp(meanY,0,1)
        local exposureZ = math.Clamp(meanZ,0,1)
        local red = tint.x * strength * (1-influence + influence*exposureX)
        local green = tint.y * strength * (1-influence + influence*exposureY)
        local blue = tint.z * strength * (1-influence + influence*exposureZ)
        local ambient = parameter(self,overrides,"ambientstrength")
        self.matrixA:SetUnpacked(
            x.x*ambient, x.y*ambient, x.z*ambient, parameter(self,overrides,"metallicbias"),
            nx.x*ambient, nx.y*ambient, nx.z*ambient, red,
            y.x*ambient, y.y*ambient, y.z*ambient, parameter(self,overrides,"emissionstrength"),
            ny.x*ambient, ny.y*ambient, ny.z*ambient, blue)
        self.matrixB:SetUnpacked(
            z.x*ambient, z.y*ambient, z.z*ambient, green,
            nz.x*ambient, nz.y*ambient, nz.z*ambient, parameter(self,overrides,"basestrength"),
            parameter(self,overrides,"iridescenceweight"), parameter(self,overrides,"iridescencethickness"),
            parameter(self,overrides,"iridescencebrightness"), parameter(self,overrides,"iridescencesaturation"),
            self.surfaceBits, parameter(self,overrides,"alphacutoff"), parameter(self,overrides,"environmentmaxmip"),
            lodCarrier(parameter(self,overrides,"debugview"),specular))
        if scene then
            self.matrixA:SetUnpacked(red,green,blue,parameter(self,overrides,"basestrength"),
                parameter(self,overrides,"metallicbias"),parameter(self,overrides,"emissionstrength"),
                parameter(self,overrides,"specularstrength"),ambient,
                ((modelSlot%32)*32+.5)/1024,(192+math.floor(modelSlot/32)+.5)/1024,0,0,
                parameter(self,overrides,"flashlightstrength"),0,0,0)
            material:SetTexture("$texture7",CE8.SceneState.texture)
        end
        material:SetMatrix("$viewprojmat", self.matrixA)
        material:SetMatrix("$invviewprojmat", self.matrixB)
    end
}
matproxy.Add(surfaceProxy)
local directProxy = {
    name = "CE8Light",
    init = function(self, material, values)
        self.directPass = true
        surfaceProxy.init(self, material, values)
        self.whiteCookie = namedTexture("color/white", false)
    end,
    bind = function(self, material, ent)
        local overrides,specular = writePaint(self, material, ent)
        local light = IsValid(ent) and ent.CE8ActiveLight or nil
        local batch=IsValid(ent) and ent.CE8ActiveLightBatch or nil
        if batch then
            material:SetTexture("$texture5",batch.texture)
            self.matrixA:SetUnpacked(unpack(batch.ids,1,16))
            local debug=parameter(self,overrides,"debugview")>.5
            self.matrixB:SetUnpacked(
                debug and 0 or batch.count,parameter(self,overrides,"flashlightstrength"),
                parameter(self,overrides,"lampstrength"),parameter(self,overrides,"pointlightstrength"),
                0,0,0,0,
                parameter(self,overrides,"metallicbias"),parameter(self,overrides,"specularstrength"),
                parameter(self,overrides,"alphacutoff"),parameter(self,overrides,"basestrength"),
                self.surfaceBits,0,-1,lodCarrier(.02,specular))
        elseif not light then
            self.matrixA:SetUnpacked(0,0,0,0, 0,0,0,1, 1,0,0,1, 0,-1,0,1)
            self.matrixB:SetUnpacked(0,0,1,1, 0,0,0,0, 0,0,-1,1, 0,0,0,.02)
        else
            local p, c = light.position, light.color
            local f, r, u = light.forward, light.right, light.up
            local attenuation = light.attenuation
            local strength = light.mapLight and 1 or parameter(self,overrides,light.category == "flashlight" and "flashlightstrength"
                or light.category == "lamp" and "lampstrength" or "pointlightstrength")
            if parameter(self,overrides,"debugview") > .5 then strength = 0 end
            material:SetTexture("$texture5", light.cookie or self.whiteCookie)
            self.matrixA:SetUnpacked(
                p.x,p.y,p.z,light.directional and -1 or light.mapLight and (light.spot and 3 or 2) or light.spot and 1 or 0,
                c.x,c.y,c.z,light.range,
                f.x,f.y,f.z,light.mapLight and light.coneInner or light.near,
                r.x,r.y,r.z,light.mapLight and light.coneOuter or light.tangentHorizontal)
            self.matrixB:SetUnpacked(
                u.x,u.y,u.z,light.mapLight and light.coneExponent or light.tangentVertical,
                attenuation.x,attenuation.y,attenuation.z,strength*(light.visibility or 1),
                parameter(self,overrides,"metallicbias"),parameter(self,overrides,"specularstrength"),parameter(self,overrides,"alphacutoff"),parameter(self,overrides,"basestrength"),
                self.surfaceBits,light.diffuse or 1,light.cookie and 1 or 0,lodCarrier(.02,specular))
        end
        material:SetMatrix("$viewprojmat", self.matrixA)
        material:SetMatrix("$invviewprojmat", self.matrixB)
    end
}
matproxy.Add(directProxy)

-- Families share the verified model/light transport, then write their own
-- named effect controls into the otherwise unused paint-color fields.
function CE8.RegisterSurfaceVariant(name, direct, initialize, bind)
    local parent = direct and directProxy or surfaceProxy
    matproxy.Add({name=name,
        init=function(self, material, values)
            parent.init(self, material, values)
            initialize(self, material, values)
        end,
        bind=function(self, material, ent)
            parent.bind(self, material, ent)
            bind(self, material, ent)
        end})
end

if include then include("campaign_evolved/ce8_lighting.lua") end
if include and file.Exists("lua/campaign_evolved/ce8_hunter.lua", "GAME") then
    include("campaign_evolved/ce8_hunter.lua")
end
if include and file.Exists("lua/campaign_evolved/ce8_live_details.lua", "GAME") then
    include("campaign_evolved/ce8_live_details.lua")
end
if include then include("campaign_evolved/ce8_blade.lua"); include("campaign_evolved/ce8_shield.lua"); include("campaign_evolved/ce8_gauge.lua") end
CE8.SupportsOverallPaint=true
