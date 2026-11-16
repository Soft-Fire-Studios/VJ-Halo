-- Native UnlitGeneric displays. Lua selects existing frames/transforms only.
if SERVER then return end
CE8=CE8 or {}
local function finite(value,fallback)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return fallback end
    return value
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

matproxy.Add({name="CE8Gauge",
    init=function(self,material,values)
        local lower={};for k,v in pairs(values) do lower[k:lower()]=v end;values=lower
        self.kind=values.gaugestate or "static"
        self.fallback=finite(values.gaugevalue,0)
        self.frames=math.max(1,math.floor(finite(values.framecount,1)))
        self.rotation=finite(values.rotationspeed,0)
        self.scan=finite(values.scanspeed,0)
        if self.rotation~=0 or self.scan~=0 then self.transform=Matrix() end
    end,
    bind=function(self,material,ent)
        local value=CE8.WeaponGaugeValue(ent,self.kind,self.fallback)
        local frame=math.Clamp(math.floor(value*(self.frames-1)+.5),0,self.frames-1)
        -- Cache on the material: alternating weapons must not share ammo/heat.
        if frame~=self.frame then material:SetInt("$frame",frame);self.frame=frame end
        if self.transform then
            local time=CurTime()
            if self.time==time then return end
            self.time=time
            local angle=time*self.rotation*math.pi*2
            local c,s=math.cos(angle),math.sin(angle)
            self.transform:SetUnpacked(c,-s,0,.5-.5*c+.5*s,
                s,c,0,.5-.5*s-.5*c+(time*self.scan)%1,0,0,1,0,0,0,0,1)
            material:SetMatrix(self.scan~=0 and "$detailtexturetransform" or "$basetexturetransform",self.transform)
        end
    end
})
