-- Optional VJ weapon mounting and bounded ground-weapon retrieval.
-- VJ owns weapon firing, world-model drawing and navigation; Source picks up
-- the original entity, preserving its clip/ammo and third-party callbacks.
VJAI = VJAI or {}
VJAI.WeaponClaims = VJAI.WeaponClaims or setmetatable({}, {__mode = "k"})
local Weapons, methods = {}, {}
local claims = VJAI.WeaponClaims
local origin = Vector()

-- GMod resolves the native NPC method before an ENT/instance override. Supply
-- the authored aim only while VJ evaluates a ranged weapon's firing cone.
-- Melee, perception and unrelated NPCs retain the original native direction.
if SERVER and not VJAI.WeaponAimScopes then
    local scopes = setmetatable({}, {__mode = "k"})
    VJAI.WeaponAimScopes = scopes
    local npc = FindMetaTable("NPC")
    local native = npc.GetHeadDirection
    function npc:GetHeadDirection() return scopes[self] or native(self) end
end

local function firingCone(weapon)
    if not SERVER or not IsValid(weapon) or not weapon.IsVJBaseWeapon or not weapon.NPC_CanFire then return end
    local old = weapon.AIWeaponCone
    if old and weapon.NPC_CanFire == old.wrapper then return end
    local previous = weapon.NPC_CanFire
    local function check(self, data, owner)
        owner = owner or self:GetOwner()
        if self.IsMeleeWeapon or not IsValid(owner) or not owner.AIHeadDirection
            or not owner:AIMotionEnabled("aim") then return previous(self, data, owner) end
        local scopes = VJAI.WeaponAimScopes
        local saved = scopes[owner]
        scopes[owner] = owner:AIHeadDirection()
        local ok, result = pcall(previous, self, data, owner)
        scopes[owner] = saved
        if not ok then error(result, 0) end
        return result
    end
    weapon.AIWeaponCone = {wrapper = check}
    weapon.NPC_CanFire = check
end

function methods:AIConfigureWeapon(weapon)
    firingCone(weapon)
    local config = self.AIWeaponSettings
    if not config or not config.mount or not IsValid(weapon) or not weapon.IsVJBaseWeapon
        or (config.native and config.native(weapon)) then return false end
    local offset = weapon.WorldModelOffsetParams
    if not offset or (offset.Bone ~= "ValveBiped.Bip01_R_Hand" and not weapon.AIHandMount) then return false end
    if weapon.AIHandMount and weapon.AIHandMount.owner == self then return true end
    if self:LookupAttachment(config.mount.attachment) <= 0 then return false end
    local previous, changed = weapon.GetWorldModelOffset, weapon.OwnerChanged
    local original = offset
    local copy = {}
    for key, value in pairs(offset) do copy[key] = value end
    copy.Enabled, copy.Cache_Bone, copy.Cache_BoneID = true, nil, nil
    weapon.WorldModelOffsetParams = copy
    weapon.AIHandMount = {owner = self, original = original}
    function weapon:GetWorldModelOffset(values, owner)
        local settings = IsValid(owner) and owner.AIWeaponSettings
        local mount = settings and settings.mount
        if not mount then return previous(self, values, owner) end
        local attachment = owner:GetAttachment(owner:LookupAttachment(mount.attachment))
        if not attachment then return false end
        local position, orientation = LocalToWorld(mount.pos, mount.ang, attachment.Pos, attachment.Ang)
        position, orientation = LocalToWorld(values.Pos, values.Ang, position, orientation)
        -- Apply model roll after the weapon's own offset. Rolling the wrist
        -- first also changes its barrel direction and offset position.
        if mount.model_angle then return LocalToWorld(origin, mount.model_angle, position, orientation) end
        return position, orientation
    end
    function weapon:OwnerChanged()
        if changed then changed(self) end
        self.WorldModelOffsetParams = original
        original.Cache_Bone, original.Cache_BoneID = nil, nil
        self.GetWorldModelOffset, self.OwnerChanged, self.AIHandMount = previous, changed, nil
        if CLIENT then self:SetRenderOrigin(nil) self:SetRenderAngles(nil) end
        local owner = self:GetOwner()
        if IsValid(owner) and owner.AIConfigureWeapon then owner:AIConfigureWeapon(self) end
    end
    return true
end

local function available(actor, weapon)
    if not IsValid(weapon) or not weapon:IsWeapon() or not weapon.IsVJBaseWeapon
        or IsValid(weapon:GetOwner()) or IsValid(weapon:GetParent())
        or weapon:IsPlayerHolding() or weapon.NPC_CanBePickedUp == false then return false end
    if weapon.CanBePickedUpByNPCs and not weapon:CanBePickedUpByNPCs() then return false end
    local accept = actor.AIWeaponSettings.accepts
    if accept and not accept(weapon) then return false end
    local claim = claims[weapon]
    return not claim or not IsValid(claim.actor) or claim.actor.Dead or CurTime() >= claim.until_time or claim.actor == actor
