-- Emissive default plasma blade. Independent of CE8Surface's light sampling.
if SERVER then return end
CE8=CE8 or {}
local defaults={
    BladeBrightness=1.5, BladeOpacity=1, BladeReveal=1,
    EnergyGain=5, Energy2Gain=200, Energy2Power=6, Energy3Gain=75,
    EnergyScaleU=1.75, EnergyScaleV=.5, EnergyPanU=.05, EnergyPanV=.3,
    Energy2ScaleU=2, Energy2ScaleV=3, Energy2PanU=1, Energy2PanV=-.1,
    DistortionScaleU=1, DistortionScaleV=.7, DistortionPanU=-.1, DistortionPanV=.75,
    NoiseScaleU=1.25, NoiseScaleV=1.2, NoisePanU=-.07, NoisePanV=1,
    TopNoiseScaleU=1, TopNoiseScaleV=1.5, TopNoisePanU=-.01, TopNoisePanV=.5,
    PlasmaScaleU=3.5, PlasmaScaleV=2.5, PlasmaPanU=-.008, PlasmaPanV=.75,
    InnerOpacity=.2, OpacityPower=1.12, OpacityNoiseGain=3, EdgeGain=20,
    DistortionStrength=.15, FlowStrength=1.5, Energy3Power=8, TopNoisePower=2.5
}
local function finite(value,fallback)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return fallback end
    return math.Clamp(value,-1000,1000)
end
local function rgb(text,fallback)
    local values={}
    for value in tostring(text or fallback):gmatch("[-+]?[%d%.]+[eE]?[-+]?%d*") do
        values[#values+1]=finite(value,0)
    end
    return {values[1] or 0,values[2] or 0,values[3] or 0}
end
matproxy.Add({name="CE8Blade",
    init=function(self,material,values)
        if CE8.RefreshMaterialTextures then CE8.RefreshMaterialTextures(material) end
        local textures={"blademask","flowmap","energytexture","energy2texture",
            "distortiontexture","noisetexture","topnoisetexture","plasmatexture"}
        if CE8.NamedTexture then
            for index,name in ipairs(textures) do
                if values[name] then
                    local texture=CE8.NamedTexture(values[name],false)
                    if texture then material:SetTexture(index==1 and "$basetexture" or "$texture"..(index-1),texture) end
                end
            end
        end
        self.defaults={}
        for name,value in pairs(defaults) do
            self.defaults[name:lower()]=finite(values[name:lower()],value)
        end
        self.energy=rgb(values.energycolor,".191406 .56187 .984375")
        self.dark=rgb(values.darkcolor,".154104 .266125 .534722")
        self.a,self.b=Matrix(),Matrix()
    end,
    bind=function(self,material,ent)
        if CE8.RefreshMaterialTextures then CE8.RefreshMaterialTextures(material) end
        local overrides=IsValid(ent) and ent.CE8Parameters or nil
        local function p(name)
            name=name:lower()
            return finite(overrides and overrides[name],self.defaults[name])
        end
        local function row(index,x,y,z,w)
            local prefix="$c"..index.."_"
            material:SetFloat(prefix.."x",x);material:SetFloat(prefix.."y",y)
            material:SetFloat(prefix.."z",z);material:SetFloat(prefix.."w",w)
        end
        local detail,normal=1,1
        if CE8.MaterialLOD then detail,normal=CE8.MaterialLOD(ent) end
        row(0,self.energy[1],self.energy[2],self.energy[3],math.max(p("BladeBrightness"),0))
        row(1,self.dark[1],self.dark[2],self.dark[3],math.Clamp(p("BladeOpacity"),0,1))
        row(2,CurTime(),detail,math.min(detail,normal),math.Clamp(p("BladeReveal"),0,1))
        row(3,p("EnergyGain"),p("Energy2Gain"),math.max(.01,p("Energy2Power")),p("Energy3Gain"))
        self.a:SetUnpacked(
            p("EnergyScaleU"),p("EnergyScaleV"),p("EnergyPanU"),p("EnergyPanV"),
            p("Energy2ScaleU"),p("Energy2ScaleV"),p("Energy2PanU"),p("Energy2PanV"),
            p("DistortionScaleU"),p("DistortionScaleV"),p("DistortionPanU"),p("DistortionPanV"),
            p("NoiseScaleU"),p("NoiseScaleV"),p("NoisePanU"),p("NoisePanV"))
        self.b:SetUnpacked(
            p("TopNoiseScaleU"),p("TopNoiseScaleV"),p("TopNoisePanU"),p("TopNoisePanV"),
            p("PlasmaScaleU"),p("PlasmaScaleV"),p("PlasmaPanU"),p("PlasmaPanV"),
            math.Clamp(p("InnerOpacity"),0,1),math.max(.01,p("OpacityPower")),p("OpacityNoiseGain"),p("EdgeGain"),
            p("DistortionStrength"),p("FlowStrength"),math.max(.01,p("Energy3Power")),math.max(.01,p("TopNoisePower")))
        material:SetMatrix("$viewprojmat",self.a);material:SetMatrix("$invviewprojmat",self.b)
    end})
