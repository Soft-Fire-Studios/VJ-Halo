-- Shared weapon effects. The server dispatches positional audio and PRP particles;
-- both realms load and precache particle definitions once.
CE8 = CE8 or {}
CE8.WeaponParticles = CE8.WeaponParticles or {files = {}, systems = {}}
local cache = CE8.WeaponParticles
local FX = {}

function FX.Load(data)
    local effects = data.effects
    if not effects then return false end
    local files = effects.files or {effects.file}
    -- Check the complete resource set before dispatching any of its effects.
    for _, path in ipairs(files) do
        if not cache.files[path] and not file.Exists(path, "GAME") then return false end
    end
    for _, path in ipairs(files) do
        if not cache.files[path] then
            game.AddParticles(path)
            cache.files[path] = true
        end
    end
    for _, variant in pairs({effects.normal, effects.charged, effects.supercombine}) do
        for _, name in pairs(variant) do
            if not cache.systems[name] then
                PrecacheParticleSystem(name)
                cache.systems[name] = true
            end
        end
    end
    return true
end

function FX.ForShot(data, charged)
    local effects = data.effects
    if not effects then return end
    if charged then return effects.charged end
    return effects.normal
end

function FX.Muzzle(weapon, data, charged)
    if not SERVER or not FX.Load(data) then return false end
    local effects = FX.ForShot(data, charged)
    local settings = data.effects
    local marker = settings.muzzle_attachment or data.muzzle
    if not effects or not effects.muzzle or not marker then return false end
    local attachment = weapon:LookupAttachment(marker)
    if attachment <= 0 then return false end
    if settings.muzzle_angles then
        local transform = weapon:GetAttachment(attachment)
        if not transform then return false end
        local offset = settings.muzzle_angles
        local position, angles = LocalToWorld(Vector(), Angle(offset[1], offset[2], offset[3]),
            transform.Pos, transform.Ang)
        -- The parent is required for Source to retain the supplied orientation.
        -- Apply the correction only to the flash, never the projectile/weapon.
        ParticleEffect(effects.muzzle, position, angles, weapon)
    else
        ParticleEffectAttach(effects.muzzle, PATTACH_POINT_FOLLOW, weapon, attachment)
    end
    return true
end

function FX.Flight(projectile, data, charged)
    if not SERVER or not FX.Load(data) then return false end
    local effects = FX.ForShot(data, charged)
    if not effects or not effects.flight then return false end
    ParticleEffectAttach(effects.flight, PATTACH_ABSORIGIN_FOLLOW, projectile, 0)
    return true
end

function FX.Impact(projectile, data, charged, collision)
    if not SERVER or not collision or not collision.HitPos or projectile.CE8ImpactPlayed
        or not FX.Load(data) then return false end
    local effects = FX.ForShot(data, charged)
    if not effects or not effects.impact then return false end
    projectile.CE8ImpactPlayed = true
    -- A world-space burst outlives the projectile; attaching it to the removed
    -- entity would also remove the impact. No impact is emitted on expiry.
    ParticleEffect(effects.impact, collision.HitPos, collision.HitNormal:Angle())
    return true
end

function FX.Supercombine(data, position)
    if not SERVER or not FX.Load(data) then return false end
    local burst = data.effects.supercombine
    if not burst or not burst.impact then return false end
    ParticleEffect(burst.impact, position, Angle())
    return true
end


