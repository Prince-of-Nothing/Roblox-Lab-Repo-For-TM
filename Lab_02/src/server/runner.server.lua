--[[
  runner.server.lua
  Free-steering endless runner — server authority.

  Track generation
  ─────────────────
  Segments are generated procedurally along a running CFrame (position +
  orientation).  Each new segment appends to the end of the last, so the
  track curves seamlessly in world space.

  Segment type weights (must sum to 100):
    I  = 92 %  (straight; includes the unspecified 2 % allocated to I)
    C  =  3 %  (45° gentle curve, random L/R)
    S  =  3 %  (S-curve: 45° one way then 45° back, random initial dir)
    L  =  2 %  (90° corner, random L/R)

  Player control
  ─────────────────
  The client sends a TurnInput event with axis ∈ [-1, 1].
  The server applies incremental yaw to the character root every Heartbeat
  and keeps the LinearVelocity aligned with the character's LookVector so
  the player always runs in the direction they face.

  Lane system removed: no LANE_X, no LaneSwitch remote.
--]]

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- ── Constants ──────────────────────────────────────────────────────────────
local FORWARD_SPEED    = 30      -- studs / s  (base propulsion)
local SPEED_RAMP       = 0.5     -- studs / s  added every ramp interval
local SPEED_RAMP_INTERVAL = 8    -- seconds between speed ramps
local TURN_SPEED_DEG   = 90      -- degrees / s max yaw rate
local TURN_RATE_LIMIT  = 0.05    -- min seconds between TurnInput applications

local FLOOR_WIDTH      = 20      -- studs — track width
local FLOOR_THICK      = 2       -- studs — floor thickness
local STRAIGHT_LEN     = 60      -- studs — I-segment length

-- Curve parameters
local ARC_RADIUS       = 50      -- studs — radius for C / S / L curves
local ARC_PIECES_C     = 8       -- sub-pieces for a 45° C segment
local ARC_PIECES_L     = 16      -- sub-pieces for a 90° L segment

local SEGMENTS_AHEAD   = 10      -- keep this many segments generated ahead
local CLEANUP_BEHIND   = 4       -- remove segments this far behind the oldest active one

-- ── Segment weights ────────────────────────────────────────────────────────
-- I = 92% (the spec sums to 98%; the remaining 2% is allocated to I here)
local SEG_TYPES   = { "I", "C", "S", "L" }
local SEG_WEIGHTS = { 92,   3,   3,   2  }  -- must sum to 100
local SEG_WEIGHT_TOTAL = 100

-- ── Remote events ──────────────────────────────────────────────────────────
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    Remotes = Instance.new("Folder")
    Remotes.Name   = "Remotes"
    Remotes.Parent = ReplicatedStorage
end

local function getOrMake(name)
    local e = Remotes:FindFirstChild(name)
    if not e then
        e        = Instance.new("RemoteEvent")
        e.Name   = name
        e.Parent = Remotes
    end
    return e
end

local RunnerAdvanceEvent = getOrMake("RunnerAdvance")
local TurnInputEvent     = getOrMake("TurnInput")
local SpeedUpdateEvent   = getOrMake("SpeedUpdate")
local MilestoneUIEvent   = getOrMake("MilestoneUIEvent")
-- MagnetStatus is created here so MagnetManager can find it
getOrMake("MagnetStatus")

-- ── Track state ────────────────────────────────────────────────────────────
local trackFolder = Instance.new("Folder")
trackFolder.Name   = "TrackSegments"
trackFolder.Parent = workspace

-- trackEndCF: the CFrame at the very end of the last generated segment.
-- New segments are appended starting from this transform.
local trackEndCF  = CFrame.new(0, 0, 0)
local segmentList = {}   -- { index, segType, startCF, endCF, parts[] }
local nextSegIndex = 0

-- ── Weighted segment type picker ───────────────────────────────────────────
local function pickSegmentType()
    local r   = math.random(1, SEG_WEIGHT_TOTAL)
    local cum = 0
    for i, w in ipairs(SEG_WEIGHTS) do
        cum = cum + w
        if r <= cum then return SEG_TYPES[i] end
    end
    return "I"
