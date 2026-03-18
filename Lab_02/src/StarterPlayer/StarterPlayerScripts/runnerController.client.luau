--[[
  runnerController.client.luau - Mob Chase Escape Runner Client
  ==============================================================

  Controls:
  A/Left  - Move left on track
  D/Right - Move right on track

  Escape Objective:
  - Collect coins to purchase speed upgrades (Fibonacci sequence: 1, 1, 2, 3, 5, 8...)
  - Avoid or outrun chasing mobs that get faster over time
  - Avoid stationary mobs and lava on sides
  - Reach the finish line at 1000m to escape safely
  - Mid-line at 500m: mobs pause then speed up significantly

  UI:
  - Health indicator
  - Coins counter
  - Speed meter
  - Distance tracker
  - Current Fibonacci upgrade level and next cost
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for Remote Events
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerMoveEvt = Remotes:WaitForChild("PlayerMove")
local FreeMovementEvt = Remotes:WaitForChild("FreeMovement")
local ManualUpgradeEvt = Remotes:WaitForChild("ManualUpgrade")
local RequestRunEvt = Remotes:WaitForChild("RequestRun")

-- Receive events from server
local SpeedUpdateEvt = Remotes:WaitForChild("SpeedUpdate")
local HealthUpdateEvt = Remotes:WaitForChild("HealthUpdate")
local RunEndEvt = Remotes:WaitForChild("RunEnd")
local RunStartEvt = Remotes:WaitForChild("RunStart")
local BiomeChangeEvt = Remotes:WaitForChild("BiomeChange")
local CurrencyUpdateEvt = Remotes:WaitForChild("CurrencyUpdate")
local CoinCollectedEvt = Remotes:WaitForChild("CoinCollected")
local MilestoneEvt = Remotes:WaitForChild("MilestoneUIEvent")
local MobDamageEvt = Remotes:WaitForChild("MobDamage")
local SpeedUpgradeEvt = Remotes:WaitForChild("SpeedUpgrade")
local LavaHitEvt = Remotes:WaitForChild("LavaHit")
local MobSpawnEvt = Remotes:WaitForChild("MobSpawn")
local ZoneEnterEvt = Remotes:WaitForChild("ZoneEnter")

-- Game State
local inRun = false
local moveSpeed = 1.2 -- Studs per frame for free walking movement

-- UI State
local health = 3
local maxHealth = 3
local coins = 0
local speed = 0
local fibUpgradeLevel = 0
local distance = 0

-- Free walking input state
local movementKeys = {
    W = false,
    A = false,
    S = false,
    D = false,
    Space = false
}

-- Input handling with cooldowns
local inputCooldown = 0.15  -- Prevent spam clicking
local lastInputTime = 0

local function canInput()
    return os.clock() - lastInputTime >= inputCooldown
end

local function recordInput()
    lastInputTime = os.clock()
end

-- Free walking movement system
local function updateMovement()
    if not inRun then
        if movementLabel then
            movementLabel.Text = "Movement: Waiting for run"
            movementLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        end
        return
    end

    local moveVector = Vector3.new(0, 0, 0)
    local anyMovement = false
    local activeKeys = {}

    -- Calculate movement vector based on key states (full directional control)
    if movementKeys.W then
        moveVector = moveVector + Vector3.new(0, 0, -moveSpeed)
        anyMovement = true
        table.insert(activeKeys, "W")
    end    -- Forward
    if movementKeys.S then
        moveVector = moveVector + Vector3.new(0, 0, moveSpeed)
        anyMovement = true
        table.insert(activeKeys, "S")
    end     -- Backward
    if movementKeys.A then
        moveVector = moveVector + Vector3.new(-moveSpeed, 0, 0)
        anyMovement = true
        table.insert(activeKeys, "A")
    end    -- Left
    if movementKeys.D then
        moveVector = moveVector + Vector3.new(moveSpeed, 0, 0)
        anyMovement = true
        table.insert(activeKeys, "D")
    end     -- Right
    if movementKeys.Space then
        moveVector = moveVector + Vector3.new(0, moveSpeed * 0.5, 0)
        anyMovement = true
        table.insert(activeKeys, "Space")
    end -- Jump/Up

    -- Update movement indicator
    if anyMovement then
        movementLabel.Text = "Movement: " .. table.concat(activeKeys, "+")
        movementLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        FreeMovementEvt:FireServer(moveVector)
        -- Debug: Print movement (remove this later if needed)
        -- print("[Movement] Sending:", moveVector)
    else
        movementLabel.Text = "Movement: Ready"
        movementLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
    end
end

-- Key state management
local function setKeyState(key, state)
    if movementKeys[key] ~= nil then
        movementKeys[key] = state
    end
end

-- Bind input actions for free walking
local function bindInputs()
    -- WASD Movement
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
end

bindInputs()

-- Movement update loop
RunService.Heartbeat:Connect(updateMovement)

-- UI Creation helpers
local function createFrame(props)
    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(20, 25, 30)
    frame.BackgroundTransparency = props.BackgroundTransparency or 0.05 -- Less transparent for better visibility
    frame.BorderSizePixel = 2 -- Add border for better visibility
    frame.BorderColor3 = Color3.fromRGB(100, 100, 100) -- Gray border
    frame.Size = props.Size or UDim2.new(0, 200, 0, 100)
    frame.Position = props.Position or UDim2.new(0, 10, 0, 10)
    frame.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
    frame.ZIndex = props.ZIndex or 2 -- Ensure it's above background
    if props.Parent then
        frame.Parent = props.Parent
    end
    return frame
end

local function createLabel(props)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = props.BackgroundTransparency or 1
    label.Size = props.Size or UDim2.new(1, -12, 0, 30)
    label.Position = props.Position or UDim2.new(0, 6, 0, 6)
    label.Font = props.Font or Enum.Font.GothamSemibold
    label.TextColor3 = props.TextColor3 or Color3.fromRGB(255, 255, 255)
    label.TextScaled = props.TextScaled ~= false
    label.TextSize = props.TextSize or 16 -- Larger default text size
    label.Text = props.Text or ""
    label.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    label.TextStrokeTransparency = 0.5 -- Add text stroke for better visibility
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.ZIndex = props.ZIndex or 3 -- Above frames
    if props.Parent then
        label.Parent = props.Parent
    end
    return label
end

local function createButton(props)
    local button = Instance.new("TextButton")
    button.Size = props.Size or UDim2.new(1, -12, 0, 35)
    button.Position = props.Position or UDim2.new(0, 6, 0, 6)
    button.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(45, 55, 65)
    button.BorderSizePixel = 2
    button.BorderColor3 = Color3.fromRGB(100, 100, 100)
    button.Font = props.Font or Enum.Font.Gotham
    button.TextColor3 = props.TextColor3 or Color3.fromRGB(255, 255, 255)
    button.TextScaled = props.TextScaled ~= false
    button.TextSize = props.TextSize or 16
    button.Text = props.Text or "Button"
    button.TextStrokeTransparency = 0.5
    button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    button.ZIndex = props.ZIndex or 3
    if props.Parent then
        button.Parent = props.Parent
    end

    -- Add hover effect
    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = Color3.fromRGB(60, 70, 80)
    end)
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(45, 55, 65)
    end)

    return button
