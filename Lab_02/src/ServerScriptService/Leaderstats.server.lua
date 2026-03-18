local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- RemoteEvent
local advanceEvent = ReplicatedStorage:FindFirstChild("RunnerAdvance")
if not advanceEvent then
	advanceEvent = Instance.new("RemoteEvent")
	advanceEvent.Name = "RunnerAdvance"
	advanceEvent.Parent = ReplicatedStorage
end

-- RemoteEvent for shop data
local shopDataEvent = ReplicatedStorage:FindFirstChild("ShopData")
if not shopDataEvent then
	shopDataEvent = Instance.new("RemoteEvent")
	shopDataEvent.Name = "ShopData"
	shopDataEvent.Parent = ReplicatedStorage
end

-- RemoteEvent for obstacle hit
local obstacleHitEvent = ReplicatedStorage:FindFirstChild("ObstacleHit")
if not obstacleHitEvent then
	obstacleHitEvent = Instance.new("RemoteEvent")
	obstacleHitEvent.Name = "ObstacleHit"
	obstacleHitEvent.Parent = ReplicatedStorage
end

-- RemoteEvent for debug coin addition
local debugCoinEvent = ReplicatedStorage:FindFirstChild("DebugAddCoins")
if not debugCoinEvent then
	debugCoinEvent = Instance.new("RemoteEvent")
	debugCoinEvent.Name = "DebugAddCoins"
	debugCoinEvent.Parent = ReplicatedStorage
end

debugCoinEvent.OnServerEvent:Connect(function(player, amount)
	local stats = player:FindFirstChild("leaderstats")
	if stats and stats:FindFirstChild("Coins") then
		local chance = math.random(1, 100)
		local sign

		if chance <= 90 then
			sign = -1
		else
			sign = 1
		end
		stats.Coins.Value += sign*amount
	end
end)

-- SETTINGS
local SEGMENT_LENGTH = 50
local SEGMENT_WIDTH = 30
local START_Y = 50
local SEGMENTS_AHEAD = 8

local COIN_CHANCE = 0.6
local OBSTACLE_CHANCE = 0.35

local COIN_LOSS_ON_HIT = 5
local GRACE_PERIOD = 10  -- seconds of invulnerability after hitting obstacle
local SHOP_SPAWN_INTERVAL = 40  -- spawn shop island every 40 seconds

-- 3 lanes: -8, 0, 8
local LANES = {-8, 0, 8}

-- Calculate shop spawn interval in segments (based on movement speed)
-- FORWARD_SPEED = 50 studs/sec, SEGMENT_LENGTH = 50 studs
-- So it takes 50/50 = 1 sec per segment
-- In SHOP_SPAWN_INTERVAL (50 sec), player travels: 50 * 50 / 50 = 50 segments
local SHOP_SPAWN_SEGMENT_INTERVAL = math.ceil(SHOP_SPAWN_INTERVAL * 50 / SEGMENT_LENGTH)

-- Track data
local segments = {}
local lastIndexSpawned = -1
local shopSpawnTimer = 0
local coins = {}  -- Track all active coins for collection detection
local shops = {}  -- Track all shop islands {model, platform, zPos}
local nextShopIndex = SEGMENTS_AHEAD + 16  -- First shop spawns after 16 segments (~10 seconds at 80/sec, then some buffer)
local obstacleHitDebounce = {}  -- Track last obstacle hit time per player to prevent multi-obstacle spam

-- Helper function to get all active shop Z positions
local function getAllActiveShopPositions()
	local positions = {}
	for _, shop in ipairs(shops) do
		table.insert(positions, shop.zPos)
	end
	return positions
end

