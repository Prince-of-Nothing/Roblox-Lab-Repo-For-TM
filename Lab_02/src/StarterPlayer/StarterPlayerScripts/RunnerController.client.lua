local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local advanceEvent = ReplicatedStorage:WaitForChild("RunnerAdvance")
local shopDataEvent = ReplicatedStorage:WaitForChild("ShopData")
local obstacleHitEvent = ReplicatedStorage:WaitForChild("ObstacleHit")
local debugCoinEvent = ReplicatedStorage:WaitForChild("DebugAddCoins")

-- Disable mouse camera movement and zooming
local mouse = player:GetMouse()
mouse.TargetFilter = workspace  -- Prevent mouse from selecting anything meaningful
camera.CameraType = Enum.CameraType.Fixed  -- Lock to fixed mode, then we'll update it in heartbeat
camera.FieldOfView = 70  -- Set initial FOV

-- speeds
local FORWARD_SPEED = 50      -- studs/sec for Humanoid:Move
local STRAFE_SPEED = 40       -- studs/sec
local SHOP_MOVE_SPEED = 30    -- studs/sec while in shop
local MAX_X = 12

local SEGMENT_LENGTH = 50
local TRIGGER_MULT = 0.7
local nextTriggerZ = -(SEGMENT_LENGTH * TRIGGER_MULT)

local moveLeft = false
local moveRight = false
local moveForward = false
local moveBackward = false
local speedBoostMultiplier = 1.0
local permanentSpeedBonus = 0  -- Permanent +1 speed per boost purchase
local inShop = false
local shopPositions = {}
local lastPassedShop = nil  -- Track which shop we're at
local activeGraceTimer = nil  -- Store active grace period timer connection

-- Create UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RunnerUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Coins display
local coinsLabel = Instance.new("TextLabel")
coinsLabel.Name = "CoinsLabel"
coinsLabel.Size = UDim2.new(0, 200, 0, 50)
coinsLabel.Position = UDim2.new(1, -220, 0, 20)
coinsLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
coinsLabel.BackgroundTransparency = 0.5
coinsLabel.TextColor3 = Color3.fromRGB(255, 220, 0)
coinsLabel.TextSize = 24
coinsLabel.Font = Enum.Font.GothamBold
coinsLabel.Parent = screenGui

-- Distance tracker
local distanceLabel = Instance.new("TextLabel")
distanceLabel.Name = "DistanceLabel"
distanceLabel.Size = UDim2.new(0, 250, 0, 50)
distanceLabel.Position = UDim2.new(1, -270, 0, 80)
distanceLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
distanceLabel.BackgroundTransparency = 0.5
distanceLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
distanceLabel.TextSize = 20
distanceLabel.Font = Enum.Font.GothamBold
distanceLabel.Text = "Shop: --"
distanceLabel.Parent = screenGui

-- Speed display
local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "SpeedLabel"
speedLabel.Size = UDim2.new(0, 250, 0, 50)
speedLabel.Position = UDim2.new(1, -270, 0, 140)
speedLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
speedLabel.BackgroundTransparency = 0.5
speedLabel.TextColor3 = Color3.fromRGB(200, 100, 255)
speedLabel.TextSize = 16
speedLabel.Font = Enum.Font.GothamBold
speedLabel.Text = "Speed: 50"
speedLabel.Parent = screenGui

-- Grace period timer display
local graceLabel = Instance.new("TextLabel")
graceLabel.Name = "GraceLabel"
graceLabel.Size = UDim2.new(0, 150, 0, 50)
graceLabel.Position = UDim2.new(0, 20, 0, 20)
graceLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
graceLabel.BackgroundTransparency = 0.5
graceLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
graceLabel.TextSize = 20
graceLabel.Font = Enum.Font.GothamBold
graceLabel.Text = ""
graceLabel.Visible = false
graceLabel.ZIndex = 1000
graceLabel.Parent = screenGui

-- Shield grace timer display
local shieldLabel = Instance.new("TextLabel")
shieldLabel.Name = "ShieldLabel"
shieldLabel.Size = UDim2.new(0, 150, 0, 50)
shieldLabel.Position = UDim2.new(0, 20, 0, 80)
shieldLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shieldLabel.BackgroundTransparency = 0.5
shieldLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
shieldLabel.TextSize = 20
shieldLabel.Font = Enum.Font.GothamBold
shieldLabel.Text = ""
shieldLabel.Visible = false
shieldLabel.ZIndex = 1000
shieldLabel.Parent = screenGui

