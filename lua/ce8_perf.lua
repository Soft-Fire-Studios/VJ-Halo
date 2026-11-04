-- Temporary all-features-enabled capture; no autorun.
if CE8PerfSession and CE8PerfSession.Stop then CE8PerfSession:Stop("replaced") end
if CLIENT then include("autorun/client/ce8_surface.lua") end
CE8PerfMode="weapons"
CE8PerfEffects=false
-- Explicit, finite diagnostic. Not autorun and not part of the shipped addon.
-- Default: fixed-view validation with all features enabled for 24 seconds.
-- CE8PerfMode='scene' opts into the 30-second lighting feature comparison.
-- CE8PerfMode='flashlight' isolates close-range shadows, uploads and pixel cost.
-- CE8PerfMode='weapons' observes shots, flight, collision and effects in both realms.
-- CE8PerfEffects=true additionally compares CE8 weapon particles/muzzle lights.
-- No NPCs are spawned, no AI/convars/materials are edited, and wrappers restore.
-- Explicit opt-in for the movement-only capture; repeated loads otherwise keep
-- the same controlled feature comparison instead of silently changing modes.
local mode=CE8PerfMode or "steady"
local effectsTest=mode=="weapons" and CE8PerfEffects==true
CE8PerfEffects=nil
local baselineOnly=mode=="movement"
CE8PerfMode=nil
if CE8PerfSession and CE8PerfSession.Stop then CE8PerfSession:Stop("replaced") end
local clock = SysTime
local session = {version=2, mode=mode, realm=SERVER and "server" or "client", patches={}, phases={},
    entities={}, tracked=setmetatable({}, {__mode="k"}), drawDepth=setmetatable({}, {__mode="k"}),
    entityPatches=setmetatable({}, {__mode="k"}), start=clock(), nextScan=0}
CE8PerfSession = session
local hookID = "CE8PerformanceCapture"
local hidden={}
local nativeFlashlight={}
local effectNames,seenEffectData={},setmetatable({}, {__mode="k"})
local muzzleLights=setmetatable({}, {__mode="k"})
local phaseKey="ce8_perf_effect_phase"
local previousPhase,effectRun
local function restoreMuzzleLights()
    for data,old in pairs(muzzleLights) do
        if rawget(data,"PrimaryEffects_SpawnDynamicLight")==false then
            data.PrimaryEffects_SpawnDynamicLight=old.value
        end
    end
    muzzleLights=setmetatable({}, {__mode="k"})
end
local function restoreFlashlight()
    for ent in pairs(nativeFlashlight) do
        if IsValid(ent) and EF_NOFLASHLIGHT then ent:AddEffects(EF_NOFLASHLIGHT) end
    end
    nativeFlashlight={}
end
local function restoreVisibility()
    for ent,previous in pairs(hidden) do
        if IsValid(ent) then ent:SetNoDraw(previous) end
    end
    hidden={}
end
local stages = effectsTest and {
    {name="effects_baseline",seconds=7},{name="no_weapon_particles",seconds=7},
    {name="effects_repeat",seconds=7},{name="no_muzzle_lights",seconds=7},
    {name="no_weapon_fx",seconds=7},{name="effects_restored",seconds=7}
    } or mode=="weapons" and {{name="weapons",seconds=30}} or SERVER and {{name="ai", seconds=34}} or mode=="flashlight_guard" and {
    {name="native_projector_enabled",seconds=4},{name="guarded",seconds=4},
    {name="native_projector_enabled",seconds=4},{name="guarded",seconds=4}} or mode=="flashlight" and {
    {name="baseline",seconds=4},{name="no_shadow_draws",seconds=4},
    {name="frozen_scene_updates",seconds=4},{name="no_projectors",seconds=4},
    {name="no_details",seconds=4},{name="restored",seconds=4}} or mode=="scene" and {
    {name="baseline",seconds=5},{name="frozen_scene_updates",seconds=5},
    {name="baseline_repeat",seconds=5},{name="no_direct_lights",seconds=5},
    {name="no_normal_specular",seconds=5},{name="restored",seconds=5}} or mode=="light_batch" and {
    {name="individual_lights",seconds=6},{name="batched_lights",seconds=6},
    {name="individual_lights_repeat",seconds=6},{name="batched_lights_repeat",seconds=6}} or mode=="steady" and {
    {name="steady",seconds=24}} or baselineOnly and {
    {name="baseline_still",seconds=8},{name="baseline_moving",seconds=12}} or {
    {name="baseline",seconds=4}, {name="no_details",seconds=4},
    {name="no_normal_specular",seconds=4}, {name="no_direct_lights",seconds=4},
    {name="no_ce8_geometry",seconds=4}, {name="restored",seconds=4}}
local function size(t) local n=0 for _ in pairs(t or {}) do n=n+1 end return n end
local function isCE8(ent)
    return IsValid(ent) and (ent.IsCE8Elite or ent.CE8WeaponName or ent.CE8CharacterDefinition
        or string.find(ent:GetModel() or "", "models/campaign_evolved/ce8/",1,true)==1)
