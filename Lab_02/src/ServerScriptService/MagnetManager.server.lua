-- MagnetManager.server.lua
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local cupcakeTemplate = ServerStorage:WaitForChild("Cupcake")
local magnetTemplate = ServerStorage:WaitForChild("Magnet")

-- Create RemoteEvent for magnet status
local magnetStatusEvent = ReplicatedStorage:FindFirstChild("MagnetStatus")
if not magnetStatusEvent then
  magnetStatusEvent = Instance.new("RemoteEvent")
  magnetStatusEvent.Name = "MagnetStatus"
  magnetStatusEvent.Parent = ReplicatedStorage
end

local LANE_X = { -10, 0, 10 }
local MAGNET_DURATION = 10 -- seconds
local MAGNET_CHANCE = 0.1  -- chance per segment to spawn a magnet
local MAGNET_RANGE = 50    -- how far magnets attract cupcakes (in studs)
local MAGNET_SPEED = 50    -- how fast cupcakes move towards player

-- Keep track of active magnets for each player
local playerMagnets = {}

-- Helper to get root part
local function getRootPart(char)
  if not char then return nil end
  local hrp = char:FindFirstChild("HumanoidRootPart")
  if hrp then return hrp end
  if char.PrimaryPart then return char.PrimaryPart end
  local hum = char:FindFirstChildOfClass("Humanoid")
  if hum and hum.RootPart then return hum.RootPart end
  return char:FindFirstChildWhichIsA("BasePart")
end

-- Helper to place model at world position
local function placeModel(model, pos, parent)
  if not model.PrimaryPart then
    local pp = model:FindFirstChildWhichIsA("BasePart", true)
    if pp then model.PrimaryPart = pp end
  end
  if not model.PrimaryPart then return end

  -- Anchor and disable collisions
  for _, d in ipairs(model:GetDescendants()) do
    if d:IsA("BasePart") then
      d.Anchored = true
      d.CanCollide = false
      d.CanTouch = true
    end
  end

  local yLift = (model.PrimaryPart.Size.Y / 2) + 5 -- Raised from 1.5 to 5 studs above floor
  model:PivotTo(CFrame.new(pos + Vector3.new(0, yLift, 0)))
  model.Parent = parent or Workspace
end

-- Spawn magnet randomly on a segment
local function maybeSpawnMagnet(segmentFloor, laneX, segmentModel)
  if math.random() < MAGNET_CHANCE then
    local magnet = magnetTemplate:Clone()
    -- pick a Z somewhere in the segment
    local zPos = segmentFloor.Position.Z + math.random(-25, 25)
    local worldPos = Vector3.new(laneX, segmentFloor.Position.Y, zPos)
    placeModel(magnet, worldPos, segmentModel)
    print("Spawning magnet at", worldPos)

    -- Handle pickup
    local collected = false
    if magnet.PrimaryPart then
      magnet.PrimaryPart.Touched:Connect(function(hit)
        if collected then return end
        local char = hit:FindFirstAncestorOfClass("Model")
        if not char then return end
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end
        collected = true

        -- Activate magnet for player
        playerMagnets[player] = true
        print(player.Name .. " activated magnet power! (10s)")
        magnetStatusEvent:FireClient(player, true, MAGNET_DURATION)
        magnet:Destroy()

        -- Remove magnet after duration
        task.delay(MAGNET_DURATION, function()
          playerMagnets[player] = nil
          magnetStatusEvent:FireClient(player, false)
          print(player.Name .. "'s magnet power expired")
        end)
      end)
    end
  end
end

-- Expose a function to call from runner when spawning a segment
local MagnetManager = {}

-- segment: floor part of the segment model
function MagnetManager.SpawnOnSegment(segment)
  if not segment:FindFirstChild("Floor") then return end
  local floor = segment.Floor
  for i, laneX in ipairs(LANE_X) do
    maybeSpawnMagnet(floor, laneX, segment)
  end
end

-- Optional: check if player has active magnet
function MagnetManager.PlayerHasMagnet(player)
  return playerMagnets[player] or false
end

-- Expose via _G for runner.server.lua to access
_G.MagnetManager = MagnetManager
print("MagnetManager loaded and exposed via _G")

-- Magnet attraction system (Subway Surfers style)
RunService.Heartbeat:Connect(function(deltaTime)
  for player, hasActiveMagnet in pairs(playerMagnets) do
    if not hasActiveMagnet then continue end

    local char = player.Character
    if not char then continue end

    local rootPart = getRootPart(char)
    if not rootPart then continue end

    -- Find all cupcakes in workspace
    for _, obj in ipairs(Workspace:GetDescendants()) do
      if obj.Name == "Cupcake" and obj:IsA("Model") and obj.PrimaryPart then
        local cupcakePart = obj.PrimaryPart
        local distance = (cupcakePart.Position - rootPart.Position).Magnitude

        -- If cupcake is within magnet range, attract it
        if distance <= MAGNET_RANGE and distance > 2 then
          local direction = (rootPart.Position - cupcakePart.Position).Unit
          local moveDistance = math.min(MAGNET_SPEED * deltaTime, distance - 2)
          local newPos = cupcakePart.Position + (direction * moveDistance)

          -- Move the entire cupcake model
          obj:PivotTo(CFrame.new(newPos))
        end
      end
    end
  end
end)
