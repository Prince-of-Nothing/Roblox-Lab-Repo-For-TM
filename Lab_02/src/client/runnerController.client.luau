-- runnerController.client.luau
-- Client-side controller for the free-steering endless runner.
-- Responsibilities:
--   * Read A/D and Left/Right arrow input and send TurnAxis to server via RunnerSteer
--   * No lane teleport logic (LaneSwitch / laneIndex / LANE_X completely removed)
--   * Listen for milestone UI, speed UI, and magnet status events from server

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── Wait for server remotes ───────────────────────────────────────────────────
local Remotes          = ReplicatedStorage:WaitForChild("RunnerRemotes")
local RunnerSteer      = Remotes:WaitForChild("RunnerSteer")
local MilestoneUIEvent = Remotes:WaitForChild("MilestoneUIEvent", 10)
local SpeedUpdate      = Remotes:WaitForChild("SpeedUpdate",      10)
local MagnetStatus     = Remotes:WaitForChild("MagnetStatus",     10)

if not MilestoneUIEvent then warn("[runnerController] MilestoneUIEvent remote not found") end
if not SpeedUpdate      then warn("[runnerController] SpeedUpdate remote not found")      end
if not MagnetStatus     then warn("[runnerController] MagnetStatus remote not found")     end

local localPlayer      = Players.LocalPlayer

-- ── Steering input state ──────────────────────────────────────────────────────
-- Positive turnAxis = turn right (D / Right), negative = turn left (A / Left)
local turnLeft  = false
local turnRight = false

-- Key bindings for steering
local LEFT_KEYS  = { Enum.KeyCode.A, Enum.KeyCode.Left  }
local RIGHT_KEYS = { Enum.KeyCode.D, Enum.KeyCode.Right }

local function isLeft(key)
    for _, k in ipairs(LEFT_KEYS) do
        if key == k then return true end
    end
    return false
end

local function isRight(key)
    for _, k in ipairs(RIGHT_KEYS) do
        if key == k then return true end
    end
    return false
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if isLeft(input.KeyCode)  then turnLeft  = true end
    if isRight(input.KeyCode) then turnRight = true end
end)

UserInputService.InputEnded:Connect(function(input)
    if isLeft(input.KeyCode)  then turnLeft  = false end
    if isRight(input.KeyCode) then turnRight = false end
end)

-- ── Send steering to server every frame ───────────────────────────────────────
-- We send on every RenderStepped so the server always has fresh input.
-- The value is discrete: -1, 0, or +1.
local lastSentAxis = 0
RunService.RenderStepped:Connect(function()
    local axis = 0
    if turnLeft  then axis = axis - 1 end
    if turnRight then axis = axis + 1 end

    -- Only fire when the value changes to avoid unnecessary network traffic
    if axis ~= lastSentAxis then
        lastSentAxis = axis
        RunnerSteer:FireServer(axis)
    end
end)

-- ── Milestone UI ──────────────────────────────────────────────────────────────
if MilestoneUIEvent then
    MilestoneUIEvent.OnClientEvent:Connect(function(milestone)
        -- Display a simple screen notification
        local screenGui      = Instance.new("ScreenGui")
        screenGui.Name       = "MilestonePopup"
        screenGui.ResetOnSpawn = false

        local label          = Instance.new("TextLabel")
        label.Size           = UDim2.new(0, 320, 0, 60)
        label.Position       = UDim2.new(0.5, -160, 0.25, 0)
        label.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
        label.TextColor3     = Color3.fromRGB(20, 20, 20)
        label.TextScaled     = true
        label.Font           = Enum.Font.GothamBold
        label.Text           = "🏁 " .. tostring(milestone) .. " studs!"
        label.Parent         = screenGui

        screenGui.Parent     = localPlayer.PlayerGui

        task.delay(2.5, function()
            if screenGui.Parent then
                screenGui:Destroy()
            end
        end)
    end)
end

-- ── Speed UI ──────────────────────────────────────────────────────────────────
-- Create a small persistent HUD label that shows the current speed multiplier.
local speedGui        = Instance.new("ScreenGui")
speedGui.Name         = "SpeedHUD"
speedGui.ResetOnSpawn = false
speedGui.Parent       = localPlayer.PlayerGui

local speedLabel      = Instance.new("TextLabel")
speedLabel.Name       = "SpeedLabel"
speedLabel.Size       = UDim2.new(0, 180, 0, 40)
speedLabel.Position   = UDim2.new(1, -190, 0, 10)
speedLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
speedLabel.BackgroundTransparency = 0.45
speedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
speedLabel.TextScaled = true
speedLabel.Font       = Enum.Font.Gotham
speedLabel.Text       = "Speed: 1.0×"
speedLabel.Parent     = speedGui

if SpeedUpdate then
    SpeedUpdate.OnClientEvent:Connect(function(multiplier)
        speedLabel.Text = string.format("Speed: %.1f×", multiplier)
    end)
end

-- ── Magnet status UI ──────────────────────────────────────────────────────────
local magnetGui        = Instance.new("ScreenGui")
magnetGui.Name         = "MagnetHUD"
magnetGui.ResetOnSpawn = false
magnetGui.Parent       = localPlayer.PlayerGui

local magnetLabel      = Instance.new("TextLabel")
magnetLabel.Name       = "MagnetLabel"
magnetLabel.Size       = UDim2.new(0, 180, 0, 40)
magnetLabel.Position   = UDim2.new(1, -190, 0, 60)
magnetLabel.BackgroundColor3 = Color3.fromRGB(0, 80, 200)
magnetLabel.BackgroundTransparency = 0.45
magnetLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
magnetLabel.TextScaled = true
magnetLabel.Font       = Enum.Font.GothamBold
magnetLabel.Text       = ""
magnetLabel.Visible    = false
magnetLabel.Parent     = magnetGui

if MagnetStatus then
    MagnetStatus.OnClientEvent:Connect(function(active)
        magnetLabel.Visible = active
        magnetLabel.Text    = active and "🧲 MAGNET ACTIVE" or ""
    end)
end

-- ── Steering hint UI (shown briefly at start) ─────────────────────────────────
local hintGui          = Instance.new("ScreenGui")
hintGui.Name           = "SteerHint"
hintGui.ResetOnSpawn   = false
hintGui.Parent         = localPlayer.PlayerGui

local hintLabel        = Instance.new("TextLabel")
hintLabel.Size         = UDim2.new(0, 400, 0, 50)
hintLabel.Position     = UDim2.new(0.5, -200, 0.85, 0)
hintLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
hintLabel.BackgroundTransparency = 0.5
hintLabel.TextColor3   = Color3.fromRGB(255, 255, 255)
hintLabel.TextScaled   = true
hintLabel.Font         = Enum.Font.Gotham
hintLabel.Text         = "A / Left Arrow = Turn Left    D / Right Arrow = Turn Right"
hintLabel.Parent       = hintGui

task.delay(5, function()
    if hintGui.Parent then
        hintGui:Destroy()
    end
end)
