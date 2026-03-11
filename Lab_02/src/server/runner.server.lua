--[[
  runner.server.lua  -  5-Lane Endless Runner, Server Authority
  ================================================================

  World Structure
  Five parallel lanes (indices 1-5, X positions: -20, -10, 0, 10, 20 studs).
  The track extends in the -Z direction. Players are propelled forward
  automatically via LinearVelocity; they only control lateral lane changes.

  Difficulty
  Selected by the client before each run. Controls:
  obstaclesPerRow - how many of the 5 lanes are blocked per obstacle row
  safeLanes       - guaranteed minimum clear lanes per row
  speedMultiplier - scales base forward speed
  clusterChance   - probability that blocked lanes form an adjacent cluster

  Obstacle Types
  solid_barrier  - requires lane switch
  low_barrier    - can be cleared with jump ability
  high_barrier   - can be cleared with slide mechanic
  hazard_tile    - damaging floor tile (CanCollide false, Touched detection)
  moving_barrier - oscillates between two adjacent lanes

  Collectibles
  energy_shard   - primary currency (+1 coin)
  data_cube      - rare currency (+5 coins)
  velocity_orb   - temporary speed boost
  phase_fragment - +1 ability charge
  shield_item    - +1 shield (absorbs one collision)

  Health System
  Players start with 3 HP. Shields absorb hits first. When health reaches 0
  the run ends and results are sent to the client.

  Abilities (require phase_fragment charges)
  phase         - pass through obstacles for 2 s
  invincibility - no collision damage for 3 s
  dash          - instant teleport 2 lanes right
  timeslow      - reduce world speed to 35% for 4 s

  Speed System
  base = BASE_FORWARD_SPEED x difficultySpeedMultiplier
  Auto-ramp every SPEED_RAMP_INTERVAL seconds.
  Milestone bonus (+1.5 studs/s) every 100 m.
  Velocity_orb grants temporary +8 studs/s for 5 s.

  Score Calculation
  (distance + items x 2) x difficultyMultiplier + no-hit-time-bonus

  Biomes
  Visual floor/wall colour changes at distance milestones.
  City Neon -> Lava Factory -> Frozen Rail Yard -> Neon Jungle -> Deep Space
--]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace         = game:GetService("Workspace")

-- Constants
local NUM_LANES             = 5
local LANE_X                = { -20, -10, 0, 10, 20 }
local LANE_WIDTH            = 10

local BASE_FORWARD_SPEED    = 22
local SPEED_RAMP            = 0.4
local SPEED_RAMP_INTERVAL   = 5
local MILESTONE_SPEED_BONUS = 1.5
local MAX_SPEED             = 90

local FLOOR_Y               = 50
local FLOOR_THICK           = 2
local SEGMENT_LENGTH        = 60
local SEGMENT_WIDTH         = 52
local SEGMENTS_AHEAD        = 10
local SAFE_ZONE_SEGS        = 3
local OBS_ROWS_PER_SEG      = 3

-- Difficulty Settings
local DIFFICULTY = {
    easy       = { obstaclesPerRow=1, safeLanes=4, speedMult=1.0, clusterChance=0.00, name="Easy"       },
    normal     = { obstaclesPerRow=2, safeLanes=3, speedMult=1.2, clusterChance=0.10, name="Normal"     },
    medium     = { obstaclesPerRow=3, safeLanes=2, speedMult=1.5, clusterChance=0.25, name="Medium"     },
    hard       = { obstaclesPerRow=4, safeLanes=1, speedMult=2.0, clusterChance=0.50, name="Hard"       },
    impossible = { obstaclesPerRow=5, safeLanes=0, speedMult=2.5, clusterChance=0.70, name="Impossible" },
}

-- Obstacle Type Definitions (w = spawn weight)
local OBS_DEFS = {
    solid_barrier  = { h=5,   color=BrickColor.new("Bright red"),     w=40, jumpable=false, slidable=false, hazard=false, moving=false },
    low_barrier    = { h=2.5, color=BrickColor.new("Bright orange"),  w=25, jumpable=true,  slidable=false, hazard=false, moving=false },
    high_barrier   = { h=8,   color=BrickColor.new("Dark red"),       w=20, jumpable=false, slidable=true,  hazard=false, moving=false },
    hazard_tile    = { h=0.4, color=BrickColor.new("Neon orange"),    w=10, jumpable=false, slidable=false, hazard=true,  moving=false },
    moving_barrier = { h=5,   color=BrickColor.new("Bright violet"),  w=5,  jumpable=false, slidable=false, hazard=false, moving=true  },
}
local OBS_TOTAL_W = 0
for _, d in pairs(OBS_DEFS) do OBS_TOTAL_W = OBS_TOTAL_W + d.w end

-- Collectible Type Definitions
local COL_DEFS = {
    energy_shard   = { color=BrickColor.new("Bright yellow"), coinVal=1,  w=55 },
    data_cube      = { color=BrickColor.new("Cyan"),          coinVal=5,  w=10, rare=true },
    velocity_orb   = { color=BrickColor.new("Bright green"),  speedBoost=8, boostDur=5, w=15 },
    phase_fragment = { color=BrickColor.new("Bright violet"), abilCharge=true, w=12 },
    shield_item    = { color=BrickColor.new("White"),         shield=true, w=8 },
}
local COL_TOTAL_W = 0
for _, d in pairs(COL_DEFS) do COL_TOTAL_W = COL_TOTAL_W + d.w end

-- Biome Definitions
local BIOMES = {
    { name="City Neon Zone",   floorBC=BrickColor.new("Dark blue"),    wallBC=BrickColor.new("Cyan"),          trigDist=0    },
    { name="Lava Factory",     floorBC=BrickColor.new("Dark orange"),  wallBC=BrickColor.new("Bright red"),    trigDist=300  },
    { name="Frozen Rail Yard", floorBC=BrickColor.new("White"),        wallBC=BrickColor.new("Light blue"),    trigDist=700  },
    { name="Neon Jungle",      floorBC=BrickColor.new("Bright green"), wallBC=BrickColor.new("Dark green"),    trigDist=1200 },
    { name="Deep Space",       floorBC=BrickColor.new("Black"),        wallBC=BrickColor.new("Bright violet"), trigDist=2000 },
}

-- Ability Cooldowns (seconds)
local ABILITY_CD = { phase=8, invincibility=10, dash=5, timeslow=12 }

-- Remote Events Setup
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    Remotes = Instance.new("Folder")
    Remotes.Name = "Remotes"
    Remotes.Parent = ReplicatedStorage
end

local function getOrMake(name, cls)
    local e = Remotes:FindFirstChild(name)
    if not e then
        e = Instance.new(cls or "RemoteEvent")
        e.Name = name
        e.Parent = Remotes
    end
    return e
end

local SpeedUpdateEvt    = getOrMake("SpeedUpdate")
local MilestoneEvt      = getOrMake("MilestoneUIEvent")
local HealthUpdateEvt   = getOrMake("HealthUpdate")
local ShieldUpdateEvt   = getOrMake("ShieldUpdate")
local AbilityUpdateEvt  = getOrMake("AbilityUpdate")
local RunEndEvt         = getOrMake("RunEnd")
local RunStartEvt       = getOrMake("RunStart")
local BiomeChangeEvt    = getOrMake("BiomeChange")
local CurrencyUpdateEvt = getOrMake("CurrencyUpdate")
local UpgradeResultEvt  = getOrMake("UpgradeResult")
local ObstacleHitEvt    = getOrMake("ObstacleHit")
local AbilityCDEvt      = getOrMake("AbilityCooldown")
local LaneSwitchEvt     = getOrMake("LaneSwitch")
local PlayerJumpEvt     = getOrMake("PlayerJump")
local PlayerSlideEvt    = getOrMake("PlayerSlide")
local UseAbilityEvt     = getOrMake("UseAbility")
local SelectDiffEvt     = getOrMake("SelectDifficulty")
local BuyUpgradeEvt     = getOrMake("BuyUpgrade")
local RunnerAdvanceEvt  = getOrMake("RunnerAdvance")
local RequestRunEvt     = getOrMake("RequestRun")
getOrMake("MagnetStatus")

-- Track state
local trackFolder = Instance.new("Folder")
trackFolder.Name = "TrackSegments"
trackFolder.Parent = Workspace

local segments   = {}
local nextSegIdx = 0
local movObstacles = {}

-- _G.playerPersist  – shared with ProgressionHub.server.lua
--   Keyed by tostring(player.UserId).  Survives between runs in the same
--   server session but is NOT persisted to DataStore; production deployments
--   should add DataStore save/load here.
_G.playerPersist = _G.playerPersist or {}

local function getPersist(player)
    local uid = tostring(player.UserId)
    if not _G.playerPersist[uid] then
        _G.playerPersist[uid] = { currency=0, upgrades={} }
    end
    return _G.playerPersist[uid]
end

-- _G.playerRunData  – per-run state for each player.
--   Reset each run via initRun(); read by obstacle/collectible touch handlers
--   that are spawned inside closures and cannot receive the table by reference.
_G.playerRunData = {}

local function initRun(player, diff)
    local s     = DIFFICULTY[diff] or DIFFICULTY.normal
    local persist = getPersist(player)
    local upg   = persist.upgrades
    local startSlowBonus = (upg.start_slow or 0) * 0.08
    local abilCapBonus   = upg.ability_cap or 0
    local baseSpd = BASE_FORWARD_SPEED * s.speedMult * (1 - startSlowBonus)
    local pd = {
        difficulty       = diff,
        settings         = s,
        laneIndex        = 3,
        currentSpeed     = baseSpd,
        speedBoost       = 0,
        health           = 3,
        maxHealth        = 3,
        shields          = 0,
        abilityCharges   = 1 + abilCapBonus,
        maxAbilCharges   = 3 + abilCapBonus,
        score            = 0,
        distanceTraveled = 0,
        lastMilestone    = 0,
        lastRampTime     = os.clock(),
        energyShards     = 0,
        dataCubes        = 0,
        isAlive          = true,
        isPhasing        = false,
        isInvincible     = false,
        isSliding        = false,
        noHitBonus       = true,
        abilityCooldown  = {},
        linearVelocity   = nil,
        rootPart         = nil,
        humanoid         = nil,
        runStartTime     = os.clock(),
        runEnded         = false,
    }
    _G.playerRunData[player] = pd
    return pd
end

-- Utilities
local function getRootPart(char)
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp end
    if char.PrimaryPart then return char.PrimaryPart end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.RootPart then return hum.RootPart end
    return char:FindFirstChildWhichIsA("BasePart")
end

local function makePart(sz, bc, anchored, canCollide, mat)
    local p         = Instance.new("Part")
    p.Size          = sz
    p.Anchored      = (anchored  ~= false)
    p.CanCollide    = (canCollide ~= false)
    p.BrickColor    = bc  or BrickColor.new("Medium stone grey")
    p.Material      = mat or Enum.Material.SmoothPlastic
    p.TopSurface    = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    return p
end

local function pickWeighted(defs, total)
    local r, cum = math.random(1, total), 0
    for name, def in pairs(defs) do
        cum = cum + def.w
        if r <= cum then return name, def end
    end
    local n, d = next(defs); return n, d
end

local function getBiome(dist)
    local cur = BIOMES[1]
    for _, b in ipairs(BIOMES) do
        if dist >= b.trigDist then cur = b end
    end
    return cur
end

-- Obstacle pattern generator
local function genObstaclePattern(diff, runDist)
    local s     = DIFFICULTY[diff] or DIFFICULTY.normal
    local dFact = math.min(runDist / 1500, 1.0)
    local numObs
    if diff == "easy" then
        numObs = 1
    elseif diff == "impossible" then
        numObs = math.min(5, s.obstaclesPerRow + math.floor(dFact * 2))
    else
        numObs = math.min(NUM_LANES - 1, s.obstaclesPerRow + math.floor(dFact * 1.5))
    end
    local clusterProb = s.clusterChance + dFact * 0.15
    local lanes = { false, false, false, false, false }
    if numObs > 0 and math.random() < clusterProb then
        local maxStart = math.max(1, NUM_LANES - numObs + 1)
        local start    = math.random(1, maxStart)
        for i = 0, numObs - 1 do lanes[start + i] = true end
    else
        local placed, tries = 0, 0
        while placed < numObs and tries < 30 do
            local lane = math.random(1, NUM_LANES)
            if not lanes[lane] then
                lanes[lane] = true
                placed      = placed + 1
            end
            tries = tries + 1
        end
    end
    -- Guarantee at least one safe lane for all difficulties EXCEPT:
    -- "impossible" past 600 m, where full 5-lane blockage is intentional.
    -- Players must use the "phase" or "invincibility" ability to survive these.
    if not (diff == "impossible" and runDist > 600) then
        local safe = 0
        for _, v in ipairs(lanes) do if not v then safe = safe + 1 end end
        if safe == 0 then lanes[math.random(1, NUM_LANES)] = false end
    end
    return lanes
end

local function pickObsType(runDist)
    if runDist < 100 then return "solid_barrier", OBS_DEFS.solid_barrier end
    return pickWeighted(OBS_DEFS, OBS_TOTAL_W)
end

-- Segment creator
local function createSegment(idx, diff, runDist)
    diff    = diff    or "normal"
    runDist = runDist or 0
    local model  = Instance.new("Model")
    model.Name   = "Segment_" .. idx
    local biome  = getBiome(runDist)
    local segZ   = -(idx * SEGMENT_LENGTH)

    -- Floor
    local floor = makePart(Vector3.new(SEGMENT_WIDTH, FLOOR_THICK, SEGMENT_LENGTH),
                            biome.floorBC, true, true)
    floor.Name   = "Floor"
    floor.CFrame = CFrame.new(0, FLOOR_Y, segZ)
    floor.Parent = model
    model.PrimaryPart = floor

    -- Side walls (visual)
    for _, side in ipairs({ -1, 1 }) do
        local wall = makePart(Vector3.new(2, 10, SEGMENT_LENGTH), biome.wallBC, true, false)
        wall.Transparency = 0.55
        wall.Name         = "Wall"
        wall.CFrame       = CFrame.new(side * (SEGMENT_WIDTH / 2 + 1), FLOOR_Y + 5, segZ)
        wall.Parent       = model
    end

    -- Lane dividers (visual)
    for i = 1, NUM_LANES - 1 do
        local divX = LANE_X[i] + LANE_WIDTH / 2
        local div  = makePart(Vector3.new(0.3, 0.15, SEGMENT_LENGTH),
                               BrickColor.new("Institutional white"), true, false)
        div.Transparency = 0.65
        div.Name         = "LaneDivider"
        div.CFrame       = CFrame.new(divX, FLOOR_Y + FLOOR_THICK / 2 + 0.07, segZ)
        div.Parent       = model
    end

    -- Obstacle rows
    if idx >= SAFE_ZONE_SEGS then
        for row = 1, OBS_ROWS_PER_SEG do
            local t    = row / (OBS_ROWS_PER_SEG + 1)
            local rowZ = segZ + (t - 0.5) * SEGMENT_LENGTH
            local pat  = genObstaclePattern(diff, runDist)
            for laneIdx, hasObs in ipairs(pat) do
                if not hasObs then continue end
                local typeName, def = pickObsType(runDist)
                local h    = def.h
                local obsY = FLOOR_Y + FLOOR_THICK / 2 + h / 2
                local obs  = makePart(Vector3.new(LANE_WIDTH - 0.8, h, 4),
                                       def.color, true, not def.hazard)
                obs.Name   = "Obstacle_" .. typeName
                obs.CFrame = CFrame.new(LANE_X[laneIdx], obsY, rowZ)
                if def.hazard then
                    obs.Material  = Enum.Material.Neon
                    obs.CanTouch  = true
                end
                obs.Parent = model
                if def.moving then
                    table.insert(movObstacles, {
                        part  = obs,
                        minX  = LANE_X[math.max(1, laneIdx - 1)],
                        maxX  = LANE_X[math.min(NUM_LANES, laneIdx + 1)],
                        speed = 5,
                        posX  = LANE_X[laneIdx],
                        dir   = 1,
                    })
                end
                obs.Touched:Connect(function(hit)
                    local char = hit:FindFirstAncestorOfClass("Model")
                    if not char then return end
                    local plr = Players:GetPlayerFromCharacter(char)
                    if not plr then return end
                    local pd  = _G.playerRunData and _G.playerRunData[plr]
                    if not pd or not pd.isAlive then return end
                    if pd.isPhasing    then return end
                    if pd.isInvincible then return end
                    -- high_barrier can be cleared by sliding under it
                    -- low_barrier requires a jump (slide does NOT help here)
                    if typeName == "high_barrier" and pd.isSliding then return end
                    ObstacleHitEvt:FireClient(plr, typeName)
                    pd.noHitBonus = false
                    if pd.shields and pd.shields > 0 then
                        pd.shields = pd.shields - 1
                        ShieldUpdateEvt:FireClient(plr, pd.shields)
                    elseif pd.health and pd.health > 1 then
                        pd.health = pd.health - 1
                        HealthUpdateEvt:FireClient(plr, pd.health, pd.maxHealth)
                    else
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then hum.Health = 0 end
                    end
                end)
            end
        end
    end

    -- Collectibles
    for laneIdx = 1, NUM_LANES do
        if math.random() > 0.40 then continue end
        local typeName, def = pickWeighted(COL_DEFS, COL_TOTAL_W)
        local t    = math.random() * 0.80 + 0.10
        local colZ = segZ + (t - 0.5) * SEGMENT_LENGTH
        local col  = makePart(Vector3.new(2, 2, 2), def.color, true, false)
        col.Name     = "Collectible_" .. typeName
        col.Shape    = Enum.PartType.Ball
        col.Material = Enum.Material.Neon
        col.CanTouch = true
        col.CFrame   = CFrame.new(LANE_X[laneIdx], FLOOR_Y + FLOOR_THICK / 2 + 2, colZ)
        col.Parent   = model
        -- Tag currency collectibles for MagnetManager attraction
        if def.coinVal then CollectionService:AddTag(col, "Cupcake") end
        local grabbed = false
        col.Touched:Connect(function(hit)
            if grabbed then return end
            local char = hit:FindFirstAncestorOfClass("Model")
            if not char then return end
            local plr  = Players:GetPlayerFromCharacter(char)
            if not plr then return end
            local pd   = _G.playerRunData and _G.playerRunData[plr]
            if not pd or not pd.isAlive then return end
            grabbed = true
            col:Destroy()
            if def.coinVal then
                pd.score = pd.score + def.coinVal
                if typeName == "energy_shard" then
                    pd.energyShards = (pd.energyShards or 0) + 1
                elseif typeName == "data_cube" then
                    pd.dataCubes = (pd.dataCubes or 0) + 1
                end
                local ls = plr:FindFirstChild("leaderstats")
                if ls and ls:FindFirstChild("Coins") then
                    ls.Coins.Value = ls.Coins.Value + def.coinVal
                end
            elseif def.speedBoost then
                local boost = def.speedBoost
                pd.speedBoost = (pd.speedBoost or 0) + boost
                SpeedUpdateEvt:FireClient(plr, (pd.currentSpeed + pd.speedBoost) / BASE_FORWARD_SPEED)
                task.delay(def.boostDur or 5, function()
                    if _G.playerRunData[plr] == pd then
                        pd.speedBoost = math.max(0, pd.speedBoost - boost)
                    end
                end)
            elseif def.abilCharge then
                pd.abilityCharges = math.min(
                    (pd.abilityCharges or 0) + 1, pd.maxAbilCharges or 3)
                AbilityUpdateEvt:FireClient(plr, pd.abilityCharges)
            elseif def.shield then
                pd.shields = math.min((pd.shields or 0) + 1, 3)
                ShieldUpdateEvt:FireClient(plr, pd.shields)
            end
        end)
    end

    model.Parent = Workspace
    return model
end

-- Track management
local function buildTrack(diff)
    for _, seg in ipairs(segments) do
        if seg and seg.Parent then seg:Destroy() end
    end
    segments     = {}
    nextSegIdx   = 0
    movObstacles = {}
    for i = 0, SEGMENTS_AHEAD - 1 do
        table.insert(segments, createSegment(i, diff, 0))
    end
    nextSegIdx = SEGMENTS_AHEAD
end

local function addNextSeg(diff, runDist)
    local seg = createSegment(nextSegIdx, diff or "normal", runDist or 0)
    table.insert(segments, seg)
    nextSegIdx = nextSegIdx + 1
    if #segments > SEGMENTS_AHEAD + 5 then
        local old = table.remove(segments, 1)
        if old and old.Parent then old:Destroy() end
    end
end

-- Leaderstats
local function ensureLeaderstats(player)
    local ls = player:WaitForChild("leaderstats", 5)
    if not ls then
        ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
    end
    local function addVal(name, cls, def)
        if not ls:FindFirstChild(name) then
            local v = Instance.new(cls); v.Name = name; v.Value = def; v.Parent = ls
        end
    end
    addVal("Score",    "IntValue", 0)
    addVal("Distance", "IntValue", 0)
    addVal("Coins",    "IntValue", 0)
end

-- Character setup
local function setupCharacter(player, char, pd)
    task.wait(0.6)
    local root = getRootPart(char)
    local hum  = char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then
        warn("[runner] no root/humanoid for", player.Name); return
    end
    pd.rootPart = root
    pd.humanoid = hum
    root.CFrame = CFrame.new(LANE_X[3], FLOOR_Y + FLOOR_THICK + 5, 15)
    for _, n in ipairs({ "RunnerAtt", "RunnerVel", "RunnerGyro" }) do
        local e = root:FindFirstChild(n); if e then e:Destroy() end
    end
    local att = Instance.new("Attachment")
    att.Name  = "RunnerAtt"
    att.Parent = root
    local lv                  = Instance.new("LinearVelocity")
    lv.Name                   = "RunnerVel"
    lv.Attachment0            = att
    lv.RelativeTo             = Enum.ActuatorRelativeTo.World
    lv.MaxForce               = 150000
    lv.VectorVelocity         = Vector3.new(0, 0, -pd.currentSpeed)
    lv.Parent                 = root
    local ao            = Instance.new("AlignOrientation")
    ao.Name             = "RunnerGyro"
    ao.Attachment0      = att
    ao.Mode             = Enum.OrientationAlignmentMode.OneAttachment
    ao.MaxTorque        = 300000
    ao.Responsiveness   = 200
    ao.CFrame           = CFrame.Angles(0, 0, 0)
    ao.Parent           = root
    hum.AutoRotate      = false
    pd.linearVelocity   = lv
    pd.propAtt          = att
    SpeedUpdateEvt:FireClient(player, pd.currentSpeed / BASE_FORWARD_SPEED)
    HealthUpdateEvt:FireClient(player, pd.health, pd.maxHealth)
    ShieldUpdateEvt:FireClient(player, pd.shields)
    AbilityUpdateEvt:FireClient(player, pd.abilityCharges)
    RunStartEvt:FireClient(player, pd.difficulty)
end

-- Run end
local function endRun(player, pd)
    if pd.runEnded then return end
    pd.runEnded = true
    pd.isAlive  = false
    local s           = DIFFICULTY[pd.difficulty] or DIFFICULTY.normal
    local persist     = getPersist(player)
    local runTime     = os.clock() - pd.runStartTime
    local rawScore    = math.floor(pd.distanceTraveled) + pd.score * 2
    local noHitBonus  = pd.noHitBonus and math.floor(runTime * 5) or 0
    local scoreMult   = 1 + 0.15 * (persist.upgrades.score_mult or 0)
    local finalScore  = math.floor((rawScore * s.speedMult + noHitBonus) * scoreMult)
    local currencyEarned = pd.energyShards + pd.dataCubes * 5
    persist.currency = persist.currency + currencyEarned
    local ls = player:FindFirstChild("leaderstats")
    if ls then
        if ls:FindFirstChild("Score")    then ls.Score.Value    = math.max(ls.Score.Value, finalScore) end
        if ls:FindFirstChild("Distance") then ls.Distance.Value = math.floor(pd.distanceTraveled) end
    end
    RunEndEvt:FireClient(player, {
        distance      = math.floor(pd.distanceTraveled),
        score         = finalScore,
        coins         = pd.energyShards,
        dataCubes     = pd.dataCubes,
        difficulty    = pd.difficulty,
        timeSurvived  = math.floor(runTime),
        noHitBonus    = noHitBonus,
        totalCurrency = persist.currency,
    })
    CurrencyUpdateEvt:FireClient(player, persist.currency)
end

-- Players
Players.PlayerAdded:Connect(function(player)
    ensureLeaderstats(player)
    getPersist(player)
    local pd = initRun(player, "normal")
    player.CharacterAdded:Connect(function(char)
        local diff = (_G.playerRunData[player] and _G.playerRunData[player].difficulty) or "normal"
        pd = initRun(player, diff)
        if #segments == 0 then buildTrack(diff) end
        setupCharacter(player, char, pd)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    _G.playerRunData[player] = nil
end)

-- Remote Handlers
LaneSwitchEvt.OnServerEvent:Connect(function(player, newLane)
    local pd = _G.playerRunData[player]
    if not pd or not pd.isAlive then return end
    newLane = math.clamp(math.floor(tonumber(newLane) or 3), 1, NUM_LANES)
    pd.laneIndex = newLane
    local root = pd.rootPart
    if root and root.Parent then
        root.CFrame = CFrame.new(LANE_X[newLane], root.Position.Y, root.Position.Z)
    end
end)

PlayerJumpEvt.OnServerEvent:Connect(function(player)
    local pd = _G.playerRunData[player]
    if not pd or not pd.isAlive then return end
    local hum = pd.humanoid
    if hum and hum.Parent then hum.Jump = true end
end)

PlayerSlideEvt.OnServerEvent:Connect(function(player)
    local pd = _G.playerRunData[player]
    if not pd or not pd.isAlive or pd.isSliding then return end
    pd.isSliding = true
    task.delay(0.8, function()
        if _G.playerRunData[player] == pd then pd.isSliding = false end
    end)
end)

UseAbilityEvt.OnServerEvent:Connect(function(player, abilityName)
    local pd = _G.playerRunData[player]
    if not pd or not pd.isAlive then return end
    if not ABILITY_CD[abilityName] then return end
    if (pd.abilityCharges or 0) <= 0 then return end
    local persist = getPersist(player)
    local cdRedLv = persist.upgrades.ability_cd or 0
    local cd      = ABILITY_CD[abilityName] * (1 - 0.15 * cdRedLv)
    local now     = os.clock()
    pd.abilityCooldown = pd.abilityCooldown or {}
    if pd.abilityCooldown[abilityName] and now < pd.abilityCooldown[abilityName] then return end
    pd.abilityCooldown[abilityName] = now + cd
    pd.abilityCharges = pd.abilityCharges - 1
    AbilityUpdateEvt:FireClient(player, pd.abilityCharges)
    AbilityCDEvt:FireClient(player, abilityName, cd)
    if abilityName == "phase" then
        pd.isPhasing = true
        task.delay(2, function()
            if _G.playerRunData[player] == pd then pd.isPhasing = false end
        end)
    elseif abilityName == "invincibility" then
        pd.isInvincible = true
        task.delay(3, function()
            if _G.playerRunData[player] == pd then pd.isInvincible = false end
        end)
    elseif abilityName == "dash" then
        local root = pd.rootPart
        if root and root.Parent then
            local newLane = math.clamp(pd.laneIndex + 2, 1, NUM_LANES)
            pd.laneIndex  = newLane
            root.CFrame   = CFrame.new(LANE_X[newLane], root.Position.Y, root.Position.Z)
        end
    elseif abilityName == "timeslow" then
        local origSpeed = pd.currentSpeed
        pd.currentSpeed = origSpeed * 0.35
        if pd.linearVelocity and pd.linearVelocity.Parent then
            pd.linearVelocity.VectorVelocity = Vector3.new(0, 0, -pd.currentSpeed)
        end
        SpeedUpdateEvt:FireClient(player, pd.currentSpeed / BASE_FORWARD_SPEED)
        task.delay(4, function()
            if _G.playerRunData[player] == pd and pd.isAlive then
                pd.currentSpeed = origSpeed
                if pd.linearVelocity and pd.linearVelocity.Parent then
                    pd.linearVelocity.VectorVelocity = Vector3.new(0, 0, -pd.currentSpeed)
                end
                SpeedUpdateEvt:FireClient(player, pd.currentSpeed / BASE_FORWARD_SPEED)
            end
        end)
    end
end)

SelectDiffEvt.OnServerEvent:Connect(function(player, diff)
    if not DIFFICULTY[diff] then return end
    local pd = _G.playerRunData[player]
    if pd then pd.difficulty = diff end
    print("[runner]", player.Name, "selected:", diff)
end)

RequestRunEvt.OnServerEvent:Connect(function(player)
    local diff = (_G.playerRunData[player] and _G.playerRunData[player].difficulty) or "normal"
    buildTrack(diff)
    initRun(player, diff)
    player:LoadCharacter()
end)

RunnerAdvanceEvt.OnServerEvent:Connect(function(player)
    local pd   = _G.playerRunData[player]
    local diff = (pd and pd.difficulty) or "normal"
    local dist = (pd and pd.distanceTraveled) or 0
    addNextSeg(diff, dist)
end)

-- Upgrade purchase (minimal guard; ProgressionHub.server.lua handles it fully)
BuyUpgradeEvt.OnServerEvent:Connect(function() end)

-- Heartbeat
local lastHB = os.clock()
RunService.Heartbeat:Connect(function()
    local now = os.clock()
    local dt  = math.min(now - lastHB, 0.1)
    lastHB    = now

    -- Moving obstacles oscillation
    for i = #movObstacles, 1, -1 do
        local mo = movObstacles[i]
        if not mo.part or not mo.part.Parent then
            table.remove(movObstacles, i)
            continue
        end
        mo.posX = mo.posX + mo.speed * mo.dir * dt
        if mo.posX >= mo.maxX then mo.posX = mo.maxX; mo.dir = -1 end
        if mo.posX <= mo.minX then mo.posX = mo.minX; mo.dir =  1 end
        local cf = mo.part.CFrame
        mo.part.CFrame = CFrame.new(mo.posX, cf.Y, cf.Z)
    end

    for player, pd in pairs(_G.playerRunData) do
        if not pd.isAlive or pd.runEnded then continue end
        local char = player.Character
        if not char then continue end
        local root = pd.rootPart
        local hum  = pd.humanoid
        if not root or not root.Parent or not hum then continue end

        if hum.Health <= 0 then
            endRun(player, pd)
            continue
        end

        -- Fall off track
        if root.Position.Y < FLOOR_Y - 20 then
            hum.Health = 0
            endRun(player, pd)
            continue
        end

        -- Exit track sides
        if math.abs(root.Position.X) > SEGMENT_WIDTH / 2 + 5 then
            hum.Health = 0
            endRun(player, pd)
            continue
        end

        -- Speed ramp
        if now - pd.lastRampTime >= SPEED_RAMP_INTERVAL then
            pd.lastRampTime = now
            local s = DIFFICULTY[pd.difficulty] or DIFFICULTY.normal
            pd.currentSpeed = math.min(pd.currentSpeed + SPEED_RAMP * s.speedMult, MAX_SPEED)
        end

        -- Apply velocity
        if pd.linearVelocity and pd.linearVelocity.Parent then
            local spd = pd.currentSpeed + (pd.speedBoost or 0)
            pd.linearVelocity.VectorVelocity = Vector3.new(0, 0, -spd)
        end

        -- Distance tracking
        pd.distanceTraveled = pd.distanceTraveled + (pd.currentSpeed + (pd.speedBoost or 0)) * dt
        local ls = player:FindFirstChild("leaderstats")
        if ls and ls:FindFirstChild("Distance") then
            ls.Distance.Value = math.floor(pd.distanceTraveled)
        end

        -- Milestones
        local ms = math.floor(pd.distanceTraveled / 100)
        if ms > pd.lastMilestone then
            pd.lastMilestone = ms
            MilestoneEvt:FireClient(player, ms * 100)
            pd.currentSpeed  = math.min(pd.currentSpeed + MILESTONE_SPEED_BONUS, MAX_SPEED)
            SpeedUpdateEvt:FireClient(player, (pd.currentSpeed + (pd.speedBoost or 0)) / BASE_FORWARD_SPEED)
            BiomeChangeEvt:FireClient(player, getBiome(pd.distanceTraveled).name)
        end

        -- Auto-extend track
        if #segments > 0 then
            local last = segments[#segments]
            if last and last.PrimaryPart then
                if (root.Position.Z - (last.PrimaryPart.Position.Z - SEGMENT_LENGTH / 2)) < SEGMENT_LENGTH * 3 then
                    addNextSeg(pd.difficulty, pd.distanceTraveled)
                end
            end
        end
    end
end)

-- Initial track build
buildTrack("normal")
print("[runner] 5-lane endless runner initialised.")
