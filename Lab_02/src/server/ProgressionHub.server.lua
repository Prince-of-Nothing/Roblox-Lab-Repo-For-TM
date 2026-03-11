--[[
  ProgressionHub.server.lua
  Between-runs progression system.

  Handles:
  - Persistent currency storage (in-memory; extend with DataStore for production)
  - Upgrade definitions and purchase logic
  - Upgrade effect application on new runs
  - Broadcasts current currency / upgrade state to client on request

  Upgrade Categories:
    move_speed     – faster lane switching (shorter input delay, server-side acknowledgment)
    ability_cap    – more ability charges per run
    ability_cd     – reduced ability cooldowns
    magnet_radius  – items attract toward player (radius bonus)
    start_slow     – slightly slower early speed
    score_mult     – end-of-run score multiplier
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for the shared Remotes folder created by runner.server.lua
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)

local function waitRemote(name)
    return Remotes:WaitForChild(name, 10)
end

local CurrencyUpdateEvent = waitRemote("CurrencyUpdate")
local UpgradeResultEvent  = waitRemote("UpgradeResult")
local BuyUpgradeEvent     = waitRemote("BuyUpgrade")

-- ── Upgrade Definitions ────────────────────────────────────────────────────────
local UPGRADES = {
    move_speed    = { name = "Movement Efficiency",      baseCost = 50,  maxLevel = 3,
                      desc = "Faster lane switching response." },
    ability_cap   = { name = "Ability Capacity",          baseCost = 80,  maxLevel = 3,
                      desc = "Start each run with +1 ability charge per level." },
    ability_cd    = { name = "Ability Cooldown",          baseCost = 60,  maxLevel = 3,
                      desc = "Reduce ability cooldowns by 15% per level." },
    magnet_radius = { name = "Collection Magnet Radius",  baseCost = 70,  maxLevel = 3,
                      desc = "Collectibles attract toward player within a wider radius." },
    start_slow    = { name = "Starting Speed Control",    baseCost = 100, maxLevel = 2,
                      desc = "Begin runs at 8% lower speed per level." },
    score_mult    = { name = "Score Multiplier",          baseCost = 120, maxLevel = 3,
                      desc = "Final run score multiplied by 1.15x per level." },
    life_saver    = { name = "Life Saver",                baseCost = 100, maxLevel = 3,
                      desc = "Start each run with +1 maximum HP per level." },
    speed_up      = { name = "Speed Boost",               baseCost = 75,  maxLevel = 3,
                      desc = "Increase base run speed by 10% per level." },
}

-- Expose UPGRADES via _G so runner.server.lua can access without requiring
_G.ProgressionHubUpgrades = UPGRADES

-- ── Persist Layer ─────────────────────────────────────────────────────────────
-- Uses _G.playerPersist initialised by runner.server.lua
-- If runner hasn't run yet, initialise a safe fallback here.
_G.playerPersist = _G.playerPersist or {}

local function getPersist(player)
    local uid = tostring(player.UserId)
    if not _G.playerPersist[uid] then
        _G.playerPersist[uid] = { currency = 0, upgrades = {} }
    end
    return _G.playerPersist[uid]
end

-- ── Broadcast full upgrade state ──────────────────────────────────────────────
local function broadcastState(player)
    local persist = getPersist(player)
    CurrencyUpdateEvent:FireClient(player, persist.currency)
    -- Send each upgrade level so client can render the hub
    for id, upg in pairs(UPGRADES) do
        local level = persist.upgrades[id] or 0
        local cost  = upg.baseCost * (level + 1)
        UpgradeResultEvent:FireClient(player, "info", id, level, cost, upg.maxLevel, upg.name, upg.desc)
    end
end

-- ── Purchase Handler ──────────────────────────────────────────────────────────
BuyUpgradeEvent.OnServerEvent:Connect(function(player, upgradeId)
    local upg = UPGRADES[upgradeId]
    if not upg then
        UpgradeResultEvent:FireClient(player, false, "Unknown upgrade")
        return
    end

    local persist = getPersist(player)
    local level   = persist.upgrades[upgradeId] or 0

    if level >= upg.maxLevel then
        UpgradeResultEvent:FireClient(player, false, "Max level reached")
        return
    end

    local cost = upg.baseCost * (level + 1)
    if persist.currency < cost then
        UpgradeResultEvent:FireClient(player, false, "Not enough currency")
        return
    end

    persist.currency             = persist.currency - cost
    persist.upgrades[upgradeId] = level + 1

    CurrencyUpdateEvent:FireClient(player, persist.currency)
    UpgradeResultEvent:FireClient(player, true, upgradeId, persist.upgrades[upgradeId],
                                   upg.baseCost * (persist.upgrades[upgradeId] + 1),
                                   upg.maxLevel, upg.name, upg.desc)

    print(string.format("[ProgressionHub] %s purchased %s → Level %d",
          player.Name, upg.name, persist.upgrades[upgradeId]))
end)

-- ── Player Added: broadcast initial state after short delay ───────────────────
Players.PlayerAdded:Connect(function(player)
    task.wait(3)   -- allow runner.server.lua to finish setting up the player
    broadcastState(player)
end)

print("[ProgressionHub] Loaded.")
