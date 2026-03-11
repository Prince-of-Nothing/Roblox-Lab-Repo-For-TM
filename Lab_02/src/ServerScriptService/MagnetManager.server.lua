--[[
  MagnetManager.server.lua
  Manages the collection-magnet power-up.

  Changes from the lane-based version
  ─────────────────────────────────────
  • No per-lane spawning.  Magnet pick-ups are spawned randomly along
    segment platforms by runner.server.lua.
  • Uses CollectionService ("Cupcake" tag) instead of scanning
    Workspace:GetDescendants() for better performance.
  • When a player's magnet is active, all tagged Cupcake parts within
    MAGNET_RADIUS studs are attracted toward the player's HumanoidRootPart.
--]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local MAGNET_RADIUS   = 30    -- studs — cupcakes inside this range are attracted
local ATTRACT_SPEED   = 50    -- studs / s — attraction speed
local MAGNET_DURATION = 15    -- seconds — how long a magnet lasts
local HEARTBEAT_DT    = 1/60  -- approximate dt for cupcake movement

-- ── Remote events ──────────────────────────────────────────────────────────
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 20)

local function waitOrMake(name)
    local e = Remotes:FindFirstChild(name)
    if not e then
        -- Runner may not have created it yet; wait briefly before creating
        e = Remotes:WaitForChild(name, 5)
        if not e then
            e        = Instance.new("RemoteEvent")
            e.Name   = name
            e.Parent = Remotes
        end
    end
    return e
end

local MagnetStatusEvent = waitOrMake("MagnetStatus")

-- ── Per-player magnet state ────────────────────────────────────────────────
local playerMagnets = {}

Players.PlayerAdded:Connect(function(player)
    playerMagnets[player] = { active = false, endTime = 0 }
end)

Players.PlayerRemoving:Connect(function(player)
    playerMagnets[player] = nil
end)

-- Seed table for players already in-game when this script loads
for _, player in ipairs(Players:GetPlayers()) do
    playerMagnets[player] = { active = false, endTime = 0 }
end

-- ── Magnet part touch handler ─────────────────────────────────────────────
-- Called by runner.server.lua indirectly: magnet parts are named "Magnet"
-- and tagged "MagnetPickup".  We listen via CollectionService.
local function onMagnetAdded(part)
    part.Touched:Connect(function(hit)
        local char   = hit.Parent
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end

        local mData = playerMagnets[player]
        if not mData then return end

        -- Activate / refresh magnet duration
        mData.active  = true
        mData.endTime = os.clock() + MAGNET_DURATION
        MagnetStatusEvent:FireClient(player, true)
        part:Destroy()
    end)
end

-- Hook any magnet parts that already exist or get added later
CollectionService:GetInstanceAddedSignal("MagnetPickup"):Connect(onMagnetAdded)
for _, part in ipairs(CollectionService:GetTagged("MagnetPickup")) do
    onMagnetAdded(part)
end

-- ── Heartbeat: attract cupcakes toward active magnet players ──────────────
RunService.Heartbeat:Connect(function()
    local now = os.clock()

    for player, mData in pairs(playerMagnets) do
        if not mData.active then continue end

        -- Check expiry
        if now > mData.endTime then
            mData.active = false
            MagnetStatusEvent:FireClient(player, false)
            continue
        end

        local char = player.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then continue end

        local rootPos = root.Position

        -- Iterate over all tagged cupcakes (much cheaper than GetDescendants)
        for _, cup in ipairs(CollectionService:GetTagged("Cupcake")) do
            if not cup or not cup.Parent then continue end

            local dist = (cup.Position - rootPos).Magnitude
            if dist <= MAGNET_RADIUS and dist > 0.5 then
                local dir    = (rootPos - cup.Position).Unit
                cup.CFrame   = cup.CFrame + dir * ATTRACT_SPEED * HEARTBEAT_DT
            end
        end
    end
end)
