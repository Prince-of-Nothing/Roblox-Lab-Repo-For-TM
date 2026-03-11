-- runner.server.lua
-- Free-steering endless runner with curved track generation.
-- Requirements:
--   * No lane mechanics (LaneSwitch / laneIndex / LANE_X removed)
--   * Player steers with A/D via RunnerSteer RemoteEvent (TurnAxis in [-1,1])
--   * Server rotates character heading and drives LinearVelocity = LookVector * speed
--   * Track generated with a trackCFrame cursor; shapes I/C/S/L with weighted probabilities
--   * Segment advance driven by distanceTravelled (no Z-only assumptions)
--   * Obstacles & cupcakes spawned at random lateral offsets relative to segment CFrame

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage  = game:GetService("ServerStorage")

-- ── Constants ─────────────────────────────────────────────────────────────────
local FORWARD_SPEED       = 30      -- studs/s starting forward speed
local MAX_SPEED           = 120     -- studs/s cap
local SPEED_RAMP_RATE     = 0.04    -- studs/s gained per second
local TURN_RATE           = math.rad(80) -- max yaw rate (radians/s)

local SEGMENT_LENGTH      = 80      -- studs, length budget per segment
local SEGMENT_WIDTH       = 30      -- studs, track width
local FLOOR_THICKNESS     = 2       -- studs
local FLOOR_Y             = 2       -- world Y for floor center
-- R15 HumanoidRootPart is ~2.5 studs above the character's feet.
-- Floor top = FLOOR_Y + FLOOR_THICKNESS/2 = 3.  Correct HRP spawn = 3 + 2.5 = 5.5.
local PLAYER_SPAWN_Y      = FLOOR_Y + FLOOR_THICKNESS / 2 + 2.5

local SUB_PIECES          = 8       -- sub-parts per curved segment
local CURVE_C_ANGLE       = math.rad(45)   -- total bend for C shape
local CURVE_S_HALF_ANGLE  = math.rad(30)   -- half-bend for each arm of S shape
local CURVE_L_ANGLE       = math.rad(90)   -- total bend for L shape (corner)

local SAFE_ZONE_SEGMENTS  = 3       -- first N segments are obstacle-free
local LOOKAHEAD_SEGMENTS  = 6       -- spawn up to this many segments ahead
local TOTAL_SEGMENTS_KEPT = 10      -- delete oldest segment beyond this count

local OBSTACLE_MARGIN     = 4       -- lateral safety margin from edge (studs)
local OBSTACLE_H          = 4       -- obstacle height (studs)
local OBSTACLE_CHANCE     = 0.55    -- probability per eligible segment
local CUPCAKE_CHANCE      = 0.45    -- probability per eligible segment

-- Weighted segment shapes (weights must sum to 100)
local SHAPE_WEIGHTS = {
    { shape = "I", cumulative = 92  },
    { shape = "C", cumulative = 95  },
    { shape = "S", cumulative = 98  },
    { shape = "L", cumulative = 100 },
}

-- ── Remote / Bindable events ──────────────────────────────────────────────────
local function ensureInstance(parent, class, name)
    local obj = parent:FindFirstChild(name)
    if not obj then
        obj = Instance.new(class)
        obj.Name = name
        obj.Parent = parent
    end
    return obj
end

local Remotes          = ensureInstance(ReplicatedStorage, "Folder",        "RunnerRemotes")
local RunnerSteer      = ensureInstance(Remotes,           "RemoteEvent",   "RunnerSteer")
local MilestoneUIEvent = ensureInstance(Remotes,           "RemoteEvent",   "MilestoneUIEvent")
local SpeedUpdate      = ensureInstance(Remotes,           "RemoteEvent",   "SpeedUpdate")
-- MagnetStatus is used by MagnetManager.server.lua; create it here so the
-- client's WaitForChild resolves quickly regardless of script load order.
ensureInstance(Remotes, "RemoteEvent", "MagnetStatus")

-- BindableEvent for server-to-server communication with MagnetManager
local SegmentCreated   = ensureInstance(ServerStorage,     "BindableEvent", "SegmentCreated")

-- ── Shape picker ─────────────────────────────────────────────────────────────
local function pickShape()
    local roll = math.random(1, 100)
    for _, entry in ipairs(SHAPE_WEIGHTS) do
        if roll <= entry.cumulative then
            return entry.shape
        end
    end
    return "I"
end