-- Debug button: Add coins
local debugButton = Instance.new("TextButton")
debugButton.Name = "DebugButton"
debugButton.Size = UDim2.new(0, 120, 0, 40)
debugButton.Position = UDim2.new(0, 20, 0, 80)
debugButton.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
debugButton.BackgroundTransparency = 0.3
debugButton.TextColor3 = Color3.fromRGB(255, 255, 255)
debugButton.TextSize = 14
debugButton.Font = Enum.Font.GothamBold
debugButton.Text = "Luck?"
debugButton.Parent = screenGui

debugButton.MouseButton1Click:Connect(function()
	debugCoinEvent:FireServer(10)
end)

-- Shop mode indicator
local shopLabel = Instance.new("TextLabel")
shopLabel.Name = "ShopLabel"
shopLabel.Size = UDim2.new(0, 200, 0, 40)
shopLabel.Position = UDim2.new(0.5, -100, 0, 20)
shopLabel.BackgroundColor3 = Color3.fromRGB(100, 150, 100)
shopLabel.BackgroundTransparency = 0.3
shopLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
shopLabel.TextSize = 18
shopLabel.Font = Enum.Font.GothamBold
shopLabel.Text = "SHOP MODE"
shopLabel.Visible = false
shopLabel.Parent = screenGui

-- Red damage overlay
local damageOverlay = Instance.new("Frame")
damageOverlay.Name = "DamageOverlay"
damageOverlay.Size = UDim2.new(1, 0, 1, 0)
damageOverlay.Position = UDim2.new(0, 0, 0, 0)
damageOverlay.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
damageOverlay.BackgroundTransparency = 1
damageOverlay.Parent = screenGui
damageOverlay.ZIndex = 999

-- Shield effect particle emitter (for post-shop grace)
local function createOrGetShieldEffect(hrp)
	local shield = hrp:FindFirstChild("ShieldParticles")
	if not shield then
		shield = Instance.new("ParticleEmitter")
		shield.Name = "ShieldParticles"
		shield.Parent = hrp
		shield.Texture = "rbxasset://textures/Particles/sparkles_main.dds"
		shield.Rate = 20
		shield.Lifetime = NumberRange.new(1)
		shield.Speed = NumberRange.new(5)
		shield.Color = ColorSequence.new(Color3.fromRGB(100, 200, 255))  -- Cyan
		shield.Transparency = NumberSequence.new(0.3)
		shield.Enabled = false
	end
	return shield
end

-- Speed boost effect particle emitter (green smoke)
local function createOrGetSpeedEffect(hrp)
	local speed = hrp:FindFirstChild("SpeedParticles")
	if not speed then
		speed = Instance.new("ParticleEmitter")
		speed.Name = "SpeedParticles"
		speed.Parent = hrp
		speed.Texture = "rbxasset://textures/Particles/sparkles_main.dds"
		speed.Rate = 30
		speed.Lifetime = NumberRange.new(0.8)
		speed.Speed = NumberRange.new(10)
		speed.Color = ColorSequence.new(Color3.fromRGB(0, 255, 100))  -- Green
		speed.Transparency = NumberSequence.new(0.4)
		speed.Enabled = false
	end
	return speed
end

-- Update coins display
local stats = player:WaitForChild("leaderstats")
stats:WaitForChild("Coins")
stats.Coins.Changed:Connect(function(newValue)
	coinsLabel.Text = "Coins: " .. newValue
end)
coinsLabel.Text = "Coins: 0"

-- Listen for shop positions
shopDataEvent.OnClientEvent:Connect(function(positions)
	shopPositions = positions
end)

-- Listen for obstacle hits and show grace period timer with red flash
obstacleHitEvent.OnClientEvent:Connect(function(gracePeriod)
	-- Disconnect any previous grace timer that might still be running
	if activeGraceTimer then
		activeGraceTimer:Disconnect()
		activeGraceTimer = nil
	end

	-- Show subtle red overlay
	damageOverlay.BackgroundTransparency = 0.75  -- Less harsh than before

	-- Show grace period countdown (left side in red)
	graceLabel.Visible = true

	local startTime = tick()
	activeGraceTimer = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local remaining = math.max(0, gracePeriod - elapsed)
		local progress = math.min(elapsed / gracePeriod, 1)

		if remaining > 0 then
			graceLabel.Text = "Curse: " .. math.ceil(remaining) .. "s"
			-- Gradually fade out the red overlay
			damageOverlay.BackgroundTransparency = 0.75 + (0.25 * progress)
		else
			graceLabel.Visible = false
			damageOverlay.BackgroundTransparency = 1
			activeGraceTimer:Disconnect()
			activeGraceTimer = nil
		end
	end)
