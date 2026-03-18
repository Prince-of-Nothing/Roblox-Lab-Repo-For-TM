local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	-- Leaderstats folder (only display values here)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	-- Coins (display in leaderboard)
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = stats

	-- Store gameplay state in player, not in leaderstats (hidden from leaderboard)
	local gameState = Instance.new("Folder")
	gameState.Name = "GameState"
	gameState.Parent = player

	-- Grace period timer (timestamp when grace period ends, 0 = not in grace period)
	local gracePeriod = Instance.new("NumberValue")
	gracePeriod.Name = "GracePeriodEnd"
	gracePeriod.Value = 0
	gracePeriod.Parent = gameState

	-- Shield grace period (20 seconds from buying Grace Shield, one free hit)
	local shieldGrace = Instance.new("NumberValue")
	shieldGrace.Name = "ShieldGracePeriodEnd"
	shieldGrace.Value = 0
	shieldGrace.Parent = gameState

	-- Did player use their free hit during shield grace?
	local shieldGraceUsed = Instance.new("BoolValue")
	shieldGraceUsed.Name = "ShieldGraceHitUsed"
	shieldGraceUsed.Value = false
	shieldGraceUsed.Parent = gameState

	-- Speed boost active flag
	local speedBoost = Instance.new("BoolValue")
	speedBoost.Name = "SpeedBoostActive"
	speedBoost.Value = false
	speedBoost.Parent = gameState

	-- Grace reducer active flag
	local graceReducer = Instance.new("BoolValue")
	graceReducer.Name = "GraceReducerActive"
	graceReducer.Value = false
	graceReducer.Parent = gameState

	-- Permanent speed bonus from shop purchases (only create if it doesn't exist)
	if not gameState:FindFirstChild("PermanentSpeedBonus") then
		local speedBonus = Instance.new("IntValue")
		speedBonus.Name = "PermanentSpeedBonus"
		speedBonus.Value = 0
		speedBonus.Parent = gameState
	end

	-- Temporary speed boost end time (from speed zones)
	local tempBoostEnd = Instance.new("NumberValue")
	tempBoostEnd.Name = "TempSpeedBoostEnd"
	tempBoostEnd.Value = 0
	tempBoostEnd.Parent = gameState
end)