-- ── Floor part factory ────────────────────────────────────────────────────────
local function makeFloorPart(cf, sizeX, sizeZ, parent)
    local p = Instance.new("Part")
    p.Name            = "TrackFloor"
    p.Anchored        = true
    p.CanCollide      = true
    p.Material        = Enum.Material.SmoothPlastic
    p.BrickColor      = BrickColor.new("Medium stone grey")
    p.Size            = Vector3.new(sizeX, FLOOR_THICKNESS, sizeZ)
    p.CFrame          = cf
    p.Parent          = parent
    return p
end

-- ── Segment builder ───────────────────────────────────────────────────────────
-- Returns (list_of_parts, newTrackCFrame)
-- newTrackCFrame is the cursor AFTER this segment so the next can seamlessly join.
local function buildSegment(trackCFrame, shape, segFolder)
    local parts   = {}
    local subLen  = SEGMENT_LENGTH / SUB_PIECES
    local cursor  = trackCFrame

    if shape == "I" then
        -- Single straight floor piece centred along the forward axis
        local partCF = cursor * CFrame.new(0, 0, -SEGMENT_LENGTH / 2)
        table.insert(parts, makeFloorPart(partCF, SEGMENT_WIDTH, SEGMENT_LENGTH, segFolder))
        cursor = cursor * CFrame.new(0, 0, -SEGMENT_LENGTH)

    elseif shape == "C" then
        -- Gradual curve: SUB_PIECES sub-parts each turning curveAngle/SUB_PIECES
        local dir       = math.random(0, 1) == 0 and 1 or -1
        local angleEach = (CURVE_C_ANGLE * dir) / SUB_PIECES
        for _ = 1, SUB_PIECES do
            local partCF = cursor * CFrame.new(0, 0, -subLen / 2)
            table.insert(parts, makeFloorPart(partCF, SEGMENT_WIDTH, subLen, segFolder))
            cursor = cursor * CFrame.new(0, 0, -subLen) * CFrame.Angles(0, angleEach, 0)
        end

    elseif shape == "S" then
        -- S-curve: first half turns one way, second half turns back (net 0° change)
        local dir       = math.random(0, 1) == 0 and 1 or -1
        local halfPcs   = SUB_PIECES / 2
        local angle1    = (CURVE_S_HALF_ANGLE *  dir) / halfPcs
        local angle2    = (CURVE_S_HALF_ANGLE * -dir) / halfPcs
        for i = 1, SUB_PIECES do
            local partCF  = cursor * CFrame.new(0, 0, -subLen / 2)
            table.insert(parts, makeFloorPart(partCF, SEGMENT_WIDTH, subLen, segFolder))
            local ang     = (i <= halfPcs) and angle1 or angle2
            cursor = cursor * CFrame.new(0, 0, -subLen) * CFrame.Angles(0, ang, 0)
        end

    elseif shape == "L" then
        -- 90° corner approximated with SUB_PIECES sub-parts
        local dir       = math.random(0, 1) == 0 and 1 or -1
        local angleEach = (CURVE_L_ANGLE * dir) / SUB_PIECES
        for _ = 1, SUB_PIECES do
            local partCF = cursor * CFrame.new(0, 0, -subLen / 2)
            table.insert(parts, makeFloorPart(partCF, SEGMENT_WIDTH, subLen, segFolder))
            cursor = cursor * CFrame.new(0, 0, -subLen) * CFrame.Angles(0, angleEach, 0)
        end
    end

    return parts, cursor
end

-- ── Obstacle spawning ─────────────────────────────────────────────────────────
local function spawnObstacle(segCFrame, segFolder)
    local halfW    = SEGMENT_WIDTH / 2 - OBSTACLE_MARGIN
    local xOffset  = math.random() * halfW * 2 - halfW
    -- Place somewhere in the middle two-thirds of the segment (not at the very ends)
    local zOffset  = -(math.random() * SEGMENT_LENGTH * 0.6 + SEGMENT_LENGTH * 0.2)
    local yOffset  = FLOOR_THICKNESS / 2 + OBSTACLE_H / 2

    local worldCF  = segCFrame * CFrame.new(xOffset, yOffset, zOffset)

    local obs      = Instance.new("Part")
    obs.Name       = "Obstacle"
    obs.Size       = Vector3.new(4, OBSTACLE_H, 4)
    obs.BrickColor = BrickColor.new("Bright red")
    obs.Material   = Enum.Material.Neon
    obs.Anchored   = true
    obs.CFrame     = worldCF
    obs.Parent     = segFolder

    obs.Touched:Connect(function(hit)
        local char   = hit.Parent
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            hum.Health = 0
        end
    end)
end