end)

-- Listen for speed boost changes
local gameState = player:WaitForChild("GameState")
local speedBoostFlag = gameState:WaitForChild("SpeedBoostActive")
local permanentBonusValue = gameState:WaitForChild("PermanentSpeedBonus")

speedBoostFlag.Changed:Connect(function(newValue)
	if newValue then
		speedBoostMultiplier = 1.2  -- 20% temporary speed increase
	else
		speedBoostMultiplier = 1.0
	end
end)

permanentBonusValue.Changed:Connect(function(newValue)
	permanentSpeedBonus = newValue
end)

-- When character respawns, refresh the permanent speed bonus from the server
player.CharacterAdded:Connect(function(char)
	task.wait(0.2)

	-- Disconnect any active grace timer to prevent it from updating UI
	if activeGraceTimer then
		activeGraceTimer:Disconnect()
		activeGraceTimer = nil
	end

	-- Reset to server value (which is reset to 0 on respawn)
	local serverValue = gameState:FindFirstChild("PermanentSpeedBonus")
	if serverValue then
		permanentSpeedBonus = serverValue.Value
	end

	-- Hide grace period timer on respawn
	graceLabel.Visible = false
	damageOverlay.BackgroundTransparency = 1
end)

UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
		moveLeft = true
	elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
		moveRight = true
	elseif input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
		moveForward = true
	elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
		moveBackward = true
	elseif input.KeyCode == Enum.KeyCode.Space then
		local char = player.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then hum.Jump = true end
		end
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
		moveLeft = false
	elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
		moveRight = false
	elseif input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
		moveForward = false
	elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
		moveBackward = false
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	-- Update distance to next shop (only show shops we haven't reached yet)
	local closestShop = nil
	local closestDist = math.huge
	if #shopPositions > 0 then
		for _, shopZ in ipairs(shopPositions) do
			-- Only show shops ahead (smaller Z than player, moving in -Z direction)
			if shopZ < hrp.Position.Z then
				local dist = hrp.Position.Z - shopZ  -- Distance ahead
				if dist > 0 and dist < closestDist then
					closestDist = dist
					closestShop = shopZ
				end
			end
		end
	end

	-- Update distance label
	if closestShop then
		local metersAway = math.ceil(closestDist / 10)  -- Approximate meters
		distanceLabel.Text = "Shop in " .. metersAway .. "m"
	else
		distanceLabel.Text = "No shop nearby"
	end

	-- Check if player is IN a shop (within 25 studs of any shop position)
	local wasInShop = inShop
	inShop = false
	if #shopPositions > 0 then
		for _, shopZ in ipairs(shopPositions) do
			local dist = math.abs(shopZ - hrp.Position.Z)
			if dist < 25 then
				inShop = true
				break
			end
		end
	end

	-- Update shop mode indicator
	shopLabel.Visible = inShop

	-- Calculate and display current speed
	local baseSpeed = FORWARD_SPEED

	-- Read permanent speed bonus fresh from gameState each frame
	local speedBonusValue = gameState:FindFirstChild("PermanentSpeedBonus")
	if speedBonusValue then
		permanentSpeedBonus = speedBonusValue.Value
	end

	local bonusSpeed = permanentSpeedBonus
	local totalSpeed = baseSpeed + bonusSpeed
	local tempBoostEnd = gameState:FindFirstChild("TempSpeedBoostEnd")

	if tempBoostEnd and tick() < tempBoostEnd.Value then
		-- In speed boost zone
		speedLabel.TextColor3 = Color3.fromRGB(0, 255, 100)  -- Green when boosted
		local boostedSpeed = math.floor(totalSpeed * 1.3)
		speedLabel.Text = "Speed: " .. boostedSpeed .. " (" .. totalSpeed .. " +30%)"
	else
		-- Normal speed
		speedLabel.TextColor3 = Color3.fromRGB(200, 100, 255)  -- Purple normally
		if bonusSpeed > 0 then
			speedLabel.Text = "Speed: " .. totalSpeed .. " (base " .. baseSpeed .. " +" .. bonusSpeed .. ")"
		else
			speedLabel.Text = "Speed: " .. totalSpeed
		end
	end

	-- Check for temporary speed boost zones (for green effect)
	local tempBoostEndEffect = gameState:FindFirstChild("TempSpeedBoostEnd")
	if tempBoostEndEffect and tick() < tempBoostEndEffect.Value then
		speedBoostMultiplier = 1.3  -- +30% from speed zone

		-- Increase FOV during speed boost
		camera.FieldOfView = 80

		-- Enable green speed effect
		local speedEffect = createOrGetSpeedEffect(hrp)
		speedEffect.Enabled = true
	else
		speedBoostMultiplier = 1.0

		-- Reset FOV to normal
		camera.FieldOfView = 70

		-- Disable green speed effect
		local speedEffect = hrp:FindFirstChild("SpeedParticles")
		if speedEffect then
			speedEffect.Enabled = false
		end
	end

	-- Check for shield grace period (from buying Grace Shield)
	local shieldGraceEnd = gameState:FindFirstChild("ShieldGracePeriodEnd")
	if shieldGraceEnd and tick() < shieldGraceEnd.Value then
		-- In shield grace period - show shield effect and timer
		local shield = createOrGetShieldEffect(hrp)
		shield.Enabled = true

		-- Show shield timer
		shieldLabel.Visible = true
		local timeRemaining = math.ceil(shieldGraceEnd.Value - tick())
		shieldLabel.Text = "Shield: " .. math.max(0, timeRemaining) .. "s"
	else
		-- Shield expired - disable effect and timer
		local shield = hrp:FindFirstChild("ShieldParticles")
		if shield then
			shield.Enabled = false
		end
		shieldLabel.Visible = false
	end

	-- Set walk speed based on shop mode
	if inShop then
		hum.WalkSpeed = SHOP_MOVE_SPEED  -- Slower movement in shop
	else
		hum.WalkSpeed = FORWARD_SPEED
	end

	-- If entering shop mode, reset segment trigger so we don't advance
	if inShop and not wasInShop then
		nextTriggerZ = hrp.Position.Z
	end

	-- Movement logic
	local moveVec = Vector3.new(0, 0, 0)

	if inShop then
		-- Free movement mode in shop (all directions, but no constant forward)
		local moveDir = Vector3.new(0, 0, 0)
		if moveLeft then
			moveDir += Vector3.new(-SHOP_MOVE_SPEED, 0, 0)
		end
		if moveRight then
			moveDir += Vector3.new(SHOP_MOVE_SPEED, 0, 0)
		end
		if moveForward then
			moveDir += Vector3.new(0, 0, -SHOP_MOVE_SPEED)
		end
		if moveBackward then
			moveDir += Vector3.new(0, 0, SHOP_MOVE_SPEED)
		end
		moveVec = moveDir
	else
		-- Running mode (constant forward motion)
		moveVec = Vector3.new(0, 0, -(FORWARD_SPEED + permanentSpeedBonus) * speedBoostMultiplier)

		-- add left/right strafing
		if moveLeft then
			moveVec += Vector3.new(-STRAFE_SPEED, 0, 0)
		end
		if moveRight then
			moveVec += Vector3.new(STRAFE_SPEED, 0, 0)
		end
	end

	-- tell the humanoid to move in that direction (world space)
	hum:Move(moveVec, true)

	-- If in shop with no movement input, zero out horizontal velocity to stop forward drift
	if inShop and moveVec.Magnitude == 0 then
		hrp.Velocity = Vector3.new(0, hrp.Velocity.Y, 0)
	end
	-- trigger server for next segment (only if not in shop)
	if not inShop and hrp.Position.Z <= nextTriggerZ then
		advanceEvent:FireServer()
		nextTriggerZ = nextTriggerZ - SEGMENT_LENGTH
	end

	-- Lock camera behind player (behind by 15 studs, up by 8 studs)
	if hrp then
		local cameraDistance = 15
		local cameraHeight = 8
		local cameraPosition = hrp.Position + Vector3.new(0, cameraHeight, cameraDistance)
		camera.CFrame = CFrame.new(cameraPosition, hrp.Position + Vector3.new(0, 2, 0))
	end
end)