end

-- ── Floor piece builder ────────────────────────────────────────────────────
-- startCF  — CFrame at the "entrance" face of the piece.
-- The piece extends forward (−Z in local space) by sizeZ studs.
-- Part centre is therefore at startCF * CFrame.new(0, −thick/2, −sizeZ/2).
local function makeFloorPiece(startCF, sizeX, sizeZ, brickColor)
    local p = Instance.new("Part")
    p.Anchored    = true
    p.CanCollide  = true
    p.Size        = Vector3.new(sizeX, FLOOR_THICK, sizeZ)
    p.Material    = Enum.Material.SmoothPlastic
    p.BrickColor  = brickColor or BrickColor.new("Medium stone grey")
    p.CFrame      = startCF * CFrame.new(0, -FLOOR_THICK / 2, -sizeZ / 2)
    p.Parent      = trackFolder
    return p
end

-- ── Straight segment (type I) ──────────────────────────────────────────────
-- Returns (parts, exitCF)
local function genStraight(startCF, length)
    length = length or STRAIGHT_LEN
    local part  = makeFloorPiece(startCF, FLOOR_WIDTH, length)
    local exitCF = startCF * CFrame.new(0, 0, -length)
    return { part }, exitCF
end

-- ── Arc segment helper ─────────────────────────────────────────────────────
-- totalAngle: radians.  Positive = left turn (CCW from above); negative = right.
-- Returns (parts, exitCF)
local function genArc(startCF, totalAngle, numPieces)
    local parts      = {}
    local currentCF  = startCF
    local pieceAngle = totalAngle / numPieces
    -- chord length of each sub-piece along the arc
    local chordLen   = 2 * ARC_RADIUS * math.sin(math.abs(pieceAngle) / 2)

    for _ = 1, numPieces do
        local part = makeFloorPiece(currentCF, FLOOR_WIDTH, chordLen)
        table.insert(parts, part)
        -- Advance forward by the chord, then rotate in-place by pieceAngle around Y
        currentCF = currentCF * CFrame.new(0, 0, -chordLen) * CFrame.Angles(0, pieceAngle, 0)
    end
    return parts, currentCF
end

-- ── Full segment generator ─────────────────────────────────────────────────
-- Returns (allParts, exitCF)
local function generateSegment(segType, startCF)
    local allParts = {}
    local exitCF

    if segType == "I" then
        -- Straight
        local p, cf = genStraight(startCF)
        for _, v in ipairs(p) do table.insert(allParts, v) end
        exitCF = cf

    elseif segType == "C" then
        -- Gentle curve: 45° to a random side
        local dir = (math.random(0, 1) == 0) and 1 or -1
        local p, cf = genArc(startCF, dir * math.rad(45), ARC_PIECES_C)
        for _, v in ipairs(p) do table.insert(allParts, v) end
        exitCF = cf

    elseif segType == "S" then
        -- S-curve: 45° one way then 45° back
        local dir = (math.random(0, 1) == 0) and 1 or -1
        local p1, midCF = genArc(startCF,  dir * math.rad(45), ARC_PIECES_C)
        local p2, cf    = genArc(midCF,   -dir * math.rad(45), ARC_PIECES_C)
        for _, v in ipairs(p1) do table.insert(allParts, v) end
        for _, v in ipairs(p2) do table.insert(allParts, v) end
        exitCF = cf

    elseif segType == "L" then
        -- Sharp corner: 90° to a random side
        local dir = (math.random(0, 1) == 0) and 1 or -1
        local p, cf = genArc(startCF, dir * math.rad(90), ARC_PIECES_L)
        for _, v in ipairs(p) do table.insert(allParts, v) end
        exitCF = cf
    end

    return allParts, exitCF
end