end

-- Main UI Setup
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RunnerHUD"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100 -- Ensure it appears above other GUIs
screenGui.Parent = playerGui

print("[RunnerController] Creating streamlined UI elements...")

-- Main Game UI (Top-left corner)
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 280, 0, 140)
mainFrame.Position = UDim2.new(0.02, 0, 0.05, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 20, 25)
mainFrame.BackgroundTransparency = 0.05
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Thickness = 3
mainStroke.Color = Color3.fromRGB(100, 100, 100)
mainStroke.Parent = mainFrame

-- Speed Display (Large and prominent)
local speedDisplay = Instance.new("TextLabel")
speedDisplay.Size = UDim2.new(1, -12, 0, 35)
speedDisplay.Position = UDim2.new(0, 6, 0, 8)
speedDisplay.BackgroundTransparency = 1
speedDisplay.Text = "🚀 SPEED: 1.0x"
speedDisplay.TextColor3 = Color3.fromRGB(100, 255, 100)
speedDisplay.Font = Enum.Font.GothamBold
speedDisplay.TextScaled = true
speedDisplay.TextStrokeTransparency = 0.3
speedDisplay.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
speedDisplay.Parent = mainFrame

-- Coins Display
local coinsDisplay = Instance.new("TextLabel")
coinsDisplay.Size = UDim2.new(0.5, -10, 0, 28)
coinsDisplay.Position = UDim2.new(0, 6, 0, 45)
coinsDisplay.BackgroundTransparency = 1
coinsDisplay.Text = "💰 0"
coinsDisplay.TextColor3 = Color3.fromRGB(255, 215, 0)
coinsDisplay.Font = Enum.Font.GothamBold
coinsDisplay.TextScaled = true
coinsDisplay.TextStrokeTransparency = 0.3
coinsDisplay.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
coinsDisplay.Parent = mainFrame

-- Distance Display
local distanceDisplay = Instance.new("TextLabel")
distanceDisplay.Size = UDim2.new(0.5, -10, 0, 28)
distanceDisplay.Position = UDim2.new(0.5, 4, 0, 45)
distanceDisplay.BackgroundTransparency = 1
distanceDisplay.Text = "📏 0/1000m"
distanceDisplay.TextColor3 = Color3.fromRGB(100, 200, 255)
distanceDisplay.Font = Enum.Font.GothamBold
distanceDisplay.TextScaled = true
distanceDisplay.TextStrokeTransparency = 0.3
distanceDisplay.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
distanceDisplay.Parent = mainFrame

-- Health Display
local healthDisplay = Instance.new("TextLabel")
healthDisplay.Size = UDim2.new(0.5, -10, 0, 25)
healthDisplay.Position = UDim2.new(0, 6, 0, 75)
healthDisplay.BackgroundTransparency = 1
healthDisplay.Text = "❤️ 3/3"
healthDisplay.TextColor3 = Color3.fromRGB(255, 100, 100)
healthDisplay.Font = Enum.Font.GothamSemibold
healthDisplay.TextScaled = true
healthDisplay.TextStrokeTransparency = 0.3
healthDisplay.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
healthDisplay.Parent = mainFrame

-- Status Display (for progress messages)
local statusDisplay = Instance.new("TextLabel")
statusDisplay.Size = UDim2.new(0.5, -10, 0, 25)
statusDisplay.Position = UDim2.new(0.5, 4, 0, 75)
statusDisplay.BackgroundTransparency = 1
statusDisplay.Text = "🏃 RUN!"
statusDisplay.TextColor3 = Color3.fromRGB(255, 255, 100)
statusDisplay.Font = Enum.Font.GothamSemibold
statusDisplay.TextScaled = true
statusDisplay.TextStrokeTransparency = 0.3
statusDisplay.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
statusDisplay.Parent = mainFrame

-- Upgrade Button (Bottom of main frame)
local upgradeButton = Instance.new("TextButton")
upgradeButton.Size = UDim2.new(1, -12, 0, 30)
upgradeButton.Position = UDim2.new(0, 6, 0, 104)
upgradeButton.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
upgradeButton.Text = "🚀 UPGRADE SPEED (1 💰)"
upgradeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
upgradeButton.Font = Enum.Font.GothamBold
upgradeButton.TextScaled = true
upgradeButton.TextStrokeTransparency = 0.3
upgradeButton.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
upgradeButton.Parent = mainFrame

