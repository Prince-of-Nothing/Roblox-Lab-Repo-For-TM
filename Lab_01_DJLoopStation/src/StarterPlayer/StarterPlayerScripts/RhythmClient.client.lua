-- RhythmClient.client.lua (Updated)
-- Compact, transparent HUD with live-ticking survival timer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local plr = Players.LocalPlayer

local VolumeRemote = ReplicatedStorage:WaitForChild("SetLoopVolume")
local ToggleRemote = ReplicatedStorage:WaitForChild("ToggleLoopFromUI")

local gui = Instance.new("ScreenGui")
gui.Name = "DJHud"
gui.ResetOnSpawn = false
gui.Parent = plr:WaitForChild("PlayerGui")

-- ===== MAIN PANEL =====
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 220, 0, 390)
panel.Position = UDim2.new(0.01, 0, 0.03, 0)
panel.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
panel.BackgroundTransparency = 0.55
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Thickness = 1
panelStroke.Color = Color3.fromRGB(60, 60, 60)
panelStroke.Transparency = 0.3

-- ===== BPM HEADER =====
local bpmL = Instance.new("TextLabel")
bpmL.Size = UDim2.new(1, -12, 0, 20)
bpmL.Position = UDim2.new(0, 6, 0, 6)
bpmL.TextScaled = true
bpmL.BackgroundTransparency = 1
bpmL.TextColor3 = Color3.fromRGB(255, 100, 255)
bpmL.Font = Enum.Font.GothamBold
bpmL.Text = "♫ BPM: --"
bpmL.TextXAlignment = Enum.TextXAlignment.Left
bpmL.Parent = panel

workspace:GetAttributeChangedSignal("BPM"):Connect(function()
	bpmL.Text = "♫ BPM: " .. tostring(workspace:GetAttribute("BPM") or 0)
end)
bpmL.Text = "♫ BPM: " .. tostring(workspace:GetAttribute("BPM") or 0)

-- ===== LOOP ROWS =====
local LOOP_ORDER = { "Drums", "Bass", "Synth", "FX", "Vocals", "Perc", "Amb" }
local LOOP_FULL = { "Drums", "Bass", "Synth", "FX", "Vocals", "Percussion", "Ambience" }
local CATEGORY_COLORS = {
	Drums      = Color3.fromRGB(255, 50, 50),
	Bass       = Color3.fromRGB(50, 100, 255),
	Synth      = Color3.fromRGB(50, 255, 100),
	FX         = Color3.fromRGB(200, 50, 255),
	Vocals     = Color3.fromRGB(255, 255, 0),
	Percussion = Color3.fromRGB(255, 150, 0),
	Ambience   = Color3.fromRGB(0, 255, 255),
}

local ROW_HEIGHT = 36
local START_Y = 30

for i, shortName in ipairs(LOOP_ORDER) do
	local fullName = LOOP_FULL[i]
	local yPos = START_Y + (i - 1) * (ROW_HEIGHT + 3)
	local baseColor = CATEGORY_COLORS[fullName] or Color3.fromRGB(255, 255, 255)

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -12, 0, ROW_HEIGHT)
	row.Position = UDim2.new(0, 6, 0, yPos)
	row.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	row.BackgroundTransparency = 0.5
	row.BorderSizePixel = 0
	row.Parent = panel
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(0, 18, 0, 18)
	toggleBtn.Position = UDim2.new(0, 4, 0, 3)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	toggleBtn.Text = ""
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Parent = row
	Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(1, 0)

	local nameL = Instance.new("TextLabel")
	nameL.Size = UDim2.new(0, 70, 0, 16)
	nameL.Position = UDim2.new(0, 26, 0, 2)
	nameL.TextScaled = true
	nameL.BackgroundTransparency = 1
	nameL.TextColor3 = baseColor
	nameL.Font = Enum.Font.GothamBold
	nameL.TextXAlignment = Enum.TextXAlignment.Left
	nameL.Text = shortName
	nameL.Parent = row

	local sliderTrack = Instance.new("Frame")
	sliderTrack.Size = UDim2.new(1, -50, 0, 6)
	sliderTrack.Position = UDim2.new(0, 6, 0, 24)
	sliderTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	sliderTrack.BorderSizePixel = 0
	sliderTrack.Parent = row
	Instance.new("UICorner", sliderTrack).CornerRadius = UDim.new(1, 0)

	local sliderFill = Instance.new("Frame")
	sliderFill.Size = UDim2.new(0.8, 0, 1, 0)
	sliderFill.BackgroundColor3 = baseColor
	sliderFill.BackgroundTransparency = 0.3
	sliderFill.BorderSizePixel = 0
	sliderFill.Parent = sliderTrack
	Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("TextButton")
	knob.Size = UDim2.new(0, 12, 0, 12)
	knob.Position = UDim2.new(0.8, -6, 0.5, -6)
	knob.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
	knob.Text = ""
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = sliderTrack
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local volLabel = Instance.new("TextLabel")
	volLabel.Size = UDim2.new(0, 36, 0, 12)
	volLabel.Position = UDim2.new(1, -42, 0, 22)
	volLabel.TextScaled = true
	volLabel.BackgroundTransparency = 1
	volLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	volLabel.Font = Enum.Font.Gotham
	volLabel.Text = "80%"
	volLabel.Parent = row

	local dragging = false

	local function updateSlider(volume)
		volume = math.clamp(volume, 0, 1)
		sliderFill.Size = UDim2.new(volume, 0, 1, 0)
		knob.Position = UDim2.new(volume, -6, 0.5, -6)
		volLabel.Text = tostring(math.floor(volume * 100)) .. "%"
	end

	local function onInput(input)
		if not dragging then return end
		local trackAbsPos = sliderTrack.AbsolutePosition.X
		local trackAbsSize = sliderTrack.AbsoluteSize.X
		local mouseX = input.Position.X
		local ratio = math.clamp((mouseX - trackAbsPos) / trackAbsSize, 0, 1)
		updateSlider(ratio)
		VolumeRemote:FireServer(fullName, ratio)
	end

	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)

	sliderTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			onInput(input)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			onInput(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	local volAttr = "Vol_" .. fullName
	workspace:GetAttributeChangedSignal(volAttr):Connect(function()
		local v = workspace:GetAttribute(volAttr)
		if v and not dragging then updateSlider(v) end
	end)
	local initVol = workspace:GetAttribute(volAttr)
	if initVol then updateSlider(initVol) end

	toggleBtn.MouseButton1Click:Connect(function()
		ToggleRemote:FireServer(fullName)
	end)

	local loopAttr = "Loop_" .. fullName
	local function updateStatus()
		local on = workspace:GetAttribute(loopAttr)
		toggleBtn.BackgroundColor3 = on and baseColor or Color3.fromRGB(60, 60, 60)
		nameL.TextTransparency = on and 0 or 0.4
	end
	workspace:GetAttributeChangedSignal(loopAttr):Connect(updateStatus)
	updateStatus()
end

-- ===== SCOREBOARD SECTION =====
local feedbackY = START_Y + #LOOP_ORDER * (ROW_HEIGHT + 3) + 6

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -24, 0, 1)
divider.Position = UDim2.new(0, 12, 0, feedbackY - 2)
divider.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
divider.BackgroundTransparency = 0.4
divider.BorderSizePixel = 0
divider.Parent = panel

