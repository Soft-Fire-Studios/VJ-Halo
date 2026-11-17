-- Native PCF bindings only. Emission, motion and decay remain inside the PCFs.
if SERVER then AddCSLuaFile() AddCSLuaFile("campaign_evolved/particle_data.lua") end
CE8 = CE8 or {}
if CE8.Particles and CE8.Particles.Revision == 3 then return CE8.Particles end
local P = CE8.Particles or {}
CE8.Particles = P
P.Revision = 3
local native = include("campaign_evolved/particle_data.lua")
CE8.WeaponParticles = CE8.WeaponParticles or {files = {}, systems = {}}
local cache = CE8.WeaponParticles
local packs = {"particles/ce8_weapons.pcf", "particles/ce8_creatures.pcf", "particles/ce8_shields.pcf",
    "particles/halo_weapons.pcf", "particles/halo_creatures.pcf", "particles/hr_hunter_preview.pcf"}
local aliases = {
    ce8_hunter_charge = "hr_hunter_charge", ce8_hunter_muzzle = "hr_hunter_muzzle",
    ce8_hunter_flight = "hr_hunter_flight", ce8_hunter_impact = "hr_hunter_impact",
    ce8_jackal_shield_break_1 = "hr_jackal_depletion", ce8_jackal_shield_break_2 = "hr_jackal_depletion",
    ce8_flood_carrier_burst = "h3_carrier_burst", ce8_flood_infection_pop = "h3_infection_burst",
    ce8_flood_shared_body_destroy_2 = "h3_flood_break_m", ce8_plasma_grenade_explode_1 = "hr_grenade_impact"
}

function P.Resolve(name) return aliases[name] or name end
function P.Native(name) return native.effects[P.Resolve(name)] end

function P.Prepare(data)
    local fx = data and data.effects
    if not fx then return end
    for _, key in ipairs({"normal", "charged", "supercombine"}) do
        for kind, name in pairs(fx[key] or {}) do fx[key][kind] = P.Resolve(name) end
    end
end