local upgradeCorner = Instance.new("UICorner")
upgradeCorner.CornerRadius = UDim.new(0, 8)
upgradeCorner.Parent = upgradeButton

local upgradeStroke = Instance.new("UIStroke")
upgradeStroke.Thickness = 2
upgradeStroke.Color = Color3.fromRGB(150, 100, 200)
upgradeStroke.Parent = upgradeButton

-- Effect Popup System
local effectStyles = {
    SpeedUpgrade = {icon = "⚡", color = Color3.fromRGB(255, 180, 80), text = "SPEED BOOST!", font = Enum.Font.GothamBold},
    CoinCollected = {icon = "💰", color = Color3.fromRGB(255, 215, 0), text = "COIN!", font = Enum.Font.GothamBold},
    MobDamage = {icon = "💥", color = Color3.fromRGB(255, 50, 50), text = "HIT!", font = Enum.Font.GothamBold},
    LavaWarning = {icon = "🔥", color = Color3.fromRGB(255, 100, 0), text = "LAVA!", font = Enum.Font.GothamBold},
    MidLine = {icon = "⚠️", color = Color3.fromRGB(255, 200, 0), text = "MID-LINE!", font = Enum.Font.GothamBold},
    SafeZone = {icon = "🏁", color = Color3.fromRGB(100, 255, 100), text = "SAFE ZONE!", font = Enum.Font.GothamBold},
    RunStart = {icon = "🏃", color = Color3.fromRGB(100, 200, 255), text = "ESCAPE!", font = Enum.Font.GothamBold},
}

local popupFrame = Instance.new("Frame")
popupFrame.Size = UDim2.new(0, 240, 0, 60)
popupFrame.Position = UDim2.new(0.5, -120, 0.02, 0)
popupFrame.BackgroundTransparency = 1
popupFrame.Visible = false
popupFrame.Parent = screenGui

local popupCorner = Instance.new("UICorner")
popupCorner.CornerRadius = UDim.new(0, 18)
popupCorner.Parent = popupFrame

local popupStroke = Instance.new("UIStroke")
popupStroke.Thickness = 4
popupStroke.Color = Color3.fromRGB(255, 255, 255)
popupStroke.Parent = popupFrame

local popupIcon = Instance.new("TextLabel")
popupIcon.Size = UDim2.new(0, 50, 1, 0)
popupIcon.Position = UDim2.new(0, 0, 0, 0)
popupIcon.BackgroundTransparency = 1
popupIcon.TextScaled = true
popupIcon.Font = Enum.Font.GothamBold
popupIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
popupIcon.TextStrokeTransparency = 0.2
popupIcon.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
popupIcon.Parent = popupFrame

local popupText = Instance.new("TextLabel")
popupText.Size = UDim2.new(1, -56, 1, 0)
popupText.Position = UDim2.new(0, 56, 0, 0)
popupText.BackgroundTransparency = 1
popupText.TextScaled = true
popupText.Font = Enum.Font.GothamBold
popupText.TextColor3 = Color3.fromRGB(255, 255, 255)
popupText.TextStrokeTransparency = 0.2
popupText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
popupText.Parent = popupFrame

local popupTweening = false
local function showEffectPopup(effect)
    local style = effectStyles[effect]
    if not style or popupTweening then return end

    popupFrame.BackgroundTransparency = 0.1
    popupFrame.Visible = true
    popupFrame.BackgroundColor3 = style.color
    popupStroke.Color = style.color
    popupIcon.Text = style.icon
    popupIcon.TextColor3 = style.color
    popupIcon.Font = style.font
    popupText.Text = style.text
    popupText.TextColor3 = style.color
    popupText.Font = style.font

    -- Reset position and animate
    popupFrame.Position = UDim2.new(0.5, -120, 0.02, 0)
    popupFrame.Size = UDim2.new(0, 20, 0, 20)

    popupTweening = true

    -- Animate in
    local expandTween = TweenService:Create(popupFrame,
        TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Size = UDim2.new(0, 260, 0, 70)}
    )
    expandTween:Play()

    -- Wait then animate out
    task.delay(1.5, function()
        local shrinkTween = TweenService:Create(popupFrame,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                Position = UDim2.new(0.5, -120, -0.05, 0),
                Size = UDim2.new(0, 240, 0, 40),
                BackgroundTransparency = 1
            }
        )
        shrinkTween:Play()
        shrinkTween.Completed:Connect(function()
            popupFrame.Visible = false
            popupTweening = false
        end)
    end)
end

-- Start Button (Center screen when not in run)
local startFrame = createFrame({
    Size = UDim2.new(0, 200, 0, 80),
    Position = UDim2.new(0.5, -100, 0.5, -40),
    BackgroundColor3 = Color3.fromRGB(25, 35, 45),
    Parent = screenGui
})

local startButton = createButton({
    Size = UDim2.new(1, -12, 0, 60),
    Position = UDim2.new(0, 6, 0, 10),
    Text = "🏃 START ESCAPE RUN 🏃",
    BackgroundColor3 = Color3.fromRGB(50, 150, 50),
    TextSize = 18,
    Parent = startFrame
})

print("[RunnerController] Streamlined UI created successfully!")

-- Game Stats Panel
local statsFrame = createFrame({
    Size = UDim2.new(0, 280, 0, 180),
    Position = UDim2.new(0, 15, 0, 15),
    Parent = screenGui
})

local healthLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 5),
    Text = "Health: 3/3",
    TextColor3 = Color3.fromRGB(255, 100, 100),
    Parent = statsFrame
})

local coinsLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 30),
    Text = "💰 Coins: 0",
    TextColor3 = Color3.fromRGB(255, 215, 0),
    Font = Enum.Font.GothamBold,
    Parent = statsFrame
})

local speedLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 55),
    Text = "Speed: 1.0x",
    TextColor3 = Color3.fromRGB(100, 255, 100),
    Parent = statsFrame
})

local distanceLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 80),
    Text = "Distance: 0m",
    TextColor3 = Color3.fromRGB(100, 200, 255),
    Parent = statsFrame
})

local upgradeLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 105),
    Text = "Upgrade: Level 0 (Next: 1 coin)",
    TextColor3 = Color3.fromRGB(200, 100, 255),
    Parent = statsFrame
})

local objectiveLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 50),
    Position = UDim2.new(0, 6, 0, 130),
    Text = "ESCAPE TO 1000m!\nAvoid mobs and lava - collect coins for speed!",
    TextScaled = false,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(255, 255, 100),
    TextYAlignment = Enum.TextYAlignment.Top,
    Parent = statsFrame
})

-- Speed Overlay Panel
local speedOverlayFrame = createFrame({
    Size = UDim2.new(0, 320, 0, 140),
    Position = UDim2.new(0.5, -160, 1, -160),
    BackgroundColor3 = Color3.fromRGB(15, 20, 25),
    Parent = screenGui
})

local currentSpeedLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 30),
    Position = UDim2.new(0, 6, 0, 5),
    Text = "🚀 Current Speed: 1.0x",
    TextColor3 = Color3.fromRGB(100, 255, 100),
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    Parent = speedOverlayFrame
})

local upgradeInfoLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 35),
    Text = "Next Upgrade: 2x Speed for 1 💰",
    TextColor3 = Color3.fromRGB(200, 100, 255),
    TextSize = 14,
    Parent = speedOverlayFrame
})

local upgradeProgressLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 20),
    Position = UDim2.new(0, 6, 0, 60),
    Text = "Level 0 → Level 1",
    TextColor3 = Color3.fromRGB(150, 150, 150),
    TextSize = 12,
    Parent = speedOverlayFrame
})

local upgradeStatusLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 80),
    Text = "💡 Collect coins to upgrade speed!",
    TextColor3 = Color3.fromRGB(255, 255, 100),
    TextSize = 12,
    Parent = speedOverlayFrame
})

-- Manual Upgrade Button
local upgradeButton = createButton({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 105),
    Text = "🚀 UPGRADE SPEED (1 💰)",
    BackgroundColor3 = Color3.fromRGB(100, 50, 150),
    TextSize = 12,
    Parent = speedOverlayFrame
})

-- Movement Indicator
local movementFrame = createFrame({
    Size = UDim2.new(0, 150, 0, 50),
    Position = UDim2.new(0, 15, 1, -70),
    BackgroundColor3 = Color3.fromRGB(10, 15, 20),
    Parent = screenGui
})

local movementLabel = createLabel({
    Size = UDim2.new(1, -12, 1, -12),
    Position = UDim2.new(0, 6, 0, 6),
    Text = "Movement: Ready",
    TextColor3 = Color3.fromRGB(100, 200, 100),
    TextSize = 14,
    Font = Enum.Font.GothamBold,
    Parent = movementFrame
})
local controlFrame = createFrame({
    Size = UDim2.new(0, 200, 0, 60),
    Position = UDim2.new(1, -220, 0, 15),
    Parent = screenGui
})

local startButton = createButton({
    Size = UDim2.new(1, -12, 0, 50),
    Position = UDim2.new(0, 6, 0, 5),
    Text = "Start Escape Run",
    BackgroundColor3 = Color3.fromRGB(50, 150, 50),
    Parent = controlFrame
})

-- Game Info Panel
local infoFrame = createFrame({
    Size = UDim2.new(0, 300, 0, 200),
    Position = UDim2.new(1, -320, 0, 90),
    Parent = screenGui
})

local infoTitle = createLabel({
    Size = UDim2.new(1, -12, 0, 20),
    Position = UDim2.new(0, 6, 0, 5),
    Text = "Mob Chase Escape",
    Font = Enum.Font.GothamBold,
    TextColor3 = Color3.fromRGB(255, 100, 100),
    Parent = infoFrame
})

local controlsText = createLabel({
    Size = UDim2.new(1, -12, 0, 60),
    Position = UDim2.new(0, 6, 0, 25),
    Text = "Controls:\nW/Up - Move Forward\nS/Down - Move Backward\nA/Left - Move Left\nD/Right - Move Right\nSpace - Jump/Boost",
    TextScaled = false,
    TextSize = 14,
    TextColor3 = Color3.fromRGB(200, 200, 200),
    TextYAlignment = Enum.TextYAlignment.Top,
    Parent = infoFrame
})

local gameplayText = createLabel({
    Size = UDim2.new(1, -12, 1, -90),
    Position = UDim2.new(0, 6, 0, 90),
    Text = "• FREE MOVEMENT: Use WASD + Space for full 3D control\n• Collect gold coins to buy speed upgrades\n• Upgrades cost Fibonacci sequence (1,1,2,3,5,8...)\n• Each upgrade doubles your movement speed\n• Avoid massive mob walls - they get faster over time!\n• Avoid stationary red mobs on track\n• Stay away from lava on sides (kills you!)\n• Mid-line (500m): Creatures pause then speed up 2x\n• Finish line (1000m): SAFE ZONE - You escape!",
    TextScaled = false,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(180, 180, 180),
    TextYAlignment = Enum.TextYAlignment.Top,
    Parent = infoFrame
})

-- Central Overlay HUD (shown during runs)
local centralHUD = createFrame({
    Size = UDim2.new(0, 400, 0, 200),
    Position = UDim2.new(0.5, -200, 0.3, -100),
    BackgroundColor3 = Color3.fromRGB(15, 20, 30),
    BackgroundTransparency = 0.02,
    Visible = false,
    Parent = screenGui
})

-- Central status message
local centralStatusLabel = createLabel({
    Size = UDim2.new(1, -20, 0, 40),
    Position = UDim2.new(0, 10, 0, 10),
    Text = "🏃 Escape started! Reach 1000m to survive!",
    TextSize = 16,
    Font = Enum.Font.GothamBold,
    TextColor3 = Color3.fromRGB(255, 255, 100),
    Parent = centralHUD
})