-- ── Cupcake spawning ──────────────────────────────────────────────────────────
local function spawnCupcake(segCFrame, segFolder)
    local halfW    = SEGMENT_WIDTH / 2 - OBSTACLE_MARGIN
    local xOffset  = math.random() * halfW * 2 - halfW
    local zOffset  = -(math.random() * SEGMENT_LENGTH * 0.7 + SEGMENT_LENGTH * 0.1)
    local yOffset  = FLOOR_THICKNESS / 2 + 1.5

    local worldCF  = segCFrame * CFrame.new(xOffset, yOffset, zOffset)

    local cupcake       = Instance.new("Part")
    cupcake.Name        = "Cupcake"
    cupcake.Shape       = Enum.PartType.Ball
    cupcake.Size        = Vector3.new(2.5, 2.5, 2.5)
    cupcake.BrickColor  = BrickColor.new("Hot pink")
    cupcake.Material    = Enum.Material.Neon
    cupcake.Anchored    = true
    cupcake.CanCollide  = false
    cupcake.CFrame      = worldCF
    cupcake.Parent      = segFolder

    local collected = false
    cupcake.Touched:Connect(function(hit)
        if collected then return end
        local char   = hit.Parent
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end
        collected    = true
        cupcake:Destroy()

        local stats  = player:FindFirstChild("leaderstats")
        if stats then
            local coins = stats:FindFirstChild("Coins")
            if coins then coins.Value += 1 end
        end

        local rootPart = char:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local snd        = Instance.new("Sound")
            snd.SoundId      = "rbxassetid://3124262382"
            snd.Volume       = 0.6
            snd.Parent       = rootPart
            snd:Play()
            game:GetService("Debris"):AddItem(snd, 2)
        end
    end)
end

-- ── Per-player state ──────────────────────────────────────────────────────────
local playerData = {}

local function newPlayerData()
    return {
        running          = false,
        heading          = 0,       -- current yaw in radians (0 = facing -Z)
        turnAxis         = 0,       -- [-1, 1], from client
        currentSpeed     = FORWARD_SPEED,
        distanceTravelled= 0,
        segmentCount     = 0,
        nextSpawnDist    = 0,       -- distanceTravelled threshold for next segment
        trackCFrame      = CFrame.new(0, FLOOR_Y, 0),
        segments         = {},      -- {folder, segCFrame}
        linearVelocity   = nil,
        rootPart         = nil,
        milestoneReached = {},
        speedTimer       = 0,
    }
end

-- ── Spawn one track segment ───────────────────────────────────────────────────
local function spawnSegment(data, shape)
    local idx        = data.segmentCount + 1
    data.segmentCount = idx

    local segFolder  = Instance.new("Folder")
    segFolder.Name   = "Segment_" .. idx
    segFolder.Parent = workspace

    local startCFrame        = data.trackCFrame
    local _, newTrackCFrame  = buildSegment(startCFrame, shape, segFolder)
    data.trackCFrame         = newTrackCFrame

    -- Spawn pickups only outside the safe zone
    if idx > SAFE_ZONE_SEGMENTS then
        if math.random() < OBSTACLE_CHANCE then
            spawnObstacle(startCFrame, segFolder)
        end
        if math.random() < CUPCAKE_CHANCE then
            spawnCupcake(startCFrame, segFolder)
        end
    end

    table.insert(data.segments, { folder = segFolder, segCFrame = startCFrame })
    data.nextSpawnDist = data.nextSpawnDist + SEGMENT_LENGTH

    -- Notify MagnetManager (server-to-server BindableEvent)
    SegmentCreated:Fire(segFolder, startCFrame)
end

-- ── Start runner for a player ─────────────────────────────────────────────────
local function startRunner(player, data)
    local char     = player.Character
    if not char then return end
    local rootPart = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid then return end

    -- Prevent default character movement
    humanoid.WalkSpeed   = 0
    humanoid.JumpPower   = 0
    humanoid.AutoRotate  = false

    -- Clean up any segments from a previous run before starting fresh
    for _, seg in ipairs(data.segments) do
        if seg.folder and seg.folder.Parent then
            seg.folder:Destroy()
        end
    end

    -- Set up LinearVelocity constraint for server-driven forward motion
    local att    = Instance.new("Attachment")
    att.Name     = "RunnerAtt"
    att.Parent   = rootPart

    local lv     = Instance.new("LinearVelocity")
    lv.Name      = "RunnerVelocity"
    lv.Attachment0              = att
    lv.MaxForce                 = 1e6
    lv.VelocityConstraintMode   = Enum.VelocityConstraintMode.Vector
    lv.VectorVelocity           = Vector3.new(0, 0, -FORWARD_SPEED)
    lv.Parent    = rootPart

    -- Reset per-player state
    data.running           = true
    data.heading           = 0
    data.turnAxis          = 0
    data.currentSpeed      = FORWARD_SPEED
    data.distanceTravelled = 0
    data.segmentCount      = 0
    data.nextSpawnDist     = 0
    data.trackCFrame       = CFrame.new(0, FLOOR_Y, 0)
    data.segments          = {}
    data.milestoneReached  = {}
    data.speedTimer        = 0
    data.linearVelocity    = lv
    data.rootPart          = rootPart

    -- Teleport character above the track start
    rootPart.CFrame = CFrame.new(0, PLAYER_SPAWN_Y, 0)

    -- Pre-spawn initial lookahead segments
    for i = 1, LOOKAHEAD_SEGMENTS do
        local shape = (i <= SAFE_ZONE_SEGMENTS) and "I" or pickShape()
        spawnSegment(data, shape)
    end

    -- Stop runner when character dies
    humanoid.Died:Connect(function()
        data.running = false
        if lv.Parent   then lv:Destroy()  end
        if att.Parent  then att:Destroy() end
    end)
