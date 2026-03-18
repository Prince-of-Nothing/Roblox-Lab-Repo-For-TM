--[[
  runnerController.client.luau - Mob Chase Escape Runner Client
  ================================================================

  Controls: WASD + Space for movement
  Objective: Reach 1000m to escape, collect coins, upgrade speed
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

print("🟢 [RunnerController] Client script started!")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for Remote Events
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not Remotes then
    warn("❌ [RunnerController] Failed to find Remotes folder!")
    return
end

local FreeMovementEvt = Remotes:WaitForChild("FreeMovement", 5)
local ManualUpgradeEvt = Remotes:WaitForChild("ManualUpgrade", 5)
local RequestRunEvt = Remotes:WaitForChild("RequestRun", 5)

-- Server events
local SpeedUpdateEvt = Remotes:WaitForChild("SpeedUpdate", 5)
local HealthUpdateEvt = Remotes:WaitForChild("HealthUpdate", 5)
local RunEndEvt = Remotes:WaitForChild("RunEnd", 5)
local RunStartEvt = Remotes:WaitForChild("RunStart", 5)
local CurrencyUpdateEvt = Remotes:WaitForChild("CurrencyUpdate", 5)
local CoinCollectedEvt = Remotes:WaitForChild("CoinCollected", 5)
local MilestoneEvt = Remotes:WaitForChild("MilestoneUIEvent", 5)
local SpeedUpgradeEvt = Remotes:WaitForChild("SpeedUpgrade", 5)

print("✅ [RunnerController] All RemoteEvents loaded!")

-- Game State
local inRun = false
local moveSpeed = 1.2
local health = 3
local maxHealth = 3
local coins = 0
local speed = 1
local fibUpgradeLevel = 0
local distance = 0

-- Movement system
local movementKeys = {W = false, A = false, S = false, D = false, Space = false}

local function setKeyState(key, state)
    if movementKeys[key] then
        movementKeys[key] = state
    end
end

local function updateMovement()
    if not inRun then return end

    local moveVector = Vector3.new(0, 0, 0)

    if movementKeys.W then moveVector = moveVector + Vector3.new(0, 0, -moveSpeed) end
    if movementKeys.S then moveVector = moveVector + Vector3.new(0, 0, moveSpeed) end
    if movementKeys.A then moveVector = moveVector + Vector3.new(-moveSpeed, 0, 0) end
    if movementKeys.D then moveVector = moveVector + Vector3.new(moveSpeed, 0, 0) end
    if movementKeys.Space then moveVector = moveVector + Vector3.new(0, moveSpeed * 0.5, 0) end

    if moveVector.Magnitude > 0 then
        FreeMovementEvt:FireServer(moveVector)
    end
end

-- Bind inputs
ContextActionService:BindAction("MoveForward", function(_, state)
    setKeyState("W", state == Enum.UserInputState.Begin)
    return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.W, Enum.KeyCode.Up)

ContextActionService:BindAction("MoveBackward", function(_, state)
    setKeyState("S", state == Enum.UserInputState.Begin)
    return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.S, Enum.KeyCode.Down)

ContextActionService:BindAction("MoveLeft", function(_, state)
    setKeyState("A", state == Enum.UserInputState.Begin)
    return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.A, Enum.KeyCode.Left)

ContextActionService:BindAction("MoveRight", function(_, state)
    setKeyState("D", state == Enum.UserInputState.Begin)
    return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.D, Enum.KeyCode.Right)

ContextActionService:BindAction("Jump", function(_, state)
    setKeyState("Space", state == Enum.UserInputState.Begin)
    return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Space)

RunService.Heartbeat:Connect(updateMovement)

-- UI Creation
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RunnerHUD"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

print("[RunnerController] Creating UI...")

-- Main Stats Panel (Top-left)
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 280, 0, 120)
mainFrame.Position = UDim2.new(0, 10, 0, 10)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 20, 25)
mainFrame.BackgroundTransparency = 0.1
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = mainFrame

-- Stats Labels
local healthLabel = Instance.new("TextLabel")
healthLabel.Size = UDim2.new(1, -10, 0, 20)
healthLabel.Position = UDim2.new(0, 5, 0, 5)
healthLabel.BackgroundTransparency = 1
healthLabel.Text = "❤️ Health: 3/3"
healthLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
healthLabel.Font = Enum.Font.Gotham
healthLabel.TextScaled = true
healthLabel.TextXAlignment = Enum.TextXAlignment.Left
healthLabel.Parent = mainFrame