-- Central speed display
local centralSpeedDisplay = createLabel({
    Size = UDim2.new(0.5, -15, 0, 30),
    Position = UDim2.new(0, 10, 0, 60),
    Text = "🚀 SPEED: 1.0x",
    TextSize = 14,
    Font = Enum.Font.Gotham,
    TextColor3 = Color3.fromRGB(100, 255, 100),
    Parent = centralHUD
})

-- Central coins display
local centralCoinsDisplay = createLabel({
    Size = UDim2.new(0.5, -15, 0, 30),
    Position = UDim2.new(0.5, 5, 0, 60),
    Text = "💰 0",
    TextSize = 14,
    Font = Enum.Font.Gotham,
    TextColor3 = Color3.fromRGB(255, 215, 0),
    Parent = centralHUD
})

-- Central distance display
local centralDistanceDisplay = createLabel({
    Size = UDim2.new(1, -20, 0, 30),
    Position = UDim2.new(0, 10, 0, 100),
    Text = "📏 0m / 1000m",
    TextSize = 14,
    Font = Enum.Font.Gotham,
    TextColor3 = Color3.fromRGB(100, 200, 255),
    Parent = centralHUD
})

-- Progress bar for central display
local progressBarFrame = createFrame({
    Size = UDim2.new(1, -20, 0, 8),
    Position = UDim2.new(0, 10, 0, 135),
    BackgroundColor3 = Color3.fromRGB(50, 50, 50),
    Parent = centralHUD
})

local progressBar = createFrame({
    Size = UDim2.new(0, 0, 1, 0),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundColor3 = Color3.fromRGB(100, 255, 100),
    Parent = progressBarFrame
})

-- Central upgrade info
local centralUpgradeLabel = createLabel({
    Size = UDim2.new(1, -20, 0, 25),
    Position = UDim2.new(0, 10, 0, 150),
    Text = "Next upgrade: 1 coin",
    TextSize = 12,
    Font = Enum.Font.Gotham,
    TextColor3 = Color3.fromRGB(200, 200, 200),
    Parent = centralHUD
})

-- Event handlers for start and upgrade buttons
startButton.MouseButton1Click:Connect(function()
    if not inRun then
        print("[RunnerController] Starting escape run...")
        RequestRunEvt:FireServer()
        startButton.Text = "🏃 ESCAPING... 🏃"
        startButton.BackgroundColor3 = Color3.fromRGB(150, 150, 50)

        -- Hide start frame
        local hideTween = TweenService:Create(startFrame,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {BackgroundTransparency = 1}
        )
        hideTween:Play()
        startFrame.Visible = false
    end
end)

upgradeButton.MouseButton1Click:Connect(function()
    if inRun then
        print("[RunnerController] Attempting speed upgrade...")
        ManualUpgradeEvt:FireServer()

        -- Visual feedback
        local originalColor = upgradeButton.BackgroundColor3
        upgradeButton.BackgroundColor3 = Color3.fromRGB(200, 150, 255)
        task.delay(0.1, function()
            upgradeButton.BackgroundColor3 = originalColor
        end)
    end
end)

-- Add hover effects
upgradeButton.MouseEnter:Connect(function()
    local hoverTween = TweenService:Create(upgradeButton,
        TweenInfo.new(0.1, Enum.EasingStyle.Quad),
        {BackgroundColor3 = Color3.fromRGB(120, 70, 180)}
    )
    hoverTween:Play()
end)

upgradeButton.MouseLeave:Connect(function()
    local leaveTween = TweenService:Create(upgradeButton,
        TweenInfo.new(0.1, Enum.EasingStyle.Quad),
        {BackgroundColor3 = Color3.fromRGB(100, 50, 150)}
    )
    leaveTween:Play()
end)

-- Function to update upgrade button state
local function updateUpgradeButton()
    local fibonacci = {1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144}
    local nextCost = fibonacci[fibUpgradeLevel + 1]

    if nextCost then
        local canAfford = coins >= nextCost
        upgradeButton.Text = string.format("🚀 UPGRADE SPEED (%d 💰)", nextCost)

        -- Update central upgrade label
        centralUpgradeLabel.Text = string.format("Next upgrade: %d coins %s",
            nextCost, canAfford and "(Ready!)" or "")
        centralUpgradeLabel.TextColor3 = canAfford and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(200, 200, 200)

        if canAfford then
            upgradeButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
            upgradeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            upgradeStroke.Color = Color3.fromRGB(100, 255, 100)
        else
            upgradeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
            upgradeButton.TextColor3 = Color3.fromRGB(200, 200, 200)
            upgradeStroke.Color = Color3.fromRGB(255, 100, 100)
        end
    else
        upgradeButton.Text = "🏆 MAX SPEED REACHED!"
        upgradeButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
        upgradeButton.TextColor3 = Color3.fromRGB(0, 0, 0)
        upgradeStroke.Color = Color3.fromRGB(255, 255, 0)

        -- Update central upgrade label for max speed
        centralUpgradeLabel.Text = "🏆 MAX SPEED REACHED!"
        centralUpgradeLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    end
end

