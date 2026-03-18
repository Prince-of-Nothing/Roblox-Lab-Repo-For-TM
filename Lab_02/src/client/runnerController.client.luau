--[[
  runnerController.client.luau - 5-Lane Endless Runner Client
  ==============================================================

  Controls:
  A/Left  - Switch to left lane
  D/Right - Switch to right lane
  Space   - Jump (clear low barriers)
  S/Down  - Slide (clear high barriers)

  Abilities (require charges):
  Q - Phase (pass through obstacles)
  E - Invincibility (no collision damage)
  R - Dash (instant lane teleport)
  T - Time Slow (reduce world speed)

  UI:
  - Health and shield indicators
  - Ability charge counter
  - Difficulty selection (Easy/Normal/Medium/Hard/Impossible)
  - Run start/restart controls
  - Real-time stats display
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
local LaneSwitchEvt = Remotes:WaitForChild("LaneSwitch")
local UseAbilityEvt = Remotes:WaitForChild("UseAbility")
local PlayerJumpEvt = Remotes:WaitForChild("PlayerJump")
local PlayerSlideEvt = Remotes:WaitForChild("PlayerSlide")
local SelectDiffEvt = Remotes:WaitForChild("SelectDifficulty")
local RequestRunEvt = Remotes:WaitForChild("RequestRun")

-- Receive events from server
local SpeedUpdateEvt = Remotes:WaitForChild("SpeedUpdate")
local HealthUpdateEvt = Remotes:WaitForChild("HealthUpdate")
local ShieldUpdateEvt = Remotes:WaitForChild("ShieldUpdate")
local AbilityUpdateEvt = Remotes:WaitForChild("AbilityUpdate")
local RunEndEvt = Remotes:WaitForChild("RunEnd")
local RunStartEvt = Remotes:WaitForChild("RunStart")
local BiomeChangeEvt = Remotes:WaitForChild("BiomeChange")
local CurrencyUpdateEvt = Remotes:WaitForChild("CurrencyUpdate")
local MilestoneEvt = Remotes:WaitForChild("MilestoneUIEvent")
local AbilityCDEvt = Remotes:WaitForChild("AbilityCooldown")

-- Game State
local currentLane = 3  -- Start in center lane (lanes 1-5)
local inRun = false
local selectedDifficulty = "normal"

-- UI State
local health = 3
local maxHealth = 3
local shields = 0
local abilityCharges = 1
local speed = 0
local currency = 0

-- Ability cooldowns (in seconds)
local abilityCooldowns = {
    phase = 0,
    invincibility = 0,
    dash = 0,
    timeslow = 0
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

-- Lane switching functions
local function switchLane(direction)
    if not inRun or not canInput() then return end

    local newLane = currentLane + direction
    if newLane >= 1 and newLane <= 5 then
        currentLane = newLane
        LaneSwitchEvt:FireServer(newLane)
        recordInput()
    end
end

local function switchLeft()
    switchLane(-1)
end

local function switchRight()
    switchLane(1)
end

-- Movement abilities
local function playerJump()
    if not inRun or not canInput() then return end
    PlayerJumpEvt:FireServer()
    recordInput()
end

local function playerSlide()
    if not inRun or not canInput() then return end
    PlayerSlideEvt:FireServer()
    recordInput()
end

-- Special abilities
local function useAbility(abilityType)
    if not inRun or abilityCooldowns[abilityType] > 0 then return end
    if abilityCharges <= 0 then return end

    UseAbilityEvt:FireServer(abilityType)
end

-- Bind input actions
local function bindInputs()
    -- Lane switching
    ContextActionService:BindAction("SwitchLeft", function(_, state)
        if state == Enum.UserInputState.Begin then
            switchLeft()
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.A, Enum.KeyCode.Left)

    ContextActionService:BindAction("SwitchRight", function(_, state)
        if state == Enum.UserInputState.Begin then
            switchRight()
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.D, Enum.KeyCode.Right)

    -- Jump and slide
    ContextActionService:BindAction("PlayerJump", function(_, state)
        if state == Enum.UserInputState.Begin then
            playerJump()
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.Space)

    ContextActionService:BindAction("PlayerSlide", function(_, state)
        if state == Enum.UserInputState.Begin then
            playerSlide()
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.S, Enum.KeyCode.Down)

    -- Abilities
    ContextActionService:BindAction("UsePhase", function(_, state)
        if state == Enum.UserInputState.Begin then
            useAbility("phase")
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.Q)

    ContextActionService:BindAction("UseInvincibility", function(_, state)
        if state == Enum.UserInputState.Begin then
            useAbility("invincibility")
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.E)

    ContextActionService:BindAction("UseDash", function(_, state)
        if state == Enum.UserInputState.Begin then
            useAbility("dash")
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.R)

    ContextActionService:BindAction("UseTimeslow", function(_, state)
        if state == Enum.UserInputState.Begin then
            useAbility("timeslow")
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.T)
end

bindInputs()

-- UI Creation helpers
local function createFrame(props)
    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(20, 25, 30)
    frame.BackgroundTransparency = props.BackgroundTransparency or 0.1
    frame.BorderSizePixel = 0
    frame.Size = props.Size or UDim2.new(0, 200, 0, 100)
    frame.Position = props.Position or UDim2.new(0, 10, 0, 10)
    frame.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
    if props.Parent then
        frame.Parent = props.Parent
    end
    return frame
end

local function createLabel(props)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = props.Size or UDim2.new(1, -12, 0, 30)
    label.Position = props.Position or UDim2.new(0, 6, 0, 6)
    label.Font = props.Font or Enum.Font.GothamSemibold
    label.TextColor3 = props.TextColor3 or Color3.fromRGB(255, 255, 255)
    label.TextScaled = props.TextScaled ~= false
    label.Text = props.Text or ""
    label.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
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
    button.BorderSizePixel = 0
    button.Font = props.Font or Enum.Font.Gotham
    button.TextColor3 = props.TextColor3 or Color3.fromRGB(255, 255, 255)
    button.TextScaled = props.TextScaled ~= false
    button.Text = props.Text or "Button"
    if props.Parent then
        button.Parent = props.Parent
    end
    return button
end

-- Main UI Setup
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RunnerHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Game Stats Panel
local statsFrame = createFrame({
    Size = UDim2.new(0, 280, 0, 120),
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

local shieldLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 30),
    Text = "Shields: 0",
    TextColor3 = Color3.fromRGB(100, 200, 255),
    Parent = statsFrame
})

local abilityLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 55),
    Text = "Abilities: 1",
    TextColor3 = Color3.fromRGB(200, 100, 255),
    Parent = statsFrame
})

local speedLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 80),
    Text = "Speed: 0.0",
    TextColor3 = Color3.fromRGB(100, 255, 100),
    Parent = statsFrame
})

-- Difficulty Selection Panel
local diffFrame = createFrame({
    Size = UDim2.new(0, 250, 0, 180),
    Position = UDim2.new(0, 15, 0, 150),
    Parent = screenGui
})

local diffTitle = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 5),
    Text = "Select Difficulty",
    Font = Enum.Font.GothamBold,
    TextColor3 = Color3.fromRGB(255, 220, 100),
    Parent = diffFrame
})

local difficulties = {"easy", "normal", "medium", "hard", "impossible"}
local difficultyNames = {"Easy", "Normal", "Medium", "Hard", "Impossible"}
local difficultyButtons = {}

for i, diff in ipairs(difficulties) do
    local button = createButton({
        Size = UDim2.new(1, -12, 0, 25),
        Position = UDim2.new(0, 6, 0, 25 + (i-1) * 30),
        Text = difficultyNames[i],
        Parent = diffFrame
    })

    button.MouseButton1Click:Connect(function()
        selectedDifficulty = diff
        -- Update button colors to show selection
        for j, btn in ipairs(difficultyButtons) do
            if j == i then
                btn.BackgroundColor3 = Color3.fromRGB(100, 150, 200)
            else
                btn.BackgroundColor3 = Color3.fromRGB(45, 55, 65)
            end
        end
    end)

    difficultyButtons[i] = button
end