local coinsLabel = Instance.new("TextLabel")
coinsLabel.Size = UDim2.new(1, -10, 0, 20)
coinsLabel.Position = UDim2.new(0, 5, 0, 25)
coinsLabel.BackgroundTransparency = 1
coinsLabel.Text = "💰 Coins: 0"
coinsLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
coinsLabel.Font = Enum.Font.Gotham
coinsLabel.TextScaled = true
coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
coinsLabel.Parent = mainFrame

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(1, -10, 0, 20)
speedLabel.Position = UDim2.new(0, 5, 0, 45)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "🚀 Speed: 1.0x"
speedLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
speedLabel.Font = Enum.Font.Gotham
speedLabel.TextScaled = true
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Parent = mainFrame

local distanceLabel = Instance.new("TextLabel")
distanceLabel.Size = UDim2.new(1, -10, 0, 20)
distanceLabel.Position = UDim2.new(0, 5, 0, 65)
distanceLabel.BackgroundTransparency = 1
distanceLabel.Text = "📏 Distance: 0m/1000m"
distanceLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
distanceLabel.Font = Enum.Font.Gotham
distanceLabel.TextScaled = true
distanceLabel.TextXAlignment = Enum.TextXAlignment.Left
distanceLabel.Parent = mainFrame

-- Upgrade Button
local upgradeButton = Instance.new("TextButton")
upgradeButton.Size = UDim2.new(1, -10, 0, 25)
upgradeButton.Position = UDim2.new(0, 5, 0, 90)
upgradeButton.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
upgradeButton.Text = "🚀 UPGRADE SPEED (1 💰)"
upgradeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
upgradeButton.Font = Enum.Font.Gotham
upgradeButton.TextScaled = true
upgradeButton.BorderSizePixel = 0
upgradeButton.Parent = mainFrame

local upgradeCorner = Instance.new("UICorner")
upgradeCorner.CornerRadius = UDim.new(0, 6)
upgradeCorner.Parent = upgradeButton

-- Start Button (Center)
local startButton = Instance.new("TextButton")
startButton.Size = UDim2.new(0, 200, 0, 60)
startButton.Position = UDim2.new(0.5, -100, 0.5, -30)
startButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
startButton.Text = "🏃 START ESCAPE RUN 🏃"
startButton.TextColor3 = Color3.fromRGB(255, 255, 255)
startButton.Font = Enum.Font.GothamBold
startButton.TextScaled = true
startButton.BorderSizePixel = 0
startButton.Parent = screenGui

local startCorner = Instance.new("UICorner")
startCorner.CornerRadius = UDim.new(0, 12)
startCorner.Parent = startButton

-- CENTRAL OVERLAY (The main request)
local centralHUD = Instance.new("Frame")
centralHUD.Name = "CentralHUD"
centralHUD.Size = UDim2.new(0, 400, 0, 200)
centralHUD.Position = UDim2.new(0.5, -200, 0.3, -100)
centralHUD.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
centralHUD.BackgroundTransparency = 0.02
centralHUD.BorderSizePixel = 0
centralHUD.Visible = false
centralHUD.Parent = screenGui

local centralCorner = Instance.new("UICorner")
centralCorner.CornerRadius = UDim.new(0, 12)
centralCorner.Parent = centralHUD

local centralStroke = Instance.new("UIStroke")
centralStroke.Thickness = 2
centralStroke.Color = Color3.fromRGB(100, 100, 100)
centralStroke.Transparency = 0.3
centralStroke.Parent = centralHUD

-- Central overlay elements
local centralStatusLabel = Instance.new("TextLabel")
centralStatusLabel.Size = UDim2.new(1, -20, 0, 40)
centralStatusLabel.Position = UDim2.new(0, 10, 0, 10)
centralStatusLabel.BackgroundTransparency = 1
centralStatusLabel.Text = "🏃 Escape started! Reach 1000m to survive!"
centralStatusLabel.TextSize = 16
centralStatusLabel.Font = Enum.Font.GothamBold
centralStatusLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
centralStatusLabel.TextScaled = true
centralStatusLabel.Parent = centralHUD

