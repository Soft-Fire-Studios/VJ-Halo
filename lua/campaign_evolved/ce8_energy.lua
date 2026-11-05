-- Native Refract + UnlitGeneric energy. Scrolling belongs to engine proxies;
-- Lua supplies gameplay state and skips optional layers at the existing LOD.
if SERVER then return end
CE8=CE8 or {}
CE8.NativeEnergy=CE8.NativeEnergy or {}
local states=setmetatable({}, {__mode="k"})
local function number(value,fallback)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return fallback end
    return value
end
local function rgb(text)
    local x,y,z=tostring(text or "1 1 1"):match("(%S+)%s+(%S+)%s+(%S+)")
    return Vector(number(x,1),number(y,1),number(z,1))
end
local function srgb(value)
    return value<=.0031308 and value*12.92 or 1.055*value^(1/2.4)-.055
end
local function ramp(t,leave,arrive)
    local t2,t3=t*t,t*t*t
    return math.Clamp((2*t3-3*t2+1)*5.386724e-8+(t3-2*t2+t)*leave
        +(-2*t3+3*t2)+(t3-t2)*arrive,0,1)
end
local function state(ent,kind)
    local frame=FrameNumber()
    local row=states[ent]
    if row and row.frame==frame and row.kind==kind then return row end
    row=row or {};states[ent]=row
    row.frame,row.kind=frame,kind
    row.opacity,row.flash,row.damage=1,0,0
    local overrides=IsValid(ent) and ent.CE8Parameters or nil
    local prefix=kind=="shield" and "shield" or "blade"
    if overrides then
        row.opacity=math.Clamp(number(overrides[prefix.."opacity"],1),0,1)
            *math.Clamp(number(overrides[prefix.."reveal"],1),0,1)
    end
    if kind=="shield" and IsValid(ent) then
        local owner=ent.GetNW2Entity and ent:GetNW2Entity("ce8_barrier_owner")
        if ent.CE8MergedBarrier then owner=ent end
        local vitality=1
        if IsValid(owner) then
            local maximum=owner:GetNW2Float("ce8_barrier_max",-1)
            if maximum>=0 then vitality=maximum>0 and math.Clamp(owner:GetNW2Float("ce8_barrier_value",maximum)/maximum,0,1) or 0 end
            if owner:GetNW2Bool("ce8_barrier_down",false) then row.opacity=0 end
            local restored=owner:GetNW2Float("ce8_barrier_restored",-1)
            if restored>=0 then row.opacity=row.opacity*math.Clamp((CurTime()-restored)/.25,0,1) end
            row.flash=math.Clamp(1-(CurTime()-owner:GetNW2Float("ce8_barrier_hit",-100))/.15,0,1)
        end
        if overrides then vitality=math.Clamp(number(overrides.shieldvitality,vitality),0,1) end
        row.damage=1-vitality
    end
    return row
end

matproxy.Add({name="CE8Energy",
    init=function(self,material,values)
        local lower={}
        for key,value in pairs(values) do lower[string.lower(key)]=value end
        values=lower
        self.kind=values.kind or "blade"
        self.tint=rgb(values.shieldcolor)
        self.brightness=number(values.brightness,2)
        self.refract=number(values.refractamount,0)
        self.detail=number(values.detailstrength,.3)
        self.output=Vector(1,1,1)
        if values.refractmaterial then
            CE8.NativeEnergy[material:GetName()]={kind=self.kind,
                refract=values.refractmaterial,far=values.farmaterial}
        end
    end,
    bind=function(self,material,ent)
        if not IsValid(ent) then ent=Entity(0) end
        local data=state(ent,self.kind)
        local detail,normal=1,1
        if CE8.MaterialLOD then detail,normal=CE8.MaterialLOD(ent) end
        if self.refract>0 then
            -- Refract ignores $alpha: the draw is skipped when depleted, and
            -- distortion strength fades with recharge and existing LOD controls.
            local amount=self.refract*data.opacity*math.min(detail,normal)
            if amount~=self.last then material:SetFloat("$refractamount",amount);self.last=amount end
            return
        end
        local alpha=data.opacity
        if self.alpha~=alpha then material:SetFloat("$alpha",alpha);self.alpha=alpha end
        if self.kind=="shield" then
            local damage=data.damage
            local red,green=ramp(damage,1.9021909,0),ramp(damage,.18983896,4.097324)
            local gain=self.brightness*(1+data.flash)
            local r=srgb(1-math.exp(-math.max(0,self.tint.x+(red-self.tint.x)*damage)*gain))
            local g=srgb(1-math.exp(-math.max(0,self.tint.y+(green-self.tint.y)*damage)*gain))
            local b=srgb(1-math.exp(-math.max(0,self.tint.z+(red-self.tint.z)*damage)*gain))
            if r~=self.r or g~=self.g or b~=self.b then
                self.output.x,self.output.y,self.output.z=r,g,b
                material:SetVector("$color2",self.output);self.r,self.g,self.b=r,g,b
            end
        end
        local blend=self.detail*detail
        if self.blend~=blend then material:SetFloat("$detailblendfactor",blend);self.blend=blend end
    end
})

-- Called within the existing sorted energy draw, not a separate entity/hook.
-- The owning model's ordinary materials stay hidden in BOTH energy passes.
function CE8.DrawNativeEnergyLayers(ent,flags)
    local detail,normal=1,1
    if CE8.MaterialLOD then detail,normal=CE8.MaterialLOD(ent) end
    local glow=detail>0 and ent.CE8EmissiveMaterials or ent.CE8FarEnergyMaterials
    local refraction=ent.CE8RefractionMaterials
    local visible=false
    for _,layer in pairs(ent.CE8EnergyLayers) do
        if state(ent,layer.kind).opacity>0 then visible=true break end
    end
    if not visible then return end
    -- Let each native material choose its own blend; never apply the old
    -- custom shader's additive blend to the framebuffer-copy refraction pass.
    render.OverrideBlend(false)
    if detail>0 and normal>0 and render.GetRenderTarget()==nil then
        -- One source image per translucent view, shared across all energy props.
        if not CE8.EnergyRefractUpdated then
            render.UpdateRefractTexture();CE8.EnergyRefractUpdated=true
        end
        for slot,material in pairs(refraction) do render.MaterialOverrideByIndex(slot,material) end
        ent:DrawModel(STUDIO_RENDER or 1)
    end
    for slot,material in pairs(glow) do render.MaterialOverrideByIndex(slot,material) end
    ent:DrawModel(STUDIO_RENDER or 1)
    return glow
end
