-- Generated layout from campaign_devmap.py; map-only runtime below.
if SERVER then AddCSLuaFile() end
if game.GetMap() ~= "gm_ce8_dev" then return end

local drops = {
    [32] = Vector(-3584,2552,40),
    [64] = Vector(-2688,2552,72),
    [96] = Vector(-1792,2552,104),
    [128] = Vector(-896,2552,136),
    [192] = Vector(0,2552,200),
    [256] = Vector(896,2552,264),
    [384] = Vector(1792,2552,392),
    [512] = Vector(2688,2552,520),
    [768] = Vector(3584,2552,776)
}
local labels = {
    {"DROP 32u","Landing floor = 0",Vector(-3584,2144,2),Angle(0,0,0),0.65},
    {"32u","DROP EDGE",Vector(-3584,2352,33),Angle(0,0,0),0.5},
    {"DROP 64u","Landing floor = 0",Vector(-2688,2144,2),Angle(0,0,0),0.65},
    {"64u","DROP EDGE",Vector(-2688,2352,65),Angle(0,0,0),0.5},
    {"DROP 96u","Landing floor = 0",Vector(-1792,2144,2),Angle(0,0,0),0.65},
    {"96u","DROP EDGE",Vector(-1792,2352,97),Angle(0,0,0),0.5},
    {"DROP 128u","Landing floor = 0",Vector(-896,2144,2),Angle(0,0,0),0.65},
    {"128u","DROP EDGE",Vector(-896,2352,129),Angle(0,0,0),0.5},
    {"DROP 192u","Landing floor = 0",Vector(0,2144,2),Angle(0,0,0),0.65},
    {"192u","DROP EDGE",Vector(0,2352,193),Angle(0,0,0),0.5},
    {"DROP 256u","Landing floor = 0",Vector(896,2144,2),Angle(0,0,0),0.65},
    {"256u","DROP EDGE",Vector(896,2352,257),Angle(0,0,0),0.5},
    {"DROP 384u","Landing floor = 0",Vector(1792,2144,2),Angle(0,0,0),0.65},
    {"384u","DROP EDGE",Vector(1792,2352,385),Angle(0,0,0),0.5},
    {"DROP 512u","Landing floor = 0",Vector(2688,2144,2),Angle(0,0,0),0.65},
    {"512u","DROP EDGE",Vector(2688,2352,513),Angle(0,0,0),0.5},
    {"DROP 768u","Landing floor = 0",Vector(3584,2144,2),Angle(0,0,0),0.65},
    {"768u","DROP EDGE",Vector(3584,2352,769),Angle(0,0,0),0.5},
    {"DROP HEIGHTS","32 / 64 / 96 / 128 / 192 / 256 / 384 / 512 / 768 units",Vector(0,1856,2),Angle(0,0,0),0.8},
    {"32u COVER","448 wide / 96 deep",Vector(-3552,-2464,2),Angle(0,0,0),0.5},
    {"48u COVER","448 wide / 96 deep",Vector(-2656,-2464,2),Angle(0,0,0),0.5},
    {"64u COVER","448 wide / 96 deep",Vector(-3552,-1888,2),Angle(0,0,0),0.5},
    {"80u COVER","448 wide / 96 deep",Vector(-2656,-1888,2),Angle(0,0,0),0.5},
    {"96u COVER","448 wide / 96 deep",Vector(-3552,-1312,2),Angle(0,0,0),0.5},
    {"128u COVER","448 wide / 96 deep",Vector(-2656,-1312,2),Angle(0,0,0),0.5},
    {"160u COVER","448 wide / 96 deep",Vector(-3552,-736,2),Angle(0,0,0),0.5},
    {"192u COVER","448 wide / 96 deep",Vector(-2656,-736,2),Angle(0,0,0),0.5},
    {"COVER HEIGHTS","Low / crouch / standing / tall",Vector(-3104,-2752,2),Angle(0,0,0),0.7},
    {"COMBAT COURT","Flanking / suppression / shields / evasion",Vector(0,-1600,2),Angle(0,0,0),0.7},
    {"16u STEPS","32u tread / 256u total rise",Vector(-1216,-2352,2),Angle(0,0,0),0.5},
    {"1:4 RAMP","256u rise / 1024u run",Vector(-192,-2352,2),Angle(0,0,0),0.5},
    {"GAPS 128u / 256u","64u raised pads",Vector(1216,-2432,2),Angle(0,0,0),0.5},
    {"DIM ROOM","Lighting / sound occlusion / lost sight",Vector(-3072,128,2),Angle(0,0,0),0.55},
    {"HUMAN DOOR","48u clear width / 108u height",Vector(2032.0,160,2),Angle(0,0,0),0.4},
    {"128 x 160","128u clear width / 160u height",Vector(2496.0,160,2),Angle(0,0,0),0.4},
    {"256 x 256","256u clear width / 256u height",Vector(2992.0,160,2),Angle(0,0,0),0.4},
    {"DOORS","Narrow / Elite / large hull",Vector(2528,1472,2),Angle(0,0,0),0.6},
    {"0u","RANGE",Vector(3700,-2624,2),Angle(0,0,0),0.45},
    {"512u","RANGE",Vector(3700,-2112,2),Angle(0,0,0),0.45},
    {"1024u","RANGE",Vector(3700,-1600,2),Angle(0,0,0),0.45},
    {"1536u","RANGE",Vector(3700,-1088,2),Angle(0,0,0),0.45},
    {"2048u","RANGE",Vector(3700,-576,2),Angle(0,0,0),0.45},
    {"2560u","RANGE",Vector(3700,-64,2),Angle(0,0,0),0.45},
    {"3072u","RANGE",Vector(3700,448,2),Angle(0,0,0),0.45},
    {"3584u","RANGE",Vector(3700,960,2),Angle(0,0,0),0.45},
    {"FIRING LANE","0 to 3584 Source units",Vector(3696,-2912,2),Angle(0,0,0),0.5},
    {"PHYSICS PAD","Props / collision / grenade bounce",Vector(2304,-1536,2),Angle(0,0,0),0.5},
    {"OBSERVATION","Protected here / normal targeting on arena floor",Vector(0,-2968,1056),Angle(0,180,90),0.5},
    {"USE: ARENA","E",Vector(640,-2608,968),Angle(0,0,90),0.15},
    {"USE: OBSERVE","E",Vector(0,-2544,80),Angle(0,180,90),0.15},
    {"CE8 AI TEST ARENA","Cover west / drops north / doors and range east",Vector(0,-2820,898),Angle(0,0,0),0.55}
}