function P.Load(name)
    -- Explicitly warm the model cache before loading model-rendering PCFs.
    -- A missing/error model must be visible in the report, not counted as a
    -- successful dependency merely because its MDL exists on disk.
    if not cache.nativeModels then
        cache.nativeModels = true
        local report = {}
        for _, model in ipairs(native.models) do
            util.PrecacheModel(model)
            local valid = util.IsValidModel(model)
            report[#report + 1] = {model = model, valid = valid}
            if not valid then ErrorNoHalt("Halo particle model failed to load: " .. model .. "\n") end
        end
        if CLIENT then
            file.CreateDir("ce8")
            file.Write("ce8/particle_models.json", util.TableToJSON(report, true))
        end
    end
    for _, path in ipairs(packs) do
        if not cache.files[path] then
            if not file.Exists(path, "GAME") then return false end
            game.AddParticles(path)
            cache.files[path] = true
        end
    end
    name = P.Resolve(name)
    if name and not cache.systems[name] then
        PrecacheParticleSystem(name)
        cache.systems[name] = true
    end
    return true
end

-- Native CP attachments follow sockets inside Source. Only the special basis
-- CP used by Jackal shield planes needs orientation transport; no particle
-- positions, velocities, births, fades or rendering are simulated in Lua.
local dispatch = "ce8_native_particle"
if SERVER then util.AddNetworkString(dispatch) end
local activeBases = {}
local function basis(effect, cp, forward)
    local auxiliary = math.abs(forward.z) < 0.99 and Vector(0, 0, 1) or Vector(1, 0, 0)
    local tangent = forward:Cross(auxiliary):GetNormalized()
    local binormal = forward:Cross(tangent)
    effect:SetControlPointOrientation(cp, tangent, -binormal, forward)
end

local function worldPoints(effect, settings, position, angles, direction)
    local normal = angles:Forward()
    local incoming = direction or normal
    for cp, role in pairs(settings.points) do
        local axis = normal
        if role == "up" then axis = Vector(0, 0, 1)
        elseif role == "gravity" then axis = Vector(0, 0, -1)
        elseif role == "forward" then axis = incoming
        elseif role == "backward" then axis = -incoming
        elseif role == "reflection" then axis = incoming - 2 * incoming:Dot(normal) * normal end
        local angle = axis:Angle()
        effect:SetControlPoint(cp, position)
        effect:SetControlPointOrientation(cp, angle:Forward(), angle:Right(), angle:Up())
    end
end

if CLIENT then
    local function updateBases()
        for i = #activeBases, 1, -1 do
            local item = activeBases[i]
            if not item.effect:IsValid() or item.effect:IsFinished() or not IsValid(item.owner) then
                table.remove(activeBases, i)
            else
                local frame = item.owner:GetAttachment(item.attachment)
                basis(item.effect, item.cp, frame and frame.Ang:Forward() or item.owner:GetForward())
            end
        end
        if #activeBases == 0 then hook.Remove("Think", "CE8ParticleBases") end
    end

    net.Receive(dispatch, function()
        local name = net.ReadString()
        local attached = net.ReadBool()
        local settings = native.effects[name]
        if not settings then return end
        local owner, attachment, position, angles, direction
        if attached then
            owner, attachment = net.ReadEntity(), net.ReadUInt(8)
            if not IsValid(owner) then return end
            local frame = attachment > 0 and owner:GetAttachment(attachment)
            position, angles = frame and frame.Pos or owner:GetPos(), frame and frame.Ang or owner:GetAngles()
        else
            position, angles = net.ReadVector(), net.ReadAngle()
            if net.ReadBool() then direction = net.ReadNormal() end
        end
        if not P.Load(name) then return end
        local effect
        if attached then
            effect = CreateParticleSystem(owner, name,
                attachment > 0 and PATTACH_POINT_FOLLOW or PATTACH_ABSORIGIN_FOLLOW, attachment)
        else effect = CreateParticleSystemNoEntity(name, position, angles) end
        if not effect or not effect:IsValid() then return end
        if attached then
            for cp, marker in pairs(settings.points) do
                local id = owner:LookupAttachment(marker)
                if cp > 0 and id > 0 then
                    effect:AddControlPoint(cp, owner, PATTACH_POINT_FOLLOW, marker)
                elseif cp > 0 then
                    -- World/root locations share the supplied effect origin;
                    -- authored socket names are validated before installation.
                    local frame = attachment > 0 and owner:GetAttachments()[attachment]
                    effect:AddControlPoint(cp, owner,
                        frame and PATTACH_POINT_FOLLOW or PATTACH_ABSORIGIN_FOLLOW, frame and frame.name or "")
                end
            end
        else worldPoints(effect, settings, position, angles, direction) end
        for cp, param in pairs(settings.parameters) do
            if param.role == "world_velocity_basis" then
                effect:SetControlPointOrientation(cp, Vector(1, 0, 0), Vector(0, -1, 0), Vector(0, 0, 1))
            elseif param.role == "perpendicular_sprite_basis" then
                basis(effect, cp, angles:Forward())
                if attached then
                    activeBases[#activeBases + 1] = {effect = effect, owner = owner, attachment = attachment, cp = cp}
                    hook.Add("Think", "CE8ParticleBases", updateBases)
                end
            end
        end
    end)
end

local function sendNative(name, owner, attachment, position, angles, direction)
    net.Start(dispatch)
    net.WriteString(name)
    net.WriteBool(IsValid(owner))
    if IsValid(owner) then net.WriteEntity(owner) net.WriteUInt(attachment or 0, 8)
    else
        net.WriteVector(position) net.WriteAngle(angles or Angle())
        net.WriteBool(direction ~= nil)
        if direction then net.WriteNormal(direction:GetNormalized()) end
    end
    net.SendPVS(position or owner:GetPos())
    return true
end


-- Native model particles need all three attachment angles. CP0 is still
-- maintained by PATTACH_POINT_FOLLOW; CP1 only transports orientation data.
-- Render models has a fixed Rx(-90) basis, so its Euler values are obtained
-- from Rx(90) * attachment frame (Forward, Left, Up), in radians.
local modelFrames = {ce8_needler_reload = 1}
local message = "ce8_particle_attach"
if SERVER then util.AddNetworkString(message) end

local function modelAngles(effect, controlPoint, angles, value)
    local forward, right, up = angles:Forward(), angles:Right(), angles:Up()
    local horizontal = math.sqrt(forward.x * forward.x + forward.z * forward.z)
    value.x = math.atan2(-forward.y, horizontal)
    if horizontal > 0.000001 then
        value.y = math.atan2(-forward.z, forward.x)
        value.z = math.atan2(-right.y, up.y)
    else
        value.y = math.atan2(right.x, right.z)
        value.z = 0
    end
    effect:SetControlPoint(controlPoint, value)
end

if CLIENT then
    local active = {}
    local function update()
        for i = #active, 1, -1 do
            local item = active[i]
            local effect = item.effect
            if not effect:IsValid() or effect:IsFinished() then
                table.remove(active, i)
            elseif not IsValid(item.owner) then
                effect:StopEmission(false, false, false)
                table.remove(active, i)
            else
                local attachment = item.owner:GetAttachment(item.attachment)
                if attachment then modelAngles(effect, item.cp, attachment.Ang, item.value) end
            end
        end
        if #active == 0 then hook.Remove("Think", "CE8ParticleFrames") end
    end
    net.Receive(message, function()
        local name, owner, attachment = net.ReadString(), net.ReadEntity(), net.ReadUInt(16)
        local controlPoint = modelFrames[name]
        if not controlPoint or not IsValid(owner) or not P.Load(name) then return end
        local transform = owner:GetAttachment(attachment)
        if not transform then return end
        local effect = CreateParticleSystem(owner, name, PATTACH_POINT_FOLLOW, attachment)
        if not effect or not effect:IsValid() then return end
        local value = Vector()
        modelAngles(effect, controlPoint, transform.Ang, value)
        active[#active + 1] = {effect = effect, owner = owner, attachment = attachment,
            cp = controlPoint, value = value}
        hook.Add("Think", "CE8ParticleFrames", update)
    end)
end

function P.Attach(name, owner, attachment)
    name = P.Resolve(name)
    if not SERVER or not IsValid(owner) or not P.Load(name) then return false end
    local settings = P.Native(name)
    if settings then
        local extra = next(settings.parameters) ~= nil
        for cp in pairs(settings.points) do if cp > 0 then extra = true break end end
        if extra then return sendNative(name, owner, attachment) end
        ParticleEffectAttach(name, attachment > 0 and PATTACH_POINT_FOLLOW or PATTACH_ABSORIGIN_FOLLOW, owner, attachment)
        return true
    end
    if not modelFrames[name] then
        ParticleEffectAttach(name, PATTACH_POINT_FOLLOW, owner, attachment)
        return true
    end
    local transform = owner:GetAttachment(attachment)
    if not transform then return false end
    net.Start(message)
    net.WriteString(name)
    net.WriteEntity(owner)
    net.WriteUInt(attachment, 16)
    net.SendPVS(transform.Pos)
    return true
end

function P.Emit(name, position, angles, direction)
    name = P.Resolve(name)
    if SERVER and name and P.Load(name) then
        if P.Native(name) then return sendNative(name, nil, nil, position, angles, direction) end
        -- A world burst survives the destruction of its source entity.
        ParticleEffect(name, position, angles or Angle())
        return true
    end
    return false
end

function P.Blood(owner)
    local name = owner:sub(1, 6) == "flood_" and "h3_flood_blood"
        or owner == "jackal" and "hr_elite_blood" or "hr_" .. owner .. "_blood"
    if P.Load(name) then return name end
end

function P.CharacterBlood(definition, owner)
    definition.BloodParticle = P.Blood(owner)
    -- Keep VJ's bleed eligibility, decals and sound path. Its default particle
    -- helper kills an info_particle_system after .1s; a world dispatch avoids
    -- that entity/timer and lets each converted blood layer finish naturally.
    function definition:SpawnBloodParticles(damage, hitgroup)
        local position = damage:GetDamagePosition()
        if position:IsZero() then position = self:WorldSpaceCenter() end
        P.Emit(self.BloodParticle, position, damage:GetDamageForce():Angle())
    end
end

local weapons = {
    -- Existing finite CP0->CP1 tracers remain: the new flight roots require a
    -- moving projectile, so substituting them in ParticleTracer leaks emitters.
    assault_rifle = {muzzle = "hr_ar_muzzle", impact = "hr_ar_hit", tracer = "ce8_assault_rifle_tracer"},
    battle_rifle = {muzzle = "h3_br_muzzle", tracer = "ce8_assault_rifle_tracer"},
    magnum = {muzzle = "hr_magnum_muzzle", impact = "hr_magnum_hit", tracer = "ce8_magnum_tracer"},
    shotgun = {muzzle = "hr_shotgun_muzzle", impact = "hr_shotgun_hit", tracer = "ce8_shotgun_tracer"},
    smg_rifle = {muzzle = "h3_smg_muzzle", tracer = "ce8_smg_rifle_tracer"},
    sniper_rifle = {muzzle = "hr_sniper_muzzle", impact = "hr_sniper_hit", tracer = "ce8_assault_rifle_tracer"},
    rocket_launcher = {muzzle = "hr_rocket_muzzle", flight = "ce8_rocket_projectile", impact = "hr_rocket_hit"},
    needler = {muzzle = "hr_needler_muzzle", flight = "hr_needler_bolt", impact = "hr_needler_hit", bounce = "hr_needler_bounce", expire = "ce8_needler_shatter", reload = "ce8_needler_reload"},
    needle_rifle = {muzzle = "hr_nr_muzzle", impact = "hr_nr_hit", tracer = "ce8_needle_rifle_tracer", expire = "ce8_needler_shatter", reload = "ce8_needle_rifle_reload"},
    plasma_rifle = {muzzle = "hr_pr_muzzle", flight = "hr_pr_bolt", impact = "hr_pr_hit"},
    plasma_pistol = {muzzle = "hr_pp_muzzle", flight = "hr_pp_bolt", impact = "hr_pp_hit"},
    spike_rifle = {muzzle = "ce8_spike_rifle_muzzle", flight = "hr_spiker_bolt", impact = "ce8_spike_rifle_impact"},
    beam_rifle = {muzzle = "h3_beam_muzzle", impact = "h3_beam_hit", tracer = "ce8_beam_rifle_tracer"},
    flak_cannon = {muzzle = "hr_fuelrod_muzzle", flight = "hr_fuelrod_bolt", impact = "hr_fuelrod_hit", bounce = "ce8_flak_cannon_bounce"}
}

function P.Weapon(data, name)
    local binding = weapons[name]
    if not binding then return end
    P.Load()
    data.effects = data.effects or {}
    local fx = data.effects
    fx.normal = fx.normal or {}
    for kind, root in pairs(binding) do fx.normal[kind] = root; P.Load(root) end
    -- Keep accepted PRP layers where the CER core still needs conversion.
    if data.source_effects then
        for _, kind in ipairs({"muzzle", "flight", "impact"}) do
            if binding[kind] then data.source_effects[kind] = nil end
        end
    end
    if name == "needler" or name == "needle_rifle" then
        fx.supercombine = {impact = "hr_needler_combine"}
        fx.reload_attachment = name == "needler" and "fx_smoke" or "fx_needle_caps"
    elseif name == "plasma_pistol" then
        fx.charged = fx.charged or {}
        fx.charged.muzzle, fx.charged.flight = "hr_pp_charged_muzzle", "hr_pp_charged_bolt"
        -- Converted charged impact currently has conflicting source CP0 roles.
        fx.charged.impact = "ce8_plasma_pistol_impact_2"
    end
    if binding.tracer then data.pcf_tracer = binding.tracer end
    if binding.impact and not data.projectile then data.pcf_impact = binding.impact end
    -- CP0 keeps the established CER muzzle socket; only additional authored
    -- sockets (ejection, backwash, flare) are supplied by the native metadata.
end

function P.Character(data)
    P.Load()
    if data.grenade and data.grenade.effects then
        data.grenade.effects.normal.impact = "hr_grenade_impact"
        data.grenade.effects.normal.flight = "hr_grenade_flight"
        P.Load("hr_grenade_impact") P.Load("hr_grenade_flight")
    end
    if not data.owner or data.owner:sub(1, 6) ~= "flood_" then return end
    data.effects = data.effects or {}
    data.effects.file = "particles/ce8_creatures.pcf"
    data.effects.files = nil
    data.effects.normal = data.effects.normal or {}
    local fx = data.effects.normal
    if data.owner == "flood_carrier" then fx.death = "h3_carrier_burst"
    elseif data.owner == "flood_infection" then fx.death = "h3_infection_burst"
    elseif data.combat then fx.destroy = "h3_flood_break_m" end
end

return P
