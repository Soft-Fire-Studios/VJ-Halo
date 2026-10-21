-- CE gameplay settings, global combat multipliers and firing-accuracy curves.
CE8 = CE8 or {}
local difficulty = CE8.Difficulty or {}
CE8.Difficulty = difficulty

difficulty.Settings = {
    ce8_difficulty = {default = "normal", choices = {"normal", "heroic", "legendary"}},
    ce8_accuracy_ramp = {default = "1", min = 0, max = 1, integer = true},
    ce8_accuracy_time_scale = {default = "1", min = 0.1, max = 5},
    ce8_projectile_error_scale = {default = "1", min = 0, max = 3},
    ce8_firing_pattern = {default = "0", min = 0, max = 4, integer = true}
}

-- User-defined presets; character and weapon base values remain unchanged.
-- Choosing a difficulty loads these global multipliers once. Each ConVar can
-- then be tuned independently, without an additional hidden difficulty factor.
difficulty.Presets = {normal = 1, heroic = 2, legendary = 3}
difficulty.CombatSettings = {
    "ce8_health_scale", "ce8_damage_scale", "ce8_resistance_scale",
    "ce8_shield_scale", "ce8_shield_resistance_scale"
}
for _, name in ipairs(difficulty.CombatSettings) do
    difficulty.Settings[name] = {default = "1", min =
        (name == "ce8_damage_scale" or name == "ce8_shield_scale") and 0 or 0.01,
        max = 1000, ui_max = 5, combat = true}
end

function difficulty.Normalize(name, value)
    local setting = difficulty.Settings[name]
    if not setting then return end
    if setting.choices then
        value = tostring(value):lower()
        for _, choice in ipairs(setting.choices) do if value == choice then return value end end
        return
    end
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return end
    value = math.Clamp(value, setting.min, setting.max)
    if setting.integer then value = math.floor(value) end
    return tostring(value)
end

function difficulty.Get(name)
    local convar = GetConVar(name)
    local setting = difficulty.Settings[name]
    return difficulty.Normalize(name, convar and convar:GetString() or setting.default) or setting.default
end

function difficulty.Level(owner, weapon)
    local level = (owner and owner.CE8Difficulty) or (weapon and weapon.CE8Difficulty)
        or difficulty.Get("ce8_difficulty")
    return difficulty.Normalize("ce8_difficulty", level) or "normal"
end

function difficulty.Multiplier(name)
    return tonumber(difficulty.Get("ce8_" .. name .. "_scale"))
end

function difficulty.Combat()
    return {health = difficulty.Multiplier("health"), damage = difficulty.Multiplier("damage"),
        resistance = difficulty.Multiplier("resistance"), shield = difficulty.Multiplier("shield"),
        shield_resistance = difficulty.Multiplier("shield_resistance")}
end

function difficulty.ApplyPreset(level)
    local amount = difficulty.Presets[difficulty.Normalize("ce8_difficulty", level)]
    if not amount then return end
    for _, name in ipairs(difficulty.CombatSettings) do
        local convar = GetConVar(name)
        if convar then convar:SetString(tostring(amount)) end
    end
end

function difficulty.ApplyVitality(actor, profile, initialize)
    if not initialize and (actor.Dead or actor:Health() <= 0) then return end
    local maximum = math.max(1, math.Round(profile.health * difficulty.Multiplier("health")))
    local shields = math.max(0, profile.shield * difficulty.Multiplier("shield"))
    local healthFraction = initialize and 1 or math.Clamp(actor:Health() / math.max(1, actor:GetMaxHealth()), 0, 1)
    local shieldFraction = initialize and 1 or ((actor.CE8ShieldMax or 0) > 0
        and math.Clamp((actor.CE8Shield or 0) / actor.CE8ShieldMax, 0, 1) or 0)
    actor.StartHealth = maximum
    actor:SetMaxHealth(maximum)
    actor:SetHealth(math.max(1, math.Round(maximum * healthFraction)))
    actor.CE8ShieldMax = shields
    -- The shared shield initializer owns first-use clocks and network state.
    if not initialize or actor.CE8Shield ~= nil then
        actor.CE8Shield = shields * shieldFraction
        actor:SetNW2Float("ce8_shield_max", shields)
        actor:SetNW2Float("ce8_shield", actor.CE8Shield)
    end
end

function difficulty.RefreshActors()
    for _, actor in ipairs(ents.FindByClass("npc_vj_ce8_*")) do
        if actor.IsCE8SNPC and actor.CE8ApplyStats then actor:CE8ApplyStats(false) end
    end
end

function difficulty.ApplyDamage(_, damage)
    -- One shared dispatch covers VJ bullets, melee, other equipped weapons,
    -- explosions and supercombines. Never re-dispatch TakeDamageInfo here.
    local attacker, inflictor = damage:GetAttacker(), damage:GetInflictor()
    if (IsValid(attacker) and attacker.IsCE8SNPC)
        or (IsValid(inflictor) and inflictor.CE8NPCDamage) then
        damage:SetDamage(damage:GetDamage() * difficulty.Multiplier("damage"))
    end
