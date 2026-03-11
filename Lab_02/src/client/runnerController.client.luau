--[[
  runnerController.client.luau
  Free-steering endless runner — client input & UI.

  Lane system removed.  The player now steers freely left/right with A/D
  (or Left/Right arrows).  The axis (-1..1) is sent to the server via
  TurnInput.  The server applies yaw to the character root and keeps the
  LinearVelocity aligned with the resulting LookVector.

  RunnerAdvance is fired when the player has travelled far enough from the
  last advance position (distance-based, not Z-threshold).
--]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ── Wait for remotes ──────────────────────────────────────────────────────
local Remotes            = ReplicatedStorage:WaitForChild("Remotes", 20)
local TurnInputEvent     = Remotes:WaitForChild("TurnInput",       20)
local RunnerAdvanceEvent = Remotes:WaitForChild("RunnerAdvance",   20)
local SpeedUpdateEvent   = Remotes:WaitForChild("SpeedUpdate",     20)
local MilestoneUIEvent   = Remotes:WaitForChild("MilestoneUIEvent",20)
local MagnetStatusEvent  = Remotes:WaitForChild("MagnetStatus",    20)

if not MagnetStatusEvent then warn("[runnerController] MagnetStatus remote not found") end

-- ── Input state ───────────────────────────────────────────────────────────
local leftHeld  = false
local rightHeld = false

local TURN_KEYS_LEFT  = { Enum.KeyCode.A, Enum.KeyCode.Left  }
local TURN_KEYS_RIGHT = { Enum.KeyCode.D, Enum.KeyCode.Right }

local function isLeft(kc)
    for _, k in ipairs(TURN_KEYS_LEFT) do
        if kc == k then return true end
    end
    return false
end

local function isRight(kc)
    for _, k in ipairs(TURN_KEYS_RIGHT) do
        if kc == k then return true end
    end
    return false
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local kc = input.KeyCode
    if isLeft(kc) then
        leftHeld = true
    elseif isRight(kc) then
        rightHeld = true
    elseif kc == Enum.KeyCode.Space then
        local char = player.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.Jump = true end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, _processed)
    local kc = input.KeyCode
    if isLeft(kc) then
        leftHeld = false
    elseif isRight(kc) then
        rightHeld = false
    end
end)

-- ── Send TurnInput to server ──────────────────────────────────────────────
-- Rate-limited: send at most every SEND_INTERVAL seconds.
local SEND_INTERVAL = 0.05   -- 20 Hz
local lastSend      = 0
local lastAxis      = 0

RunService.Heartbeat:Connect(function()
    local axis
    if leftHeld and not rightHeld then
        axis = -1
    elseif rightHeld and not leftHeld then
        axis = 1
    else
        axis = 0
    end

    local now = os.clock()
    -- Only send if axis changed or interval elapsed
    if axis ~= lastAxis or (now - lastSend) >= SEND_INTERVAL then
        lastSend  = now
        lastAxis  = axis
        TurnInputEvent:FireServer(axis)
    end
end)

-- ── Distance-based RunnerAdvance ──────────────────────────────────────────
-- Fire when the player has moved ADVANCE_DIST studs since the last fire.
local ADVANCE_DIST    = 50
local lastAdvancePos  = nil

RunService.Heartbeat:Connect(function()
    local char = player.Character
    if not char then lastAdvancePos = nil; return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    if not lastAdvancePos then
        lastAdvancePos = root.Position
        return
    end

    if (root.Position - lastAdvancePos).Magnitude >= ADVANCE_DIST then
        lastAdvancePos = root.Position
        RunnerAdvanceEvent:FireServer()
    end
end)

