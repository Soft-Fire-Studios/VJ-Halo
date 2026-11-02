-- Reach artwork on VJ's existing controller. No camera, aim or weapon writes.
if not CLIENT then return end
local data = include("campaign_evolved/hud.lua")
-- Source layout correction measured against the complete native border masks.
-- Keep the exported Reach widget records unchanged (hud/reach/layout_audit.json).
local layout = {
    [data.themes.elite.health] = {scale={1.015,1.015},offset={0,1.4}},
    [data.themes.elite.shield] = {scale={1.44709,1.37863},offset={0,2.82409},origin={-0.0349105,0}}
}
local materials, colors = {}, {}
-- Requested Covenant presentation; keep the exported Reach palette as evidence.
local covenantColors = {
    disabled={55,31,87}, primary={116,70,180}, foreground={205,160,255}, neutral={205,160,255}
}
for name, theme in pairs(data.themes) do
    colors[name] = {}
    for key, rgb in pairs(theme.colors) do
        local tint=name=="elite" and covenantColors[key] or rgb
        colors[name][key] = Color(tint[1], tint[2], tint[3])
    end
    local backing=colors[name].disabled
    colors[name].background=Color(backing.r,backing.g,backing.b,170)
end
local enabled = GetConVar("vj_npc_cont_hud")
local width, height, scale
local reticleScales = {}
local fittedBounds = {}
local radarLayouts = {}
local compassLayouts = {}
local visorLayouts = {}
local reticleLimit = 72 -- Maximum diameter in the 1080p design space.
local contacts, nextRadar, radarOwner = {}, 0, nil
local radarRange, radarRadius = 1000, 80 -- Source policy; native world range is unresolved.
local polygon = {{}, {}, {}, {}}

local function controlled()
    enabled = enabled or GetConVar("vj_npc_cont_hud")
    local player = LocalPlayer()
    local controller = IsValid(player) and player.VJ_Controller
    if not IsValid(controller) or controller:GetPlayer() ~= player
        or not controller:GetNW2Bool("ce8_hud") or (enabled and not enabled:GetBool()) then return end
    local npc = controller:GetNPC()
    if IsValid(npc) and npc.IsCE8SNPC and npc:Health() > 0 then return controller, npc, player end
end

local function viewport()
    local w, h = ScrW(), ScrH()
    if w == width and h == height then return end
    width, height = w, h
    visorLayouts = {}
    -- Size follows one aspect-preserving 1080p scale; placement uses viewport anchors.
    scale = math.min(w / 1920, h / 1080)
    local fontSize = math.max(12, math.floor(22 * scale))
    surface.CreateFont("CE8HUD", {font = "Tahoma", size = fontSize, weight = 600, antialias = true})
    surface.CreateFont("CE8HUDSmall", {font = "Tahoma", size = math.max(10, math.floor(14 * scale)), weight = 500, antialias = true})
end

local function position(x, y, anchor)
    x,y = x*scale,y*scale
    if anchor == "top_right" then x = width+x
    elseif anchor == "top_center" or anchor == "bottom_center" then x = width*0.5+x end
    if anchor == "bottom_left" or anchor == "bottom_center" then y = height+y end
    return x,y
end