local function makeFeedbackLabel(text, yOffset, color)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -12, 0, 16)
	l.Position = UDim2.new(0, 6, 0, feedbackY + yOffset)
	l.TextScaled = true
	l.BackgroundTransparency = 1
	l.TextColor3 = color
	l.Font = Enum.Font.GothamBold
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = panel
	return l
end

local survivalL   = makeFeedbackLabel("⏱ Alive: 0s",       4,  Color3.fromRGB(100, 255, 100))
local bestTimeL   = makeFeedbackLabel("🏆 Best Time: 0s",  22, Color3.fromRGB(255, 215, 0))
local streakL     = makeFeedbackLabel("🔥 Streak: 0",      40, Color3.fromRGB(255, 180, 50))
local bestStreakL  = makeFeedbackLabel("👑 Best Streak: 0", 58, Color3.fromRGB(255, 130, 0))

-- ===== LIVE TIMER (ticks every second on client) =====
-- Server sets SurvivalStart (tick() timestamp) and Alive (bool).
-- Client computes elapsed time locally for smooth updates.

local serverTimeOffset = 0 -- difference between server tick() and client tick()

-- Approximate offset: server sends its tick via SurvivalStart
-- We recalculate offset whenever SurvivalStart changes
local function getServerNow()
	return tick() + serverTimeOffset
end

plr:GetAttributeChangedSignal("SurvivalStart"):Connect(function()
	local serverStart = plr:GetAttribute("SurvivalStart") or 0
	-- When server just set this, the actual server time ≈ serverStart
	-- But we also get SurvivalTime from the server as a sanity check
	local serverTime = plr:GetAttribute("SurvivalTime") or 0
	if serverStart > 0 and serverTime >= 0 then
		-- offset = server_tick - client_tick
		-- server_tick ≈ serverStart + serverTime
		serverTimeOffset = (serverStart + serverTime) - tick()
	end
end)

-- Initialize offset
local initStart = plr:GetAttribute("SurvivalStart") or 0
if initStart > 0 then
	serverTimeOffset = initStart - tick()
end

task.spawn(function()
	while true do
		local isAlive = plr:GetAttribute("Alive")
		local startTime = plr:GetAttribute("SurvivalStart") or 0

		if isAlive and startTime > 0 then
			local elapsed = math.floor(getServerNow() - startTime)
			if elapsed < 0 then elapsed = 0 end
			survivalL.Text = string.format("⏱ Alive: %ds", elapsed)
		else
			survivalL.Text = "⏱ Alive: 0s"
		end

		task.wait(1)
	end
end)

-- ===== SERVER ATTRIBUTE LISTENERS (for non-timer stats) =====
plr:GetAttributeChangedSignal("BestSurvivalTime"):Connect(function()
	local b = plr:GetAttribute("BestSurvivalTime") or 0
	bestTimeL.Text = string.format("🏆 Best Time: %ds", b)
end)

plr:GetAttributeChangedSignal("Streak"):Connect(function()
	local s = plr:GetAttribute("Streak") or 0
	streakL.Text = string.format("🔥 Streak: %d", s)
end)

plr:GetAttributeChangedSignal("BestStreak"):Connect(function()
	local bs = plr:GetAttribute("BestStreak") or 0
	bestStreakL.Text = string.format("👑 Best Streak: %d", bs)
end)
end)