-- ── Collectible / obstacle spawning ───────────────────────────────────────
-- Items are placed relative to the segment's local coordinate frame so
-- they lie on top of the floor surface regardless of track orientation.
local function spawnOnSegment(segData)
    local sCF = segData.startCF
    local eCF = segData.endCF

    -- ── Cupcakes (tagged for magnet system) ──
    local numCups = math.random(1, 3)
    for _ = 1, numCups do
        local tFwd = math.random()           -- 0–1 along segment
        local xOff = (math.random() - 0.5) * (FLOOR_WIDTH - 4)

        -- Interpolate CFrame along the segment and raise above floor
        local worldCF = sCF:Lerp(eCF, tFwd) * CFrame.new(xOff, FLOOR_THICK + 1.5, 0)

        local cup       = Instance.new("Part")
        cup.Name        = "Cupcake"
        cup.Shape       = Enum.PartType.Ball
        cup.Size        = Vector3.new(2, 2, 2)
        cup.BrickColor  = BrickColor.new("Bright pink")
        cup.Material    = Enum.Material.Neon
        cup.Anchored    = true
        cup.CanCollide  = false
        cup.CFrame      = worldCF
        cup.Parent      = workspace

        CollectionService:AddTag(cup, "Cupcake")

        cup.Touched:Connect(function(hit)
            local char   = hit.Parent
            local player = Players:GetPlayerFromCharacter(char)
            if player then
                local ls = player:FindFirstChild("leaderstats")
                if ls and ls:FindFirstChild("Score") then
                    ls.Score.Value = ls.Score.Value + 1
                end
                -- Also increment Coins if present (from Leaderstats.server.lua)
                if ls and ls:FindFirstChild("Coins") then
                    ls.Coins.Value = ls.Coins.Value + 1
                end
                cup:Destroy()

                -- Play pickup sound at the player's root part
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then
                    local snd       = Instance.new("Sound")
                    snd.SoundId     = "rbxassetid://3124262382"
                    snd.Volume      = 0.6
                    snd.Parent      = root
                    snd:Play()
                    game:GetService("Debris"):AddItem(snd, 2)
                end
            end
        end)
    end

    -- ── Magnet pickups (rare, ~1 per 5 segments) ──
    if math.random(1, 5) == 1 then
        local tFwd  = math.random() * 0.6 + 0.2
        local xOff  = (math.random() - 0.5) * (FLOOR_WIDTH - 4)
        local mCF   = sCF:Lerp(eCF, tFwd) * CFrame.new(xOff, FLOOR_THICK + 1.5, 0)

        local mag       = Instance.new("Part")
        mag.Name        = "Magnet"
        mag.Shape       = Enum.PartType.Ball
        mag.Size        = Vector3.new(2.5, 2.5, 2.5)
        mag.BrickColor  = BrickColor.new("Bright yellow")
        mag.Material    = Enum.Material.Neon
        mag.Anchored    = true
        mag.CanCollide  = false
        mag.CFrame      = mCF
        mag.Parent      = workspace

        CollectionService:AddTag(mag, "MagnetPickup")
    end

    -- ── Obstacles (skip very first few segments) ──
    if segData.index >= 3 then
        local numObs = math.random(0, 2)
        for _ = 1, numObs do
            local tFwd = math.random() * 0.7 + 0.15
            local xOff = (math.random() - 0.5) * (FLOOR_WIDTH - 6)
            local worldCF = sCF:Lerp(eCF, tFwd) * CFrame.new(xOff, FLOOR_THICK + 2, 0)

            local obs       = Instance.new("Part")
            obs.Name        = "Obstacle"
            obs.Size        = Vector3.new(4, 4, 4)
            obs.BrickColor  = BrickColor.new("Bright red")
            obs.Material    = Enum.Material.SmoothPlastic
            obs.Anchored    = true
            obs.CanCollide  = true
            obs.CFrame      = worldCF
            obs.Parent      = workspace

            obs.Touched:Connect(function(hit)
                local char = hit.Parent
                if char and char:FindFirstChildOfClass("Humanoid") then
                    char:FindFirstChildOfClass("Humanoid").Health = 0
                end
            end)
        end
    end
end