-- ── HUD: speed display ────────────────────────────────────────────────────
local function getOrMakeHUD()
    local gui = player.PlayerGui:FindFirstChild("RunnerHUD")
    if gui then return gui end

    gui          = Instance.new("ScreenGui")
    gui.Name     = "RunnerHUD"
    gui.ResetOnSpawn = false
    gui.Parent   = player.PlayerGui

    -- Speed label (bottom-left)
    local speedLabel         = Instance.new("TextLabel")
    speedLabel.Name          = "SpeedLabel"
    speedLabel.Size          = UDim2.new(0.2, 0, 0.06, 0)
    speedLabel.Position      = UDim2.new(0.01, 0, 0.88, 0)
    speedLabel.BackgroundTransparency = 0.5
    speedLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    speedLabel.TextColor3    = Color3.fromRGB(255, 255, 255)
    speedLabel.TextScaled    = true
    speedLabel.Font          = Enum.Font.GothamBold
    speedLabel.Text          = "Speed: --"
    speedLabel.Parent        = gui

    -- Steering hint (bottom-centre)
    local hintLabel          = Instance.new("TextLabel")
    hintLabel.Name           = "HintLabel"
    hintLabel.Size           = UDim2.new(0.4, 0, 0.05, 0)
    hintLabel.Position       = UDim2.new(0.3, 0, 0.94, 0)
    hintLabel.BackgroundTransparency = 1
    hintLabel.TextColor3     = Color3.fromRGB(200, 200, 200)
    hintLabel.TextScaled     = true
    hintLabel.Font           = Enum.Font.Gotham
    hintLabel.Text           = "A / D  —  Steer    Space  —  Jump"
    hintLabel.Parent         = gui

    return gui
end

SpeedUpdateEvent.OnClientEvent:Connect(function(newSpeed)
    local gui   = getOrMakeHUD()
    local label = gui:FindFirstChild("SpeedLabel")
    if label then
        label.Text = string.format("Speed: %.0f", newSpeed)
    end
end)

-- Initialise HUD on load
task.spawn(function()
    task.wait(2)
    getOrMakeHUD()
end)

-- ── Milestone UI ──────────────────────────────────────────────────────────
MilestoneUIEvent.OnClientEvent:Connect(function(distance)
    local gui = player.PlayerGui:FindFirstChild("MilestoneGui")
    if not gui then
        gui              = Instance.new("ScreenGui")
        gui.Name         = "MilestoneGui"
        gui.ResetOnSpawn = false
        gui.Parent       = player.PlayerGui
    end

    local label = gui:FindFirstChild("MilestoneLabel")
    if not label then
        label                    = Instance.new("TextLabel")
        label.Name               = "MilestoneLabel"
        label.Size               = UDim2.new(0.5, 0, 0.12, 0)
        label.Position           = UDim2.new(0.25, 0, 0.08, 0)
        label.BackgroundTransparency = 0.4
        label.BackgroundColor3   = Color3.fromRGB(0, 0, 0)
        label.TextColor3         = Color3.fromRGB(255, 215, 0)
        label.TextScaled         = true
        label.Font               = Enum.Font.GothamBold
        label.Parent             = gui
    end

    label.Text    = string.format("🏃 %d m reached!", distance)
    label.Visible = true

    task.delay(3, function()
        if label and label.Parent then
            label.Visible = false
        end
    end)
end)

-- ── Magnet status HUD ─────────────────────────────────────────────────────
-- Shows a visible indicator while the magnet power-up is active.
local magnetGui        = Instance.new("ScreenGui")
magnetGui.Name         = "MagnetHUD"
magnetGui.ResetOnSpawn = false
magnetGui.Parent       = player.PlayerGui

local magnetLabel                  = Instance.new("TextLabel")
magnetLabel.Name                   = "MagnetLabel"
magnetLabel.Size                   = UDim2.new(0.25, 0, 0.06, 0)
magnetLabel.Position               = UDim2.new(0.375, 0, 0.02, 0)
magnetLabel.BackgroundColor3       = Color3.fromRGB(0, 80, 200)
magnetLabel.BackgroundTransparency = 0.3
magnetLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
magnetLabel.TextScaled             = true
magnetLabel.Font                   = Enum.Font.GothamBold
magnetLabel.Text                   = "MAGNET ACTIVE"
magnetLabel.Visible                = false
magnetLabel.Parent                 = magnetGui

if MagnetStatusEvent then
    MagnetStatusEvent.OnClientEvent:Connect(function(active)
        magnetLabel.Visible = active == true
    end)
end