-- Helper: create part
local function makePart(size, color, anchored, canCollide)
	local p = Instance.new("Part")
	p.Size = size
	p.Anchored = anchored
	p.CanCollide = canCollide
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- Create one segment
local function createSegment(index, noObstacles)
	local model = Instance.new("Model")
	model.Name = "Segment_" .. index

	local floor = makePart(
		Vector3.new(SEGMENT_WIDTH, 2, SEGMENT_LENGTH),
		Color3.fromRGB(60, 60, 60),
		true,
		true
	)
	floor.CFrame = CFrame.new(0, START_Y, -index * SEGMENT_LENGTH)
	floor.Name = "Floor"
	floor.Parent = model
	model.PrimaryPart = floor

	-- COINS (3 lanes, random positions)
	if math.random() < COIN_CHANCE then
		local selectedLane = LANES[math.random(1, #LANES)]
		local coin = makePart(Vector3.new(0.1, 2,3), Color3.fromRGB(218, 32, 255), true, false)
		coin.Shape = Enum.PartType.Cylinder
		coin.Orientation = Vector3.new(0, 90, 0)
		coin.Name = "Coin"
		coin.Position = floor.Position + Vector3.new(
			selectedLane,
			5,
			math.random(-SEGMENT_LENGTH/2 + 5, SEGMENT_LENGTH/2 - 5)
		)
		coin.Parent = model

		-- Add to coins table for distance-based collection
		table.insert(coins, coin)
	end

	-- OBSTACLES (can spawn in 0, 1, or 2 lanes - always leave at least 1 lane clear)
	-- Skip obstacles if noObstacles flag is true
	if not noObstacles then
		-- Decide obstacle pattern: how many lanes will have obstacles
		local obstaclePattern = math.random(0, 9)  -- 0-9 for different probabilities
		local obstacleLanes = {}
		if obstaclePattern <= 2 then
			-- No obstacles (30%)
			obstacleLanes = {}
		elseif obstaclePattern <= 5 then
			-- 1 obstacle in a random lane (40%)
			obstacleLanes = {LANES[math.random(1, #LANES)]}
		else
			-- 2 obstacles in random lanes (30%)
			local lane1 = LANES[math.random(1, #LANES)]
			local lane2 = LANES[math.random(1, #LANES)]
			-- Ensure they're different lanes
			while lane2 == lane1 do
				lane2 = LANES[math.random(1, #LANES)]
			end
			obstacleLanes = {lane1, lane2}
		end

		-- Spawn obstacles in the selected lanes
		
		for _, laneX in ipairs(obstacleLanes) do
			local obstacle = makePart(Vector3.new(4, 6, 0.1), Color3.fromRGB(91, 51, 88), true, true)
			obstacle.Name = "Obstacle"
			obstacle.CFrame = floor.CFrame * CFrame.new(
				laneX,
				4,
				math.random(-SEGMENT_LENGTH/2 + 5, SEGMENT_LENGTH/2 - 5)
			)
			obstacle.Parent = model

			-- Collision handler for this obstacle
			obstacle.Touched:Connect(function(hit)
				local plr = Players:GetPlayerFromCharacter(hit.Parent)
				if not plr then return end

				-- Per-player debounce: prevent multiple obstacles from hitting within 0.5 seconds
				local now = tick()
				if obstacleHitDebounce[plr] and (now - obstacleHitDebounce[plr]) < 0.5 then
					return  -- Too soon, ignore
				end
				obstacleHitDebounce[plr] = now

				local stats = plr:FindFirstChild("leaderstats")
				local char = plr.Character
				if not stats or not char then return end

				local hum = char:FindFirstChildOfClass("Humanoid")
				if not hum then return end

				local gameState = plr:FindFirstChild("GameState")
				if not gameState then
					gameState = Instance.new("Folder")
					gameState.Name = "GameState"
					gameState.Parent = plr
				end

				-- Ensure grace periods exist
				local shieldGraceEnd = gameState:FindFirstChild("ShieldGracePeriodEnd")
				if not shieldGraceEnd then
					shieldGraceEnd = Instance.new("NumberValue")
					shieldGraceEnd.Name = "ShieldGracePeriodEnd"
					shieldGraceEnd.Value = 0
					shieldGraceEnd.Parent = gameState
				end

				local shieldGraceUsed = gameState:FindFirstChild("ShieldGraceHitUsed")
				if not shieldGraceUsed then
					shieldGraceUsed = Instance.new("BoolValue")
					shieldGraceUsed.Name = "ShieldGraceHitUsed"
					shieldGraceUsed.Value = false
					shieldGraceUsed.Parent = gameState
				end

				-- Ensure normal grace period exists
				local graceValue = gameState:FindFirstChild("GracePeriodEnd")
				if not graceValue then
					graceValue = Instance.new("NumberValue")
					graceValue.Name = "GracePeriodEnd"
					graceValue.Value = 0
					graceValue.Parent = gameState
				end

				-- Check if in shield grace period (from Grace Shield purchase)
				if now < shieldGraceEnd.Value then
					-- In shield grace period
					if not shieldGraceUsed.Value then
						-- First hit in shield - use the free hit
						shieldGraceUsed.Value = true
						shieldGraceEnd.Value = 0  -- Shield is consumed
						graceValue.Value = 0  -- Reset normal grace period too for clean slate

						-- Play soft shield/protection sound
						local shieldSound = Instance.new("Sound")
						shieldSound.SoundId = "rbxassetid://120459258956850"  -- Shield break sound
						shieldSound.Volume = 0.2
						shieldSound.Parent = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
						game:GetService("Debris"):AddItem(shieldSound, 2)
						shieldSound:Play()

						-- Disable collision on this obstacle so player can pass through
						obstacle.CanCollide = false
						task.wait(0.5)
						obstacle.CanCollide = true

						return  -- No coins lost, no red screen, back to normal gameplay
					else
						-- Second hit in shield grace period - DEATH (shield consumed)
						hum.Health = 0
						return
					end
				end

				-- NOT in shield grace - check normal grace period
				if now < graceValue.Value then
					-- Second hit within grace period - DEATH
					hum.Health = 0
					stats.Coins.Value = 0  -- Lose all coins
					return
				end

				-- First hit: lose coins and set grace period
				stats.Coins.Value =stats.Coins.Value - COIN_LOSS_ON_HIT
				if(stats.Coins.Value<0) then
					hum.Health = 0
					stats.Coins.Value = 0  -- Lose all coi
				end
				graceValue.Value = now + GRACE_PERIOD

				-- Play metallic hit sound
				local hitSound = Instance.new("Sound")
				hitSound.SoundId = "rbxassetid://138080762"  -- Metallic hit
				hitSound.Volume = 0.25
				hitSound.Parent = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
				game:GetService("Debris"):AddItem(hitSound, 0.5)
				hitSound:Play()

				-- Disable collision on this obstacle so player can pass through
				obstacle.CanCollide = false
				task.wait(0.5)
				obstacle.CanCollide = true

				obstacleHitEvent:FireClient(plr, GRACE_PERIOD)
			end)
		end
	end  -- End if not noObstacles

	-- SPEED BOOST ZONES (green rectangles, spawn occasionally)
	if math.random() < 0.13 then  -- 13% chance (spawn a bit more often)
		local selectedLane = LANES[math.random(1, #LANES)]
		local speedZone = makePart(Vector3.new(3, 1, 8), Color3.fromRGB(0, 200, 80), true, false)
		speedZone.Name = "SpeedBoostZone"
		speedZone.CFrame = floor.CFrame * CFrame.new(
			selectedLane,
			1,
			math.random(-SEGMENT_LENGTH/2 + 5, SEGMENT_LENGTH/2 - 5)
		)
		speedZone.Parent = model

		-- Speed zone touch detection
		local zoneDebounce = {}
		speedZone.Touched:Connect(function(hit)
			local hum = hit.Parent:FindFirstChildOfClass("Humanoid")
			if not hum then return end
			local player = Players:FindFirstChild(hit.Parent.Name)
			if not player or zoneDebounce[player] then return end

			zoneDebounce[player] = true

			local gameState = player:FindFirstChild("GameState")
			if gameState then
				local tempBoost = gameState:FindFirstChild("TempSpeedBoostEnd")
				if not tempBoost then
					tempBoost = Instance.new("NumberValue")
					tempBoost.Name = "TempSpeedBoostEnd"
					tempBoost.Value = 0
					tempBoost.Parent = gameState
				end
				local boostEndTime = tick() + 5
				tempBoost.Value = boostEndTime

				-- Play whoosh sound
				local whooshSound = Instance.new("Sound")
				whooshSound.SoundId = "rbxassetid://83211426606907"  -- Acceleration pad whoosh
				whooshSound.Volume = 0.2
				whooshSound.Parent = hit.Parent:FindFirstChild("HumanoidRootPart") or hit.Parent.PrimaryPart
				game:GetService("Debris"):AddItem(whooshSound, 2)
				whooshSound:Play()

				local speedZoneEvent = ReplicatedStorage:FindFirstChild("SpeedZoneHit")
				if not speedZoneEvent then
					speedZoneEvent = Instance.new("RemoteEvent")
					speedZoneEvent.Name = "SpeedZoneHit"
					speedZoneEvent.Parent = ReplicatedStorage
				end
				speedZoneEvent:FireClient(player, 5)  -- 5 second duration
			end

			task.wait(1)
			zoneDebounce[player] = nil
		end)
	end

	model.Parent = Workspace
	return model
end

-- Create shop island segment (floor only, no obstacles/coins)
local function createShopSegment(index)
	local model = Instance.new("Model")
	model.Name = "ShopSegment_" .. index

	local floor = makePart(
		Vector3.new(SEGMENT_WIDTH, 2, SEGMENT_LENGTH),
		Color3.fromRGB(100, 150, 100),
		true,
		true
	)
	floor.CFrame = CFrame.new(0, 50, -index * SEGMENT_LENGTH)
	floor.Name = "Floor"
	floor.Parent = model
	model.PrimaryPart = floor

	model.Parent = Workspace
	return model
end

-- Create shop island
local function createShopIsland(index)
	local model = Instance.new("Model")
	model.Name = "ShopIsland_" .. index

	-- Platform
	local platform = makePart(
		Vector3.new(30, 2, 20),
		Color3.fromRGB(100, 150, 100),
		true,
		true
	)
	platform.CFrame = CFrame.new(0, START_Y, -index * SEGMENT_LENGTH)
	platform.Name = "Platform"
	platform.Parent = model
	model.PrimaryPart = platform

	-- Shop signs (visual indicators) with text labels positioned above
	local sign1 = makePart(Vector3.new(4, 6, 1), Color3.fromRGB(0, 100, 200), true, false)
	sign1.CFrame = platform.CFrame * CFrame.new(-8, 5, 0)
	sign1.Name = "SpeedBoost"
	sign1.Parent = model

	-- Add text label to sign1 (smaller, better positioned)
	local billboard1 = Instance.new("BillboardGui")
	billboard1.MaxDistance = 100  -- Only show when close
	billboard1.Size = UDim2.new(5, 0, 4, 0)
	billboard1.StudsOffset = Vector3.new(0, 4, 0)  -- Position above
	billboard1.Parent = sign1
	local textLabel1 = Instance.new("TextLabel")
	textLabel1.Size = UDim2.new(1, 0, 1, 0)
	textLabel1.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	textLabel1.BackgroundTransparency = 0.4
	textLabel1.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel1.TextSize = 12
	textLabel1.Font = Enum.Font.GothamBold
	textLabel1.Text = "SPEED BOOST\n+3 permanent\nCost: 10 coins"
	textLabel1.Parent = billboard1

	-- Add touch handler for Speed Boost
	local speedBoostDebounce = {}
	sign1.Touched:Connect(function(hit)
		local hum = hit.Parent:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local player = Players:FindFirstChild(hit.Parent.Name)
		if not player or speedBoostDebounce[player] then return end

		-- Check if player already bought from this specific shop
		local gameState = player:FindFirstChild("GameState")
		if not gameState then return end

		local shopsPurchased = gameState:FindFirstChild("ShopsPurchased")
		if not shopsPurchased then
			shopsPurchased = Instance.new("Folder")
			shopsPurchased.Name = "ShopsPurchased"
			shopsPurchased.Parent = gameState
		end

		local shopId = "Shop_" .. index .. "_Speed"
		if shopsPurchased:FindFirstChild(shopId) then
			return
		end

		speedBoostDebounce[player] = true
		task.wait(1)
		speedBoostDebounce[player] = nil

		local stats = player:FindFirstChild("leaderstats")
		if stats and stats:FindFirstChild("Coins") then
			if stats.Coins.Value >= 10 then
				stats.Coins.Value -= 10
				-- Permanent speed bonus: increase by +3
				local speedBonus = gameState:FindFirstChild("PermanentSpeedBonus")
				if not speedBonus then
					speedBonus = Instance.new("IntValue")
					speedBonus.Name = "PermanentSpeedBonus"
					speedBonus.Value = 0
					speedBonus.Parent = gameState
				end
				speedBonus.Value += 3

				-- Play kaching sound
				local kachingSound = Instance.new("Sound")
				kachingSound.SoundId = "rbxassetid://138273059623491"  -- Kaching/cash register sound
				kachingSound.Volume = 0.4
				kachingSound.Parent = player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart
				game:GetService("Debris"):AddItem(kachingSound, 2)
				kachingSound:Play()

				-- Mark as purchased
				local purchased = Instance.new("BoolValue")
				purchased.Name = shopId
				purchased.Value = true
				purchased.Parent = shopsPurchased

				-- Change sign to gray to show it's disabled
				sign1.Color = Color3.fromRGB(150, 150, 150)
				textLabel1.Text = "SOLD OUT"
			end
		end
	end)

	local sign2 = makePart(Vector3.new(4, 6, 1), Color3.fromRGB(150, 100, 200), true, false)
	sign2.CFrame = platform.CFrame * CFrame.new(8, 5, 0)
	sign2.Name = "GraceReducer"
	sign2.Parent = model

	-- Add text label to sign2
	local billboard2 = Instance.new("BillboardGui")
	billboard2.MaxDistance = 100  -- Only show when close
	billboard2.Size = UDim2.new(5, 0, 4, 0)
	billboard2.StudsOffset = Vector3.new(0, 4, 0)  -- Position above
	billboard2.Parent = sign2
	local textLabel2 = Instance.new("TextLabel")
	textLabel2.Size = UDim2.new(1, 0, 1, 0)
	textLabel2.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	textLabel2.BackgroundTransparency = 0.4
	textLabel2.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel2.TextSize = 12
	textLabel2.Font = Enum.Font.GothamBold
	textLabel2.Text = "SHIELD GRACE\n20s +1 free hit\nCost: 15 coins"
	textLabel2.Parent = billboard2

	-- Add touch handler for Grace Reducer (now grants 20-second shield)
	local graceDebounce = {}
	sign2.Touched:Connect(function(hit)
		local hum = hit.Parent:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local player = Players:FindFirstChild(hit.Parent.Name)
		if not player or graceDebounce[player] then return end

		-- Check if player already bought from this specific shop
		local gameState = player:FindFirstChild("GameState")
		if not gameState then return end

		local shopsPurchased = gameState:FindFirstChild("ShopsPurchased")
		if not shopsPurchased then
			shopsPurchased = Instance.new("Folder")
			shopsPurchased.Name = "ShopsPurchased"
			shopsPurchased.Parent = gameState
		end

		local shopId = "Shop_" .. index .. "_Grace"
		if shopsPurchased:FindFirstChild(shopId) then
			return
		end

		graceDebounce[player] = true
		task.wait(1)
		graceDebounce[player] = nil

		local stats = player:FindFirstChild("leaderstats")
		if stats and stats:FindFirstChild("Coins") then
			if stats.Coins.Value >= 15 then
				stats.Coins.Value -= 15
				-- Grant 20-second shield grace period
				local shieldGrace = gameState:FindFirstChild("ShieldGracePeriodEnd")
				if not shieldGrace then
					shieldGrace = Instance.new("NumberValue")
					shieldGrace.Name = "ShieldGracePeriodEnd"
					shieldGrace.Value = 0
					shieldGrace.Parent = gameState
				end
				shieldGrace.Value = tick() + 20

				local shieldUsed = gameState:FindFirstChild("ShieldGraceHitUsed")
				if not shieldUsed then
					shieldUsed = Instance.new("BoolValue")
					shieldUsed.Name = "ShieldGraceHitUsed"
					shieldUsed.Value = false
					shieldUsed.Parent = gameState
				end
				shieldUsed.Value = false  -- Reset the used flag

				-- Play kaching sound
				local kachingSound = Instance.new("Sound")
				kachingSound.SoundId = "rbxassetid://138273059623491"  -- Kaching/cash register sound
				kachingSound.Volume = 0.4
				kachingSound.Parent = player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart
				game:GetService("Debris"):AddItem(kachingSound, 2)
				kachingSound:Play()

				-- Schedule shield expiration sound (play after 20 seconds if not used)
				task.delay(20, function()
					if player and player.Character and not shieldUsed.Value then  -- Only play if shield wasn't used
						local hrp = player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart
						if hrp then
							local shieldExpireSound = Instance.new("Sound")
							shieldExpireSound.SoundId = "rbxassetid://120459258956850"  -- Shield break sound
							shieldExpireSound.Volume = 0.2
							shieldExpireSound.Parent = hrp
							game:GetService("Debris"):AddItem(shieldExpireSound, 2)
							shieldExpireSound:Play()
						end
					end
				end)

				-- Mark as purchased
				local purchased = Instance.new("BoolValue")
				purchased.Name = shopId
				purchased.Value = true
				purchased.Parent = shopsPurchased

				-- Change sign to gray
				sign2.Color = Color3.fromRGB(150, 150, 150)
				textLabel2.Text = "SOLD OUT"
			end
		end
	end)

	model.Parent = Workspace
	return model, platform
end

-- Build track
local function buildInitialTrack()
	segments = {}
	for i = 0, SEGMENTS_AHEAD - 1 do
		-- Don't spawn obstacles on first 2 segments to avoid spawning into danger
		local noObstacles = (i < 2)
		local seg = createSegment(i, noObstacles)
		table.insert(segments, seg)
	end
	lastIndexSpawned = SEGMENTS_AHEAD - 1
end

buildInitialTrack()

-- Function to get all planned shop Z positions
local function getPlannedShopPositions(currentIndex, lookAheadCount)
	local positions = {}
	local shopIndex = nextShopIndex
	for i = 1, lookAheadCount do
		if shopIndex >= currentIndex then
			table.insert(positions, -shopIndex * SEGMENT_LENGTH)
		end
		shopIndex += SHOP_SPAWN_SEGMENT_INTERVAL
	end
	if #positions > 0 then
		return positions
	else
		return positions
	end
end

-- Spawn player
local function placeOnTrack(player, character)
	if #segments == 0 then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local pos = segments[1].PrimaryPart.Position
		hrp.CFrame = CFrame.new(pos + Vector3.new(0, 5, 5), pos + Vector3.new(0, 5, -200))
	end
end

-- Broadcast initial shop positions to new players and handle character spawn
Players.PlayerAdded:Connect(function(player)
	task.wait(0.5)  -- Wait for player to load
	local shopPositions = getPlannedShopPositions(lastIndexSpawned, 10)  -- Look ahead 10 shops
	shopDataEvent:FireClient(player, shopPositions)

	player.CharacterAdded:Connect(function(char)
		task.wait(0.2)

		local gameState = player:FindFirstChild("GameState")
		if not gameState then
			-- Create gameState if it doesn't exist
			gameState = Instance.new("Folder")
			gameState.Name = "GameState"
			gameState.Parent = player
		end

		-- Reset grace period (normal)
		local gracePeriod = gameState:FindFirstChild("GracePeriodEnd")
		if not gracePeriod then
			gracePeriod = Instance.new("NumberValue")
			gracePeriod.Name = "GracePeriodEnd"
			gracePeriod.Value = 0
			gracePeriod.Parent = gameState
		else
			gracePeriod.Value = 0
		end

		-- Reset shield grace
		local shieldGracePeriod = gameState:FindFirstChild("ShieldGracePeriodEnd")
		if not shieldGracePeriod then
			shieldGracePeriod = Instance.new("NumberValue")
			shieldGracePeriod.Name = "ShieldGracePeriodEnd"
			shieldGracePeriod.Value = 0
			shieldGracePeriod.Parent = gameState
		else
			shieldGracePeriod.Value = 0
		end

		local shieldGraceUsed = gameState:FindFirstChild("ShieldGraceHitUsed")
		if not shieldGraceUsed then
			shieldGraceUsed = Instance.new("BoolValue")
			shieldGraceUsed.Name = "ShieldGraceHitUsed"
			shieldGraceUsed.Value = false
			shieldGraceUsed.Parent = gameState
		else
			shieldGraceUsed.Value = false
		end

		local tempBoost = gameState:FindFirstChild("TempSpeedBoostEnd")
		if not tempBoost then
			tempBoost = Instance.new("NumberValue")
			tempBoost.Name = "TempSpeedBoostEnd"
			tempBoost.Value = 0
			tempBoost.Parent = gameState
		else
			tempBoost.Value = 0
		end

		-- RESET permanent speed bonus on respawn
		local speedBonus = gameState:FindFirstChild("PermanentSpeedBonus")
		if not speedBonus then
			speedBonus = Instance.new("IntValue")
			speedBonus.Name = "PermanentSpeedBonus"
			speedBonus.Value = 0
			speedBonus.Parent = gameState
		else
			speedBonus.Value = 0
		end

		placeOnTrack(player, char)
	end)
end)

-- Segment advance with shop spawning
advanceEvent.OnServerEvent:Connect(function()
	-- Only destroy segments that go beyond 2 behind the player (keep at least 2 tiles behind for visuals)
	if #segments > SEGMENTS_AHEAD + 2 then
		local firstSeg = segments[1]
		if firstSeg then
			firstSeg:Destroy()
			table.remove(segments, 1)
		end
	end

	lastIndexSpawned += 1

	-- Check if we should spawn a shop at this index
	if lastIndexSpawned == nextShopIndex then
		-- Create special shop segment (no obstacles/coins)
		local shopSegment = createShopSegment(lastIndexSpawned)
		table.insert(segments, shopSegment)

		-- Create shop island on this segment
		local shopModel, shopPlatform = createShopIsland(lastIndexSpawned)
		table.insert(shops, {model = shopModel, platform = shopPlatform, zPos = shopPlatform.Position.Z})

		-- Schedule next shop
		nextShopIndex += SHOP_SPAWN_SEGMENT_INTERVAL

		-- Broadcast all active shops + predicted future shops
		local activShops = getAllActiveShopPositions()
		local predictedShops = getPlannedShopPositions(lastIndexSpawned, 10)
		local allShops = {}
		for _, z in ipairs(activShops) do table.insert(allShops, z) end
		for _, z in ipairs(predictedShops) do table.insert(allShops, z) end
		shopDataEvent:FireAllClients(allShops)
	else
		-- Normal segment
		table.insert(segments, createSegment(lastIndexSpawned))
	end
end)

-- Fallback: Broadcast shop positions every 5 seconds to ensure clients stay updated
RunService.Heartbeat:Connect(function(deltaTime)
	shopSpawnTimer += deltaTime

	if shopSpawnTimer >= 5 then  -- Update every 5 seconds
		shopSpawnTimer = 0
		local activShops = getAllActiveShopPositions()
		local predictedShops = getPlannedShopPositions(lastIndexSpawned, 10)
		local allShops = {}
		for _, z in ipairs(activShops) do table.insert(allShops, z) end
		for _, z in ipairs(predictedShops) do table.insert(allShops, z) end
		shopDataEvent:FireAllClients(allShops)
	end
end)

-- Coin collection detection (distance-based)
RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end

		-- Check distance to each coin
		for i = #coins, 1, -1 do
			local coin = coins[i]
			if not coin.Parent then
				-- Coin was destroyed, remove from table
				table.remove(coins, i)
			else
				local distance = (coin.Position - hrp.Position).Magnitude
				if distance < 5 then  -- Collection range
					-- Collect coin
					local stats = player:FindFirstChild("leaderstats")
					if stats and stats:FindFirstChild("Coins") then
						stats.Coins.Value += 1

						-- Play coin pickup sound
						local sound = Instance.new("Sound")
						sound.SoundId = "rbxassetid://135904960416116"  -- Coin pickup sound
						sound.Volume = 0.3
						sound.Parent = hrp
						game:GetService("Debris"):AddItem(sound, 0.5)
						sound:Play()
					end

					coin:Destroy()
					table.remove(coins, i)
				end
			end
		end
	end
end)

-- Falling = death
RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hrp.Position.Y < (START_Y - 10) then
			hum.Health = 0
		end
	end
end)