-- Continuous UI update system (like the example)
RunService.RenderStepped:Connect(function()
    local stats = player:FindFirstChild("leaderstats")
    if stats then
        -- Update coins display
        if stats:FindFirstChild("Coins") then
            coinsDisplay.Text = "💰 " .. stats.Coins.Value
        end

        -- Update distance display
        if stats:FindFirstChild("Distance") and stats:FindFirstChild("Till Home") then
            local current = stats.Distance.Value
            local remaining = stats["Till Home"].Value
            distanceDisplay.Text = string.format("📏 %dm/1000m", current)

            -- Progress-based status messages
            local progress = (current / 1000) * 100
            if progress >= 100 then
                statusDisplay.Text = "🎉 SAFE!"
                statusDisplay.TextColor3 = Color3.fromRGB(100, 255, 100)
            elseif progress >= 50 then
                statusDisplay.Text = string.format("⚠️ %.0f%%", progress)
                statusDisplay.TextColor3 = Color3.fromRGB(255, 200, 100)
            else
                statusDisplay.Text = string.format("🏃 %.0f%%", progress)
                statusDisplay.TextColor3 = Color3.fromRGB(255, 255, 100)
            end
        end

        -- Update speed display
        if stats:FindFirstChild("Speed") then
            local speedValue = stats.Speed.Value
            speedDisplay.Text = string.format("🚀 SPEED: %.1fx", speedValue)

            -- Color based on speed
            if speedValue >= 8 then
                speedDisplay.TextColor3 = Color3.fromRGB(255, 100, 255) -- Purple for high speed
            elseif speedValue >= 4 then
                speedDisplay.TextColor3 = Color3.fromRGB(255, 200, 100) -- Orange for medium speed
            else
                speedDisplay.TextColor3 = Color3.fromRGB(100, 255, 100) -- Green for normal speed
            end
        end
    end

    -- Dynamic border effects based on performance
    if coins >= 20 then
        -- Rainbow border for high coin count
        local hue = (tick() % 3) / 3
        mainStroke.Color = Color3.fromHSV(hue, 0.8, 1)
    elseif fibUpgradeLevel >= 5 then
        -- Gold border for high upgrade level
        mainStroke.Color = Color3.fromRGB(255, 215, 0)
    else
        -- Default gray border
        mainStroke.Color = Color3.fromRGB(100, 100, 100)
    end

    -- Update upgrade button based on current state
    updateUpgradeButton()
end)

print("[RunnerController] UI created successfully!")

-- Server event handlers
SpeedUpdateEvt.Event:Connect(function(newSpeed)
    print("[RunnerController] Speed update:", newSpeed)
    speed = newSpeed
    speedLabel.Text = string.format("Speed: %.1fx", speed)
    currentSpeedLabel.Text = string.format("🚀 Current Speed: %.1fx", speed)
    centralSpeedDisplay.Text = string.format("🚀 SPEED: %.1fx", speed)

    -- Update upgrade status
    local fibonacci = {1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144}
    local nextCost = fibonacci[fibUpgradeLevel + 1]
    if nextCost then
        upgradeInfoLabel.Text = string.format("Next Upgrade: %.1fx Speed for %d 💰", speed * 2, nextCost)
        upgradeStatusLabel.Text = coins >= nextCost and "✅ Ready to upgrade!" or "💡 Collect more coins to upgrade!"
        upgradeStatusLabel.TextColor3 = coins >= nextCost and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 255, 100)
    else
        upgradeInfoLabel.Text = "🏆 MAX SPEED REACHED!"
        upgradeStatusLabel.Text = "🎉 You have reached maximum speed!"
        upgradeStatusLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    end

    -- Update upgrade button
    updateUpgradeButton()
end)

HealthUpdateEvt.Event:Connect(function(newHealth, newMaxHealth)
    print("[RunnerController] Health update:", newHealth, "/", newMaxHealth)
    health = newHealth
    maxHealth = newMaxHealth
    healthLabel.Text = string.format("Health: %d/%d", health, maxHealth)
end)

CurrencyUpdateEvt.Event:Connect(function(newCoins)
    print("[RunnerController] Currency update:", newCoins)
    coins = newCoins
    coinsLabel.Text = string.format("💰 Coins: %d", coins)
    centralCoinsDisplay.Text = string.format("💰 %d", coins)

    -- Update upgrade button state when coins change
    updateUpgradeButton()
end)

-- Enhanced coin collection feedback
CoinCollectedEvt.Event:Connect(function(coinValue, worldPosition)
    print("[RunnerController] Coin collected! Value:", coinValue)

    -- Update coin display with animation
    coins = coins + coinValue
    coinsLabel.Text = string.format("💰 Coins: %d", coins)
    centralCoinsDisplay.Text = string.format("💰 %d", coins)

    -- Create flying coin animation
    local gui = Instance.new("ScreenGui")
    gui.Name = "CoinCollected"
    gui.Parent = playerGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 100, 0, 50)
    label.BackgroundTransparency = 1
    label.Text = "+" .. coinValue .. " 💰"
    label.TextColor3 = Color3.fromRGB(255, 215, 0)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = gui

    -- Convert world position to screen position
    local camera = Workspace.CurrentCamera
    local screenPos, onScreen = camera:WorldToScreenPoint(worldPosition)

    if onScreen then
        label.Position = UDim2.new(0, screenPos.X - 50, 0, screenPos.Y - 25)
    else
        label.Position = UDim2.new(0.5, -50, 0.5, -25)
    end

    -- Animate the label flying up and fading
    local tween = TweenService:Create(label,
        TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Position = UDim2.new(label.Position.X.Scale, label.Position.X.Offset,
                               label.Position.Y.Scale, label.Position.Y.Offset - 100),
            TextTransparency = 1
        }
    )
    tween:Play()
    tween.Completed:Connect(function()
        gui:Destroy()
    end)

    -- Animate the coins labels for feedback
    local scaleTween = TweenService:Create(coinsLabel,
        TweenInfo.new(0.3, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
        { TextSize = coinsLabel.TextSize * 1.2 }
    )
    scaleTween:Play()
    scaleTween.Completed:Connect(function()
        local backTween = TweenService:Create(coinsLabel,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextSize = coinsLabel.TextSize / 1.2 }
        )
        backTween:Play()
    end)

    -- Also animate the central coins display
    local centralScaleTween = TweenService:Create(centralCoinsDisplay,
        TweenInfo.new(0.3, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
        { TextSize = 28 }
    )
    centralScaleTween:Play()
    centralScaleTween.Completed:Connect(function()
        local centralBackTween = TweenService:Create(centralCoinsDisplay,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextSize = 24 }
        )
        centralBackTween:Play()
    end)

    -- Update speed overlay upgrade status
    local fibonacci = {1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144}
    local nextCost = fibonacci[fibUpgradeLevel + 1]
    if nextCost then
        upgradeStatusLabel.Text = coins >= nextCost and "✅ Ready to upgrade!" or "💡 Collect more coins to upgrade!"
        upgradeStatusLabel.TextColor3 = coins >= nextCost and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 255, 100)
    end

    -- Update upgrade button
    updateUpgradeButton()
