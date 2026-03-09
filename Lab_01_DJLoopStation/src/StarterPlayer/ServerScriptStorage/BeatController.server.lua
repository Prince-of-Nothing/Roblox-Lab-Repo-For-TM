-- BeatController.server.lua (Updated)
-- Master tempo, instant loop toggles.
-- RESPECTS existing sounds in workspace.Music — only sets defaults on NEW sounds.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- === REMOTES ===
local function getOrCreateRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local VolumeRemote = getOrCreateRemote("SetLoopVolume")
local ToggleRemote = getOrCreateRemote("ToggleLoopFromUI")

-- === NORMAL LIGHTING ===
Lighting.Ambient = Color3.fromRGB(255, 180, 180)
Lighting.OutdoorAmbient = Color3.fromRGB(180, 255, 180)
Lighting.FogColor = Color3.fromRGB(200, 200, 255)
Lighting.FogEnd = 1000
Lighting.Brightness = 2
Lighting.ClockTime = 14

-- === TEMPO ===
local BPM = 120
local BEATS_PER_BAR = 4
local BEAT = 60 / BPM
local BAR = BEAT * BEATS_PER_BAR
local FADE_TIME = 0.15

workspace:SetAttribute("BPM", BPM)

-- === LOOPS SOURCE ===
local LOOPS_FOLDER = workspace:FindFirstChild("Music")
if not LOOPS_FOLDER then
	LOOPS_FOLDER = Instance.new("Folder")
	LOOPS_FOLDER.Name = "Music"
	LOOPS_FOLDER.Parent = workspace
end

local LOOP_ORDER = { "Drums", "Bass", "Synth", "FX", "Vocals", "Percussion", "Ambience" }

-- Defaults ONLY used when creating a NEW sound (not found in Music folder)
local SOUND_DEFAULTS = {
	Drums      = { Pitch = 1.0, Id = "rbxassetid://1847668636" },
	Bass       = { Pitch = 0.6, Id = "rbxassetid://1847668636" },
	Synth      = { Pitch = 1.2, Id = "rbxassetid://1847668636" },
	FX         = { Pitch = 0.8, Id = "rbxassetid://1835560410" },
	Vocals     = { Pitch = 1.5, Id = "rbxassetid://1847668636" },
	Percussion = { Pitch = 2.0, Id = "rbxassetid://1847668636" },
	Ambience   = { Pitch = 0.4, Id = "rbxassetid://1835560410" },
}

local loops = {}
local active = {}
local targetVolumes = {}

for _, name in ipairs(LOOP_ORDER) do
	local s = LOOPS_FOLDER:FindFirstChild(name)
	local isNew = false

	if not s then
		-- Sound doesn't exist — create with defaults
		s = Instance.new("Sound")
		s.Name = name
		s.Parent = LOOPS_FOLDER
		isNew = true
	end

	-- Only apply defaults to NEWLY created sounds
	if isNew then
		local defaults = SOUND_DEFAULTS[name] or {}
		s.SoundId = defaults.Id or "rbxassetid://1847668636"
		s.PlaybackSpeed = defaults.Pitch or 1.0
	end

	-- These properties are always set (required for the system to work)
	s.Looped = true
	s.Volume = 0
	s.Playing = true

	loops[name] = s
	active[name] = false
	targetVolumes[name] = 0.8
	workspace:SetAttribute("Loop_" .. name, false)
	workspace:SetAttribute("Vol_" .. name, 0.8)
end

local function crossfade(sound: Sound, vol: number)
	TweenService:Create(
		sound,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Volume = vol }
	):Play()
end

-- === INSTANT TOGGLE ===
local function applyToggle(loopName: string)
	local s = loops[loopName]
	if not s then return end

	if active[loopName] then
		active[loopName] = false
		crossfade(s, 0.0)
		workspace:SetAttribute("Loop_" .. loopName, false)
	else
		active[loopName] = true
		crossfade(s, targetVolumes[loopName])
		workspace:SetAttribute("Loop_" .. loopName, true)
	end
end

-- === VOLUME SLIDER HANDLER ===
VolumeRemote.OnServerEvent:Connect(function(player, loopName, volume)
	if type(loopName) ~= "string" or type(volume) ~= "number" then return end
	if not loops[loopName] then return end

	volume = math.clamp(volume, 0, 1)
	targetVolumes[loopName] = volume
	workspace:SetAttribute("Vol_" .. loopName, volume)

	if active[loopName] then
		crossfade(loops[loopName], volume)
	end
end)

-- === UI TOGGLE HANDLER ===
ToggleRemote.OnServerEvent:Connect(function(player, loopName)
	if type(loopName) ~= "string" then return end
	if not loops[loopName] then return end

	if _G.DJ and _G.DJ.RequestToggle then
		_G.DJ.RequestToggle(loopName, player)
	end
end)

-- === PUBLIC API ===
_G.DJ = _G.DJ or {}

function _G.DJ.RequestToggle(loopName: string)
	applyToggle(loopName)
end

function _G.DJ.ForceAllOff()
	for _, name in ipairs(LOOP_ORDER) do
		if active[name] then
			active[name] = false
			crossfade(loops[name], 0.0)
			workspace:SetAttribute("Loop_" .. name, false)
		end
	end
end

function _G.DJ.SetBPM(newBPM: number)
	BPM = math.clamp(math.floor(newBPM + 0.5), 60, 180)
	workspace:SetAttribute("BPM", BPM)
	BEAT = 60 / BPM
	BAR = BEAT * BEATS_PER_BAR
end