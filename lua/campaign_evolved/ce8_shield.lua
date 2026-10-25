-- Jackal energy barrier; shares the sword's sorted emissive renderer and LOD.
-- No map, projector, cubemap, normal-map or specular lighting is sampled here.
if SERVER then return end
CE8=CE8 or {}
local defaults={
    ShieldBrightness=2,ShieldOpacity=1,ShieldReveal=1,ColorPower=2,
    ShieldVitality=1,ShieldDamageTint=1,
    EnergyScaleU=15,EnergyScaleV=.25,EnergyPanU=.01,EnergyPanV=.5,
    PatternScaleU=11,PatternScaleV=3,PatternPower=3,PatternGain=.2,
    DistortionScaleU=3,DistortionScaleV=.35,DistortionPanU=-.0125,DistortionPanV=.055,
    NoiseScaleU=3.5,NoiseScaleV=1.5,NoisePanU=-.07,NoisePanV=.3,
    HighlightScaleU=7,HighlightScaleV=1,HighlightPanU=-.15,HighlightPanV=1,
    PlasmaPanU=.1,PlasmaPanV=.13,Plasma2PanU=0,Plasma2PanV=.08,
    EnergyPower=5,EnergyGain=.2,EdgeGain=3,NotchGain=3,
    DistortionStrength=.044,BaseOpacity=.18,InnerPower=30,InnerGain=2
}
local function finite(value,fallback)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return fallback end
    return math.Clamp(value,-1000,1000)
end
local function rgb(value,fallback)
    local out={}
    for v in tostring(value or fallback):gmatch("[-+]?[%d%.]+[eE]?[-+]?%d*") do out[#out+1]=finite(v,0) end
    return {out[1] or 0,out[2] or 0,out[3] or 0}
end
-- C_JackalShieldVitality_Color: two unweighted cubic keys per RGB channel.
-- Native red/blue tangents match; green catches up near depletion. The cooked
-- material links are absent, so blending this ramp by lost strength is our mapping.
local function damageChannel(t,leave,arrive)
    local t2,t3=t*t,t*t*t
    return math.Clamp((2*t3-3*t2+1)*5.386724e-8+(t3-2*t2+t)*leave
        +(-2*t3+3*t2)+(t3-t2)*arrive,0,1)
end
matproxy.Add({name="CE8Shield",
    init=function(self,material,values)
        if CE8.RefreshMaterialTextures then CE8.RefreshMaterialTextures(material) end
        self.defaults={}
        for name,value in pairs(defaults) do self.defaults[name:lower()]=finite(values[name:lower()],value) end
        self.outer=rgb(values.shieldcolor,"0 .244171 .625")
        self.inner=rgb(values.innercolor,".162029 .693872 .527115")
        self.a,self.b=Matrix(),Matrix()
    end,
    bind=function(self,material,ent)
        if CE8.RefreshMaterialTextures then CE8.RefreshMaterialTextures(material) end
        local overrides=IsValid(ent) and ent.CE8Parameters or nil
        local function p(name)
            name=name:lower()
            return finite(overrides and overrides[name],self.defaults[name])
        end
        local function row(i,x,y,z,w)
            local prefix="$c"..i.."_"
            material:SetFloat(prefix.."x",x);material:SetFloat(prefix.."y",y)
            material:SetFloat(prefix.."z",z);material:SetFloat(prefix.."w",w)
        end
        local detail,normal=1,1
        if CE8.MaterialLOD then detail,normal=CE8.MaterialLOD(ent) end
        local outer=overrides and overrides.shieldcolor and rgb(overrides.shieldcolor) or self.outer
        local inner=overrides and overrides.innercolor and rgb(overrides.innercolor) or self.inner
        local eye=EyePos()
        local reveal,flash=1,0
        local vitality=math.Clamp(p("ShieldVitality"),0,1)
        local owner=IsValid(ent) and ent.GetNW2Entity and ent:GetNW2Entity("ce8_barrier_owner")
        if IsValid(owner) then
            local maximum=owner:GetNW2Float("ce8_barrier_max",-1)
            if maximum>=0 and not (overrides and overrides.shieldvitality~=nil) then
                vitality=maximum>0 and math.Clamp(owner:GetNW2Float("ce8_barrier_value",maximum)/maximum,0,1) or 0
            end
            if owner:GetNW2Bool("ce8_barrier_down",false) then reveal=0 end
            local restored=owner:GetNW2Float("ce8_barrier_restored",-1)
            if restored>=0 then reveal=reveal*math.Clamp((CurTime()-restored)/.25,0,1) end
            flash=math.Clamp(1-(CurTime()-owner:GetNW2Float("ce8_barrier_hit",-100))/.15,0,1)
        end
        local r,g,b=outer[1],outer[2],outer[3]
        local ir,ig,ib=inner[1],inner[2],inner[3]
        local damage=1-vitality
        local tint=damage*math.Clamp(p("ShieldDamageTint"),0,1)
        if tint>0 then
            local red=damageChannel(damage,1.9021909,0)
            local green=damageChannel(damage,.18983896,4.097324)
            r,g,b=r+(red-r)*tint,g+(green-g)*tint,b+(red-b)*tint
            ir,ig,ib=ir+(red-ir)*tint,ig+(green-ig)*tint,ib+(red-ib)*tint
        end
        row(0,r,g,b,math.max(p("ShieldBrightness"),0)*(1+flash))
        row(1,ir,ig,ib,math.Clamp(p("ShieldOpacity"),0,1))
        row(2,CurTime(),detail,math.min(detail,normal),math.Clamp(p("ShieldReveal"),0,1)*reveal)
        row(3,eye.x,eye.y,eye.z,math.max(.01,p("ColorPower")))
        self.a:SetUnpacked(
            p("EnergyScaleU"),p("EnergyScaleV"),p("EnergyPanU"),p("EnergyPanV"),
            p("PatternScaleU"),p("PatternScaleV"),math.max(.01,p("PatternPower")),p("PatternGain"),
            p("DistortionScaleU"),p("DistortionScaleV"),p("DistortionPanU"),p("DistortionPanV"),
            p("NoiseScaleU"),p("NoiseScaleV"),p("NoisePanU"),p("NoisePanV"))
        self.b:SetUnpacked(
            p("HighlightScaleU"),p("HighlightScaleV"),p("HighlightPanU"),p("HighlightPanV"),
            p("PlasmaPanU"),p("PlasmaPanV"),p("Plasma2PanU"),p("Plasma2PanV"),
            math.max(.01,p("EnergyPower")),p("EnergyGain"),p("EdgeGain"),p("NotchGain"),
            p("DistortionStrength"),math.Clamp(p("BaseOpacity"),0,1),math.max(.01,p("InnerPower")),p("InnerGain"))
        material:SetMatrix("$viewprojmat",self.a);material:SetMatrix("$invviewprojmat",self.b)
    end})
