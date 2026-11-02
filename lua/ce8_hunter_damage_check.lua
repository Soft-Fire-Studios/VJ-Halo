-- Temporary engine validation. Only its own hidden Hunter/blocker are changed.
include("autorun/vj_ce8.lua")
if CLIENT then return end
local C=CE8.Collision
local shooter=player.GetHumans()[1]
if not IsValid(shooter) then return end
local actor=ents.Create("npc_vj_ce8_hunter")
actor.HasSounds=false;actor.DisableFindEnemy=true;actor.DisableSelectSchedule=true
actor:SetPos(shooter:GetPos()+Vector(0,0,500));actor:SetNoDraw(true)
actor:Spawn();actor:AddFlags(FL_NOTARGET);actor:SetMoveType(MOVETYPE_NONE)
local report={shots={},time=os.date("!%Y-%m-%dT%H:%M:%SZ")}
local blocker
timer.Simple(.5,function()
    local ok,err=xpcall(function()
        assert(IsValid(actor),"Temporary Hunter removed before check")
        -- Raw ents.Create does not use the spawn-menu weapon grant. Collision
        -- setup must be explicit here, not dependent on OnWeaponChange.
        report.setup={before=table.Count(actor.ColliderParts or {}),model=actor:GetModel(),
            position=actor:GetPos(),in_world=util.IsInWorld(actor:GetPos()),proxies={}}
        C.Equip(actor)
        assert(actor:GetHitBoxCount(actor:GetHitboxSet())==1,
            "Hunter model is still cached with empty hitboxes; restart GMod first")
        for surface,proxy in pairs(actor.ColliderParts or {}) do
            report.setup.proxies[surface]={valid=IsValid(proxy),owner=IsValid(proxy) and proxy:GetOwner()==actor,
                model=IsValid(proxy) and proxy:GetModel()}
        end
        assert(IsValid(actor.ColliderParts.metal) and IsValid(actor.ColliderParts.flesh),"Temporary Hunter collision proxies were not created")
        actor:ResetSequence("bind_pose");actor:SetCycle(0);actor:SetPlaybackRate(0)
        actor:SetMaxHealth(1000);actor:SetHealth(1000)
        local weapon=actor:GetActiveWeapon();if IsValid(weapon) then weapon:SetNoDraw(true) end
        report.forwarding={}
        local onDamaged=actor.OnDamaged
        actor.OnDamaged=function(self,damage,group,status)
            if #report.forwarding<32 then
                local scope=self.ColliderDamage
                report.forwarding[#report.forwarding+1]={status=status,amount=damage:GetDamage(),group=group,
                    scoped=scope~=nil,same_userdata=scope and scope.info==damage or false,
                    matched=C.IsForwarded(self,damage),god=self.GodMode or false}
            end
            return onDamaged(self,damage,group,status)
        end
        local samples={}
        report.sampling={regions={},obstructions={},rays=0}
        for _,shape in ipairs(C.Shapes) do
            if not samples[shape.region] then
                local matrix=actor:GetBoneMatrix(actor:LookupBone(shape.bone))
                for _,face in ipairs(shape.faces) do
                    local a,b,c=Vector(unpack(shape.vertices[face[1]])),Vector(unpack(shape.vertices[face[2]])),Vector(unpack(shape.vertices[face[3]]))
                    local middle=(a+b+c)/3;local normal=(b-a):Cross(c-a):GetNormalized()
                    local start=LocalToWorld(middle+normal*4,angle_zero,matrix:GetTranslation(),matrix:GetAngles())
                    local finish=LocalToWorld(middle-normal*4,angle_zero,matrix:GetTranslation(),matrix:GetAngles())
                    local tr=util.TraceLine({start=start,endpos=finish,mask=MASK_SHOT,filter=shooter})
                    report.sampling.rays=report.sampling.rays+1
                    local hit=IsValid(tr.Entity) and tr.Entity.IsPRPCollider and tr.Entity:GetOwner()==actor and tr.Entity.ColliderContact
                    local reason=hit and hit.region or (tr.HitWorld and "world" or IsValid(tr.Entity) and tr.Entity:GetClass() or "miss")
                    report.sampling.obstructions[reason]=(report.sampling.obstructions[reason] or 0)+1
                    if hit and hit.region==shape.region then
                        samples[shape.region]={start=start,finish=finish}
                        report.sampling.regions[shape.region]=true
                        break
                    end
                end
            end
        end
        local function shot(region,amount)
            local sample=assert(samples[region],"No sample for "..region)
            local before=actor:Health()
            shooter:FireBullets({Src=sample.start,Dir=(sample.finish-sample.start):GetNormalized(),Distance=8,
                Damage=amount,Num=1,Spread=vector_origin,Tracer=0,Force=1})
            return {lost=before-actor:Health(),hit=actor.ColliderLastHit,group=actor:GetLastDamageHitGroup()}
        end
        for _,region in ipairs({"armor","shield","body","weakspot"}) do report.shots[region]=shot(region,12) end
        assert(report.shots.armor.lost==0 and report.shots.shield.lost==0,"Armor leaked health")
        assert(report.shots.body.lost>0 and report.shots.weakspot.lost>report.shots.body.lost,"Worm damage missing")
        -- Observe actual FireBullets modes too: GMod/MW may use wider hulls.
        report.bullet_modes={}
        for _,mode in ipairs({{num=1,hull=0},{num=1,hull=1},{num=4,hull=0},{num=4,hull=1}}) do
            local row={num=mode.num,hull=mode.hull,hits={}}
            report.bullet_modes[#report.bullet_modes+1]=row
            local sample=samples.body
            shooter:FireBullets({Src=sample.start,Dir=(sample.finish-sample.start):GetNormalized(),Distance=8,
                Damage=1,Num=mode.num,HullSize=mode.hull,Spread=vector_origin,Tracer=0,Force=1,
                Callback=function(_,tr,d)
                    row.hits[#row.hits+1]={class=IsValid(tr.Entity) and tr.Entity:GetClass() or "world",
                        proxy=IsValid(tr.Entity) and tr.Entity.IsPRPCollider or false,startsolid=tr.StartSolid}
                    d:SetDamage(0);return {damage=false,effects=false}
                end})
        end
        local resistance=include("campaign_evolved/difficulty.lua").Multiplier("resistance")
        local threshold=actor:GetMaxHealth()*actor:CE8Data().anatomy.regions.weakspot_shell.fraction
        local first=shot("weakspot_shell",threshold*resistance*.5)
        assert(first.lost==0 and not actor:AIAnatomyMissing("weakspot_shell"),"Shell damaged body or broke early")
        local second=shot("weakspot_shell",threshold*resistance)
        assert(second.lost==0 and actor:AIAnatomyMissing("weakspot_shell"),"Shell did not break independently")
        report.shell={first=first,second=second,active=C.Active(actor,"weakspot_shell"),
            state=actor:GetBodygroup(actor:FindBodygroupByName("weakspot_shell")),threshold=threshold}
        assert(not report.shell.active and report.shell.state==2,"Destroyed shell still collides")
        actor:AIAnatomyRestore({maximum=1000,damage={},lost={}})
        local origin=actor:GetPos()+Vector(400,0,80)
        local contact=C.BlastContact(actor,origin,shooter)
        report.blast={exposed=contact and contact.region}
        local function blast()
            local d=DamageInfo();d:SetAttacker(shooter);d:SetInflictor(shooter)
            d:SetDamage(12);d:SetDamageType(DMG_BLAST);d:SetDamagePosition(origin);d:SetReportedPosition(origin)
            local before=actor:Health();actor:TakeDamageInfo(d)
            return {lost=before-actor:Health(),hit=actor.ColliderLastHit}
        end
        report.blast.open=blast()
        blocker=ents.Create("prop_physics")
        blocker:SetModel("models/hunter/blocks/cube4x4x4.mdl")
        blocker:SetPos(actor:GetPos()+Vector(200,0,80));blocker:SetNoDraw(true);blocker:Spawn()
        local physics=blocker:GetPhysicsObject();if IsValid(physics) then physics:EnableMotion(false) end
        report.blast.blocker_model=blocker:GetModel()
        report.blast.blocked=blast()
        assert(report.blast.blocked.lost==0 and report.blast.blocked.hit.region=="blocked","Blast passed through blocker")
        blocker:Remove();blocker=nil
        -- Native radius damage must reach the NPC at most once, not per proxy.
        local count=0
        local previous=actor.OnTakeDamage
        actor.OnTakeDamage=function(self,d) count=count+1;return previous(self,d) end
        util.BlastDamage(shooter,shooter,samples.body.start,24,12)
        actor.OnTakeDamage=nil
        report.blast.radius_calls=count
        assert(count<=1,"Radius damage duplicated by proxies")
    end,debug.traceback)
    if IsValid(blocker) then blocker:Remove() end
    if IsValid(actor) then C.Remove(actor);actor:Remove() end
    report.error=not ok and err or nil
    file.CreateDir("campaign_evolved")
    file.Write("campaign_evolved/collision_damage_rules.json",util.TableToJSON(report,true))
    print("CE8 Hunter damage check "..(ok and "passed" or "failed").."; report saved.")
    if not ok then ErrorNoHalt(err.."\n") end
end)
