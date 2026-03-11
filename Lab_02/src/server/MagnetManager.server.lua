-- MagnetManager.server.lua
-- Manages magnet pickup items on the track and the cupcake-attraction behaviour.
-- Changes from the old lane-based design:
--   * Removed LANE_X loop; magnets now spawn at a single random lateral offset
--     within the segment width (same approach as obstacles and cupcakes).
--   * Listens to the "SegmentCreated" BindableEvent fired by runner.server.lua
--     to receive (segFolder, segCFrame) for each new segment.
--   * Attraction loop pulls nearby Cupcake parts toward the player while active.

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- ── Constants ─────────────────────────────────────────────────────────────────
local MAGNET_SPAWN_CHANCE   = 0.20   -- probability of spawning a magnet per segment
local MAGNET_ATTRACT_RADIUS = 25     -- studs
local MAGNET_ATTRACT_SPEED  = 35     -- studs/s
local MAGNET_DURATION       = 10     -- seconds the effect lasts

local SEGMENT_WIDTH         = 30
local FLOOR_THICKNESS       = 2
local OBSTACLE_MARGIN       = 4
local SPAWN_HEIGHT          = 1.5    -- above floor surface

-- ── Remote events ─────────────────────────────────────────────────────────────
-- runner.server.lua creates the RunnerRemotes folder and MagnetStatus event
-- before any player joins.  Use WaitForChild so MagnetManager works regardless
-- of which server script starts first.
local Remotes      = ReplicatedStorage:WaitForChild("RunnerRemotes")
local MagnetStatus = Remotes:WaitForChild("MagnetStatus")

-- ── BindableEvent from runner.server.lua ─────────────────────────────────────
local SegmentCreated = ServerStorage:WaitForChild("SegmentCreated")

-- ── Per-player magnet state ───────────────────────────────────────────────────
local playerMagnets = {}   -- [Player] = { active: bool, endTime: number }

Players.PlayerAdded:Connect(function(player)
    playerMagnets[player] = { active = false, endTime = 0 }
end)

Players.PlayerRemoving:Connect(function(player)
    playerMagnets[player] = nil
end)

-- ── Spawn a magnet pickup on a segment ───────────────────────────────────────
-- segCFrame is the CFrame at the start of the segment (same reference used for
-- obstacles and cupcakes in runner.server.lua).
local function spawnOnSegment(segFolder, segCFrame)
    if math.random() > MAGNET_SPAWN_CHANCE then return end

    -- Random lateral offset within the track width
    local halfW   = SEGMENT_WIDTH / 2 - OBSTACLE_MARGIN
    local xOffset = math.random() * halfW * 2 - halfW
    -- Random position along the segment (avoid the very start and end)
    local zOffset = -(math.random() * 50 + 10)
    local yOffset = FLOOR_THICKNESS / 2 + SPAWN_HEIGHT

    local worldCF = segCFrame * CFrame.new(xOffset, yOffset, zOffset)

    local magnet        = Instance.new("Part")
    magnet.Name         = "Magnet"
    magnet.Shape        = Enum.PartType.Ball
    magnet.Size         = Vector3.new(2.5, 2.5, 2.5)
    magnet.BrickColor   = BrickColor.new("Electric blue")
    magnet.Material     = Enum.Material.Neon
    magnet.Anchored     = true
    magnet.CanCollide   = false
    magnet.CFrame       = worldCF
    magnet.Parent       = segFolder

    local collected = false
    magnet.Touched:Connect(function(hit)
        if collected then return end
        local char   = hit.Parent
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end

        collected = true
        magnet:Destroy()

        -- Activate magnetic attraction for this player
        local entry     = playerMagnets[player]
        if not entry then return end

        entry.active    = true
        entry.endTime   = tick() + MAGNET_DURATION

        MagnetStatus:FireClient(player, true)

        task.delay(MAGNET_DURATION, function()
            local current = playerMagnets[player]
            if current and tick() >= current.endTime then
                current.active = false
                MagnetStatus:FireClient(player, false)
            end
        end)
    end)
end

-- ── Listen for new segments ───────────────────────────────────────────────────
SegmentCreated.Event:Connect(function(segFolder, segCFrame)
    spawnOnSegment(segFolder, segCFrame)
end)

-- ── Attraction heartbeat ──────────────────────────────────────────────────────
-- Pulls Cupcake parts within MAGNET_ATTRACT_RADIUS toward the player while active.
RunService.Heartbeat:Connect(function(dt)
    for player, entry in pairs(playerMagnets) do
        if not entry.active then continue end
        if tick() > entry.endTime then
            entry.active = false
            MagnetStatus:FireClient(player, false)
            continue
        end

        local char     = player.Character
        if not char then continue end
        local rootPart = char:FindFirstChild("HumanoidRootPart")
        if not rootPart then continue end

        local playerPos = rootPart.Position

        -- Scan workspace descendants for cupcakes to attract.
        -- NOTE: GetDescendants() every heartbeat is intentionally simple for a
        -- prototype; replace with a tracked cupcake table for better performance.
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj.Name == "Cupcake" and obj:IsA("BasePart") then
                -- Guard: part may have been collected/destroyed on this same frame
                if not obj.Parent then continue end
                local dist = (obj.Position - playerPos).Magnitude
                if dist < MAGNET_ATTRACT_RADIUS and dist > 0.5 then
                    local dir  = (playerPos - obj.Position).Unit
                    -- Use pcall to safely skip parts destroyed mid-iteration
                    pcall(function()
                        obj.CFrame = CFrame.new(obj.Position + dir * MAGNET_ATTRACT_SPEED * dt)
                    end)
                end
            end
        end
    end
end)