end

local function allowed(actor)
    local config = actor.AIWeaponSettings
    if not config or not config.pickup or actor.Dead or actor:Health() <= 0 or actor.Weapon_Disabled
        or actor.VJ_Controlled or IsValid(actor:GetActiveWeapon()) or actor.AttackType
        or actor:GetState() ~= VJ_STATE_NONE or actor:IsBusy("Activities")
        or actor.IsGuard or actor.IsFollowing or actor.DisableChasingEnemy then return false end
    if config.allowed and not config.allowed(actor) then return false end
    local disabled, weapons = GetConVar("ai_disabled"), GetConVar("vj_npc_wep")
    return not (disabled and disabled:GetBool()) and not (weapons and not weapons:GetBool())
end

function methods:AICancelWeaponPickup()
    local job = self.AIWeaponPickup
    if not job then return end
    self.AIWeaponPickup = nil
    if claims[job.weapon] and claims[job.weapon].actor == self then claims[job.weapon] = nil end
    for field, previous in pairs(job.locks or {}) do
        if self[field] == job.until_time then self[field] = previous end
    end
    if self.CurrentSchedule == job.schedule then self:StopCurrentSchedule() end
end

function methods:AITakeGroundWeapon(weapon)
    if not allowed(self) or not available(self, weapon) or not self:Visible(weapon)
        or self:GetPos():DistToSqr(weapon:GetPos()) > self.AIWeaponSettings.pickup.reach ^ 2 then return false end
    if not self:PickupWeapon(weapon) or weapon:GetOwner() ~= self then return false end
    self:SelectWeapon(weapon)
    self:DoChangeWeapon() -- Existing entity: never Give a replacement class.
    self:AICancelWeaponPickup()
    return true
end

function methods:AIThinkWeaponPickup(now)
    local config, job = self.AIWeaponSettings, self.AIWeaponPickup
    if not allowed(self) then self:AICancelWeaponPickup() return false end
    local settings = config.pickup
    if job then
        if now >= job.until_time or not available(self, job.weapon) or self.CurrentSchedule ~= job.schedule
            or job.weapon:GetPos():DistToSqr(job.position) > 96 ^ 2 then
            self:AICancelWeaponPickup()
            return false
        end
        if self:AITakeGroundWeapon(job.weapon) then return false end
        return true
    end
    if now < (self.AINextWeaponSearch or 0) then return false end
    self.AINextWeaponSearch = now + settings.interval + (self:EntIndex() % 8) * 0.025
    local enemy = self:GetEnemy()
    if IsValid(enemy) and self:GetPos():DistToSqr(enemy:GetPos()) <= settings.enemy_distance ^ 2 then return false end
    local budget = VJAI.WeaponSearchBudget
    if not budget or now >= budget.until_time then budget = {until_time = now + 0.25, scans = 2} VJAI.WeaponSearchBudget = budget end
    if budget.scans <= 0 then return false end
    budget.scans = budget.scans - 1
    local nearest, distance, tested = nil, settings.radius ^ 2, 0
    for _, weapon in ipairs(ents.FindInSphere(self:GetPos(), settings.radius)) do
        if weapon:IsWeapon() then
            tested = tested + 1
            if tested > 16 then break end
            local delta = self:GetPos():DistToSqr(weapon:GetPos())
            if delta < distance and available(self, weapon) and self:Visible(weapon) then nearest, distance = weapon, delta end
        end
    end
    if not nearest then return false end
    if self:AITakeGroundWeapon(nearest) then return false end
    job = {weapon = nearest, position = nearest:GetPos(), until_time = now + settings.timeout}
    self.AIWeaponPickup, claims[nearest] = job, {actor = self, until_time = job.until_time}
    self:StopCurrentSchedule()
    if self.CurrentSchedule then self:AICancelWeaponPickup() return false end
    job.locks = {}
    for _, field in ipairs({"NextChaseTime", "NextIdleTime"}) do
        if (self[field] or 0) < job.until_time then
            job.locks[field], self[field] = self[field] or 0, job.until_time
        end
    end
    self:SetLastPosition(job.position)
    self:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH", function(schedule)
        job.schedule = schedule
        schedule.CanShootWhenMoving = false
        schedule.RunCode_OnFail = function() if self.AIWeaponPickup == job then self:AICancelWeaponPickup() end end
    end)
    return true
end

function Weapons.Attach(ENT, config)
    ENT.AIWeaponSettings = config
    for name, fn in pairs(methods) do ENT[name] = fn end
end
return Weapons