-- Sound descriptors are immutable. Selection history lives separately and is
-- collected when an old sound table is replaced during a script refresh.
CE8.WeaponAudioSelections = CE8.WeaponAudioSelections or setmetatable({}, {__mode = "k"})
local selections = CE8.WeaponAudioSelections
local function choose(node)
    local count = #node.children
    if count == 0 then return end
    if count == 1 then return 1 end
    local state = selections[node]
    if not state then state = {recent = {}}; selections[node] = state end
    if node.shuffle and (not state.bag or not next(state.bag)) then
        state.bag = {}
        for i = 1, count do state.bag[i] = true end
    end
    local blocked = {}
    for _, i in ipairs(state.recent) do blocked[i] = true end
    local total, candidates = 0, {}
    for i = 1, count do
        if not blocked[i] and (not node.shuffle or state.bag[i]) then
            local weight = node.weights and node.weights[i] or 1
            if weight > 0 then total = total + weight; candidates[#candidates + 1] = {i, total} end
        end
    end
    if total <= 0 then return end
    local draw, selected = math.Rand(0, total), candidates[#candidates][1]
    for _, row in ipairs(candidates) do if draw < row[2] then selected = row[1] break end end
    if state.bag then state.bag[selected] = nil end
    state.recent[#state.recent + 1] = selected
    local retain = math.min(node.avoid or 0, count - 1)
    while #state.recent > retain do table.remove(state.recent, 1) end
    return selected
end

local function emitTree(node, position, level, filter, gain, pitch)
    if node.gain then gain = gain + math.Rand(node.gain[1], node.gain[2]) end
    if node.pitch then pitch = pitch + math.Rand(node.pitch[1], node.pitch[2]) end
    if node.file then
        -- Use a world emitter: impact tails survive projectile removal. Source
        -- supplies spatial attenuation; the bank's bus/RTPC mix is not recreated.
        EmitSound(node.file, position, 0, CHAN_AUTO, math.Clamp(10 ^ (gain / 20), 0, 1),
            level, 0, math.Clamp(100 * 2 ^ (pitch / 1200), 1, 255), 0, filter)
    elseif node.random then
        local index = choose(node)
        if index then emitTree(node.children[index], position, level, filter, gain, pitch) end
    else
        for _, child in ipairs(node.children or {}) do emitTree(child, position, level, filter, gain, pitch) end
    end
end

function FX.Sound(tree, position, level, filter)
    if not SERVER or not tree or not position then return false end
    emitTree(tree, position, level or 75, filter, 0, 0)
    return true
end

local impactMaterials = {
    [MAT_CONCRETE] = "concrete", [MAT_DIRT] = "dirt", [MAT_GRASS] = "grass",
    [MAT_SAND] = "sand", [MAT_SNOW] = "snow", [MAT_SLOSH] = "water",
    [MAT_METAL] = "metal", [MAT_GRATE] = "metal", [MAT_VENT] = "metal",
    [MAT_COMPUTER] = "metal", [MAT_WOOD] = "wood", [MAT_GLASS] = "glass",
    [MAT_TILE] = "stone", [MAT_FOLIAGE] = "grass", [MAT_WARPSHIELD] = "energy",
    [MAT_FLESH] = "flesh_human", [MAT_BLOODYFLESH] = "flesh_human",
    [MAT_ALIENFLESH] = "flesh_elite", [MAT_ANTLION] = "flesh_elite"
}
local impactProperties = {"ice", "snow", "sand", "dirt", "grass", "glass", "wood", "metal", "concrete", "stone", "water"}

function FX.ContactSurface(contact)
    local target = contact.HitEntity or contact.Entity
    if IsValid(target) then
        if target.CE8ImpactSurface then return target.CE8ImpactSurface end
        if (target.CE8Shield or 0) > 0 then
            return target.CE8UnitLabel == "jackal" and "shield_jackal" or "shield_elite"
        end
        if target:IsPlayer() and target:Armor() > 0 then return "shield_spartan" end
    end
    local surface = contact.SurfaceProps or contact.TheirSurfaceProps
    local property = surface and string.lower(util.GetSurfacePropName(surface) or "") or ""
    local mat = contact.MatType
    if not mat and surface then
        local data = util.GetSurfaceData(surface)
        mat = data and data.material
    end
    local key = impactMaterials[mat] or "default"
    if key == "flesh_human" or key == "flesh_elite" then
        if IsValid(target) then
            if target.IsCE8Elite then return "flesh_elite" end
            local label = target.CE8UnitLabel
            if label == "elite" or label == "grunt" or label == "hunter" or label == "jackal" or label == "flood" then
                return "flesh_" .. label
            end
            if target:IsPlayer() then return "flesh_human" end
        end
        return key
    end
    for _, name in ipairs(impactProperties) do
        if string.find(property, name, 1, true) then return name end
    end
    return key
end

function FX.ContactSound(sounds, collision, surface, kind, charged)
    local contact = sounds and sounds.contact
    if not contact or not collision or not collision.HitPos or collision.HitSky then return false end
    if charged and contact.charged then contact = contact.charged end
    local tree = kind == "ricochet" and contact.ricochet or nil
    if kind ~= "ricochet" then
        local surfaces = contact.impact
        surface = surface or FX.ContactSurface(collision)
        tree = surfaces and (surfaces[surface] or surfaces.default)
        local target = collision.HitEntity or collision.Entity
        if tree and string.sub(surface, 1, 7) == "shield_" and IsValid(target)
            and target.AIHasCapability and target:AIHasCapability("shield")
            and target:AIProfile().shield.sound then
            -- The character shield service already owns this exact surface
            -- cue, including its impact throttle and break replacement. Keep
            -- weapon-specific energy layers without doubling the shield sound.
            for i = 2, #(tree.children or {}) do
                FX.Sound(tree.children[i], collision.HitPos, contact.level or 75)
            end
            return true
        end
    end
    return FX.Sound(tree, collision.HitPos, contact.level or 75)
end

function FX.Flyby(sounds, start, finish, owner)
    local settings = sounds and sounds.contact and sounds.contact.flyby
    if not SERVER or not settings or not start or not finish then return end
    local segment = finish - start
    local length2 = segment:LengthSqr()
    if length2 <= 0 then return end
    for _, listener in ipairs(player.GetHumans()) do
        if IsValid(listener) and listener ~= owner then
            local eye = listener:EyePos()
            local fraction = (eye - start):Dot(segment) / length2
            -- The native half-open interval prevents the same junction being
            -- handled by both adjacent flight segments. No lifetime latch:
            -- curved shots can pass a listener again later.
            if fraction >= 0 and fraction < 1 then
                local closest = start + segment * fraction
                if (eye - closest):LengthSqr() < settings.radius * settings.radius then
                    local recipients = RecipientFilter()
                    recipients:AddPlayer(listener)
                    FX.Sound(settings.event, closest, settings.level or 75, recipients)
                end
            end
        end
    end
end

function FX.ProjectileFlyby(projectile, finish)
    if not projectile.CE8Sounds or not projectile.CE8AudioPosition then return end
    FX.Flyby(projectile.CE8Sounds, projectile.CE8AudioPosition, finish, projectile:GetOwner())
    projectile.CE8AudioPosition = Vector(finish)
end

return FX