local function text(value, x, y, color, align, small, anchor)
    local px,py = position(x,y,anchor)
    draw.SimpleText(value, small and "CE8HUDSmall" or "CE8HUD", px,py,
        color, align or TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end

local function visor(theme,palette)
    if not theme.visor then return end
    local quads=visorLayouts[theme]
    if not quads then
        quads={}
        local reference=theme.visor_reference
        local rw,rh=reference.width,reference.height
        local unit=math.min(width/rw,height/rh)
        for _,ref in ipairs(theme.visor) do
            local r=ref.rect
            local x,y,w,h=r[1]*rw,r[2]*rh,r[3]*rw,r[4]*rh
            local left,right
            if ref.role=="connector" then
                -- Extend only the central connectors when the aspect changes;
                -- the native corner pieces keep their shape at screen edges.
                left=ref.side=="right" and width/2+(x-rw/2)*unit or x*unit
                right=ref.side=="left" and width/2+(x+w-rw/2)*unit or width+(x+w-rw)*unit
            else
                left=ref.side=="right" and width+(x-rw)*unit or x*unit
                right=left+w*unit
            end
            local top=ref.edge=="bottom" and height+(y-rh)*unit or y*unit
            quads[#quads+1]={texture=ref.texture,left=left,right=right,top=top,bottom=top+h*unit,uv=ref.uv}
        end
        visorLayouts[theme]=quads
    end
    surface.SetDrawColor(palette.foreground)
    for _,q in ipairs(quads) do
        local material=materials[q.texture]
        if not material then material=Material(data.textures[q.texture].material);materials[q.texture]=material end
        surface.SetMaterial(material)
        local uv=q.uv
        polygon[1].x,polygon[1].y,polygon[1].u,polygon[1].v=q.left,q.top,uv[1],uv[2]
        polygon[2].x,polygon[2].y,polygon[2].u,polygon[2].v=q.right,q.top,uv[3],uv[2]
        polygon[3].x,polygon[3].y,polygon[3].u,polygon[3].v=q.right,q.bottom,uv[3],uv[4]
        polygon[4].x,polygon[4].y,polygon[4].u,polygon[4].v=q.left,q.bottom,uv[1],uv[4]
        surface.DrawPoly(polygon)
    end
end

-- Mirrors duplicate the authored half/quarter around its normalized origin.
-- Negative widget scales flip that rectangle; they do not create new copies.
local function piece(ref, cx, cy, sx, sy, tint, fraction)
    local sprite = data.sprites[ref.texture] and data.sprites[ref.texture][ref.sprite]
    local material = materials[ref.texture]
    if not material and data.textures[ref.texture] then
        material = Material(data.textures[ref.texture].material)
        materials[ref.texture] = material
    end
    if not sprite or not material then return end
    local info = data.textures[ref.texture]
    if info.frames > 1 then material:SetInt("$frame", math.floor(math.Clamp(fraction or 1,0,1) * (info.frames - 1) + 0.5)) end
    surface.SetMaterial(material)
    surface.SetDrawColor(tint)
    local w, h = sprite.width * sx, sprite.height * sy
    local origin = layout[ref] and layout[ref].origin or ref.mirror_offset
    local ox = origin and origin[1] or (sprite.pivot[1] / sprite.width)
    local oy = origin and origin[2] or (sprite.pivot[2] / sprite.height)
    local angle = math.rad(ref.rotation or 0)
    local cosine, sine = math.cos(angle), math.sin(angle)
    local u0,v0,u1,v1 = unpack(sprite.uv)
    for ix = 0, ref.mirror_x and 1 or 0 do
        for iy = 0, ref.mirror_y and 1 or 0 do
            local x0, x1, y0, y1 = -ox*w, (1-ox)*w, -oy*h, (1-oy)*h
            if ix == 1 then x0,x1 = -x1,-x0 end
            if iy == 1 then y0,y1 = -y1,-y0 end
            local ua,ub = ix == 1 and u1 or u0, ix == 1 and u0 or u1
            local va,vb = iy == 1 and v1 or v0, iy == 1 and v0 or v1
            if x1 < x0 then x0,x1,ua,ub = x1,x0,ub,ua end
            if y1 < y0 then y0,y1,va,vb = y1,y0,vb,va end
            local function point(index,x,y,u,v)
                local p=polygon[index]
                p.x,p.y,p.u,p.v = cx+x*cosine-y*sine,cy+x*sine+y*cosine,u,v
            end
            point(1,x0,y0,ua,va); point(2,x1,y0,ub,va)
            point(3,x1,y1,ub,vb); point(4,x0,y1,ua,vb)
            surface.DrawPoly(polygon)
        end
    end
end

-- Measure the entire mirrored/rotated widget, not just its source half/quarter.
local function bounds(ref, sx, sy)
    local sprite = data.sprites[ref.texture][ref.sprite]
    local w,h = sprite.width*sx,sprite.height*sy
    local origin = layout[ref] and layout[ref].origin or ref.mirror_offset
    local ox = origin and origin[1] or sprite.pivot[1]/sprite.width
    local oy = origin and origin[2] or sprite.pivot[2]/sprite.height
    local cosine,sine = math.cos(math.rad(ref.rotation or 0)),math.sin(math.rad(ref.rotation or 0))
    local left,top,right,bottom = math.huge,math.huge,-math.huge,-math.huge
    for mx=0,ref.mirror_x and 1 or 0 do for my=0,ref.mirror_y and 1 or 0 do
        for ix=0,1 do for iy=0,1 do
            local x,y = (ix-ox)*w*(mx==1 and -1 or 1),(iy-oy)*h*(my==1 and -1 or 1)
            local px,py = x*cosine-y*sine,x*sine+y*cosine
            left,top,right,bottom = math.min(left,px),math.min(top,py),math.max(right,px),math.max(bottom,py)
        end end
    end end
    return left,top,right,bottom
end

local function widgetMetrics(ref, theme)
    -- Preserve native relative proportions and the existing bitmap conversion.
    local sx,sy = theme.attributes.scale[1]*0.5,theme.attributes.scale[2]*0.5
    local x,y = 0,0
    local parent = ref.parent
    if parent then
        x,y = parent.offset[1]*sx,parent.offset[2]*sy
        sx,sy = sx*parent.scale[1],sy*parent.scale[2]
    end
    x,y,sx,sy = x+ref.offset[1]*sx,y+ref.offset[2]*sy,sx*ref.scale[1],sy*ref.scale[2]
    local adjustment = layout[ref]
    if adjustment then
        x,y = x+adjustment.offset[1],y+adjustment.offset[2]
        sx,sy = sx*adjustment.scale[1],sy*adjustment.scale[2]
    end
    return x,y,sx,sy
end

local function widget(ref, theme, tint, fraction, aimX, aimY, fit)
    if not ref then return end
    local anchor = ref.anchor == "parent" and ref.parent and ref.parent.anchor or ref.anchor
    local x,y = position(0,40,"top_center")
    if anchor == "crosshair" then x,y = aimX,aimY
    elseif anchor == "top_right" then x,y = position(-40,40,anchor)
    elseif anchor == "top_left" then x,y = position(40,40,anchor) end
    local dx,dy,sx,sy = widgetMetrics(ref,theme)
    local unit = scale*(fit or 1)
    piece(ref,x+dx*unit,y+dy*unit,sx*unit,sy*unit,tint,fraction)
end

local function compass(theme, palette, player)
    local ref=theme.compass
    if not ref then return end
    local strip=compassLayouts[theme]
    if not strip then
        local sprite=data.sprites[ref.texture][ref.sprite]
        local dx,dy,sx,sy=widgetMetrics(ref,theme)
        local window=ref.native_uv_window
        strip={dx=dx,dy=dy,width=sprite.width*sx*window[1],height=sprite.height*sy*window[2],
            window=window[1],uv=sprite.uv,vspan=window[2]}
        compassLayouts[theme]=strip
    end
    local material=materials[ref.texture]
    if not material then material=Material(data.textures[ref.texture].material);materials[ref.texture]=material end
    -- Reach's looping yaw_slide window, driven by the Source camera yaw.
    -- Only the alpha strip is used for Spartan; its black-backed additive
    -- companion stays in the archive until the native blend is reproduced.
    surface.SetMaterial(material)
    surface.SetDrawColor(palette.foreground)
    local cx,cy=position(strip.dx,40+strip.dy,"top_center")
    local w,h=strip.width*scale,strip.height*scale
    local left,top=cx-w*0.5,cy-h*0.5
    local u0,v0,u1,v1=unpack(strip.uv)
    local vs=(v1-v0)*strip.vspan
    v0=v0+(v1-v0-vs)*0.5
    local start=(-player:EyeAngles().y/360-strip.window*0.5)%1
    local remaining=strip.window
    -- Split at the native image edge instead of sampling POT padding.
    for segment=1,2 do
        if remaining<=0 then break end
        local span=math.min(remaining,1-start)
        local right=left+w*span/strip.window
        local ua,ub=u0+(u1-u0)*start,u0+(u1-u0)*(start+span)
        polygon[1].x,polygon[1].y,polygon[1].u,polygon[1].v=left,top,ua,v0
        polygon[2].x,polygon[2].y,polygon[2].u,polygon[2].v=right,top,ub,v0
        polygon[3].x,polygon[3].y,polygon[3].u,polygon[3].v=right,top+h,ub,v0+vs
        polygon[4].x,polygon[4].y,polygon[4].u,polygon[4].v=left,top+h,ua,v0+vs
        surface.DrawPoly(polygon)
        left,start,remaining=right,0,remaining-span
    end
end

local function reticleScale(reticle, theme)
    local cache = reticleScales[theme]
    if not cache then cache={};reticleScales[theme]=cache end
    if cache[reticle] then return cache[reticle] end
    -- Measure every layer and mirrored/rotated corner once. Scaling the whole
    -- group preserves its spacing and center at VJ's projected aim position.
    local extent = 0
    for _,ref in ipairs(reticle.layers or {reticle}) do
        local dx,dy,sx,sy = widgetMetrics(ref,theme)
        local l,t,r,b = bounds(ref,sx,sy)
        extent=math.max(extent,math.abs(dx+l),math.abs(dy+t),math.abs(dx+r),math.abs(dy+b))
    end
    local fit=math.min(1,reticleLimit/math.max(1,extent*2))
    cache[reticle]=fit
    return fit
end

-- Fitted resource widgets use a fixed safe-area box. Packed bitmap/manual-UV
-- ammo crops differ between MCC revisions; show capacity fraction plus digits.
local function fitted(ref, x, y, w, h, tint, fraction, anchor)
    if not ref then return end
    local box = fittedBounds[ref]
    if not box then box={bounds(ref,1,1)};fittedBounds[ref]=box end
    local bw,bh = box[3]-box[1],box[4]-box[2]
    local factor = math.min(w/math.max(1,bw),h/math.max(1,bh))*scale
    local px,py = position(x,y,anchor)
    piece(ref,px+(w*scale-bw*factor)*0.5-box[1]*factor,py+(h*scale-bh*factor)*0.5-box[2]*factor,
        factor,factor,tint,fraction)
end

local function radar(npc, player, controller, theme, palette)
    local now = CurTime()
    if radarOwner ~= npc then contacts = {};nextRadar=0;radarOwner=npc end
    if now >= nextRadar then
        nextRadar = now + 0.2
        local candidates = ents.FindInSphere(npc:GetPos(),radarRange)
        local origin=npc:GetPos()
        table.sort(candidates,function(a,b) return a:GetPos():DistToSqr(origin)<b:GetPos():DistToSqr(origin) end)
        contacts = {}
        for _, entity in ipairs(candidates) do
            if entity ~= npc and entity ~= player and entity ~= controller:GetBullseye()
                and (entity:IsNPC() or entity:IsPlayer() or entity:IsNextBot()) and entity:Health()>0 then
                contacts[#contacts+1]=entity
                if #contacts>=32 then break end
            end
        end
    end
    local group=radarLayouts[theme]
    if not group then
        group={entries={},left=math.huge,top=math.huge,right=-math.huge,bottom=-math.huge}
        for _,ref in ipairs({theme.radar_background,theme.radar}) do
            local x,y,sx,sy=widgetMetrics(ref,theme)
            local l,t,r,b=bounds(ref,sx,sy)
            local entry={ref=ref,x=x,y=y,sx=sx,sy=sy,left=x+l,top=y+t,right=x+r,bottom=y+b}
            group.entries[#group.entries+1]=entry
            group.left,group.top=math.min(group.left,entry.left),math.min(group.top,entry.top)
            group.right,group.bottom=math.max(group.right,entry.right),math.max(group.bottom,entry.bottom)
        end
        group.factor=2*radarRadius/math.max(group.right-group.left,group.bottom-group.top)
        radarLayouts[theme]=group
    end
    local cx,cy = position(102,-116,"bottom_left")
    local factor=group.factor*scale
    local x,y=cx-(group.left+group.right)*0.5*factor,cy-(group.top+group.bottom)*0.5*factor
    for index,entry in ipairs(group.entries) do
        piece(entry.ref,x+entry.x*factor,y+entry.y*factor,entry.sx*factor,entry.sy*factor,
            index==1 and palette.background or palette.foreground)
    end
    -- Contacts follow the foreground ring, not the larger background quarters.
    local ring=group.entries[2]
    cx,cy=x+(ring.left+ring.right)*0.5*factor,y+(ring.top+ring.bottom)*0.5*factor
    local r=math.min(ring.right-ring.left,ring.bottom-ring.top)*0.5*factor
    local origin,angle=npc:GetPos(),player:EyeAngles().y
    local c,s=math.cos(math.rad(angle)),math.sin(math.rad(angle))
    -- Client PVS contacts only. Neutral marks avoid inventing client relationships.
    surface.SetDrawColor(palette.neutral)
    for _,entity in ipairs(contacts) do
        if IsValid(entity) and entity:Health()>0 and entity:GetVelocity():LengthSqr()>16 then
            local delta=entity:GetPos()-origin
            local x,y=(delta.x*s-delta.y*c)/radarRange,-(delta.x*c+delta.y*s)/radarRange
            if x*x+y*y<=1 then surface.DrawRect(cx+x*r-2*scale,cy+y*r-2*scale,4*scale,4*scale) end
        end
    end
    text("MOTION",102,-28,palette.foreground,TEXT_ALIGN_CENTER,true,"bottom_left")
end

hook.Add("HUDShouldDraw","CE8PossessionHUD",function(name)
    if name == "CHudCrosshair" and controlled() then return false end
end)

hook.Add("HUDPaint","CE8PossessionHUD",function()
    local controller,npc,player=controlled()
    if not controller then contacts={};radarOwner=nil;return end
    viewport()
    local flood=(npc.CE8UnitLabel or ""):sub(1,6)=="flood_"
    local key=flood and "spartan" or "elite"
    local theme,palette=data.themes[key],colors[key]
    visor(theme,palette)
    compass(theme,palette,player)
    local vitals=controller:GetNW2Vector("ce8_vitals")
    local weaponState=controller:GetNW2Vector("ce8_weapon_state")
    local health=math.Clamp(npc:Health()/math.max(1,controller:GetNW2Float("ce8_max_health",100)),0,1)
    -- Retain the dim meter silhouette behind the remaining bright fill.
    widget(theme.health,theme,palette.disabled,1)
    widget(theme.health_border,theme,palette.foreground)
    widget(theme.health,theme,health<0.25 and palette.warning or palette.foreground,health)
    if vitals.y>0 then
        widget(theme.shield,theme,palette.disabled,1)
        widget(theme.shield_border,theme,palette.foreground)
        widget(theme.shield,theme,palette.foreground,vitals.x/vitals.y)
    end
    local weapon=controller:GetNPCWeapon()
    local binding=IsValid(weapon) and data.weapons[weapon.CE8WeaponName] or data.fallback
    binding=binding or data.fallback
    local ammo=controller:GetNPCWeaponAmmo()
    fitted(binding.schematic,-210,42,168,60,palette.foreground,1,"top_right")
    if IsValid(weapon) then
        text(weapon.PrintName or controller:GetNPCName(),-42,107,palette.foreground,TEXT_ALIGN_RIGHT,true,"top_right")
        if weaponState.z>0 then
            fitted(binding.ammo_meter,-240,134,198,24,palette.disabled,1,"top_right")
            fitted(binding.ammo_meter,-240,134,198,24,palette.foreground,ammo/weaponState.z,"top_right")
            text(math.max(0,ammo),-42,163,palette.foreground,TEXT_ALIGN_RIGHT,false,"top_right")
        end
        if weaponState.x>0 then text("HEAT "..math.floor(weaponState.x*100).."%",-42,192,palette.warning,TEXT_ALIGN_RIGHT,true,"top_right") end
        if weaponState.y>0 then text("CHARGE "..math.floor(weaponState.y*100).."%",-42,212,palette.foreground,TEXT_ALIGN_RIGHT,true,"top_right") end
    end
    if vitals.z>0 then
        fitted(theme.grenade_plasma or theme.grenade,38,40,42,52,palette.foreground)
        text(math.floor(vitals.z),90,56,palette.foreground)
    end
    local target=controller:GetBullseye()
    local x,y=width/2,height/2
    if IsValid(target) then
        local screen=target:GetPos():ToScreen()
        if screen.visible then x,y=screen.x,screen.y end
    end
    local reticle=binding.reticle or data.fallback.reticle
    local fit=reticleScale(reticle,theme)
    if reticle.layers then
        for _,ref in ipairs(reticle.layers) do widget(ref,theme,palette.foreground,1,x,y,fit) end
    else widget(reticle,theme,palette.foreground,1,x,y,fit) end
    radar(npc,player,controller,theme,palette)
    local status="SPACE: jump / leap"
    if controller:GetNW2Bool("ce8_crouched") then status="CROUCHED  |  CTRL: stand   "..status
    elseif controller:GetNW2Bool("ce8_crouch_supported") then status="CTRL: crouch toggle   "..status end
    text(status,0,-34,palette.foreground,TEXT_ALIGN_CENTER,true,"bottom_center")
end)