end

-- ── Heartbeat: steering + physics + segment management ───────────────────────
RunService.Heartbeat:Connect(function(dt)
    for player, data in pairs(playerData) do
        if not data.running then continue end

        local rootPart = data.rootPart
        if not (rootPart and rootPart.Parent) then continue end

        -- 1. Update heading from turn input
        if data.turnAxis ~= 0 then
            data.heading = data.heading + TURN_RATE * data.turnAxis * dt
        end

        -- 2. Reconstruct flat CFrame from heading (keeps character upright)
        local pos     = rootPart.CFrame.Position
        local lookDir = Vector3.new(math.sin(data.heading), 0, -math.cos(data.heading))
        -- CFrame.lookAt(eye, lookAt) makes the -Z axis (LookVector) face toward lookAt.
        -- lookDir is always unit-length (sin²+cos²=1), so pos+lookDir is never equal to pos.
        rootPart.CFrame = CFrame.lookAt(pos, pos + lookDir)

        -- 3. Ramp speed
        data.currentSpeed = math.min(
            data.currentSpeed + SPEED_RAMP_RATE * dt,
            MAX_SPEED
        )

        -- 4. Update LinearVelocity direction to follow character heading
        local lv = data.linearVelocity
        if lv and lv.Parent then
            lv.VectorVelocity = lookDir * data.currentSpeed
        end

        -- 5. Integrate distance
        data.distanceTravelled = data.distanceTravelled + data.currentSpeed * dt

        -- 6. Spawn new segments when approaching the frontier
        while data.distanceTravelled + SEGMENT_LENGTH * LOOKAHEAD_SEGMENTS
              >= data.nextSpawnDist do
            spawnSegment(data, pickShape())
        end

        -- 7. Despawn oldest segments beyond the keep limit
        while #data.segments > TOTAL_SEGMENTS_KEPT do
            local oldest = table.remove(data.segments, 1)
            if oldest.folder and oldest.folder.Parent then
                oldest.folder:Destroy()
            end
        end

        -- 8. Milestone events
        local dist = math.floor(data.distanceTravelled)
        for _, milestone in ipairs({ 100, 250, 500, 1000, 2000, 5000 }) do
            if dist >= milestone and not data.milestoneReached[milestone] then
                data.milestoneReached[milestone] = true
                MilestoneUIEvent:FireClient(player, milestone)
            end
        end

        -- 9. Periodic speed update to client (~0.5 s intervals)
        data.speedTimer = data.speedTimer + dt
        if data.speedTimer >= 0.5 then
            data.speedTimer = 0
            SpeedUpdate:FireClient(player, data.currentSpeed / FORWARD_SPEED)
        end
    end
end)

-- ── RunnerSteer handler ───────────────────────────────────────────────────────
-- Client sends TurnAxis in range [-1, 1].  Positive = turn right (D key).
RunnerSteer.OnServerEvent:Connect(function(player, turnAxis)
    local data = playerData[player]
    if not data then return end
    if type(turnAxis) ~= "number" then return end
    data.turnAxis = math.clamp(turnAxis, -1, 1)
end)

-- ── Player lifecycle ──────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
    local data = newPlayerData()
    playerData[player] = data

    player.CharacterAdded:Connect(function()
        task.wait(0.5)  -- allow character to fully load
        startRunner(player, data)
    end)

    if player.Character then
        task.wait(0.5)
        startRunner(player, data)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    local data = playerData[player]
    if data then
        for _, seg in ipairs(data.segments) do
            if seg.folder and seg.folder.Parent then
                seg.folder:Destroy()
            end
        end
    end
    playerData[player] = nil
end)
