-- Native material startup and optional energy-layer distance controls.
if SERVER then return end
CE8=CE8 or {}
CE8.MaterialLODReady=true
local detailDistance=CreateClientConVar("ce8_detail_distance","1024",true,false,
    "Animated energy detail distance; 0 is unlimited.",0,32768)
local normalDistance=CreateClientConVar("ce8_normal_distance","2048",true,false,
    "Energy refraction distance; native body normals remain engine-controlled.",0,32768)
local states=setmetatable({}, {__mode="k"})
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
    local d,n,s = detailDistance:GetFloat(),normalDistance:GetFloat(),0
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


include("campaign_evolved/ce8_gauge.lua")
include("campaign_evolved/ce8_energy.lua")
include("campaign_evolved/ce8_bloom.lua")
