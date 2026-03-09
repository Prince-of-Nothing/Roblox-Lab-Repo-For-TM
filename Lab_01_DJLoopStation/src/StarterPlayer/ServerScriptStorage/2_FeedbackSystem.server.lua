-- FeedbackSystem.server.lua (Updated)
-- Handles positive/negative feedback: visuals, audio, scoreboard, and death penalties.
-- On death: all loops forced OFF, player can immediately re-engage.
-- Exposes SurvivalStart for client-side live timer.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

-- ===== CONFIG =====
local SURVIVAL_CHECK_INTERVAL = 16
local RESPAWN_DELAY = 5
local MAX_VOLUME_THRESHOLD = 0.75

-- ===== PLAYER STATE =====
local playerState = {}

local function initPlayer(player)
	local now = tick()
	playerState[player] = {
		alive = true,
		survivalStart = now,
		streak = 0,
		bestStreak = 0,
		bestTime = 0,
	}
	player:SetAttribute("SurvivalTime", 0)
	player:SetAttribute("SurvivalStart", now)
	player:SetAttribute("Streak", 0)
	player:SetAttribute("BestStreak", 0)
	player:SetAttribute("BestSurvivalTime", 0)
	player:SetAttribute("Alive", true)
end

local function cleanupPlayer(player)
	playerState[player] = nil
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(cleanupPlayer)
for _, p in ipairs(Players:GetPlayers()) do initPlayer(p) end

-- ===== SURVIVAL SCORE =====
local function getSurvivalTime(player)
	local state = playerState[player]
	if not state or not state.alive then return 0 end
	return math.floor(tick() - state.survivalStart)
end

local function updateRecords(player)
	local state = playerState[player]
	if not state then return end

	local current = getSurvivalTime(player)
	if current > state.bestTime then
		state.bestTime = current
		player:SetAttribute("BestSurvivalTime", state.bestTime)
	end

	if state.streak > state.bestStreak then
		state.bestStreak = state.streak
		player:SetAttribute("BestStreak", state.bestStreak)
	end
end

-- ===== FORCE ALL LOOPS OFF =====
local LOOP_ORDER = { "Drums", "Bass", "Synth", "FX", "Vocals", "Percussion", "Ambience" }

local function resetAllLoops()
	local musicFolder = workspace:FindFirstChild("Music")
	if not musicFolder then return end

	for _, name in ipairs(LOOP_ORDER) do
		workspace:SetAttribute("Loop_" .. name, false)
		local sound = musicFolder:FindFirstChild(name)
		if sound then
			TweenService:Create(
				sound,
				TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Volume = 0 }
			):Play()
		end
	end

	if _G.DJ and _G.DJ.ForceAllOff then
		_G.DJ.ForceAllOff()
	end
end

-- ===== SURVIVAL DECISION =====
local function decideSurvival()
	local loops = workspace:FindFirstChild("Music")
	if not loops then return true end

	local activeCount = 0
	local totalVolume = 0
	local totalLoops = #LOOP_ORDER

	for _, name in ipairs(LOOP_ORDER) do
		local isActive = workspace:GetAttribute("Loop_" .. name)
		if isActive then
			activeCount += 1
			local sound = loops:FindFirstChild(name)
			if sound then
				totalVolume += sound.Volume
			end
		end
	end

	if activeCount == 0 then return false end
	if activeCount == totalLoops then return false end

	local deathChance = 0

	local idealCount = math.floor(totalLoops / 2)
	local countDeviation = math.abs(activeCount - idealCount) / totalLoops
	deathChance += countDeviation * 0.3

	local avgVolume = totalVolume / math.max(activeCount, 1)
	if avgVolume >= MAX_VOLUME_THRESHOLD then
		deathChance += 0.25
	end

	local allMaxVolume = true
	for _, name in ipairs(LOOP_ORDER) do
		local isActive = workspace:GetAttribute("Loop_" .. name)
		if isActive then
			local sound = loops:FindFirstChild(name)
			if sound and sound.Volume < MAX_VOLUME_THRESHOLD then
				allMaxVolume = false
				break
			end
		end
	end
	if allMaxVolume and activeCount > 1 then
		deathChance += 0.3
	end

	deathChance += math.random() * 0.15
	deathChance = math.clamp(deathChance, 0, 1)

	return math.random() > deathChance
end

-- ===== POSITIVE FEEDBACK =====
local POSITIVE_LIGHTING = {
	Ambient = Color3.fromRGB(180, 255, 200),
	OutdoorAmbient = Color3.fromRGB(200, 255, 220),
	FogEnd = 1500,
	Brightness = 3,
}