local roomMin, roomMax = Vector(-800,-2976,896), Vector(800,-2384,1184)
local function InRoom(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:GetPos():WithinAABox(roomMin,roomMax)
end

if SERVER then
    -- Preserve the player's previous notarget flag. No global ai_ignoreplayers,
    -- god-mode setting, NPC relationships or difficulty settings are modified.
    CE8DevMapObservers = CE8DevMapObservers or setmetatable({}, {__mode="k"})
    local observers = CE8DevMapObservers
    local function Protect(ply)
        local inside = InRoom(ply)
        if inside and observers[ply] == nil then
            observers[ply] = ply:IsFlagSet(FL_NOTARGET)
            ply:SetNoTarget(true)
        elseif not inside and observers[ply] ~= nil then
            ply:SetNoTarget(observers[ply])
            observers[ply] = nil
        elseif inside and not ply:IsFlagSet(FL_NOTARGET) then
            ply:SetNoTarget(true)
        end
    end
    timer.Create("CE8DevMapObservers", 0.1, 0, function()
        for _, ply in ipairs(player.GetAll()) do Protect(ply) end
    end)
    hook.Add("PlayerSpawn", "CE8DevMapObservers", function(ply)
        timer.Simple(0, function() if IsValid(ply) then Protect(ply) end end)
    end)
    hook.Add("EntityTakeDamage", "CE8DevMapObservers", function(ent)
        if InRoom(ent) then return true end
    end)
    local function Travel(ply, pos, angle)
        if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
        if ply:InVehicle() then
            ply:ChatPrint("Leave the vehicle before using the test-map teleport.")
            return
        end
        -- Never put the player inside a prop, NPC or another observer.
        local mins, maxs = ply:GetHull()
        for _, offset in ipairs({Vector(0,0,0),Vector(96,0,0),Vector(-96,0,0),
                                 Vector(0,96,0),Vector(0,-96,0)}) do
            local at = pos + offset
            local tr = util.TraceHull({start=at,endpos=at,mins=mins,maxs=maxs,
                                       mask=MASK_PLAYERSOLID,filter=ply})
            if not tr.Hit and not tr.StartSolid then
                ply:SetPos(at)
                ply:SetLocalVelocity(vector_origin)
                ply:SetEyeAngles(angle)
                Protect(ply)
                return
            end
        end
        ply:ChatPrint("That test destination is occupied. Clear it and try again.")
    end
    local function Observe(ply) Travel(ply,Vector(0,-2656,904),Angle(16,90,0)) end
    local function Floor(ply) Travel(ply,Vector(0,-2464,8),Angle(0,90,0)) end
    concommand.Add("ce8_dev_observe",Observe,nil,"Return to the protected observation room.")
    concommand.Add("ce8_dev_floor",Floor,nil,"Enter the arena with normal AI targeting.")
    concommand.Add("ce8_dev_drop",function(ply,_,args)
        local pos = drops[tonumber(args[1])]
        if pos then Travel(ply,pos,Angle(15,-90,0))
        elseif IsValid(ply) then
            ply:ChatPrint("Drop heights: 32, 64, 96, 128, 192, 256, 384, 512, 768")
        end
    end,nil,"Move yourself to a measured drop platform: ce8_dev_drop 256")
    hook.Add("AcceptInput","CE8DevMapButtons",function(ent,input,activator)
        if input ~= "Trigger" or not IsValid(activator) or not activator:IsPlayer() then return end
        if ent:GetName() == "ce8_relay_floor" then Floor(activator)
        elseif ent:GetName() == "ce8_relay_observe" then Observe(activator) end
    end)
    return
end

surface.CreateFont("CE8DevTitle",{font="Roboto",size=44,weight=800})
surface.CreateFont("CE8DevSub",{font="Roboto",size=24,weight=500})
local white, pale, dark = Color(240,246,255), Color(165,208,245), Color(12,20,30,235)
hook.Add("PostDrawTranslucentRenderables","CE8DevMapLabels",function(depth,sky)
    if depth or sky then return end
    local eye = EyePos()
    for _, label in ipairs(labels) do
        if eye:DistToSqr(label[3]) < 6500^2 then
            cam.Start3D2D(label[3],label[4],label[5])
                surface.SetFont("CE8DevTitle")
                local w = surface.GetTextSize(label[1])
                surface.SetFont("CE8DevSub")
                w = math.max(w,surface.GetTextSize(label[2]))+40
                draw.RoundedBox(6,-w/2,-38,w,90,dark)
                draw.SimpleText(label[1],"CE8DevTitle",0,-34,white,TEXT_ALIGN_CENTER)
                draw.SimpleText(label[2],"CE8DevSub",0,12,pale,TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end
end)
hook.Add("HUDPaint","CE8DevMapStatus",function()
    if not InRoom(LocalPlayer()) then return end
    draw.SimpleText("OBSERVATION: AI targeting and damage blocked","DermaDefaultBold",
                    24,ScrH()-76,white)
    draw.SimpleText("Use orange button or ce8_dev_floor  |  Return: ce8_dev_observe",
                    "DermaDefault",24,ScrH()-54,pale)
end)
