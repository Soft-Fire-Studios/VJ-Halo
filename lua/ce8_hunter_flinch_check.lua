-- Temporary additive-reaction test. Run again to restore original settings.
-- An active earlier hard-flinch test is replaced with this soft-flinch test.
if not SERVER then return end
CE8 = CE8 or {}
local previous = CE8.HunterFlinchTest
if previous then
    for rank, settings in pairs(previous.ranks) do rank.flinch = settings end
    for actor, settings in pairs(previous.actors) do
        if IsValid(actor) then
            actor.CanFlinch = settings.enabled
            actor.FlinchChance = settings.chance
            actor.FlinchCooldown = settings.cooldown
            actor.NextFlinchT = math.max(CurTime(), actor.NextFlinchT or 0)
        end
    end
    CE8.HunterFlinchTest = nil
    if previous.mode == "soft" then
        print("CE8 Hunter flinch test OFF: original thresholds restored.")
        return
    end
end

local actors = ents.FindByClass("npc_vj_ce8_hunter*")
if #actors == 0 then print("CE8: spawn a Hunter first, then run this script again.") return end
local state = {ranks = {}, actors = {}, mode = "soft"}
for _, actor in ipairs(actors) do
    if not actor.Dead and actor.CE8RankSettings then
        local rank = actor:CE8RankSettings()
        if not state.ranks[rank] then
            state.ranks[rank] = rank.flinch
            rank.flinch = {threshold = math.huge, unshielded = math.huge, soft = 0, soft_unshielded = 0, cooldown = 0}
        end
        state.actors[actor] = {enabled = actor.CanFlinch, chance = actor.FlinchChance, cooldown = actor.FlinchCooldown}
        actor.CanFlinch = true
        actor.FlinchChance = 1
        actor.FlinchCooldown = false -- VJ waits for the reaction's own duration.
        actor.NextFlinchT = 0
    end
end
CE8.HunterFlinchTest = state
print("CE8 Hunter SOFT flinch test ON: any positive worm damage selects an authored additive s_ping. Run again to restore.")