local centralSpeedDisplay = Instance.new("TextLabel")
centralSpeedDisplay.Size = UDim2.new(0.5, -15, 0, 30)
centralSpeedDisplay.Position = UDim2.new(0, 10, 0, 60)
centralSpeedDisplay.BackgroundTransparency = 1
centralSpeedDisplay.Text = "🚀 SPEED: 1.0x"
centralSpeedDisplay.TextSize = 14
centralSpeedDisplay.Font = Enum.Font.Gotham
centralSpeedDisplay.TextColor3 = Color3.fromRGB(100, 255, 100)
centralSpeedDisplay.TextScaled = true
centralSpeedDisplay.Parent = centralHUD

local centralCoinsDisplay = Instance.new("TextLabel")
centralCoinsDisplay.Size = UDim2.new(0.5, -15, 0, 30)
centralCoinsDisplay.Position = UDim2.new(0.5, 5, 0, 60)
centralCoinsDisplay.BackgroundTransparency = 1
centralCoinsDisplay.Text = "💰 0"
centralCoinsDisplay.TextSize = 14
centralCoinsDisplay.Font = Enum.Font.Gotham
centralCoinsDisplay.TextColor3 = Color3.fromRGB(255, 215, 0)
centralCoinsDisplay.TextScaled = true
centralCoinsDisplay.Parent = centralHUD

local centralDistanceDisplay = Instance.new("TextLabel")
centralDistanceDisplay.Size = UDim2.new(1, -20, 0, 30)
centralDistanceDisplay.Position = UDim2.new(0, 10, 0, 100)
centralDistanceDisplay.BackgroundTransparency = 1
centralDistanceDisplay.Text = "📏 0m / 1000m"
centralDistanceDisplay.TextSize = 14
centralDistanceDisplay.Font = Enum.Font.Gotham
centralDistanceDisplay.TextColor3 = Color3.fromRGB(100, 200, 255)
centralDistanceDisplay.TextScaled = true
centralDistanceDisplay.Parent = centralHUD

-- Progress bar
local progressBarFrame = Instance.new("Frame")
progressBarFrame.Size = UDim2.new(1, -20, 0, 8)
progressBarFrame.Position = UDim2.new(0, 10, 0, 140)
progressBarFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
progressBarFrame.BorderSizePixel = 0
progressBarFrame.Parent = centralHUD

local progressBar = Instance.new("Frame")
progressBar.Size = UDim2.new(0, 0, 1, 0)
progressBar.Position = UDim2.new(0, 0, 0, 0)
progressBar.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
progressBar.BorderSizePixel = 0
progressBar.Parent = progressBarFrame

local centralUpgradeLabel = Instance.new("TextLabel")
centralUpgradeLabel.Size = UDim2.new(1, -20, 0, 25)
centralUpgradeLabel.Position = UDim2.new(0, 10, 0, 160)
centralUpgradeLabel.BackgroundTransparency = 1
centralUpgradeLabel.Text = "Next upgrade: 1 coin"
centralUpgradeLabel.TextSize = 12
centralUpgradeLabel.Font = Enum.Font.Gotham
centralUpgradeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
centralUpgradeLabel.TextScaled = true
centralUpgradeLabel.Parent = centralHUD

print("[RunnerController] Central HUD overlay created!")
print("[RunnerController] UI setup complete!")

-- Initialize UI state
mainFrame.Visible = false
startButton.Visible = true

-- Event Handlers
startButton.MouseButton1Click:Connect(function()
    if not inRun then
        print("[RunnerController] Starting escape run...")
        RequestRunEvt:FireServer()
        startButton.Text = "🏃 STARTING... 🏃"
        startButton.BackgroundColor3 = Color3.fromRGB(150, 150, 50)
    end
end)

upgradeButton.MouseButton1Click:Connect(function()
    if inRun then
        print("[RunnerController] Attempting speed upgrade...")
        ManualUpgradeEvt:FireServer()
    end
end)

-- Upgrade button state function
local function updateUpgradeButton()
    local fibonacci = {1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144}
    local nextCost = fibonacci[fibUpgradeLevel + 1]

    if nextCost then
        local canAfford = coins >= nextCost
        upgradeButton.Text = string.format("🚀 UPGRADE SPEED (%d 💰)", nextCost)
        upgradeButton.BackgroundColor3 = canAfford and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(150, 50, 50)

        centralUpgradeLabel.Text = string.format("Next upgrade: %d coins %s", nextCost, canAfford and "(Ready!)" or "")
        centralUpgradeLabel.TextColor3 = canAfford and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(200, 200, 200)
    else
        upgradeButton.Text = "🏆 MAX SPEED REACHED!"
        upgradeButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
        centralUpgradeLabel.Text = "🏆 MAX SPEED REACHED!"
        centralUpgradeLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    end
