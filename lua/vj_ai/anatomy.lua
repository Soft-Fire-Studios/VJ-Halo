-- Event-driven damage sections. VJ retains damage, weapon and attack scheduling.
local anatomy = {}

local function configuration(self)
    local settings = self.AIAnatomyBinding.settings
    return type(settings) == "function" and settings(self) or settings
end

local function bodygroup(self, name, value)
    local id = self:FindBodygroupByName(name)
    if id < 0 then return end
    if value == nil then value = self:GetBodygroupCount(id) - 1 end
    if value >= 0 and self:GetBodygroup(id) ~= value then self:SetBodygroup(id, value) end
end

local function current(self)
    if not self.AIAnatomy then
        self.AIAnatomy = {damage = {}, lost = {}, responses = {}, disabled = {}, bodygroups = {}}
    end
    return self.AIAnatomy
end

local function disarm(self, state)
    if state.disarmed then return end
    state.disarmed = true
    local weapon = self:GetActiveWeapon()
    -- Drop before disabling: DoChangeWeapon deletes weapons when disabled.
    if IsValid(weapon) then self:DropWeapon(weapon, nil, self:GetForward()) end
    self.Weapon_Disabled = true
    self:CapabilitiesRemove(bit.bor(CAP_USE_WEAPONS, CAP_WEAPON_RANGE_ATTACK1))
    if self.WeaponInventory then
        for slot, entry in pairs(self.WeaponInventory) do
            if entry == weapon then self.WeaponInventory[slot] = nil end
        end
    end
    self.WeaponEntity = self:GetActiveWeapon()
    self.WeaponInventoryStatus = VJ.WEP_INVENTORY_NONE
    self.WeaponAttackState = VJ.WEP_ATTACK_STATE_NONE
    self.WeaponAttackAnim = ACT_INVALID
    self:SetWeaponState()
    self:UpdateAnimationTranslations()
    -- VJ does not call this callback on its invalid-weapon branch. Reuse the
    -- host's one-time grip/equipment handling, including its network update.
    if self.OnWeaponChange then self:OnWeaponChange(self.WeaponEntity, weapon, false)
    elseif self.AIApplyGrip then self:AIApplyGrip(0) end
end

local function apply(self, config, state)
    local groups, disabled, weaponLost = {}, {}, false
    for name, part in pairs(config.regions) do
        local group = part.bodygroup or name
        if state.bodygroups[group] == nil then
            local id = self:FindBodygroupByName(group)
            if id >= 0 then state.bodygroups[group] = self:GetBodygroup(id) end
        end
        groups[group] = state.bodygroups[group]
        if state.lost[name] then
            groups[group] = part.blank or false
            for _, capability in ipairs(part.disables or {}) do disabled[capability] = true end
            weaponLost = weaponLost or part.disarm == true
        end
    end
    for name, part in pairs(config.regions) do
        if part.stump then
            local stump = config.regions[part.stump]
            groups[part.stump] = state.lost[name] and not state.lost[part.stump]
                and (part.stump_visible or 0) or ((stump and stump.blank) or false)
        end
    end
    for group, value in pairs(groups) do
        if value == false then bodygroup(self, group) else bodygroup(self, group, value) end
    end
    state.disabled = disabled
    if disabled.melee then self.HasMeleeAttack = false end
    if disabled.leap then
        self.HasLeapAttack = false
        if self.AIEndLeap then self:AIEndLeap(CurTime(), "anatomy") end
    end
    if disabled.charge and self.AIEndCharge then self:AIEndCharge(CurTime()) end
    if weaponLost then disarm(self, state) end
    if config.hitbox_sets then
        local selected = config.hitbox_sets(self, state.lost)
        if selected ~= nil and state.hitbox_set ~= selected then
            self:SetHitboxSet(selected)
            state.hitbox_set = selected
        end
    end
end

