-- Temporary observation of existing Hunters. No spawns, damage or behavior changes.
if CLIENT then return end
if CE8CollisionHitCheck then CE8CollisionHitCheck() end
local C=PRP and PRP.Colliders
local player=player.GetHumans()[1]
if not C or not IsValid(player) then print("PRP colliders/player unavailable") return end
local targets=ents.FindByClass("npc_vj_ce8_hunter*")
table.sort(targets,function(a,b)return a:GetPos():DistToSqr(player:GetPos())<b:GetPos():DistToSqr(player:GetPos())end)
local watched,restore={},{}
local report={time=os.date("!%Y-%m-%dT%H:%M:%SZ"),events={},rays={},actors={}}
local function entity(e)
    return IsValid(e) and {id=e:EntIndex(),class=e:GetClass(),owner=e:GetOwner():EntIndex()} or nil
end
local function hit(h)
    if not h then return end
    return {position=h.HitPos,fraction=h.Fraction,group=h.group,region=h.region,part=h.part,scale=h.damage_scale}
end
local function event(row)
    if #report.events>=240 then return end
    row.time=CurTime();report.events[#report.events+1]=row
end
for i=1,math.min(4,#targets) do
    local actor=targets[i]
    watched[actor]=true
    report.actors[#report.actors+1]={entity=entity(actor),model=actor:GetModel(),health=actor:Health(),
        groups=actor:GetBodyGroups(),set=actor:GetHitboxSet(),solid=actor:GetSolid(),flags=actor:GetSolidFlags()}
    for _,name in ipairs({"OnTraceAttack","OnDamaged"}) do
        local original=actor[name]
        if original then
            local raw=rawget(actor:GetTable(),name)
            local wrapper
            if name=="OnTraceAttack" then
                wrapper=function(self,damage,direction,trace)
                    event({stage="trace",actor=self:EntIndex(),amount=damage:GetDamage(),position=damage:GetDamagePosition(),
                        start=trace.StartPos,hit=trace.HitPos,group=trace.HitGroup,region=trace.ColliderRegion,
                        scaled=trace.ColliderScaled,source=entity(trace.Entity)})
                    return original(self,damage,direction,trace)
                end
            else
                wrapper=function(self,damage,group,status)
                    local row={stage=status,actor=self:EntIndex(),amount=damage:GetDamage(),health=self:Health(),
                        position=damage:GetDamagePosition(),force=damage:GetDamageForce(),group=group,
                        forwarded=C.IsForwarded(self,damage),attacker=entity(damage:GetAttacker())}
                    event(row)
                    local result=original(self,damage,group,status)
                    row.after=damage:GetDamage();row.last=self.ColliderLastHit
                    return result
                end
            end
            actor[name]=wrapper
            restore[#restore+1]=function()if IsValid(actor) and actor[name]==wrapper then actor[name]=raw end end
        end
    end
end
if not next(watched) then print("No existing Hunter found") return end
local function compare(start,direction,trace,source)
    if #report.rays>=96 then return end
    local row={time=CurTime(),source=source,start=start,direction=direction,native=entity(trace.Entity),
        native_hit=trace.HitPos,native_fraction=trace.Fraction,start_solid=trace.StartSolid,meshes={}}
    for actor in pairs(watched) do
        if IsValid(actor) then
            local h=C.Trace(actor,nil,start,direction*8192,false)
            if h then row.meshes[#row.meshes+1]={actor=actor:EntIndex(),hit=hit(h),health=actor:Health(),
                native_to_mesh=trace.HitPos:Distance(h.HitPos)} end
        end
    end
    report.rays[#report.rays+1]=row
end
hook.Add("PostEntityFireBullets","CE8CollisionHitCheck",function(shooter,data)
    local trace=data.Trace
    if trace and trace.StartPos and trace.HitPos then
        local e=trace.Entity
        if shooter==player or watched[e] or IsValid(e) and e.IsPRPCollider and watched[e:GetOwner()] then
            compare(trace.StartPos,data.Dir or (trace.HitPos-trace.StartPos):GetNormalized(),trace,"bullet")
        end
    end
end)
hook.Add("PostEntityTakeDamage","CE8CollisionHitCheck",function(target,damage,took)
    if watched[target] or target.IsPRPCollider and watched[target:GetOwner()] then
        event({stage="post_damage",entity=entity(target),amount=damage:GetDamage(),took=took,health=target:Health()})
    end
end)
local function finish()
    hook.Remove("PostEntityFireBullets","CE8CollisionHitCheck")
    hook.Remove("PostEntityTakeDamage","CE8CollisionHitCheck")
    timer.Remove("CE8CollisionHitCheck")
    for _,fn in ipairs(restore) do fn() end
    file.CreateDir("campaign_evolved")
    file.Write("campaign_evolved/collision_hits.json",util.TableToJSON(report,true))
    CE8CollisionHitCheck=nil
    print("CE8 collision hit report saved; observation stopped.")
end
CE8CollisionHitCheck=finish
local ticks=0
timer.Create("CE8CollisionHitCheck",.25,72,function()
    ticks=ticks+1
    if not IsValid(player) then finish() return end
    local weapon=player:GetActiveWeapon()
    report.weapon=IsValid(weapon) and weapon:GetClass() or nil
    -- Restore each proxy's transient contact after the comparison trace.
    local contacts={}
    for actor in pairs(watched) do
        if IsValid(actor) then
            for _,proxy in pairs(actor.ColliderParts or {}) do
                if IsValid(proxy) then contacts[#contacts+1]={proxy,proxy.ColliderContact} end
            end
        end
    end
    local start,direction=player:GetShootPos(),player:GetAimVector()
    local trace=util.TraceLine({start=start,endpos=start+direction*8192,mask=MASK_SHOT,filter=player})
    for _,row in ipairs(contacts) do row[1].ColliderContact=row[2] end
    compare(start,direction,trace,"aim")
    if ticks>=72 then finish() end
end)
print("CE8 collision observation: shoot working and failing worm areas for 18 seconds.")
