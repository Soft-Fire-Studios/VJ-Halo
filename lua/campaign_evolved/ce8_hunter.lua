-- Named Hunter family controls. Original Combat Evolved assets, no flesh proxy.
if SERVER or not CE8 or not CE8.RegisterSurfaceVariant then return end
local schema=CE8.Controls or {}
local function finite(value,default)
    value=tonumber(value)
    if not value or value~=value or math.abs(value)==math.huge then return default end
    return value
end
local function initialize(self,material,values)
    self.hunterDefaults={}
    for key,info in pairs(schema) do
        self.hunterDefaults[key]=math.Clamp(finite(values[key],info.default),info.min,info.max)
    end
    local components={}
    for value in tostring(values.emissivetint or "1 1 1"):gmatch("[-+]?[%d%.]+[eE]?[-+]?%d*") do
        components[#components+1]=math.max(finite(value,1),0)
    end
    self.hunterEmissiveTint=Vector(components[1] or 1,components[2] or 1,components[3] or 1)
end
local function parameters(self,ent)
    if CE8.MaterialOwner then ent=CE8.MaterialOwner(ent) end
    return function(name)
        local key=string.lower(name)
        local info=schema[key]
        local overrides=IsValid(ent) and ent.CE8Parameters or nil
        return math.Clamp(finite(overrides and overrides[key],self.hunterDefaults[key]),info.min,info.max)
    end
end
local function component(material,prefix,x,y,z)
    material:SetFloat(prefix.."x",x)
    material:SetFloat(prefix.."y",y)
    material:SetFloat(prefix.."z",z)
end
local function worm(self,material,ent)
    local p=parameters(self,ent)
    component(material,"$c1_",p("WormTileU"),p("WormTileV"),CurTime()*p("CrawlSpeed"))
    component(material,"$c2_",p("SpecularLobeStrength"),p("WormNormalStrength"),p("CrawlAxis"))
    component(material,"$c3_",p("SpecularPower1"),p("SpecularPower2"),p("SpecularLobeBlend"))
end
local function plasma(self,material,ent)
    local p=parameters(self,ent)
    component(material,"$c1_",self.colors[2].x,self.colors[2].y,self.colors[2].z)
    component(material,"$c2_",CurTime()*p("FlowSpeed"),CurTime()*p("SineWaveSpeed"),p("NoiseTiling"))
    component(material,"$c3_",p("PlasmaFlowInfluence"),p("SineWaveAmount"),p("EnvironmentMaxMip"))
    material:SetFloat("$c1_w",p("PlasmaGlowIntensity"))
    material:SetFloat("$c2_w",p("EmissiveMultiplier"))
    material:SetFloat("$c3_w",p("BaseEmissiveContrast"))
    if not self.directPass then
        self.matrixB:SetField(3,1,self.hunterEmissiveTint.x)
        self.matrixB:SetField(3,2,self.hunterEmissiveTint.y)
        self.matrixB:SetField(3,3,self.hunterEmissiveTint.z)
        self.matrixB:SetField(3,4,p("PlasmaGlowPower"))
        self.matrixB:SetField(4,1,p("NoiseHeight1"))
        self.matrixB:SetField(4,2,p("NoiseHeight2"))
        self.matrixB:SetField(4,3,p("NoiseHeight3"))
        material:SetMatrix("$invviewprojmat",self.matrixB)
    end
end
CE8.RegisterSurfaceVariant("CE8Worm",false,initialize,worm)
CE8.RegisterSurfaceVariant("CE8WormLight",true,initialize,worm)
CE8.RegisterSurfaceVariant("CE8Plasma",false,initialize,plasma)
CE8.RegisterSurfaceVariant("CE8PlasmaLight",true,initialize,plasma)
