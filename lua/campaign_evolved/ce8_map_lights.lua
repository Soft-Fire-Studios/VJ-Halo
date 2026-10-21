-- Transport authored BSP lights into the CE material's existing specular pass.
-- The BSP header/record layout is an engine file-format contract; material
-- response remains the CE GGX/dual-lobe implementation in the 8tex programs.
if SERVER then return end
CE8 = CE8 or {}
local enabled = CreateClientConVar("ce8_map_lights", "1", true, false,
    "Include authored map sun/point/spot lights in CE8 specular passes.", 0, 1)
local maximumBytes = 2 * 1024 * 1024
local function uint(data, at)
    local a,b,c,d = data:byte(at,at+3)
    if not d then return end
    return a+b*256+c*65536+d*16777216
end
local function float(data, at)
    local bits = uint(data,at)
    if not bits then return end
    local exponent, fraction = math.floor(bits/8388608)%256, bits%8388608/8388608
    if exponent == 255 then return end
    local sign = bits >= 2147483648 and -1 or 1
    return sign * math.ldexp(exponent == 0 and fraction or 1+fraction,
        exponent == 0 and -126 or exponent-127)
end
local function vector(data, at)
    local x,y,z = float(data,at),float(data,at+4),float(data,at+8)
    if not x or not y or not z then return end
    return Vector(x,y,z)
end
function CE8.DecodeMapWorldLights(data, version)
    if version ~= 0 then return nil,"unsupported worldlight record version "..tostring(version) end
    if type(data) ~= "string" or #data > maximumBytes or #data%88 ~= 0 then
        return nil,"invalid worldlight record length"
    end
    local sources, counts = {}, {}
    for at=1,#data,88 do
        local kind = uint(data,at+40)
        counts[kind] = (counts[kind] or 0)+1
        -- Sky ambient is already in ComputeLighting. Surface/quakelight emitters
        -- need a separately verified area/falloff contract and are not guessed.
        if kind == 1 or kind == 2 or kind == 3 then
            local position,intensity,normal = vector(data,at),vector(data,at+12),vector(data,at+24)
            local radius = float(data,at+60)
            local constant,linear,quadratic = float(data,at+64),float(data,at+68),float(data,at+72)
            local inner,outer,exponent = float(data,at+48),float(data,at+52),float(data,at+56)
            local owner = uint(data,at+84)
            if position and intensity and normal and radius and constant and linear and quadratic
                and inner and outer and exponent and owner == 0 then
                local squared = normal.x^2+normal.y^2+normal.z^2
                if kind == 1 or squared > 1e-12 then
                    if squared > 1e-12 then
                        local scale = 1/math.sqrt(squared)
                        normal = Vector(normal.x*scale,normal.y*scale,normal.z*scale)
                    end
                    sources[#sources+1] = {key="map:"..tostring((at-1)/88),position=position,
                        color=intensity,forward=normal,directional=kind==3,spot=kind==2,
                        range=radius>0 and math.min(radius,32768) or 32768,
                        attenuation=Vector(math.max(constant,0),math.max(linear,0),math.max(quadratic,0)),
                        coneInner=inner,coneOuter=outer,coneExponent=math.max(exponent,0),
                        mapLight=true,diffuse=0,category="map",style=uint(data,at+44),record=(at-1)/88}
                end
            end
        end
    end
    return sources,nil,counts
end
local mapName,hdrMode,cached
local function readLump(handle, header, index)
    local at=9+index*16
    local offset,length,version,uncompressed = uint(header,at),uint(header,at+4),uint(header,at+8),uint(header,at+12)
    if not offset or not length or length == 0 then return end
    if length > maximumBytes or offset < 1036 or offset+length > handle:Size() then
        return nil,"invalid worldlight lump bounds"
    end
    handle:Seek(offset)
    local data=handle:Read(length)
    if data:sub(1,4)=="LZMA" then
        local original,packed=uint(data,5),uint(data,9)
        if not original or not packed or original>maximumBytes or packed+17>#data then
            return nil,"invalid compressed worldlight lump"
        end
        -- GMod's decoder consumes size:uint64, properties:5 bytes, raw LZMA.
        local ok,decoded=pcall(util.Decompress,data:sub(5,8)..string.rep("\0",4)..data:sub(13,17)..data:sub(18,17+packed),maximumBytes)
        if not ok or not decoded or #decoded~=original then return nil,"cannot decode worldlight LZMA" end
        data=decoded
    elseif uncompressed~=0 then return nil,"unknown compressed worldlight lump" end
    local result,message,counts=CE8.DecodeMapWorldLights(data,version)
    return result,message,{lump=index,version=version,bytes=#data,counts=counts}
end
function CE8.GetMapLightSources()
    if enabled:GetFloat() <= 0 then return {} end
    local map,hdr = game.GetMap(),render.GetHDREnabled and render.GetHDREnabled() or false
    if cached and mapName==map and hdrMode==hdr then return cached end
    mapName,hdrMode,cached=map,hdr,{}
    -- Lua exposes no current light-style brightness getter. Retain authored
    -- radiance (including named sun styles); runtime style switches/animation
    -- remain an explicit transport limitation, rather than guessing a state.
    local report={map=map,hdr=hdr,source="maps/"..map..".bsp",
        lightStyles="authored_static_radiance; runtime_style_changes_unavailable"}
    CE8.MapLightReport=report
    local handle=file.Open(report.source,"rb","GAME")
    if not handle then report.error="BSP not readable";return cached end
    local header=handle:Read(1036)
    if #header~=1036 or header:sub(1,4)~="VBSP" then handle:Close();report.error="invalid BSP header";return cached end
    report.bspVersion=uint(header,5)
    local result,message,metadata=readLump(handle,header,hdr and 54 or 15)
    if not result and hdr then result,message,metadata=readLump(handle,header,15) end
    handle:Close()
    if result then cached=result;for key,value in pairs(metadata) do report[key]=value end
    else report.error=message or "map contains no readable worldlights" end
    report.active=#cached
    if report.error then ErrorNoHalt("CE8 map lights: "..report.error.."\n") end
    return cached
end
if CE8.RegisterLightProvider then CE8.RegisterLightProvider("authored_map",CE8.GetMapLightSources,true) end
