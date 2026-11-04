-- Bounded severed/death debris. VJ owns death, weapons, physics and fading.
local models = include("campaign_evolved/flood_gib_models.lua")
-- One detachable bodygroup can contain several independent authored shells.
local byBodygroup = {}
for owner, pieces in pairs(models) do
    local groups = {}; byBodygroup[owner] = groups
    local names = {}; for name in pairs(pieces) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local piece = pieces[name]
        local group = piece.bodygroup or name
        groups[group] = groups[group] or {}
        groups[group][#groups[group] + 1] = piece
    end
end
local FX = include("campaign_evolved/weapon_fx.lua")
CE8 = CE8 or {}
CE8.FloodGibs = CE8.FloodGibs or setmetatable({}, {__mode = "k"})
CE8.FloodGibCorpses = CE8.FloodGibCorpses or setmetatable({}, {__mode = "k"})
local live = CE8.FloodGibs
local corpses = CE8.FloodGibCorpses
local Gibs = {}
local retainBody = {flood_combat_human = true, flood_combat_elite = true, flood_tank = true}

local function enabled(actor)
    local setting = GetConVar("vj_npc_gib")
    return actor.CanGib and (not setting or setting:GetBool())
end

local function liveCount()
    local count = 0
    for gib in pairs(live) do
        if IsValid(gib) then count = count + 1 else live[gib] = nil end
    end
    return count
end

local function visible(actor, name, piece, region)
    local group = actor:FindBodygroupByName(piece.bodygroup or region and region.bodygroup or name)
    if group < 0 then return end
    local variant = actor:GetBodygroup(group)
    local blank = region and region.blank or actor:GetBodygroupCount(group) - 1
    if variant >= 0 and variant < blank then return variant end
end

local function anchor(actor, piece)
    if piece.attachment then
        local id = actor:LookupAttachment(piece.attachment)
        if id > 0 then return actor:GetAttachment(id) end
    elseif piece.bone then
        local id = actor:LookupBone(piece.bone)
        local matrix = id and actor:GetBoneMatrix(id)
        if matrix then return {Pos = matrix:GetTranslation(), Ang = matrix:GetAngles()} end
    end
    -- One-time fallback for an unavailable server bone matrix, never a bone
    -- writer/update loop. This bind frame is measured from the compiled model.
    if piece.bind_pos and piece.bind_ang then
        local p, a = piece.bind_pos, piece.bind_ang
        local pos, ang = LocalToWorld(Vector(p[1], p[2], p[3]), Angle(a[1], a[2], a[3]), actor:GetPos(), actor:GetAngles())
        return {Pos = pos, Ang = ang}
    end
end

local function registerCleanup(actor, entity, creator)
    creator = creator or actor:GetCreator()
    if IsValid(creator) and creator:IsPlayer() then
        entity:SetCreator(creator)
        cleanup.Add(creator, "npcs", entity)
    end
end

local function spawn(actor, piece, variant, damage, full, record)
    local frame = anchor(actor, piece)
    if not frame then return end
    local force = damage:GetDamageForce()
    local velocity = actor:GetVelocity() + VectorRand() * math.Rand(30, 60) + Vector(0, 0, 80)
        + force:GetNormalized() * math.min(force:Length() / 70, full and 300 or 180)
    if full then
        local radial = frame.Pos - actor:WorldSpaceCenter()
        velocity = velocity + radial:GetNormalized() * math.Rand(60, 120)
    end
    local create = record and record.create or actor.CreateGibEntity
    if not create then return end
    local spin = VectorRand() * math.Rand(60, 150)
    local gib = create(actor, piece.ragdoll and "prop_ragdoll" or "obj_vj_gib", piece.model, {
        Pos = frame.Pos, Ang = frame.Ang, Vel = velocity, Vel_ApplyDmgForce = false,
        BloodType = record and record.blood or actor.BloodColor,
        AngVel = spin, RemoveOnCorpseDelete = not full
    }, function(entity)
        entity:SetBodygroup(0, variant)
        entity:SetColor(actor:GetColor())
        entity:SetSkin(actor:GetSkin())
        if piece.ragdoll then
            -- Initialize the severed limb from the current pose once. VPhysics
            -- owns every joint afterward; there is no bone/update callback.
            for index = 0, entity:GetPhysicsObjectCount() - 1 do
                local physics = entity:GetPhysicsObjectNum(index)
                local bone = entity:TranslatePhysBoneToBone(index)
                local source = actor:LookupBone(entity:GetBoneName(bone))
                local matrix = source and actor:GetBoneMatrix(source)
                if IsValid(physics) then
                    if matrix then
                        physics:SetPos(matrix:GetTranslation())
                        physics:SetAngles(matrix:GetAngles())
                    end
                    physics:SetVelocity(velocity)
                    physics:SetAngleVelocity(spin)
                    physics:Wake()
                end
            end
        end
    end)
    if not IsValid(gib) then return end
    gib.CE8FloodGib = true
    live[gib] = true
    registerCleanup(actor, gib, record and record.creator)
    return gib
end

function Gibs.Sever(actor, owner, regions, changed, damage)
    if not enabled(actor) or not actor.CreateGibEntity or actor.CE8BodyDestroyed then return end
    local pieces = byBodygroup[owner]
    if not pieces then return end
    local count = liveCount()
    for _, name in ipairs(changed) do
        if count >= 128 then break end
        local region = regions[name]
        for _, piece in ipairs(pieces[region and region.bodygroup or name] or {}) do
            if count >= 128 then break end
            -- Called before bodygroup changes: hidden stumps cannot duplicate arms.
            local variant = visible(actor, name, piece, region)
            if variant ~= nil and spawn(actor, piece, variant, damage, false) then count = count + 1 end
        end
    end
end

local function preserveChildren(actor, children, creator)
    for i = #(children or {}), 1, -1 do
        local entity = children[i]
        if IsValid(entity) and (live[entity] or entity.CE8FloodGib or entity:IsWeapon()) then
            table.remove(children, i)
            registerCleanup(actor, entity, creator)
        end
    end
end

local function detachPart(actor, name, piece)
    local group = actor:FindBodygroupByName(piece.bodygroup or name)
    if group >= 0 then actor:SetBodygroup(group, actor:GetBodygroupCount(group) - 1) end
    -- Authored arm stumps close the remaining body's wound. Never manufacture
    -- a torso/leg cut or emit the newly revealed stump in this same burst.
    local stump = name == "l_forearm" and "l_upperarm" or name == "r_forearm" and "r_upperarm"
    local id = stump and actor:FindBodygroupByName(stump)
    if id and id >= 0 then actor:SetBodygroup(id, 0) end
end

function Gibs.Destroy(actor, owner, damage, body, abandon)
    local target = body or actor
    local record = body and corpses[body]
    -- A retained combat ragdoll can be destroyed after its actor's explosive
    -- death. Its registered integrity is separate from that prior gib event.
    if target.CE8BodyDestroyed and not record then return true end
    local debris = enabled(target)
    if not models[owner] or (not debris and not abandon) then return false end
    if body then corpses[body] = nil end -- Commit before callbacks can reenter.
    -- Combat corpses lose the main body when their integrity is exhausted.
    -- Live explosive deaths and the Tank still keep their authored whole body.
    local keepBody = not abandon and retainBody[owner] and not (body and
        (owner == "flood_combat_human" or owner == "flood_combat_elite"))
    target.CE8BodyDestroyed = true
    local infection = CE8.FloodInfection
    if infection then infection.DestroyBody(target) end
    -- VJ's no-corpse branch and corpse removal callback otherwise delete these.
    preserveChildren(target, body and target.ChildEnts or target.DeathCorpse_ChildEnts, record and record.creator)
    local choices = {}
    for name, piece in pairs(models[owner]) do
        local variant = visible(target, name, piece)
        if variant ~= nil then choices[#choices + 1] = {name = name, piece = piece, variant = variant} end
    end
    table.sort(choices, function(a, b)
        local ap, bp = a.piece.priority or 50, b.piece.priority or 50
        return ap < bp or ap == bp and a.name < b.name
    end)
    local limit = debris and math.min(12, math.max(0, 128 - liveCount())) or 0
    local first, total = nil, 0
    for _, choice in ipairs(choices) do
        if total >= limit then break end
        local gib = spawn(target, choice.piece, choice.variant, damage, true, record)
        if gib then
            first, total = first or gib, total + 1
            if keepBody then detachPart(target, choice.name, choice.piece) end
        end
    end
    target.CE8DeathGibCount = total
    local feedback = record and record.feedback or abandon and actor.CE8CorpseFeedback
    if not keepBody and feedback then
        local position = target:WorldSpaceCenter()
        local soundSetting, allSounds = GetConVar("vj_npc_snd_gib"), GetConVar("vj_npc_snd")
        local sound = record and record.sound or not record and actor.HasSounds ~= false and actor.HasGibOnDeathSounds ~= false
        local effects = record and record.effects or not record and actor.HasGibOnDeathEffects ~= false
        if sound and (not soundSetting or soundSetting:GetBool()) and (not allSounds or allSounds:GetBool()) then
            FX.Sound(feedback.sound, position, 80)
        end
        if debris and effects and FX.Load(feedback) then ParticleEffect(feedback.effects.normal.destroy, position, Angle()) end
    end
    if first and not keepBody then undo.ReplaceEntity(target, first) end
    if body then
        if not keepBody then body:Remove() end
    end
    return true -- Destruction commits even when the debris budget is full.
end

function Gibs.RegisterCorpse(actor, body)
    if not IsValid(body) or body:GetClass() ~= "prop_ragdoll" or body:IsFlagSet(FL_DISSOLVING)
        or not enabled(actor) or not actor.CanGibOnDeath then return end
    local owner = actor:CE8Data().owner
    if actor.CE8BodyDestroyed and owner ~= "flood_combat_human" and owner ~= "flood_combat_elite" then return end
    body.CanGib, body.BloodColor = actor.CanGib, actor.BloodColor
    corpses[body] = {owner = owner, remaining = math.max(1, actor:GetMaxHealth()),
        create = actor.CreateGibEntity, creator = actor:GetCreator(), blood = actor.BloodColor,
        feedback = actor.CE8CorpseFeedback,
        sound = actor.HasSounds ~= false and actor.HasGibOnDeathSounds ~= false,
        effects = actor.HasGibOnDeathEffects ~= false}
end

function Gibs.CorpseDamage(body, damage)
    local record = corpses[body]
    if not record or not IsValid(body) or body:IsFlagSet(FL_DISSOLVING) or not enabled(body) then return end
    local bullet = damage:IsDamageType(DMG_BULLET)
    if damage:IsDamageType(DMG_DISSOLVE) or (not bullet and damage:IsDamageType(DMG_NEVERGIB)) then return end
    local force = not bullet and damage:IsDamageType(DMG_ALWAYSGIB)
    local eligible = bullet or force or damage:IsDamageType(DMG_BLAST) or damage:IsDamageType(DMG_SLASH)
        or damage:IsDamageType(DMG_CLUB) or damage:IsDamageType(DMG_ENERGYBEAM) or damage:IsDamageType(DMG_PLASMA)
    local amount = damage:GetDamage()
    if not eligible or amount <= 0 then return end
    -- Source policy: dead-body integrity equals that actor's scaled maxhealth.
    -- FireBullets' auto ALWAYS/NEVER flags must not bypass cumulative integrity.
    record.remaining = record.remaining - amount
    if force or record.remaining <= 0 then Gibs.Destroy(body, record.owner, damage, body) end
end

function Gibs.Attach(ENT, data, sounds)
    if data.effects and data.effects.normal.destroy then
        ENT.CE8CorpseFeedback = {effects = data.effects, sound = sounds.playback.combatform_limb_destroyed}
    end
    local previous, corpse, drop = ENT.HandleGibOnDeath, ENT.OnCreateDeathCorpse, ENT.OnDeathWeaponDrop
    function ENT:HandleGibOnDeath(damage, hitgroup)
        local overrides = {AllowCorpse = retainBody[data.owner] and not (self.CE8Escape and self.CE8Escape.child),
            AllowSound = not data.burst and not self.CE8BurstPlayed and not (self.CE8Escape and self.CE8Escape.child)}
        if self.CE8BodyDestroyed then return true, overrides end
        if enabled(self) and not damage:IsDamageType(DMG_DISSOLVE) and not damage:IsDamageType(DMG_NEVERGIB)
            and (damage:IsDamageType(DMG_BLAST) or damage:IsDamageType(DMG_ALWAYSGIB) and not damage:IsDamageType(DMG_BULLET)) then
            return Gibs.Destroy(self, data.owner, damage), overrides
        end
        if previous then return previous(self, damage, hitgroup) end
        return false
    end
    function ENT:OnCreateDeathCorpse(damage, hitgroup, body)
        if corpse then corpse(self, damage, hitgroup, body) end
        if self.CE8BodyDestroyed and IsValid(body) then
            body.CE8BodyDestroyed = true
            preserveChildren(body, body.ChildEnts, self:GetCreator())
        end
        Gibs.RegisterCorpse(self, body)
    end
    function ENT:OnDeathWeaponDrop(damage, hitgroup, weapon)
        if drop then drop(self, damage, hitgroup, weapon) end
        if self.CE8BodyDestroyed and IsValid(weapon) and not IsValid(weapon:GetOwner()) and self.WeaponEntity == weapon then
            self.WeaponEntity = nil -- VJ already dropped it; do not delete it in its no-corpse branch.
            registerCleanup(self, weapon)
        end
    end
end

-- Only registered Flood ragdolls are inspected. No world scans or Think hook;
-- final accepted values include other hooks' outgoing damage multipliers.
hook.Add("PostEntityTakeDamage", "CE8_FloodGibDamage", function(body, damage, accepted)
    if accepted then Gibs.CorpseDamage(body, damage) end
end)

return Gibs
