-- Native CE weapon displays, independent of the model lighting passes.
if SERVER then return end
CE8=CE8 or {}
local defaults={GaugeMode=0,GaugeValue=0,GaugeBrightness=1,GaugeOpacity=1,
    GaugeClip=0,PackedScale=.725,RotationSpeed=0,
    GainA=1,GainB=1,GainC=1,ScanlineLow=1,
    UVScaleU=1,UVScaleV=1,UVOffsetU=0,UVOffsetV=0,
    SpentIntensity=.1,GlowIntensity=.5,HeatFillSoftness=.04}
local function finite(value,fallback)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return fallback end
    return value
end
local function rgb(value,fallback)
    if value==nil then return fallback end
    if type(value)=="table" then
        return {finite(value[1],fallback[1]),finite(value[2],fallback[2]),finite(value[3],fallback[3])}
    end
    local out={}
    for n in tostring(value or ""):gmatch("[-+]?[%d%.]+[eE]?[-+]?%d*") do out[#out+1]=finite(n,0) end
    return {out[1] or fallback[1],out[2] or fallback[2],out[3] or fallback[3]}
end
-- Heat is sent only when its slope changes. Each weapon retains its own state.
function CE8.WeaponGaugeValue(ent,kind,fallback)
    if not IsValid(ent) then return fallback end
    local explicit=finite(ent.CE8GaugeValue,nil)
    if explicit~=nil then return math.Clamp(explicit,0,1) end
    local data=ent.CE8Data
    if kind=="heat" and data and data.heat and ent.GetNW2Vector then
        local state=ent:GetNW2Vector("ce8_weapon_heat",vector_origin)
        local raw=math.max(0,finite(state.x,0)-math.max(0,CurTime()-finite(state.y,CurTime()))*math.max(0,finite(state.z,0)))
        return math.Clamp(raw/math.max(.0001,finite(data.heat.threshold,1)),0,1)
    elseif kind=="ammo" and data and ent.Clip1 and finite(data.clip,0)>0 then
        -- NPC clips are explicitly replicated to spectators as well as owners.
        local rounds=ent.GetNW2Int and ent:GetNW2Int("ce8_weapon_ammo",-1) or -1
        if rounds<0 then rounds=finite(ent:Clip1(),-1) end
        if rounds>=0 then return math.Clamp(rounds/data.clip,0,1) end
    end
    return fallback
end
local function parameter(self,overrides,name)
    local value=overrides and overrides[name]
    return value==nil and self.defaults[name] or finite(value,self.defaults[name])
end
local function color(self,overrides,name,key)
    return rgb(overrides and overrides[key],self.colors[name])
end
local registers={
    {"$c0_x","$c0_y","$c0_z","$c0_w"},{"$c1_x","$c1_y","$c1_z","$c1_w"},
    {"$c2_x","$c2_y","$c2_z","$c2_w"},{"$c3_x","$c3_y","$c3_z","$c3_w"}
}
local function row(material,index,x,y,z,w)
    local names=registers[index+1]
    material:SetFloat(names[1],x);material:SetFloat(names[2],y)
    material:SetFloat(names[3],z);material:SetFloat(names[4],w)
end
matproxy.Add({name="CE8Gauge",
    init=function(self,material,values)
        if CE8.RefreshMaterialTextures then CE8.RefreshMaterialTextures(material) end
        if CE8.NamedTexture then
            for index,name in ipairs({"gaugetexture","masktexture","detailtexture"}) do
                if values[name] then
                    local texture=CE8.NamedTexture(values[name],false)
                    if texture then material:SetTexture(index==1 and "$basetexture" or "$texture"..(index-1),texture) end
                end
            end
        end
        self.defaults={}
        for name,value in pairs(defaults) do self.defaults[name:lower()]=finite(values[name:lower()],value) end
        self.kind=tostring(values.gaugestate or "static"):lower()
        self.colors={tint=rgb(values.gaugetint,{1,1,1}),a=rgb(values.colora,{1,1,1}),
            b=rgb(values.colorb,{1,1,1}),c=rgb(values.colorc,{1,1,1}),d=rgb(values.colord,{1,1,1})}
        self.a,self.b=Matrix(),Matrix()
    end,
    bind=function(self,material,ent)
        if CE8.RefreshMaterialTextures then CE8.RefreshMaterialTextures(material) end
        local overrides=IsValid(ent) and ent.CE8Parameters or nil
        local detail=1
        if CE8.MaterialLOD then detail=CE8.MaterialLOD(ent) end
        local value=CE8.WeaponGaugeValue(ent,self.kind,math.Clamp(parameter(self,overrides,"gaugevalue"),0,1))
        local tint,a,b,c,d=color(self,overrides,"tint","gaugetint"),color(self,overrides,"a","colora"),
            color(self,overrides,"b","colorb"),color(self,overrides,"c","colorc"),color(self,overrides,"d","colord")
        row(material,0,parameter(self,overrides,"gaugemode"),value,CurTime(),detail)
        row(material,1,tint[1],tint[2],tint[3],math.max(0,parameter(self,overrides,"gaugebrightness")))
        row(material,2,a[1],a[2],a[3],math.Clamp(parameter(self,overrides,"gaugeopacity"),0,1))
        row(material,3,b[1],b[2],b[3],math.Clamp(parameter(self,overrides,"gaugeclip"),0,1))
        self.a:SetUnpacked(c[1],c[2],c[3],math.max(.001,parameter(self,overrides,"packedscale")),
            d[1],d[2],d[3],parameter(self,overrides,"rotationspeed"),
            parameter(self,overrides,"gaina"),parameter(self,overrides,"gainb"),parameter(self,overrides,"gainc"),math.Clamp(parameter(self,overrides,"scanlinelow"),0,1),
            parameter(self,overrides,"uvscaleu"),parameter(self,overrides,"uvscalev"),parameter(self,overrides,"uvoffsetu"),parameter(self,overrides,"uvoffsetv"))
        self.b:SetUnpacked(math.max(0,parameter(self,overrides,"spentintensity")),math.max(0,parameter(self,overrides,"glowintensity")),math.max(.001,parameter(self,overrides,"heatfillsoftness")),0,
            0,0,0,0,0,0,0,0,0,0,0,0)
        material:SetMatrix("$viewprojmat",self.a);material:SetMatrix("$invviewprojmat",self.b)
    end})