end
local function isNPC(ent)
    return ent.IsCE8Elite or (ent.IsNPC and ent:IsNPC()) or (ent.IsNextBot and ent:IsNextBot())
end
local function stat(label)
    local phase=session.current
    if not phase or not session.measuring then return end
    local row=phase.calls[label]
    if not row then row={count=0,seconds=0,max_seconds=0};phase.calls[label]=row end
    return row
end
local function finished(row,started,...)
    if row then
        local dt=clock()-started
        row.count=row.count+1;row.seconds=row.seconds+dt
        row.max_seconds=math.max(row.max_seconds,dt)
    end
    return ...
end
local function allocated(row,started,kb,...)
    if row then
        local delta=collectgarbage("count")-kb
        row.net_rise_kb=(row.net_rise_kb or 0)+math.max(0,delta)
        row.net_drop_kb=(row.net_drop_kb or 0)+math.max(0,-delta)
    end
    return finished(row,started,...)
end
local function drawFinished(ent,row,started,...)
    session.drawDepth[ent]=session.drawDepth[ent]-1
    return finished(row,started,...)
end
local function patch(target,key,replacement,temporaryEntity)
    local original=rawget(target,key)
    target[key]=replacement
    if temporaryEntity then
        -- Hundreds of short-lived projectiles must not be retained by the profiler.
        local list=session.entityPatches[target]
        if not list then list={};session.entityPatches[target]=list end
        list[#list+1]={key=key,original=original,replacement=replacement}
    else
        session.patches[#session.patches+1]={target=target,key=key,original=original,replacement=replacement}
    end
end
local function measure(target,key,label,resolved,temporaryEntity)
    local fn=resolved or target[key]
    if type(fn)~="function" then return end
    local sampleTrace=mode=="weapons" and CLIENT and target==util and (key=="TraceLine" or key=="TraceHull")
    patch(target,key,function(...)
        local row=stat(label)
        if not row then return fn(...) end
        if sampleTrace and row.count%64==0 then
            -- Attribute a bounded fraction of client traces to their real Lua
            -- caller. Native particle traces are instead visible through PRP.
            local info=debug.getinfo(2,"Sl") or {}
            local caller="trace_sample:"..key..":"..(info.short_src or "native")..":"..(info.currentline or 0)
            return finished(row,clock(),allocated(stat(caller),clock(),collectgarbage("count"),fn(...)))
        end
        if label=="CE8:GetDirectLights" or label=="CE8:BindLiveDetails"
            or label=="npc:CE8BindRenderer" or label=="weapon:CE8BindRenderer" then
            return allocated(row,clock(),collectgarbage("count"),fn(...))
        end
        return finished(row,clock(),fn(...))
    end,temporaryEntity)
end
local function trackShot(ent)
    if not IsValid(ent) or ent:GetClass()~="obj_ce8_projectile" or session.tracked[ent] then return end
    session.tracked[ent]=true
    local data=ent:GetTable()
    local methods=SERVER and {"PreInit","InitPhys","Init","Think","OnThink","PhysicsUpdate",
        "StartTouch","PhysicsCollide","OnCollision","DealDamage","CE8ContactTrace","CE8AdvanceVelocity",
        "CE8CheckNeedles","CE8EmbedNeedle","CustomOnRemove"} or {"Draw","DrawTranslucent"}
    for _,name in ipairs(methods) do measure(data,name,"projectile:"..name,ent[name],true) end
end
local function entityInfo(ent)
    local index=ent:EntIndex()
    local row=session.entities[index]
    if row then return row end
    row={id=index,class=ent:GetClass(),model=ent:GetModel(),rank=ent.CE8Rank or ent.CE8CharacterRank,
        material_slots=ent.GetMaterials and #ent:GetMaterials() or nil,
        draws={},draw_flags={},light_categories={},views={}}
    if CLIENT then
        row.distance=EyePos():Distance(ent:WorldSpaceCenter())
        row.base_override_slots=size(ent.CE8OverrideMaterials)
        row.light_override_slots=size(ent.CE8LightMaterials)
        row.emissive_override_slots=size(ent.CE8EmissiveMaterials)
    end
    session.entities[index]=row
    return row
end
local function scan()
    local population={total=0,ce8=0,npcs=0,projectiles=0,weapons=0,lamps=0,lights=0,
        flying=0,stuck=0,projectile_weapons={},trails=0,sprites=0,dynamic_lights=0}
    for _,ent in ipairs(ents.GetAll()) do
        population.total=population.total+1
        local class=ent:GetClass()
        if class=="gmod_lamp" then population.lamps=population.lamps+1 end
        if class=="gmod_light" then population.lights=population.lights+1 end
        if class=="light_dynamic" then population.dynamic_lights=population.dynamic_lights+1 end
        if class=="env_spritetrail" then population.trails=population.trails+1 end
        if class=="env_sprite" then population.sprites=population.sprites+1 end
        local ours=isCE8(ent) or class=="obj_ce8_projectile"
        if ours then
            if effectsTest and SERVER then
                local data=ent.CE8Data
                if type(data)=="table" and not seenEffectData[data] then
                    seenEffectData[data]=true
                    local effects=data.effects
                    if effects then
                        for _,variant in ipairs({"normal","charged"}) do
                            for _,name in pairs(effects[variant] or {}) do
                                if type(name)=="string" then effectNames[name]=true end
                            end
                        end
                    end
                end
                local phase=session.current and session.current.name
                if ent.CE8WeaponName and class~="obj_ce8_projectile"
                    and (phase=="no_muzzle_lights" or phase=="no_weapon_fx") then
                    local values=ent:GetTable()
                    if not muzzleLights[values] then
                        muzzleLights[values]={value=rawget(values,"PrimaryEffects_SpawnDynamicLight")}
                        values.PrimaryEffects_SpawnDynamicLight=false
                    end
                end
            end
            population.ce8=population.ce8+1
            if isNPC(ent) then population.npcs=population.npcs+1
            elseif class=="obj_ce8_projectile" then
                population.projectiles=population.projectiles+1
                if ent.CE8NeedleTarget or ent.CE8StuckTo then population.stuck=population.stuck+1
                else population.flying=population.flying+1 end
                local name=ent.CE8WeaponName or "unknown"
                population.projectile_weapons[name]=(population.projectile_weapons[name] or 0)+1
            elseif ent.CE8WeaponName then population.weapons=population.weapons+1 end
            if mode~="weapons" or class~="obj_ce8_projectile" then entityInfo(ent) end
            if mode=="weapons" then trackShot(ent) end
            if CLIENT and session.current and session.current.name=="no_ce8_geometry"
                and hidden[ent]==nil and ent.GetNoDraw and ent.SetNoDraw then
                hidden[ent]=ent:GetNoDraw();ent:SetNoDraw(true)
            end
            -- The scene capture measures shared rendering, not hundreds of
            -- inherited entity Think methods. Keep its observer overhead small.
            if not session.tracked[ent] and (SERVER or (mode~="scene" and not CE8.SceneState)) then
                session.tracked[ent]=true
                local methods=SERVER and {"Think","RunAI","OnThink","OnThinkActive","AIUpdate",
                    "AIThinkActions","AIThinkTactics","AIThinkDialogue","CE8ThinkReactions",
                    "UpdatePoseParamTracking"} or {"Think","CE8ApplyGrip","CE8BindRenderer"}
                if mode=="weapons" and SERVER and isNPC(ent) then
                    methods[#methods+1]="CheckForDangers"
                    methods[#methods+1]="MaintainRelationships"
                end
                if mode=="weapons" and ent.CE8WeaponName and class~="obj_ce8_projectile" then
                    methods={"Think","OnThink","PrimaryAttack","NPC_CanFire","CE8SpawnProjectile",
                        "CE8BeginShot","CE8FinishShot","OnPrimaryAttack","OnPrimaryAttack_BulletCallback"}
                end
                local kind=isNPC(ent) and "npc" or ent.CE8WeaponName and "weapon" or "projectile"
                local data=ent:GetTable()
                for _,name in ipairs(methods) do measure(data,name,kind..":"..name,ent[name],mode=="weapons") end
            end
        end
    end
    session.population=population
    if session.current then
        local phase=session.current
        phase.population=population
        if mode=="weapons" then
            phase.timeline=phase.timeline or {}
            if #phase.timeline<64 then
                local calls={}
                for label,row in pairs(phase.calls) do
                    calls[label]={count=row.count,seconds=row.seconds,max_seconds=row.max_seconds}
                end
                phase.timeline[#phase.timeline+1]={time=clock()-phase.start,population=population,
                    lua_kb=collectgarbage("count"),calls=calls,frames=#phase.frames}
            end
        end
    end
end
local function summarize(values)
    local sorted={};local total=0
    for i,v in ipairs(values) do sorted[i]=v;total=total+v end
    table.sort(sorted)
    local function pct(q) return sorted[math.max(1,math.ceil(#sorted*q))] or 0 end
    local mean=#sorted>0 and total/#sorted or 0
    return {samples=#sorted,mean_ms=mean*1000,p50_ms=pct(.5)*1000,p95_ms=pct(.95)*1000,
        p99_ms=pct(.99)*1000,max_ms=pct(1)*1000,fps=mean>0 and 1/mean or 0}
end
function session:Stop(reason)
    if self.stopped then return end
    self.stopped=true;self.measuring=false
    restoreVisibility()
    restoreFlashlight()
    restoreMuzzleLights()
    if effectsTest and SERVER and effectRun then
        local active=GetGlobal2String(phaseKey,"")
        if active:sub(1,#effectRun+1)==effectRun..":" then SetGlobal2String(phaseKey,previousPhase) end
    end
    hook.Remove("Think",hookID);hook.Remove("PreRender",hookID);hook.Remove("PostRender",hookID)
    hook.Remove("PreDrawOpaqueRenderables",hookID)
    hook.Remove("NetworkEntityCreated",hookID)
    hook.Remove("ShutDown",hookID);timer.Remove(hookID)
    for i=#self.patches,1,-1 do
        local p=self.patches[i]
        -- Do not overwrite a real Lua reload or another addon's later change.
        if rawget(p.target,p.key)==p.replacement then p.target[p.key]=p.original end
    end
    self.patches={} -- Do not retain entity tables or wrapped closures after capture.
    for target,list in pairs(self.entityPatches) do
        for i=#list,1,-1 do
            local p=list[i]
            if rawget(target,p.key)==p.replacement then target[p.key]=p.original end
        end
    end
    self.entityPatches={}
    local report={version=self.version,mode=self.mode,realm=self.realm,map=game.GetMap(),reason=reason,
        elapsed=clock()-self.start,entities=self.entities,population=self.population,phases={},effects_test=effectsTest,
        convars=self.convars,notes={
            "Function timings are inclusive; nested totals must not be added together.",
            "Ordinary weapon mode observes without disabling damage, collisions, particles, audio or rendering.",
            "Optional effects_test skips only new CE8 weapon particle emissions and/or their VJ muzzle lights in named phases; existing particles expire naturally. Gameplay/audio/materials stay enabled; server publishes the phase to the client.",
            "Global effects/trace counters include other addons; PRP traces include all collider users.",
            "Native physics/particle GPU cost is not directly measured by Lua wrappers.",
            "ShouldCollide timing samples one in 64 callbacks; counts include every call.",
            "trace_sample rows contain one in 64 client Lua trace calls, not estimated totals; PRP queries are timed in both realms.",
            "DrawModel time includes CPU submission/driver stalls, not a GPU timer.",
            "DrawModel re-entry through Lua Draw is recorded separately as nested; neither count is a GPU draw-call count.",
            "Client phase deltas isolate costs; movement/combat/view changes can confound them.",
            "Server Think interval is tick spacing, not total server CPU time.",
            "Temporary instrumentation adds overhead; comparisons use the same wrappers.",
            "Allocation deltas are net Lua heap changes, inclusive and affected by garbage collection.",
            "Frozen scene phase skips CE8SceneLights only, retaining its last GPU records; material proxies still run.",
            "No-direct phase removes selected map/projector lights, retaining ambient and cubemap shading.",
            "No-normal/specular phase uses existing distance branches; it retains base color and ambient.",
            "Flashlight mode skips only CE8 shadow submissions, then freezes scene uploads, filters projectors, and disables detail layers separately.",
            "Flashlight-guard mode alternates native projector acceptance only; custom beam/map/detail shading remains enabled.",
            "Scene upload quads are tiny numeric-data writes, not repeated full model submissions."},
        unfocused_seconds=self.unfocusedSeconds or 0}
    for _,phase in ipairs(self.phases) do
        local out={name=phase.name,frames=summarize(phase.frames),render=summarize(phase.render),
            calls=phase.calls,views=phase.views,population=phase.population,cache_start=phase.cache_start,cache_end=phase.cache_end,
            lua_kb_start=phase.lua_kb_start,lua_kb_end=phase.lua_kb_end,
            memory=phase.memory,spikes=phase.spikes,scene=phase.scene,timeline=phase.timeline,
            camera_start=phase.camera_start,camera_end=phase.camera_end}
        report.phases[#report.phases+1]=out
        if CLIENT then print(string.format("CE8 perf %-20s %6.1f FPS | p95 %6.2f ms",out.name,out.frames.fps,out.frames.p95_ms)) end
    end
    file.CreateDir("campaign_evolved")
    local path="campaign_evolved/performance_"..self.realm..".json"
    file.Write(path,util.TableToJSON(report,true))
    print("CE8 performance "..self.realm.." saved: data/"..path.." ("..reason.."). All overrides restored.")
end
local function install()
    for _,name in ipairs({"TraceLine","TraceHull"}) do measure(util,name,"global:"..name) end
    if mode=="weapons" then
        if PRP and PRP.Colliders then
            for _,name in ipairs({"Trace","Contact","BlastContact"}) do measure(PRP.Colliders,name,"collider:"..name) end
        end
        if SERVER then
            local meta=FindMetaTable("Entity")
            local spawn=meta.Spawn
            if spawn then patch(meta,"Spawn",function(ent,...)
                if IsValid(ent) and ent:GetClass()=="obj_ce8_projectile" then
                    trackShot(ent)
                    local row=stat("spawn:"..(ent.CE8WeaponName or "unknown"))
                    return finished(row,clock(),spawn(ent,...))
                end
                if IsValid(ent) and ent:GetClass()=="light_dynamic" then
                    return finished(stat("spawn:light_dynamic"),clock(),spawn(ent,...))
                end
                return spawn(ent,...)
            end) end
            for _,name in ipairs({"Aim","Predict","Steer","Advance"}) do
                if CE8.Ballistics then measure(CE8.Ballistics,name,"ballistics:"..name) end
            end
            for _,name in ipairs({"Sweep","ProjectileHit","Redirect"}) do
                if CE8.Barrier then measure(CE8.Barrier,name,"barrier:"..name) end
            end
            local hooks=hook.GetTable().ShouldCollide or {}
            for name,fn in pairs(hooks) do
                if type(name)=="string" and (name:find("CE8",1,true) or name:find("PRP",1,true)) then
                    patch(hooks,name,function(...)
                        local row=stat("pair:"..name)
                        if not row then return fn(...) end
                        row.count=row.count+1
                        if row.count%64~=1 then return fn(...) end
                        local function result(started,...)
                            local dt=clock()-started
                            row.samples=(row.samples or 0)+1;row.sample_seconds=(row.sample_seconds or 0)+dt
                            row.seconds=row.sample_seconds/row.samples*row.count
                            row.max_seconds=math.max(row.max_seconds,dt)
                            return ...
                        end
                        return result(clock(),fn(...))
                    end)
                end
            end
        else
            hook.Add("NetworkEntityCreated",hookID,trackShot)
        end
        local globals=_G
        for _,name in ipairs({"ParticleEffect","ParticleEffectAttach","EmitSound"}) do measure(globals,name,"effect:"..name) end
        if effectsTest and SERVER then
            for _,key in ipairs({"ParticleEffect","ParticleEffectAttach"}) do
                local original=globals[key]
                if type(original)=="function" then patch(globals,key,function(name,...)
                    local phase=session.current and session.current.name
                    if effectNames[name] and (phase=="no_weapon_particles" or phase=="no_weapon_fx") then
                        local row=stat("suppressed:"..name)
                        if row then row.count=row.count+1 end
                        return
                    end
                    return original(name,...)
                end) end
            end
        end
        measure(util,"SpriteTrail","effect:SpriteTrail")
        if VJ then measure(VJ,"EmitSound","sound:VJ.EmitSound") end
        for _,event in ipairs({"EntityFireBullets","PostEntityFireBullets"}) do
            for name,fn in pairs(hook.GetTable()[event] or {}) do
                if type(name)=="string" and (name:find("CE8",1,true) or name:find("PRP",1,true)) then
                    measure(hook.GetTable()[event],name,"hook:"..event..":"..name)
                end
            end
        end
    end
    if CLIENT then
        if matproxy and matproxy.Call then
            local call=matproxy.Call
            patch(matproxy,"Call",function(name,...)
                local proxy=matproxy.ActiveList and matproxy.ActiveList[name]
                local label=proxy and proxy.name
                local row=label and label:sub(1,3)=="CE8" and stat("proxy:"..label) or nil
                if row then return allocated(row,clock(),collectgarbage("count"),call(name,...)) end
                return call(name,...)
            end)
        end
        local names={"DrawEmissiveModel","BindLiveDetails","RefreshMaterialTextures",
            "ActiveCharacterMaterials","ApplyModelDepth","GetMapLightSources","UpdateLightBatch","AmbientLighting","BeginLightFrame"}
        for _,name in ipairs(names) do measure(CE8,name,"CE8:"..name) end
        local selected=CE8.GetDirectLights
        if selected then
            local empty={}
            local filtered={}
            patch(CE8,"GetDirectLights",function(...)
                if session.current and session.current.name=="no_direct_lights" then return empty end
                local row=stat("CE8:GetDirectLights")
                if session.current and session.current.name=="no_projectors" then
                    local lights,region=finished(row,clock(),selected(...))
                    if not region then return lights,region end
                    local cached=filtered[region]
                    if not cached then cached={lights={},region={}};filtered[region]=cached end
                    for key,value in pairs(region) do cached.region[key]=value end
                    cached.region.projectorCount=0
                    local count=0
                    for _,light in ipairs(lights) do
                        if light.mapLight then count=count+1;cached.lights[count]=light end
                    end
                    for i=#cached.lights,count+1,-1 do cached.lights[i]=nil end
                    return cached.lights,cached.region
                end
                return finished(row,clock(),selected(...))
            end)
        end
        if mode=="scene" or mode=="flashlight" or mode=="flashlight_guard" or CE8.SceneState then
            local hooks=hook.GetTable()
            assert(CE8.SceneState and hooks.PreRender and hooks.PreRender.CE8SceneLights
                and hooks.PostRender and hooks.PostRender.CE8SceneParameters,
                "Current CE8 scene renderer is not loaded; no comparison was started")
            for _,entry in ipairs({{"PreRender","CE8SceneLights"},{"PostRender","CE8SceneParameters"}}) do
                local event,id=entry[1],entry[2]
                local original=hooks[event][id]
                patch(hooks[event],id,function(...)
                    local phase=session.current
                    if id=="CE8SceneLights" and phase and phase.name=="frozen_scene_updates" then return end
                    local row=stat(id)
                    local started=clock()
                    original(...)
                    if row then
                        finished(row,started)
                        local count=CE8.SceneState.uploads or 0
                        local totals=phase.scene[id]
                        totals.upload_quads=totals.upload_quads+count
                        totals.max_upload_quads=math.max(totals.max_upload_quads,count)
                        if id=="CE8SceneLights" and CE8.LightRegions then
                            local info=CE8.LightRegions
                            local regions=phase.scene.regions
                            regions.frames=regions.frames+1
                            regions.traces=regions.traces+(info.traces or 0)
                            regions.hulls=regions.hulls+(info.hulls or 0)
                            regions.max_traces=math.max(regions.max_traces,info.traces or 0)
                            regions.static_rankings=regions.static_rankings+(info.rankings or 0)
                            regions.projector_rankings=regions.projector_rankings+(info.projectorRankings or 0)
                        end
                    end
                end)
            end
        end
        measure(render,"ComputeLighting","render:ComputeLighting")
        measure(render,"MaterialOverrideByIndex","render:MaterialOverrideByIndex")
        local batch=CE8.GetLightBatch
        if mode=="light_batch" and batch then
            local individual={count=0}
            patch(CE8,"GetLightBatch",function(ent,lights)
                local result=batch(ent,lights)
                local phase=session.current and session.current.name or ""
                if phase:find("individual_lights",1,true)==1 then
                    individual.fallback=lights
                    return individual
                end
                return result
            end)
        end
        local direct=CE8.DrawDirectLights
        if direct then patch(CE8,"DrawDirectLights",function(...)
            if session.current and session.current.name=="no_direct_lights" then return end
            local row=stat("CE8:DrawDirectLights")
            return finished(row,clock(),direct(...))
        end) end
        local lod=CE8.MaterialLOD
        if lod then patch(CE8,"MaterialLOD",function(...)
            local d,n,s=lod(...)
            local mode=session.current and session.current.name
            if mode=="no_details" then return 0,n,s end
            if mode=="no_normal_specular" then return 0,0,0 end
            return d,n,s
        end) end
        local meta=FindMetaTable("Entity")
        local draw=meta.DrawModel
        patch(meta,"DrawModel",function(ent,flags,...)
            if not isCE8(ent) then return draw(ent,flags,...) end
            local phase=session.current
            if phase and phase.name=="no_ce8_geometry" then return end
            local depth=session.drawDepth[ent] or 0
            session.drawDepth[ent]=depth+1
            local kind=(ent.CE8ActiveLight or ent.CE8ActiveLightBatch) and "light" or ent.CE8DrawingEmissive and "emissive" or
                flags and bit.band(flags,bit.bor(STUDIO_SHADOWDEPTHTEXTURE or 0,STUDIO_SSAODEPTHTEXTURE or 0))~=0 and "shadow" or "base"
            if phase and phase.name=="no_shadow_draws" and kind=="shadow" then
                session.drawDepth[ent]=depth
                local skipped=stat("DrawModel:shadow_skipped")
                if skipped then skipped.count=skipped.count+1 end
                return
            end
            if phase and phase.name=="native_projector_enabled" and kind~="shadow"
                and ent.CE8Draft and EF_NOFLASHLIGHT and ent.RemoveEffects then
                -- Reproduce the captured missing bit at the actual submission,
                -- after the new guard. No shader/material/lighting changes.
                if ent:IsEffectActive(EF_NOFLASHLIGHT) then nativeFlashlight[ent]=true end
                ent:RemoveEffects(EF_NOFLASHLIGHT)
            end
            if depth>0 then kind="nested:"..kind end
            local row=stat("DrawModel:"..(mode=="weapons" and ent:GetClass()=="obj_ce8_projectile" and "projectile:" or "")..kind)
            if row then
                if mode=="weapons" and ent:GetClass()=="obj_ce8_projectile" then
                    return drawFinished(ent,row,clock(),draw(ent,flags,...))
                end
                local info=entityInfo(ent);local key=phase.name..":"..kind
                info.draws[key]=(info.draws[key] or 0)+1
                local flag=tostring(flags or "nil")
                info.draw_flags[flag]=(info.draw_flags[flag] or 0)+1
                if ent.GetEffects then
                    info.effects=info.effects or {}
                    local effects=tostring(ent:GetEffects())
                    info.effects[effects]=(info.effects[effects] or 0)+1
                    info.no_flashlight=EF_NOFLASHLIGHT and bit.band(ent:GetEffects(),EF_NOFLASHLIGHT)~=0 or false
                end
                local view=phase.name..":"..(session.view or "unknown")
                info.views[view]=(info.views[view] or 0)+1
                local count=ent.CE8SelectedLights or 0
                local scene=phase.scene
                scene.selected_light_sum=scene.selected_light_sum+count
                scene.selected_light_samples=scene.selected_light_samples+1
                scene.max_selected_lights=math.max(scene.max_selected_lights,count)
                if ent.CE8ActiveLightBatch then
                    info.light_categories.batch=(info.light_categories.batch or 0)+1
                    info.batch_sources=(info.batch_sources or 0)+ent.CE8ActiveLightBatch.count
                end
                if ent.CE8ActiveLight then
                    local cat=ent.CE8ActiveLight.category or "unknown"
                    info.light_categories[cat]=(info.light_categories[cat] or 0)+1
                end
            end
            return drawFinished(ent,row,clock(),draw(ent,flags,...))
        end)
    end
    scan()
end
local function cache()
    if not CLIENT or not CE8 then return end
    local result=CE8.LiveDetailCacheStats and CE8.LiveDetailCacheStats() or {}
    local state=CE8.LiveDetailState or {}
    result.shader_updates=size(state.shaderUpdates);result.programs=size(state.programs)
    result.generation=state.generation
    local batch=CE8.LightBatchState
    if batch then result.light_batch={records=size(batch.records),slots=batch.count,uploads=batch.uploads,
        cookie_uploads=batch.cookieUploads,error=batch.error,ready_materials=size(batch.readyMaterials)} end
    local scene=CE8.SceneState
    if scene then result.scene={models=size(scene.modelSlots),lights=size(scene.lights),
        parameters=#scene.parameters,pending=#scene.pending,error=scene.error,
        light_overflow=scene.lightOverflow,cookie_overflow=scene.cookieOverflow,regions=size(scene.regions),region_overflow=scene.regionOverflow} end
    result.active_proxy_programs={}
    for _,proxy in pairs(matproxy and matproxy.ActiveList or {}) do
        if proxy.name and proxy.name:sub(1,3)=="CE8" and proxy.Material then
            local program=proxy.Material:GetString("$pixshader") or "none"
            result.active_proxy_programs[program]=(result.active_proxy_programs[program] or 0)+1
        end
    end
    return result
end
local function cameraInfo()
    if not CLIENT then return end
    local p=EyePos()
    local a=EyeAngles and EyeAngles()
    return {x=p.x,y=p.y,z=p.z,pitch=a and a.p,yaw=a and a.y,roll=a and a.r}
end
local function advance(now,requested)
    restoreVisibility()
    restoreFlashlight()
    restoreMuzzleLights()
    if session.current then
        session.current.cache_end=cache();session.current.lua_kb_end=collectgarbage("count")
        session.current.camera_end=cameraInfo()
    end
    local index=requested or #session.phases+1
    local spec=stages[index]
    if not spec then session:Stop("complete") return end
    local phase={name=spec.name,start=now,finish=now+spec.seconds,frames={},render={},calls={},views={},
        lua_kb_start=collectgarbage("count"),cache_start=cache(),spikes={},
        camera_start=cameraInfo(),scene={selected_light_sum=0,selected_light_samples=0,max_selected_lights=0,
            regions={frames=0,traces=0,hulls=0,max_traces=0,static_rankings=0,projector_rankings=0},
            CE8SceneLights={upload_quads=0,max_upload_quads=0},CE8SceneParameters={upload_quads=0,max_upload_quads=0}},
        memory={net_rise_kb=0,net_drop_kb=0,large_drop_frames=0,large_drop_max_ms=0}}
    session.phases[index]=phase;session.current=phase;session.previousFrame=nil
    if effectsTest and SERVER then SetGlobal2String(phaseKey,effectRun..":"..index) end
    session.measuring=false
    if CLIENT and spec.name=="no_ce8_geometry" then scan() end
    if effectsTest then scan() end
    print("CE8 performance: "..spec.name)
    if CLIENT and spec.name=="baseline_moving" and notification then
        notification.AddLegacy("CE8 capture: move and look around now for 12 seconds.",NOTIFY_GENERIC,8)
    end
end
local function step()
    local now=clock()
    -- Background throttling can look like a shader bottleneck. Do not change
    -- the user's settings: suspend capture time while the game lacks focus.
    local unavailable=CLIENT and ((system and system.HasFocus and not system.HasFocus())
        or gui.IsConsoleVisible() or gui.IsGameUIVisible())
    if unavailable then
        session.pauseStart=session.pauseStart or now
        session.measuring=false;session.previousFrame=nil;session.previousKB=nil
        return
    elseif session.pauseStart then
        local paused=now-session.pauseStart
        session.unfocusedSeconds=(session.unfocusedSeconds or 0)+paused
        if effectsTest and session.current then
            -- Server phases keep running while a client is unfocused. Do not
            -- relabel those samples as an earlier visual condition.
            session.pauseStart=nil;session:Stop("focus_interrupted");return
        elseif session.current then
            session.current.start=session.current.start+paused
            session.current.finish=session.current.finish+paused
        else session.start=session.start+paused end
        session.pauseStart=nil
    end
    if not session.ready then
        if CLIENT and (gui.IsConsoleVisible() or gui.IsGameUIVisible()) then return end
        if now-session.start<3 then return end
        if effectsTest and CLIENT then
            local active=GetGlobal2String(phaseKey,"")
            local run,index=active:match("^([^:]+):(%d+)$")
            if not run then return end
            -- Start with the matching baseline, never invent missing phases.
            if tonumber(index)~=1 then session:Stop("missed_effects_start");return end
            effectRun=run;session.effectIndex=1
        end
        session.ready=true;install();advance(now)
    end
    if not session.current then return end
    if effectsTest and CLIENT then
        local active=GetGlobal2String(phaseKey,"")
        local run,index=active:match("^([^:]+):(%d+)$")
        index=tonumber(index)
        if run~=effectRun then session:Stop(session.effectIndex==#stages and "complete" or "server_stopped");return end
        if index~=session.effectIndex then
            if index~=session.effectIndex+1 then session:Stop("missed_effects_phase");return end
            session.effectIndex=index;advance(now,index)
        end
    elseif now>=session.current.finish then advance(now) end
    if session.stopped then return end
    session.measuring=now-session.current.start>(effectsTest and 1.5 or .5)
    if now>=session.nextScan then session.nextScan=now+1;scan() end
    if SERVER then
        if session.measuring and session.previousFrame then
            local frames=session.current.frames
            if #frames<16384 then frames[#frames+1]=now-session.previousFrame end
        end
        session.previousFrame=now
    end
end
local ok,message=xpcall(function()
    if effectsTest and SERVER then
        previousPhase=GetGlobal2String(phaseKey,"")
        effectRun=tostring(clock())
        SetGlobal2String(phaseKey,effectRun..":armed")
    end
    session.convars={}
    for _,name in ipairs({"ce8_detail_distance","ce8_normal_distance","ce8_specular_distance",
        "ce8_max_direct_lights","ce8_light_hz","ce8_light_occlusion","ce8_map_lights",
        "mat_queue_mode","mat_vsync","fps_max","engine_no_focus_sleep","ai_disabled","ai_ignoreplayers",
        "r_flashlightdepthtexture","r_flashlightdepthres","r_flashlightmodels","r_flashlightrender",
        "r_flashlightfov","r_flashlightfar","mat_antialias","mat_aaquality","r_shadows"}) do
        local cv=GetConVar(name);if cv then session.convars[name]=cv:GetString() end
    end
    hook.Add("Think",hookID,function()
        local success,err=xpcall(step,debug.traceback)
        if not success then session:Stop("error: "..tostring(err)) end
    end)
    if CLIENT then
        hook.Add("PreDrawOpaqueRenderables",hookID,function(depth,sky,sky3d)
            local rt=render.GetRenderTarget and render.GetRenderTarget()
            local view=(rt and rt:GetName() or "backbuffer")..":"..tostring(depth)..":"..tostring(sky)..":"..tostring(sky3d)
            session.view=view
            if session.current and session.measuring then
                local views=session.current.views;views[view]=(views[view] or 0)+1
            end
        end)
        hook.Add("PreRender",hookID,function()
            local now=clock();session.renderStart=now
            if session.current and session.measuring and session.previousFrame then
                local frames=session.current.frames
                local dt=now-session.previousFrame
                if #frames<16384 then frames[#frames+1]=dt end
                local kb=collectgarbage("count")
                local delta=session.previousKB and kb-session.previousKB or 0
                local memory=session.current.memory
                if delta>=0 then memory.net_rise_kb=memory.net_rise_kb+delta
                else memory.net_drop_kb=memory.net_drop_kb-delta end
                if delta < -1024 then
                    memory.large_drop_frames=memory.large_drop_frames+1
                    memory.large_drop_max_ms=math.max(memory.large_drop_max_ms,dt*1000)
                end
                local spikes=session.current.spikes
                if dt>.02 and #spikes<64 then
                    spikes[#spikes+1]={ms=dt*1000,lua_kb_delta=delta,view=session.view}
                end
                session.previousKB=kb
            end
            session.previousFrame=now
        end)
        hook.Add("PostRender",hookID,function()
            if session.current and session.measuring and session.renderStart then
                local frames=session.current.render
                if #frames<16384 then frames[#frames+1]=clock()-session.renderStart end
            end
        end)
    end
    timer.Create(hookID,60,1,function() session:Stop("watchdog") end)
    hook.Add("ShutDown",hookID,function() session:Stop("shutdown") end)
    concommand.Add("ce8_perf_stop",function() if CE8PerfSession then CE8PerfSession:Stop("manual") end end)
    print("CE8 performance "..session.realm.." armed. Close console. "..(effectsTest and
        "Keep this firefight/view for 45 seconds. Weapon particles and muzzle lights briefly switch off, then restore. Gameplay stays enabled." or mode=="weapons" and
        "Keep the firefight in view for 30 seconds. All gameplay and visuals stay enabled." or CLIENT and mode=="flashlight_guard" and
        "Keep the flashlight ON and hold this view for 17 seconds. Old/corrected draw states alternate, then restore." or CLIENT and mode=="flashlight" and
        "Keep the flashlight ON at the slow close-up distance for 25 seconds. All comparisons restore automatically." or CLIENT and mode=="scene" and
        "Hold the same swarm/view for 30 seconds. Scene lighting comparisons restore automatically." or CLIENT and mode=="steady" and
        "Hold this view for 25 seconds. All features stay enabled." or baselineOnly and
        "Hold still until the movement notification, then move/look around. All features stay enabled." or
        "Hold the view for 30 seconds; visual comparisons restore automatically."))
end,debug.traceback)
if not ok then session:Stop("setup error: "..tostring(message)) end