local function destroyed(self, config, state, name, changed)
    local part = config.regions[name]
    if not part or state.lost[name] then return end
    state.lost[name] = true
    state.damage[name] = math.max(state.damage[name] or 0, self:GetMaxHealth() * part.fraction)
    changed[#changed + 1] = name
    for _, child in ipairs(part.children or {}) do destroyed(self, config, state, child, changed) end
end

local function receive(self, config, state, hit, damage)
    local amount, maximum, changed = damage:GetDamage(), self:GetMaxHealth(), {}
    local bodyDamage = amount
    if amount <= 0 or maximum <= 0 or self.GodMode or self.Dead or self:Health() <= 0 then return end
    for name, value in pairs(hit.regions) do
        local part = config.regions[name]
        if part and part.health_scale ~= nil then
            bodyDamage = bodyDamage - amount * value / hit.total * (1 - part.health_scale)
        end
        if part and not state.lost[name] and part.fraction and part.fraction > 0 then
            local total = (state.damage[name] or 0) + amount * value / hit.total
            state.damage[name] = total
            local remaining = 1 - total / (maximum * part.fraction)
            local responses = state.responses[name] or {}
            state.responses[name] = responses
            for index, response in ipairs(part.responses or {}) do
                if not responses[index] and remaining <= response.remaining + 0.000001 then
                    responses[index] = true
                    for _, region in ipairs(response.remove or {}) do destroyed(self, config, state, region, changed) end
                end
            end
            if remaining <= 0.000001 then destroyed(self, config, state, name, changed) end
        end
    end
    damage:SetDamage(math.max(0, bodyDamage))
    if #changed == 0 then return end
    local callbacks = self.AIAnatomyBinding.callbacks
    if callbacks.severed then callbacks.severed(self, changed, state, damage) end
    apply(self, config, state)
    local lethal = false
    for _, name in ipairs(changed) do
        lethal = lethal or config.regions[name].lethal == true
        if callbacks.changed then callbacks.changed(self, name, state, damage) end
    end
    if lethal then
        -- The same accepted damage event kills the host, retaining its attacker,
        -- inflictor and VJ's death lifecycle. No recursive TakeDamageInfo call.
        damage:SetDamage(math.max(damage:GetDamage(), self:Health()))
        if callbacks.lethal then callbacks.lethal(self, damage, state) end
    end
end

local function sameEvent(hit, damage)
    if not hit or hit.time ~= CurTime() or hit.attacker ~= damage:GetAttacker()
        or hit.inflictor ~= damage:GetInflictor() or hit.kind ~= damage:GetDamageType() then return false end
    local position = damage:GetDamagePosition()
    return hit.position:DistToSqr(position) < 0.0001
end

local function record(self, region, damage, tracedBlast)
    local amount = damage:GetDamage()
    if amount <= 0 or self.Dead or self.GodMode or (damage:IsDamageType(DMG_BLAST) and not tracedBlast) then return end
    local pending = self.AIAnatomyPending
    -- TraceAttack may aggregate several pellets before one OnTakeDamage call.
    if not pending or pending.time ~= CurTime() or pending.attacker ~= damage:GetAttacker()
        or pending.inflictor ~= damage:GetInflictor() or pending.kind ~= damage:GetDamageType() then
        pending = {time = CurTime(), attacker = damage:GetAttacker(), inflictor = damage:GetInflictor(),
            kind = damage:GetDamageType(), total = 0, regions = {}}
        self.AIAnatomyPending = pending
    end
    pending.total = pending.total + amount
    if region then pending.regions[region] = (pending.regions[region] or 0) + amount end
    local position = damage:GetDamagePosition()
    pending.position = Vector(position.x, position.y, position.z)
end

function anatomy.Attach(definition, settings, callbacks)
    local binding = rawget(definition, "AIAnatomyBinding")
    if binding then binding.settings, binding.callbacks = settings, callbacks or {} return end
    definition.AIAnatomyBinding = {settings = settings, callbacks = callbacks or {}}
    local initialize, traceAttack, damaged = definition.Init, definition.OnTraceAttack, definition.OnDamaged
    local capability, melee, corpse = definition.AIHasCapability, definition.OnMeleeAttackExecute, definition.OnCreateDeathCorpse

    function definition:AIAnatomyMissing(region)
        return self.AIAnatomy and self.AIAnatomy.lost[region] == true or false
    end

    function definition:AIAnatomySnapshot()
        local state, snapshot = current(self), {version = 1, maximum = self:GetMaxHealth(), damage = {}, lost = {}}
        for name, value in pairs(state.damage) do snapshot.damage[name] = value end
        for name, value in pairs(state.lost) do snapshot.lost[name] = value end
        return snapshot
    end

    function definition:AIAnatomyRestore(snapshot, options)
        local config, state = configuration(self), current(self)
        state.damage, state.lost, state.responses = {}, {}, {}
        local reset = options and options.reset or {}
        local scale = self:GetMaxHealth() / math.max(1, tonumber(snapshot.maximum) or self:GetMaxHealth())
        for name, part in pairs(config.regions) do
            if not reset[name] then
                local amount = math.max(0, tonumber(snapshot.damage and snapshot.damage[name]) or 0) * scale
                state.damage[name] = amount
                state.lost[name] = snapshot.lost and snapshot.lost[name] == true or nil
                local remaining = 1 - amount / math.max(0.001, self:GetMaxHealth() * part.fraction)
                state.responses[name] = {}
                for index, response in ipairs(part.responses or {}) do
                    state.responses[name][index] = remaining <= response.remaining + 0.000001 or nil
                end
            end
        end
        self.AIAnatomyPending, self.AIAnatomyEvent = nil, nil
        apply(self, config, state)
    end

    function definition:Init(...)
        if initialize then initialize(self, ...) end
        apply(self, configuration(self), current(self))
    end

    function definition:OnTraceAttack(damage, direction, trace)
        local result
        if traceAttack then result = traceAttack(self, damage, direction, trace) end
        if trace.Entity ~= nil and trace.Entity ~= self then return result end
        local config = configuration(self)
        local region
        if config.trace_region then region = config.trace_region(self, trace)
        else
            local regions = config.hit_regions(self)
            region = regions and regions[(trace.HitBox or -2) + 1]
        end
        record(self, region, damage, config.traced_blasts)
        return result
    end

    function definition:OnDamaged(damage, hitgroup, status)
        local result
        if damaged then result = damaged(self, damage, hitgroup, status) end
        if status == "Init" then
            local hit = self.AIAnatomyPending
            self.AIAnatomyPending, self.AIAnatomyEvent = nil, nil
            if sameEvent(hit, damage) then
                self.AIAnatomyEvent = hit
            else
                local config = configuration(self)
                local region
                if not damage:IsDamageType(DMG_BLAST) and config.direct_trace then
                    local trace = config.direct_trace(self, damage)
                    if trace and trace.Entity == self and trace.HitBox ~= nil
                        and trace.HitBoxSet == self:GetHitboxSet() then
                        local regions = config.hit_regions(self)
                        region = regions and regions[trace.HitBox + 1]
                    end
                end
                -- No last-hitgroup fallback for generic damage or explosions.
                if region and damage:GetDamage() > 0 then
                    self.AIAnatomyEvent = {regions = {[region] = damage:GetDamage()}, total = damage:GetDamage()}
                end
            end
        elseif status == "PreDamage" then
            local hit = self.AIAnatomyEvent
            self.AIAnatomyEvent = nil -- Consume before callbacks can cause another event.
            if hit and hit.total > 0 then receive(self, configuration(self), current(self), hit, damage) end
        end
        return result
    end

    if capability then
        function definition:AIHasCapability(name)
            if self.AIAnatomy and self.AIAnatomy.disabled[name] then return false end
            return capability(self, name)
        end
    end
    function definition:OnMeleeAttackExecute(status, ...)
        if self.AIAnatomy and self.AIAnatomy.disabled.melee then return true end
        if melee then return melee(self, status, ...) end
    end
    function definition:OnCreateDeathCorpse(damage, hitgroup, body)
        if corpse then corpse(self, damage, hitgroup, body) end
        if not IsValid(body) then return end
        body.AIAnatomySnapshotData = self:AIAnatomySnapshot()
        local state = current(self)
        if state.hitbox_set ~= nil then body:SetHitboxSet(state.hitbox_set) end
    end
end

return anatomy