end)

MilestoneEvt.Event:Connect(function(dist)
    print("[RunnerController] Distance milestone:", dist)
    distance = dist
    distanceLabel.Text = string.format("Distance: %dm", distance)
    local remaining = math.max(0, 1000 - distance)
    centralDistanceDisplay.Text = string.format("📏 %dm / 1000m", distance)

    -- Update progress bar
    local progressPercent = (distance / 1000) * 100
    progressBar.Size = UDim2.new(math.min(progressPercent / 100, 1), 0, 1, 0)

    -- Show progress in central status
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
    print("[RunnerController] Speed upgrade:", level, "cost was", cost)
    fibUpgradeLevel = level
    local fibonacci = {1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144}
    local nextCost = fibonacci[fibUpgradeLevel + 1] or "MAX"

    -- Update main upgrade label
    upgradeLabel.Text = string.format("Upgrade: Level %d (Next: %s coin%s)",
        fibUpgradeLevel, tostring(nextCost), nextCost == 1 and "" or "s")

    -- Update speed overlay
    upgradeProgressLabel.Text = string.format("Level %d → Level %d", level - 1, level)

    if nextCost ~= "MAX" then
        upgradeInfoLabel.Text = string.format("Next Upgrade: %.1fx Speed for %s 💰", speed * 2, tostring(nextCost))
        upgradeStatusLabel.Text = coins >= nextCost and "✅ Ready to upgrade!" or "💡 Collect more coins to upgrade!"
        upgradeStatusLabel.TextColor3 = coins >= nextCost and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 255, 100)
    else
        upgradeInfoLabel.Text = "🏆 MAX SPEED REACHED!"
        upgradeStatusLabel.Text = "🎉 You have reached maximum speed!"
        upgradeStatusLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    end

    -- Upgrade animation
    local upgradeTween = TweenService:Create(currentSpeedLabel,
        TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
        { TextSize = 24 }
    )
    upgradeTween:Play()
    upgradeTween.Completed:Connect(function()
        local backTween = TweenService:Create(currentSpeedLabel,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextSize = 18 }
        )
        backTween:Play()
    end)

    -- Update upgrade button
    updateUpgradeButton()
end)

RunStartEvt.Event:Connect(function()
    print("[RunnerController] Run started!")
    inRun = true
    startButton.Text = "In Progress"
    startButton.BackgroundColor3 = Color3.fromRGB(150, 100, 50)

    -- Show central HUD and fade in
    centralHUD.Visible = true
    centralHUD.BackgroundTransparency = 1
    local fadeIn = TweenService:Create(centralHUD,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.02 }
    )
    fadeIn:Play()

    -- Update central status
    centralStatusLabel.Text = "🏃 Escape started! Reach 1000m to survive!"
    centralStatusLabel.TextColor3 = Color3.fromRGB(255, 255, 100)

    -- Initialize upgrade button state
    updateUpgradeButton()
end)

RunEndEvt.Event:Connect(function(results)
    print("[RunnerController] Run ended:", results)
    inRun = false
    startButton.Text = "Start Escape Run"
    startButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)

    -- Show run results in central HUD
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

    print("Escape attempt complete! Result:", escaped)
    print("Distance:", results.distance, "Score:", results.score)
    print("Coins collected:", results.coins)

    if results.escaped then
        print("🎉 CONGRATULATIONS! You successfully escaped the mob chase! 🎉")
    else
        print("💀 You were caught by the mobs. Try again!")
    end

    -- Hide central HUD after 5 seconds
    task.delay(5, function()
        if not inRun then
            local fadeOut = TweenService:Create(centralHUD,
                TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { BackgroundTransparency = 1 }
            )
            fadeOut:Play()
            fadeOut.Completed:Connect(function()
                if not inRun then
                    centralHUD.Visible = false
                end
            end)
        end
    end)
end)

BiomeChangeEvt.Event:Connect(function(biomeName)
    print("🌍 Biome changed to:", biomeName)
end)

-- New game-specific event handlers
MobDamageEvt.Event:Connect(function(mobType)
    -- Visual feedback for mob damage with screen shake effect
    print("💥 Hit by", mobType, "mob! Health lost!")

    -- Create a brief screen shake effect
    local camera = Workspace.CurrentCamera
    local originalCF = camera.CFrame
    for i = 1, 10 do
        local shakeOffset = Vector3.new(
            math.random(-2, 2),
            math.random(-2, 2),
            math.random(-2, 2)
        )
        camera.CFrame = originalCF + shakeOffset
        task.wait(0.05)
    end
    camera.CFrame = originalCF
end)

LavaHitEvt.Event:Connect(function(bodyPart)
    -- Visual feedback for lava damage with red screen tint
    print("🔥 LAVA WARNING: Your", bodyPart, "is being consumed!")

    -- Create a red warning overlay
    local gui = Instance.new("ScreenGui")
    gui.Name = "LavaWarning"
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    frame.BackgroundTransparency = 0.7
    frame.BorderSizePixel = 0
    frame.Parent = gui

    -- Fade out the warning
    local tween = TweenService:Create(frame,
        TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 1}
    )
    tween:Play()
    tween.Completed:Connect(function()
        gui:Destroy()
    end)