end

function difficulty.Select(data, owner, weapon, now, started)
    local requested = owner.CE8FiringPattern
    if requested == nil then requested = weapon.CE8FiringPattern end
    if requested == nil then requested = tonumber(difficulty.Get("ce8_firing_pattern")) end
    requested = tonumber(difficulty.Normalize("ce8_firing_pattern", requested) or "0")
    local state = {error_scale = tonumber(difficulty.Get("ce8_projectile_error_scale"))}
    if requested > 0 or #data.profiles == 1 then
        local index = math.Clamp(math.floor(requested > 0 and requested or 1), 1, #data.profiles)
        state.mode = data.melee and "melee" or "manual"
        state.pattern = index
        return data.profiles[index], state
    end
    local level = difficulty.Level(owner, weapon)
    local curve = data.accuracy[level]
    local duration = curve.time * tonumber(difficulty.Get("ce8_accuracy_time_scale"))
    local progress = 0
    if difficulty.Get("ce8_accuracy_ramp") == "1" then
        progress = duration > 0 and math.Clamp((now - (started or now)) / duration, 0, 1) or 1
    end
    local accuracy = math.Clamp(curve.bounds[1] + (curve.bounds[2] - curve.bounds[1]) * progress, 0, 1)
    local low, high = data.profiles[1], data.profiles[2]
    local profile = {}
    for _, key in ipairs({"rate", "projectile_error"}) do
        profile[key] = low[key] + (high[key] - low[key]) * accuracy
    end
    for _, key in ipairs({"duration", "separation"}) do
        profile[key] = {}
        for index = 1, 2 do profile[key][index] = low[key][index] + (high[key][index] - low[key][index]) * accuracy end
    end
    state.mode, state.pattern, state.difficulty = "automatic", 0, level
    state.accuracy, state.progress = accuracy, progress
    state.elapsed = math.max(0, now - (started or now))
    return profile, state
end

function difficulty.ApplyBulletSpread(owner, bullet)
    if not IsValid(owner) or not owner:IsNPC() then return end
    local weapon = bullet.Inflictor
    if not IsValid(weapon) or not weapon.CE8WeaponName or not weapon.CE8ShotProfile
        or not weapon.CE8Data or weapon.CE8Data.projectile or weapon.CE8Data.melee
        or weapon:GetOwner() ~= owner then return end
    local spread = weapon:CE8ShotSpread(owner)
    bullet.Spread = Vector(spread, spread, 0)
    return true
end

function difficulty.Setup()
    -- Replicated ConVars must exist in both realms. Only the server archives
    -- the authoritative values; the menu sends edits back through the server.
    local flags = FCVAR_REPLICATED + (SERVER and FCVAR_ARCHIVE or 0)
    if not GetConVar("ce8_difficulty") then
        CreateConVar("ce8_difficulty", "normal", flags, "Campaign Evolved difficulty")
    end
    local initial = difficulty.Presets[difficulty.Get("ce8_difficulty")]
    for name, setting in pairs(difficulty.Settings) do
        if not GetConVar(name) then
            CreateConVar(name, setting.combat and tostring(initial) or setting.default, flags,
                "Campaign Evolved gameplay setting", setting.min, setting.max)
        end
    end
    if SERVER then
        local function refresh()
            timer.Create("CE8CombatStats", 0, 1, difficulty.RefreshActors)
        end
        cvars.AddChangeCallback("ce8_difficulty", function(_, _, level)
            difficulty.ApplyPreset(level)
        end, "CE8CombatPreset")
        for _, name in ipairs({"ce8_health_scale", "ce8_shield_scale"}) do
            cvars.AddChangeCallback(name, refresh, "CE8CombatStats")
        end
        hook.Add("EntityTakeDamage", "CE8CombatDamage", difficulty.ApplyDamage)
        util.AddNetworkString("CE8DifficultySetting")
        net.Receive("CE8DifficultySetting", function(_, player)
            if not IsValid(player) or not player:IsAdmin() then return end
            local name, input = net.ReadString(), net.ReadString()
            local value = difficulty.Normalize(name, input)
            if not value then return end
            GetConVar(name):SetString(value)
            if name == "ce8_difficulty" then difficulty.ApplyPreset(value) end
        end)
        hook.Add("EntityFireBullets", "CE8FiringAccuracy", difficulty.ApplyBulletSpread)
    else
        hook.Add("AddToolMenuCategories", "CE8DifficultyCategory", function()
            spawnmenu.AddToolCategory("DrVrej", "CampaignEvolved", "Campaign Evolved")
        end)
        hook.Add("PopulateToolMenu", "CE8DifficultyMenu", function()
            spawnmenu.AddToolMenuOption("DrVrej", "CampaignEvolved", "CE8Difficulty", "Difficulty", "", "", difficulty.BuildPanel)
            spawnmenu.AddToolMenuOption("DrVrej", "CampaignEvolved", "CE8Rendering", "Rendering", "", "", difficulty.BuildRenderingPanel)
        end)
    end
end

if CLIENT then
    local function send(name, input)
        local value = difficulty.Normalize(name, input)
        if not value then return end
        net.Start("CE8DifficultySetting")
        net.WriteString(name)
        net.WriteString(value)
        net.SendToServer()
    end

    function difficulty.BuildRenderingPanel(panel)
        panel:ClearControls()
        panel:Help("Local CE8 rendering settings, measured in Source units from your camera to the model. Zero keeps that feature at every distance. Features fade over the final quarter of the distance.")
        panel:NumSlider("Detail distance", "ce8_detail_distance", 0, 32768, 0)
        panel:NumSlider("Normal map distance", "ce8_normal_distance", 0, 32768, 0)
        panel:NumSlider("Specular / reflection distance", "ce8_specular_distance", 0, 32768, 0)
        panel:Help("The energy blade uses detail distance for its animated layers and normal distance for flow distortion. Its emissive silhouette remains visible; it does not calculate lighting or reflections.")
        local reset=panel:Button("Restore rendering defaults")
        reset.DoClick=function()
            RunConsoleCommand("ce8_detail_distance","1024")
            RunConsoleCommand("ce8_normal_distance","2048")
            RunConsoleCommand("ce8_specular_distance","3072")
        end
    end

    function difficulty.BuildPanel(panel)
        panel:ClearControls()
        panel:Help("Global Campaign Evolved SNPC settings. Selecting a difficulty loads its 1x / 2x / 3x combat preset and changes AI behavior. You can then edit each multiplier separately.")
        local player = LocalPlayer()
        local enabled = IsValid(player) and player:IsAdmin()
        local levels = panel:ComboBox("Difficulty")
        for _, name in ipairs(difficulty.Settings.ce8_difficulty.choices) do
            levels:AddChoice(name:sub(1, 1):upper() .. name:sub(2), name, difficulty.Get("ce8_difficulty") == name)
        end
        levels:SetEnabled(enabled)
        levels.OnSelect = function(_, _, _, value)
            -- A pending slider edit predates this preset selection.
            for _, name in ipairs(difficulty.CombatSettings) do timer.Remove("CE8Setting_" .. name) end
            send("ce8_difficulty", value)
            timer.Simple(0.5, function() if IsValid(panel) then difficulty.BuildPanel(panel) end end)
        end

        local ramp = panel:CheckBox("Build accuracy during combat")
        ramp:SetValue(difficulty.Get("ce8_accuracy_ramp") == "1")
        ramp:SetEnabled(enabled)
        ramp.OnChange = function(_, value) send("ce8_accuracy_ramp", value and 1 or 0) end

        local function slider(label, name, decimals)
            local setting = difficulty.Settings[name]
            local control = panel:NumSlider(label, nil, setting.min, setting.ui_max or setting.max, decimals)
            control:SetValue(tonumber(difficulty.Get(name)))
            control:SetEnabled(enabled)
            control.OnValueChanged = function(_, value)
                timer.Create("CE8Setting_" .. name, 0.15, 1, function() send(name, value) end)
            end
        end
        slider("Health multiplier", "ce8_health_scale", 2)
        slider("Damage dealt multiplier", "ce8_damage_scale", 2)
        slider("Health resistance multiplier", "ce8_resistance_scale", 2)
        slider("Shield capacity multiplier", "ce8_shield_scale", 2)
        slider("Shield resistance multiplier", "ce8_shield_resistance_scale", 2)
        panel:Help("Resistance 2 halves damage to that layer. Capacity changes preserve remaining health/shield percentages. Console multipliers support values up to 1000; zero damage or shield capacity is allowed.")
        slider("Accuracy ramp time multiplier", "ce8_accuracy_time_scale", 2)
        panel:Help("Higher values make accuracy build more slowly.")
        slider("Weapon spread multiplier", "ce8_projectile_error_scale", 2)

        local profiles = panel:ComboBox("Firing profile")
        local selected = tonumber(difficulty.Get("ce8_firing_pattern"))
        profiles:AddChoice("Automatic", 0, selected == 0)
        for index = 1, 4 do profiles:AddChoice("Native profile " .. index, index, selected == index) end
        profiles:SetEnabled(enabled)
        profiles.OnSelect = function(_, _, _, value) send("ce8_firing_pattern", value) end
        panel:Help("Manual profiles override the accuracy blend. Weapons with fewer profiles use their last available profile.")
        local reset = panel:Button("Restore defaults")
        reset:SetEnabled(enabled)
        reset.DoClick = function()
            for name, setting in pairs(difficulty.Settings) do
                timer.Remove("CE8Setting_" .. name)
                send(name, setting.default)
            end
            -- Rebuild after the replicated settings arrive from the server.
            timer.Simple(0.5, function() if IsValid(panel) then difficulty.BuildPanel(panel) end end)
        end
    end
end

return difficulty