local function positiveVisuals()
	local info = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for prop, value in pairs(POSITIVE_LIGHTING) do
		TweenService:Create(Lighting, info, { [prop] = value }):Play()
	end

	local padsFolder = workspace:FindFirstChild("Pads")
	if padsFolder then
		for _, pad in ipairs(padsFolder:GetChildren()) do
			local loopName = pad:GetAttribute("Loop")
			if loopName and workspace:GetAttribute("Loop_" .. loopName) then
				local burst = Instance.new("ParticleEmitter")
				burst.Rate = 0
				burst.Lifetime = NumberRange.new(0.8, 1.5)
				burst.Speed = NumberRange.new(8, 15)
				burst.SpreadAngle = Vector2.new(180, 180)
				burst.Color = ColorSequence.new(Color3.fromRGB(255, 255, 100))
				burst.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(1, 0),
				})
				burst.Parent = pad
				burst:Emit(25)
				task.delay(2, function() burst:Destroy() end)
			end
		end
	end
end

local function positiveAudio()
	local cheer = Instance.new("Sound")
	cheer.SoundId = "rbxassetid://1837756997"
	cheer.Volume = 0.6
	cheer.Parent = workspace
	cheer:Play()
	task.delay(4, function() cheer:Destroy() end)
end

local function rewardSurvival(player)
	local state = playerState[player]
	if not state then return end

	state.streak += 1
	updateRecords(player)
	positiveVisuals()
	positiveAudio()

	player:SetAttribute("SurvivalTime", getSurvivalTime(player))
	player:SetAttribute("Streak", state.streak)
end

-- ===== NEGATIVE FEEDBACK =====
local DOOM_LIGHTING = {
	Ambient = Color3.fromRGB(0, 0, 0),
	OutdoorAmbient = Color3.fromRGB(0, 0, 0),
	FogColor = Color3.fromRGB(10, 0, 0),
	FogEnd = 30,
	Brightness = 0.05,
}

local NORMAL_LIGHTING = {
	Ambient = Color3.fromRGB(255, 180, 180),
	OutdoorAmbient = Color3.fromRGB(180, 255, 180),
	FogColor = Color3.fromRGB(200, 200, 255),
	FogEnd = 1000,
	Brightness = 2,
}

local function dimLighting()
	local info = TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for prop, value in pairs(DOOM_LIGHTING) do
		TweenService:Create(Lighting, info, { [prop] = value }):Play()
	end
end

local function restoreLighting()
	local info = TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for prop, value in pairs(NORMAL_LIGHTING) do
		TweenService:Create(Lighting, info, { [prop] = value }):Play()
	end
end

local function deathAudio()
	local doom = Instance.new("Sound")
	doom.SoundId = "rbxassetid://1835560410"
	doom.Volume = 0.8
	doom.PlaybackSpeed = 0.5
	doom.Parent = workspace
	doom:Play()
	task.delay(5, function() doom:Destroy() end)
end

local function punishDeath(player)
	local state = playerState[player]
	if not state then return end

	-- Save records BEFORE resetting
	updateRecords(player)

	-- Reset current stats
	state.alive = false
	state.streak = 0
	player:SetAttribute("Alive", false)
	player:SetAttribute("SurvivalTime", 0)
	player:SetAttribute("SurvivalStart", 0)
	player:SetAttribute("Streak", 0)

	-- Kill all loops immediately
	resetAllLoops()

	-- Death effects
	dimLighting()
	deathAudio()

	-- Kill character
	task.delay(1.5, function()
		if player.Character then
			player.Character:BreakJoints()
		end
	end)

	-- Respawn and reset
	task.delay(RESPAWN_DELAY, function()
		local now = tick()
		state.alive = true
		state.survivalStart = now
		player:SetAttribute("Alive", true)
		player:SetAttribute("SurvivalStart", now)
		player:SetAttribute("SurvivalTime", 0)
		restoreLighting()
	end)
end

-- ===== PASS-THROUGH =====
_G.DJ = _G.DJ or {}
local originalToggle = _G.DJ.RequestToggle

_G.DJ.RequestToggle = function(loopName: string, player: Player?)
	if originalToggle then
		originalToggle(loopName)
	end
end

-- ===== PERIODIC SURVIVAL CHECK =====
task.spawn(function()
	while true do
		task.wait(SURVIVAL_CHECK_INTERVAL)

		local survived = decideSurvival()

		for _, player in ipairs(Players:GetPlayers()) do
			local state = playerState[player]
			if state and state.alive then
				if survived then
					rewardSurvival(player)
				else
					punishDeath(player)
				end
			end
		end
	end
end)