-- ── Add one segment to the track ──────────────────────────────────────────
local function addSegment()
    local segType = pickSegmentType()
    local idx     = nextSegIndex
    nextSegIndex  = nextSegIndex + 1

    local startCF              = trackEndCF
    local parts, exitCF        = generateSegment(segType, startCF)
    trackEndCF                 = exitCF

    local segData = {
        index   = idx,
        segType = segType,
        startCF = startCF,
        endCF   = exitCF,
        parts   = parts,
    }
    table.insert(segmentList, segData)
    spawnOnSegment(segData)
    return segData
end

-- ── Clean up old segments that are far behind all players ─────────────────
local function cleanupOldSegments()
    if #segmentList <= SEGMENTS_AHEAD + CLEANUP_BEHIND then return end

    -- Find the minimum *logical* segment index that any player is near
    local minActiveSeg = nextSegIndex  -- start high; reduce below
    for _, p in ipairs(Players:GetPlayers()) do
        local char = p.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        for _, seg in ipairs(segmentList) do
            local d = (seg.startCF.Position - root.Position).Magnitude
            if d < STRAIGHT_LEN * 2 then
                -- segmentList is ordered by index, so the first segment within
                -- range is the earliest one near the player. Record it and stop
                -- scanning; we want the minimum index across all players.
                if seg.index < minActiveSeg then minActiveSeg = seg.index end
                break
            end
        end
    end

    -- Destroy segments whose logical index is more than CLEANUP_BEHIND behind
    local removeBelow = minActiveSeg - CLEANUP_BEHIND
    local newList     = {}
    for _, seg in ipairs(segmentList) do
        if seg.index < removeBelow then
            for _, part in ipairs(seg.parts) do
                if part and part.Parent then part:Destroy() end
            end
        else
            table.insert(newList, seg)
        end
    end
    segmentList = newList
end

-- ── Initial track ─────────────────────────────────────────────────────────
for _ = 1, SEGMENTS_AHEAD do
    addSegment()
end

-- ── Player data ───────────────────────────────────────────────────────────
local playerData = {}

-- Leaderstats.server.lua (also in ServerScriptService) creates the
-- "leaderstats" folder with a "Coins" IntValue.  We add "Score" and
-- "Distance" to that existing folder rather than creating a duplicate.
local function ensureLeaderstats(player)
    -- Wait up to 5 seconds for Leaderstats.server.lua to create the folder.
    local ls = player:FindFirstChild("leaderstats")
        or player:WaitForChild("leaderstats", 5)
    if not ls then
        -- Fallback: create our own if the other script is absent.
        ls        = Instance.new("Folder")
        ls.Name   = "leaderstats"
        ls.Parent = player
    end

    if not ls:FindFirstChild("Score") then
        local score       = Instance.new("IntValue")
        score.Name        = "Score"
        score.Value       = 0
        score.Parent      = ls
    end

    if not ls:FindFirstChild("Distance") then
        local dist        = Instance.new("IntValue")
        dist.Name         = "Distance"
        dist.Value        = 0
        dist.Parent       = ls
    end
end

