-- Leaderstats.server.lua
-- Creates the "leaderstats" folder with Coins, Score, and Distance values.
-- runner.server.lua adds Score and Distance if they are missing, so this
-- script just pre-creates all three to guarantee the display order on the
-- Roblox leaderboard.

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local score = Instance.new("IntValue")
	score.Name = "Score"
	score.Value = 0
	score.Parent = stats

	local distance = Instance.new("IntValue")
	distance.Name = "Distance"
	distance.Value = 0
	distance.Parent = stats

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = stats
end)