end)

MobSpawnEvt.Event:Connect(function(mobType, position)
    -- Enhanced visual feedback for mob spawning
    print("⚠️ DANGER: A", mobType, "creature has spawned behind you!")
    print("🏃‍♂️ RUN FASTER! It's getting closer!")
end)

ZoneEnterEvt.Event:Connect(function(zoneType)
    if zoneType == "midline" then
        print("⚠️ MID-LINE REACHED! Mobs pause for 3 seconds then speed up 2x!")
    elseif zoneType == "safezone" then
        print("🏁 FINISH LINE! You're safe from the mobs!")
    end
end)

print("[RunnerController] 🏃 Streamlined mob chase escape client loaded! 🏃")
print("🎮 New UI Features: Compact HUD, Effect popups, Dynamic colors, Smooth animations!")
print("🚀 Experience the escape with crystal clear visual feedback!")
print("[RunnerController] Client initialization complete!")

-- Initialize UI state
mainFrame.Visible = false
startFrame.Visible = true

-- Enhanced streamlined event handlers (override old ones with improved versions)
-- These will work with the new UI system while maintaining compatibility
local function handleSpeedUpdate(newSpeed)
    speed = newSpeed
    if speed > 1 then
        showEffectPopup("SpeedUpgrade")
    end
end

local function handleCoinCollection(coinValue, worldPosition)
    coins = coins + coinValue
    showEffectPopup("CoinCollected")

    -- Flying coin animation
    local flyingCoin = Instance.new("TextLabel")
    flyingCoin.Size = UDim2.new(0, 50, 0, 30)
    flyingCoin.BackgroundTransparency = 1
    flyingCoin.Text = "+" .. coinValue .. "💰"
    flyingCoin.TextColor3 = Color3.fromRGB(255, 215, 0)
    flyingCoin.TextScaled = true
    flyingCoin.Font = Enum.Font.GothamBold
    flyingCoin.TextStrokeTransparency = 0.3
    flyingCoin.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    flyingCoin.Parent = screenGui
    flyingCoin.Position = UDim2.new(0, 300, 0, 60)

    local flyTween = TweenService:Create(flyingCoin,
        TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Position = UDim2.new(0.02, 150, 0.05, 45),
            TextTransparency = 1
        }
    )
    flyTween:Play()
    flyTween.Completed:Connect(function()
        flyingCoin:Destroy()
    end)
end

local function handleUpgrade(level, cost)
    fibUpgradeLevel = level
    showEffectPopup("SpeedUpgrade")

    -- Animate main frame
    local expandTween = TweenService:Create(mainFrame,
        TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Size = UDim2.new(0, 290, 0, 150)}
    )
    expandTween:Play()
    expandTween.Completed:Connect(function()
        local contractTween = TweenService:Create(mainFrame,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = UDim2.new(0, 280, 0, 140)}
        )
        contractTween:Play()
    end)
end

local function handleRunStart()
    inRun = true
    showEffectPopup("RunStart")

    -- Show main UI with animation
    mainFrame.Visible = true
    mainFrame.BackgroundTransparency = 1
    local fadeIn = TweenService:Create(mainFrame,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0.05}
    )
    fadeIn:Play()

    -- Hide start frame
    local fadeOut = TweenService:Create(startFrame,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 1}
    )
    fadeOut:Play()
    fadeOut.Completed:Connect(function()
        startFrame.Visible = false
    end)
end

local function handleRunEnd(results)
    inRun = false

    if results.escaped then
        showEffectPopup("SafeZone")
    end

    -- Show result message
    statusDisplay.Text = results.escaped and "🎉 ESCAPED!" or "💀 CAUGHT"
    statusDisplay.TextColor3 = results.escaped and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 50, 50)

    -- Flash effect
    local flashColor = results.escaped and Color3.fromRGB(20, 60, 20) or Color3.fromRGB(60, 20, 20)
    local flash = TweenService:Create(mainFrame,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, true),
        {BackgroundColor3 = flashColor}
    )
    flash:Play()
    flash.Completed:Connect(function()
        mainFrame.BackgroundColor3 = Color3.fromRGB(15, 20, 25)
    end)

    -- Show start frame again after delay
    task.delay(3, function()
        startFrame.Visible = true
        startFrame.BackgroundTransparency = 1
        local showStart = TweenService:Create(startFrame,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.05}
        )
        showStart:Play()

        -- Hide main UI
        local hideMain = TweenService:Create(mainFrame,
            TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 1}
        )
        hideMain:Play()
        hideMain.Completed:Connect(function()
            mainFrame.Visible = false
        end)
    end)
end

-- Connect enhanced handlers alongside existing ones for compatibility
SpeedUpdateEvt.Event:Connect(handleSpeedUpdate)
CoinCollectedEvt.Event:Connect(handleCoinCollection)
SpeedUpgradeEvt.Event:Connect(handleUpgrade)
RunStartEvt.Event:Connect(handleRunStart)
RunEndEvt.Event:Connect(handleRunEnd)

-- Enhanced effect handlers
MobDamageEvt.Event:Connect(function(mobType)
    showEffectPopup("MobDamage")
    -- Screen shake
    local originalPos = mainFrame.Position
    for i = 1, 6 do
        mainFrame.Position = UDim2.new(
            originalPos.X.Scale, originalPos.X.Offset + math.random(-2, 2),
            originalPos.Y.Scale, originalPos.Y.Offset + math.random(-2, 2)
        )
        task.wait(0.02)
    end
    mainFrame.Position = originalPos
end)

LavaHitEvt.Event:Connect(function(bodyPart)
    showEffectPopup("LavaWarning")
end)

ZoneEnterEvt.Event:Connect(function(zoneType)
    if zoneType == "midline" then
        showEffectPopup("MidLine")
    elseif zoneType == "safezone" then
        showEffectPopup("SafeZone")
    end
end)