Players.PlayerAdded:Connect(function(player)
    ensureLeaderstats(player)

    playerData[player] = {
        speed            = FORWARD_SPEED,
        turnAxis         = 0,
        currentYaw       = 0,          -- accumulated yaw in radians
        distanceTraveled = 0,
        lastMilestone    = 0,
        lastRampTime     = os.clock(),
        lastTurnTime     = 0,
        linearVelocity   = nil,
        propAtt          = nil,
    }

    player.CharacterAdded:Connect(function(character)
        local data = playerData[player]
        if not data then return end

        -- Reset per-run state
        data.currentYaw       = 0
        data.distanceTraveled = 0
        data.lastMilestone    = 0
        data.speed            = FORWARD_SPEED
        data.lastRampTime     = os.clock()

        task.wait(1) -- allow character to fully load

        local root = character:WaitForChild("HumanoidRootPart")
        local hum  = character:WaitForChild("Humanoid")

        -- Teleport to track start (raised above floor)
        character:PivotTo(CFrame.new(0, FLOOR_THICK + 5, 0))
        data.currentYaw = 0

        -- Attachment for LinearVelocity
        local att        = Instance.new("Attachment")
        att.Name         = "PropulsionAtt"
        att.Parent       = root

        -- LinearVelocity pushes the character forward along its look vector.
        -- VelocityConstraintMode = Line applies force only along LineDirection.
        local lv                         = Instance.new("LinearVelocity")
        lv.Attachment0                   = att
        lv.MaxForce                      = 1e5
        lv.VelocityConstraintMode        = Enum.VelocityConstraintMode.Line
        lv.LineDirection                 = root.CFrame.LookVector
        lv.LineVelocity                  = data.speed
        lv.RelativeTo                    = Enum.ActuatorRelativeTo.World
        lv.Parent                        = root

        data.linearVelocity = lv
        data.propAtt        = att

        -- Disable Humanoid auto-rotation so the server controls yaw fully
        hum.AutoRotate = false
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    playerData[player] = nil
end)

-- ── TurnInput remote ──────────────────────────────────────────────────────
-- Client fires this with axis ∈ [-1, 1] (A/Left = -1, D/Right = 1)
TurnInputEvent.OnServerEvent:Connect(function(player, axis)
    local data = playerData[player]
    if not data then return end

    -- Rate-limit processing
    local now = os.clock()
    if now - data.lastTurnTime < TURN_RATE_LIMIT then return end
    data.lastTurnTime = now

    data.turnAxis = math.clamp(tonumber(axis) or 0, -1, 1)
end)

-- ── RunnerAdvance: client requests more track ─────────────────────────────
RunnerAdvanceEvent.OnServerEvent:Connect(function(_player)
    addSegment()
    cleanupOldSegments()
end)

-- ── Heartbeat: physics, turning, speed ramp, milestones ───────────────────
local lastHeartbeat = os.clock()

RunService.Heartbeat:Connect(function()
    local now = os.clock()
    local dt  = math.min(now - lastHeartbeat, 0.1) -- cap dt to avoid spiral
    lastHeartbeat = now

    for player, data in pairs(playerData) do
        local character = player.Character
        if not character then continue end

        local root = character:FindFirstChild("HumanoidRootPart")
        local hum  = character:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then continue end

        -- ── Speed ramp ──
        if now - data.lastRampTime >= SPEED_RAMP_INTERVAL then
            data.lastRampTime = now
            data.speed        = data.speed + SPEED_RAMP
            SpeedUpdateEvent:FireClient(player, data.speed)
        end

        -- ── Yaw / steering ──
        if math.abs(data.turnAxis) > 0.01 then
            data.currentYaw = data.currentYaw
                + math.rad(TURN_SPEED_DEG) * data.turnAxis * dt
        end

        -- Apply yaw: preserve position, update orientation around world Y
        local pos    = root.Position
        local newRot = CFrame.fromEulerAnglesYXZ(0, data.currentYaw, 0)
        root.CFrame  = CFrame.new(pos) * newRot

        -- ── Keep propulsion aligned with look vector ──
        if data.linearVelocity and data.linearVelocity.Parent then
            local look      = root.CFrame.LookVector
            local horizFlat = Vector3.new(look.X, 0, look.Z)
            -- Guard against zero vector (e.g. character looking straight up/down)
            if horizFlat.Magnitude > 0.001 then
                data.linearVelocity.LineDirection = horizFlat.Unit
            end
            data.linearVelocity.LineVelocity = data.speed
        end

        -- ── Distance tracking ──
        data.distanceTraveled = data.distanceTraveled + data.speed * dt

        local ls = player:FindFirstChild("leaderstats")
        if ls and ls:FindFirstChild("Distance") then
            ls.Distance.Value = math.floor(data.distanceTraveled)
        end

        -- ── Milestones every 100 m ──
        local milestone = math.floor(data.distanceTraveled / 100)
        if milestone > data.lastMilestone then
            data.lastMilestone = milestone
            MilestoneUIEvent:FireClient(player, milestone * 100)
            data.speed = data.speed + 2  -- milestone speed bonus
        end

        -- ── Auto-extend track if player approaches the end ──
        local distToEnd = (trackEndCF.Position - root.Position).Magnitude
        if distToEnd < STRAIGHT_LEN * 3 then
            addSegment()
            cleanupOldSegments()
        end
    end
end)
