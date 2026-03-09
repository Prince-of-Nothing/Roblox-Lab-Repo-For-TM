-- PadManager.server.lua (Updated)
-- Spawns grid with unique pad names. Pads 8-9 are empty (no loop).
-- Fixed: no duplicate loop assignments.
-- Fixed: dead bodies can't activate pads.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- ===== Grid placement =====
local ROWS, COLS  = 3, 3
local SPACING     = 8
local PAD_SIZE    = Vector3.new(8, 2, 8)
local FORWARD_OFFSET = -30

local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
local spawnPos = spawn and spawn.Position or Vector3.new(0, 0, 0)
local BASE_POS = spawnPos + Vector3.new(0, 0, FORWARD_OFFSET)
local GRID_Y   = spawnPos.Y + 0.1

-- ===== Pads folder =====
local PadsFolder = workspace:FindFirstChild("Pads")
if not PadsFolder then
	PadsFolder = Instance.new("Folder")
	PadsFolder.Name = "Pads"
	PadsFolder.Parent = workspace
end

local function makePad(pos: Vector3, index: number)
	local p = Instance.new("Part")
	p.Size = PAD_SIZE
	p.Anchored = true
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(230, 230, 230)
	p.Position = Vector3.new(pos.X, GRID_Y, pos.Z)
	p.Name = string.format("Pad_%02d", index)
	p.Parent = PadsFolder
	return p
end

if #PadsFolder:GetChildren() == 0 then
	local idx = 1
	for r = 1, ROWS do
		for c = 1, COLS do
			local pos = BASE_POS + Vector3.new((c - 1) * SPACING, 0, (r - 1) * SPACING)
			makePad(pos, idx)
			idx += 1
		end
	end
end

-- ===== Map pads to loops =====
local LOOP_ORDER = { "Drums", "Bass", "Synth", "FX", "Vocals", "Percussion", "Ambience" }
local CATEGORY_COLORS = {
	Drums      = Color3.fromRGB(255, 50, 50),
	Bass       = Color3.fromRGB(50, 100, 255),
	Synth      = Color3.fromRGB(50, 255, 100),
	FX         = Color3.fromRGB(200, 50, 255),
	Vocals     = Color3.fromRGB(255, 255, 0),
	Percussion = Color3.fromRGB(255, 150, 0),
	Ambience   = Color3.fromRGB(0, 255, 255),
}
local INACTIVE_COLOR = Color3.fromRGB(60, 60, 60)
local EMPTY_COLOR = Color3.fromRGB(30, 30, 30)

local pads = PadsFolder:GetChildren()
table.sort(pads, function(a, b) return a.Name < b.Name end)

for i, pad in ipairs(pads) do
	pad:SetAttribute("Loop", nil)
	if i <= #LOOP_ORDER then
		pad:SetAttribute("Loop", LOOP_ORDER[i])
	else
		pad.Color = EMPTY_COLOR
		pad.Material = Enum.Material.SmoothPlastic
	end
end

-- ===== Color + Particle management =====
local function getTargetColor(loopName: string): Color3
	local on = workspace:GetAttribute("Loop_" .. loopName)
	local baseColor = CATEGORY_COLORS[loopName] or INACTIVE_COLOR
	if on then
		return baseColor
	else
		return Color3.new(baseColor.R * 0.25, baseColor.G * 0.25, baseColor.B * 0.25)
	end
end

local function clearParticles(pad: Part)
	for _, child in ipairs(pad:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			child:Destroy()
		end
	end
end

local function burstParticle(pad: Part, color: Color3)
	clearParticles(pad)
	local burst = Instance.new("ParticleEmitter")
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.5, 1)
	burst.Speed = NumberRange.new(5, 10)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Color = ColorSequence.new(color)
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Parent = pad
	burst:Emit(15)
	task.delay(1.5, function()
		if burst and burst.Parent then burst:Destroy() end
	end)
end

local function bindActiveTint(pad: Part, loopName: string)
	local attr = "Loop_" .. loopName

	local function update()
		local on = workspace:GetAttribute(attr)
		local targetColor = getTargetColor(loopName)

		TweenService:Create(
			pad,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Color = targetColor }
		):Play()

		if on then
			burstParticle(pad, targetColor)
		else
			clearParticles(pad)
		end
	end

	workspace:GetAttributeChangedSignal(attr):Connect(update)
	update()
end

-- ===== Player detection (ALIVE check) =====
local function getAlivePlayerFromHit(hit)
	local char = hit.Parent
	if not char then return nil end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end

	-- Dead body check: reject if health is 0 or state is Dead
	if hum.Health <= 0 then return nil end
	if hum:GetState() == Enum.HumanoidStateType.Dead then return nil end

	local player = Players:GetPlayerFromCharacter(char)
	if not player then return nil end

	-- Also check the FeedbackSystem's Alive attribute
	if player:GetAttribute("Alive") == false then return nil end

	return player
end

-- ===== Bind pads =====
for _, pad in ipairs(pads) do
	local loopName = pad:GetAttribute("Loop")
	if loopName then
		bindActiveTint(pad, loopName)

		local debounce = {}
		pad.Touched:Connect(function(hit)
			local player = getAlivePlayerFromHit(hit)
			if not player then return end
			if debounce[player] then return end
			debounce[player] = true

			if _G.DJ and _G.DJ.RequestToggle then
				_G.DJ.RequestToggle(loopName, player)
			end

			task.delay(0.4, function() debounce[player] = nil end)
		end)
	end
end

-- ===== BPM Pulse Effect =====
task.spawn(function()
	while true do
		local bpm = workspace:GetAttribute("BPM") or 120
		local beatTime = 60 / bpm

		for _, pad in ipairs(pads) do
			local loopName = pad:GetAttribute("Loop")
			if loopName and workspace:GetAttribute("Loop_" .. loopName) then
				local info = TweenInfo.new(beatTime / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
				TweenService:Create(pad, info, { Transparency = 0.4 }):Play()
			else
				TweenService:Create(
					pad,
					TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Transparency = 0 }
				):Play()
			end
		end
		task.wait(beatTime)
	end
end)