end

-- Server Event Handlers
SpeedUpdateEvt.Event:Connect(function(newSpeed)
    speed = newSpeed
    speedLabel.Text = string.format("🚀 Speed: %.1fx", speed)
    centralSpeedDisplay.Text = string.format("🚀 SPEED: %.1fx", speed)
    updateUpgradeButton()
end)

HealthUpdateEvt.Event:Connect(function(newHealth, newMaxHealth)
    health = newHealth
    maxHealth = newMaxHealth
    healthLabel.Text = string.format("❤️ Health: %d/%d", health, maxHealth)
end)

CurrencyUpdateEvt.Event:Connect(function(newCoins)
    coins = newCoins
    coinsLabel.Text = string.format("💰 Coins: %d", coins)
    centralCoinsDisplay.Text = string.format("💰 %d", coins)
    updateUpgradeButton()
end)

CoinCollectedEvt.Event:Connect(function(coinValue, worldPosition)
    coins = coins + coinValue
    coinsLabel.Text = string.format("💰 Coins: %d", coins)
    centralCoinsDisplay.Text = string.format("💰 %d", coins)
    updateUpgradeButton()
end)

MilestoneEvt.Event:Connect(function(dist)
    distance = dist
    distanceLabel.Text = string.format("📏 Distance: %dm/1000m", distance)
    centralDistanceDisplay.Text = string.format("📏 %dm / 1000m", distance)

    -- Update progress bar
    local progressPercent = (distance / 1000) * 100
    progressBar.Size = UDim2.new(math.min(progressPercent / 100, 1), 0, 1, 0)

    -- Update status message
    if progressPercent >= 100 then
        centralStatusLabel.Text = "🎉 ESCAPED! You reached the safe zone! 🎉"
        centralStatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    elseif progressPercent >= 50 then
        centralStatusLabel.Text = string.format("⚠️ MID-LINE PASSED! %.1f%% complete", progressPercent)
        centralStatusLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
    else
        centralStatusLabel.Text = string.format("🏃 %.1f%% to safety • Avoid mobs and lava!", progressPercent)
        centralStatusLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
    end
end)

SpeedUpgradeEvt.Event:Connect(function(level, cost)
    fibUpgradeLevel = level
    updateUpgradeButton()
end)

RunStartEvt.Event:Connect(function()
    print("[RunnerController] Run started - showing central overlay!")
    inRun = true

    -- Hide start button, show main UI
    startButton.Visible = false
    mainFrame.Visible = true

    -- Show central HUD overlay
    centralHUD.Visible = true
    centralHUD.BackgroundTransparency = 1

    local fadeIn = TweenService:Create(centralHUD,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.02 }
    )
    fadeIn:Play()

    centralStatusLabel.Text = "🏃 Escape started! Reach 1000m to survive!"
    centralStatusLabel.TextColor3 = Color3.fromRGB(255, 255, 100)

    updateUpgradeButton()
end)

RunEndEvt.Event:Connect(function(results)
    print("[RunnerController] Run ended!")
    inRun = false

    -- Show results in central HUD
    local escaped = results.escaped and "ESCAPED!" or "CAUGHT!"
    local resultColor = results.escaped and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)

    centralStatusLabel.Text = string.format("🏁 %s\nDistance: %dm • Coins: %d\nClick start to try again!",
        escaped, results.distance, results.coins)
    centralStatusLabel.TextColor3 = resultColor

    -- Flash the central HUD
    local flash = TweenService:Create(centralHUD,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, true),
        { BackgroundColor3 = resultColor }
    )
    flash:Play()

    -- Reset UI after delay
    task.delay(3, function()
        if not inRun then
            local fadeOut = TweenService:Create(centralHUD,
                TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { BackgroundTransparency = 1 }
            )
            fadeOut:Play()
            fadeOut.Completed:Connect(function()
                centralHUD.Visible = false
                mainFrame.Visible = false
                startButton.Visible = true
                startButton.Text = "🏃 START ESCAPE RUN 🏃"
                startButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
            end)
        end
    end)
end)

print("[RunnerController] 🏃 Simplified client loaded successfully! 🏃")