-- Set normal as default selected
difficultyButtons[2].BackgroundColor3 = Color3.fromRGB(100, 150, 200)

-- Run Control Panel
local controlFrame = createFrame({
    Size = UDim2.new(0, 200, 0, 80),
    Position = UDim2.new(1, -220, 0, 15),
    Parent = screenGui
})

local startButton = createButton({
    Size = UDim2.new(1, -12, 0, 30),
    Position = UDim2.new(0, 6, 0, 8),
    Text = "Start Run",
    BackgroundColor3 = Color3.fromRGB(50, 150, 50),
    Parent = controlFrame
})

local currencyLabel = createLabel({
    Size = UDim2.new(1, -12, 0, 25),
    Position = UDim2.new(0, 6, 0, 45),
    Text = "Coins: 0",
    TextColor3 = Color3.fromRGB(255, 215, 0),
    Parent = controlFrame
})

-- Controls Info Panel
local controlsFrame = createFrame({
    Size = UDim2.new(0, 300, 0, 150),
    Position = UDim2.new(1, -320, 0, 110),
    Parent = screenGui
})

local controlsTitle = createLabel({
    Size = UDim2.new(1, -12, 0, 20),
    Position = UDim2.new(0, 6, 0, 5),
    Text = "Controls",
    Font = Enum.Font.GothamBold,
    TextColor3 = Color3.fromRGB(200, 200, 255),
    Parent = controlsFrame
})

local controlsText = createLabel({
    Size = UDim2.new(1, -12, 1, -30),
    Position = UDim2.new(0, 6, 0, 25),
    Text = "A/D - Switch Lanes\nSpace - Jump\nS - Slide\nQ - Phase\nE - Invincibility\nR - Dash\nT - Time Slow",
    TextScaled = false,
    TextSize = 14,
    TextColor3 = Color3.fromRGB(200, 200, 200),
    TextYAlignment = Enum.TextYAlignment.Top,
    Parent = controlsFrame
})

-- Event handlers for start button
startButton.MouseButton1Click:Connect(function()
    if not inRun then
        SelectDiffEvt:FireServer(selectedDifficulty)
        RequestRunEvt:FireServer()
        startButton.Text = "Running..."
        startButton.BackgroundColor3 = Color3.fromRGB(150, 150, 50)
    end
end)

-- Server event handlers
SpeedUpdateEvt.Event:Connect(function(newSpeed)
    speed = newSpeed
    speedLabel.Text = string.format("Speed: %.1f", speed)
end)

HealthUpdateEvt.Event:Connect(function(newHealth, newMaxHealth)
    health = newHealth
    maxHealth = newMaxHealth
    healthLabel.Text = string.format("Health: %d/%d", health, maxHealth)
end)

ShieldUpdateEvt.Event:Connect(function(newShields)
    shields = newShields
    shieldLabel.Text = string.format("Shields: %d", shields)
end)

AbilityUpdateEvt.Event:Connect(function(newCharges)
    abilityCharges = newCharges
    abilityLabel.Text = string.format("Abilities: %d", abilityCharges)
end)

CurrencyUpdateEvt.Event:Connect(function(newCurrency)
    currency = newCurrency
    currencyLabel.Text = string.format("Coins: %d", currency)
end)

RunStartEvt.Event:Connect(function()
    inRun = true
    currentLane = 3
    startButton.Text = "In Progress"
    startButton.BackgroundColor3 = Color3.fromRGB(150, 100, 50)
end)

RunEndEvt.Event:Connect(function(results)
    inRun = false
    startButton.Text = "Start Run"
    startButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)

    -- Show run results (simplified for now)
    print("Run completed! Distance:", results.distance, "Score:", results.score)
end)

AbilityCDEvt.Event:Connect(function(abilityType, cooldownTime)
    abilityCooldowns[abilityType] = cooldownTime
end)

-- Cooldown countdown
RunService.Heartbeat:Connect(function(dt)
    for ability, remaining in pairs(abilityCooldowns) do
        if remaining > 0 then
            abilityCooldowns[ability] = math.max(0, remaining - dt)
        end
    end
end)

print("[RunnerController] 5-Lane client controller loaded!")