-- CannabisUI.client.lua
-- Client script for Cannabis Idle Game GUI

print("[DEBUG 1] CannabisUI script starting...")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[DEBUG 2] Services loaded")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

print("[DEBUG 3] Player and mouse obtained")

-- Game state (synced from server)
local plotStates: {[number]: {[string]: any}} = {}
local upgradeData: {[string]: any} = {}

-- Remote events (will be set after GUI creation)
local PlantSeedEvent
local WaterPlantEvent
local PurchaseUpgradeEvent
local SyncGameStateEvent
local CannabisCollectedEvent

print("[DEBUG 4] Variables initialized, creating GUI...")

-- ========================
-- GUI CREATION
-- ========================
local playerGui = player:WaitForChild("PlayerGui")
print("[DEBUG 5] PlayerGui found: " .. tostring(playerGui))

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CannabisUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

print("[DEBUG 6] ScreenGui created and parented")

-- CANNABIS COUNTER (top-right)
local leafFrame = Instance.new("Frame")
leafFrame.Name = "LeafCounter"
leafFrame.Size = UDim2.new(0, 200, 0, 60)
leafFrame.Position = UDim2.new(1, -220, 0, 20)
leafFrame.BackgroundColor3 = Color3.fromRGB(30, 60, 30)
leafFrame.BackgroundTransparency = 0.3
leafFrame.BorderSizePixel = 0
leafFrame.Parent = screenGui

local leafCorner = Instance.new("UICorner")
leafCorner.CornerRadius = UDim.new(0, 10)
leafCorner.Parent = leafFrame

local leafLabel = Instance.new("TextLabel")
leafLabel.Name = "LeafLabel"
leafLabel.Size = UDim2.new(1, 0, 1, 0)
leafLabel.BackgroundTransparency = 1
leafLabel.Text = "Cannabis: 0"
leafLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
leafLabel.TextSize = 28
leafLabel.Font = Enum.Font.GothamBold
leafLabel.Parent = leafFrame

local obtainedFrame = Instance.new("Frame")
obtainedFrame.Name = "CannabisObtained"
obtainedFrame.Size = UDim2.new(0, 200, 0, 44)
obtainedFrame.Position = UDim2.new(1, -220, 0, 86)
obtainedFrame.BackgroundColor3 = Color3.fromRGB(30, 60, 30)
obtainedFrame.BackgroundTransparency = 0.35
obtainedFrame.BorderSizePixel = 0
obtainedFrame.Parent = screenGui

local obtainedCorner = Instance.new("UICorner")
obtainedCorner.CornerRadius = UDim.new(0, 10)
obtainedCorner.Parent = obtainedFrame

local obtainedLabel = Instance.new("TextLabel")
obtainedLabel.Name = "ObtainedLabel"
obtainedLabel.Size = UDim2.new(1, 0, 1, 0)
obtainedLabel.BackgroundTransparency = 1
obtainedLabel.Text = "Obtained: 0"
obtainedLabel.TextColor3 = Color3.fromRGB(160, 220, 160)
obtainedLabel.TextSize = 20
obtainedLabel.Font = Enum.Font.GothamBold
obtainedLabel.Parent = obtainedFrame

local collectPopup = Instance.new("TextLabel")
collectPopup.Name = "CollectPopup"
collectPopup.Size = UDim2.new(0, 220, 0, 40)
collectPopup.Position = UDim2.new(1, -230, 0, 136)
collectPopup.BackgroundTransparency = 1
collectPopup.Text = ""
collectPopup.TextColor3 = Color3.fromRGB(120, 255, 120)
collectPopup.TextStrokeTransparency = 0.3
collectPopup.TextSize = 24
collectPopup.Font = Enum.Font.GothamBlack
collectPopup.Visible = false
collectPopup.Parent = screenGui

print("[DEBUG 7] Cannabis counters created")

-- SHOP TOGGLE BUTTON
local shopToggle = Instance.new("TextButton")
shopToggle.Name = "ShopToggle"
shopToggle.Size = UDim2.new(0, 100, 0, 40)
shopToggle.Position = UDim2.new(1, -220, 0, 142)
shopToggle.BackgroundColor3 = Color3.fromRGB(80, 120, 80)
shopToggle.Text = "SHOP"
shopToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
shopToggle.TextSize = 18
shopToggle.Font = Enum.Font.GothamBold
shopToggle.BorderSizePixel = 0
shopToggle.Parent = screenGui

local shopToggleCorner = Instance.new("UICorner")
shopToggleCorner.CornerRadius = UDim.new(0, 8)
shopToggleCorner.Parent = shopToggle

print("[DEBUG 8] Shop toggle created")

-- SHOP PANEL
local shopPanel = Instance.new("Frame")
shopPanel.Name = "ShopPanel"
shopPanel.Size = UDim2.new(0, 280, 0, 350)
shopPanel.Position = UDim2.new(1, -300, 0, 190)
shopPanel.BackgroundColor3 = Color3.fromRGB(40, 60, 40)
shopPanel.BackgroundTransparency = 0.1
shopPanel.BorderSizePixel = 0
shopPanel.Visible = true
shopPanel.Parent = screenGui

local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 12)
shopCorner.Parent = shopPanel

local shopTitle = Instance.new("TextLabel")
shopTitle.Name = "Title"
shopTitle.Size = UDim2.new(1, 0, 0, 40)
shopTitle.BackgroundTransparency = 1
shopTitle.Text = "UPGRADES"
shopTitle.TextColor3 = Color3.fromRGB(150, 220, 150)
shopTitle.TextSize = 22
shopTitle.Font = Enum.Font.GothamBold
shopTitle.Parent = shopPanel

-- Yield Upgrade Button
local yieldButton = Instance.new("TextButton")
yieldButton.Name = "YieldButton"
yieldButton.Size = UDim2.new(0.9, 0, 0, 70)
yieldButton.Position = UDim2.new(0.05, 0, 0, 50)
yieldButton.BackgroundColor3 = Color3.fromRGB(60, 100, 60)
yieldButton.TextColor3 = Color3.fromRGB(255, 255, 255)
yieldButton.TextSize = 14
yieldButton.Font = Enum.Font.Gotham
yieldButton.TextWrapped = true
yieldButton.Text = "Yield Boost\nLevel 1/5\nCost: 10 Cannabis"
yieldButton.BorderSizePixel = 0
yieldButton.Parent = shopPanel

local yieldCorner = Instance.new("UICorner")
yieldCorner.CornerRadius = UDim.new(0, 8)
yieldCorner.Parent = yieldButton

-- Plot Unlock Button
local plotButton = Instance.new("TextButton")
plotButton.Name = "PlotButton"
plotButton.Size = UDim2.new(0.9, 0, 0, 70)
plotButton.Position = UDim2.new(0.05, 0, 0, 130)
plotButton.BackgroundColor3 = Color3.fromRGB(60, 100, 60)
plotButton.TextColor3 = Color3.fromRGB(255, 255, 255)
plotButton.TextSize = 14
plotButton.Font = Enum.Font.Gotham
plotButton.TextWrapped = true
plotButton.Text = "Unlock Plot\nPlots: 1/6\nCost: 50 Cannabis"
plotButton.BorderSizePixel = 0
plotButton.Parent = shopPanel

local plotCorner = Instance.new("UICorner")
plotCorner.CornerRadius = UDim.new(0, 8)
plotCorner.Parent = plotButton

-- Autopicker Button
local autopickerButton = Instance.new("TextButton")
autopickerButton.Name = "AutopickerButton"
autopickerButton.Size = UDim2.new(0.9, 0, 0, 70)
autopickerButton.Position = UDim2.new(0.05, 0, 0, 210)
autopickerButton.BackgroundColor3 = Color3.fromRGB(60, 100, 60)
autopickerButton.TextColor3 = Color3.fromRGB(255, 255, 255)
autopickerButton.TextSize = 14
autopickerButton.Font = Enum.Font.Gotham
autopickerButton.TextWrapped = true
autopickerButton.Text = "Autopicker\nAuto-collect cannabis leaves!\nCost: 1000 Cannabis"
autopickerButton.BorderSizePixel = 0
autopickerButton.Parent = shopPanel

local autopickerCorner = Instance.new("UICorner")
autopickerCorner.CornerRadius = UDim.new(0, 8)
autopickerCorner.Parent = autopickerButton

print("[DEBUG 9] Shop panel and buttons created")

-- PLOT INFO PANEL (bottom-center)
local plotInfoPanel = Instance.new("Frame")
plotInfoPanel.Name = "PlotInfoPanel"
plotInfoPanel.Size = UDim2.new(0, 300, 0, 150)
plotInfoPanel.Position = UDim2.new(0.5, -150, 1, -170)
plotInfoPanel.BackgroundColor3 = Color3.fromRGB(40, 60, 40)
plotInfoPanel.BackgroundTransparency = 0.1
plotInfoPanel.BorderSizePixel = 0
plotInfoPanel.Visible = true
plotInfoPanel.Parent = screenGui

local plotInfoCorner = Instance.new("UICorner")
plotInfoCorner.CornerRadius = UDim.new(0, 12)
plotInfoCorner.Parent = plotInfoPanel

local plotInfoTitle = Instance.new("TextLabel")
plotInfoTitle.Name = "Title"
plotInfoTitle.Size = UDim2.new(1, 0, 0, 30)
plotInfoTitle.BackgroundTransparency = 1
plotInfoTitle.Text = "Plot 1"
plotInfoTitle.TextColor3 = Color3.fromRGB(150, 220, 150)
plotInfoTitle.TextSize = 18
plotInfoTitle.Font = Enum.Font.GothamBold
plotInfoTitle.Parent = plotInfoPanel

local plotInfoText = Instance.new("TextLabel")
plotInfoText.Name = "Info"
plotInfoText.Size = UDim2.new(1, -20, 0, 60)
plotInfoText.Position = UDim2.new(0, 10, 0, 30)
plotInfoText.BackgroundTransparency = 1
plotInfoText.Text = "Empty plot\nClick to plant!"
plotInfoText.TextColor3 = Color3.fromRGB(200, 200, 200)
plotInfoText.TextSize = 14
plotInfoText.Font = Enum.Font.Gotham
plotInfoText.TextWrapped = true
plotInfoText.TextXAlignment = Enum.TextXAlignment.Left
plotInfoText.Parent = plotInfoPanel

local plotActionButton = Instance.new("TextButton")
plotActionButton.Name = "ActionButton"
plotActionButton.Size = UDim2.new(0.8, 0, 0, 40)
plotActionButton.Position = UDim2.new(0.1, 0, 1, -50)
plotActionButton.BackgroundColor3 = Color3.fromRGB(80, 140, 80)
plotActionButton.Text = "Plant Seed"
plotActionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
plotActionButton.TextSize = 16
plotActionButton.Font = Enum.Font.GothamBold
plotActionButton.BorderSizePixel = 0
plotActionButton.Parent = plotInfoPanel

local actionCorner = Instance.new("UICorner")
actionCorner.CornerRadius = UDim.new(0, 8)
actionCorner.Parent = plotActionButton

print("[DEBUG 10] Plot info panel created")

-- INSTRUCTIONS (top-left)
local instructions = Instance.new("TextLabel")
instructions.Name = "Instructions"
instructions.Size = UDim2.new(0, 250, 0, 80)
instructions.Position = UDim2.new(0, 20, 0, 20)
instructions.BackgroundColor3 = Color3.fromRGB(30, 50, 30)
instructions.BackgroundTransparency = 0.5
instructions.Text = "Click soil to plant/water\nWalk on cannabis leaves to collect\nBuy upgrades in shop!"
instructions.TextColor3 = Color3.fromRGB(180, 220, 180)
instructions.TextSize = 14
instructions.Font = Enum.Font.Gotham
instructions.TextWrapped = true
instructions.BorderSizePixel = 0
instructions.Parent = screenGui

local instrCorner = Instance.new("UICorner")
instrCorner.CornerRadius = UDim.new(0, 8)
instrCorner.Parent = instructions

print("[DEBUG 11] Instructions created - ALL GUI ELEMENTS DONE")

-- ========================
-- STATE TRACKING
-- ========================
local selectedPlotIndex = nil
selectedPlotIndex = 1

-- ========================
-- UI UPDATE FUNCTIONS
-- ========================
local function updateLeafCounter()
	local stats = player:FindFirstChild("leaderstats")
	if stats and stats:FindFirstChild("Cannabis") then
		leafLabel.Text = "Cannabis: " .. stats.Cannabis.Value
	elseif stats and stats:FindFirstChild("Leaves") then
		leafLabel.Text = "Cannabis: " .. stats.Leaves.Value
	end
end

local function updateCannabisObtained()
	local gameState = player:FindFirstChild("GameState")
	if gameState and gameState:FindFirstChild("CannabisObtained") then
		obtainedLabel.Text = "Obtained: " .. gameState.CannabisObtained.Value
	elseif upgradeData.cannabisObtained then
		obtainedLabel.Text = "Obtained: " .. upgradeData.cannabisObtained
	end
end

local function showCollectPopup(amount)
	collectPopup.Text = "+" .. tostring(amount) .. " Cannabis"
	collectPopup.Visible = true
	collectPopup.TextTransparency = 0
	collectPopup.Position = UDim2.new(1, -230, 0, 136)

	task.spawn(function()
		for i = 1, 12 do
			collectPopup.Position = collectPopup.Position - UDim2.new(0, 0, 0, 2)
			collectPopup.TextTransparency = i / 12
			task.wait(0.03)
		end
		collectPopup.Visible = false
	end)
end

local function updateShopButtons()
	if not upgradeData.yieldLevel then return end

	-- Yield button
	local yieldLevel = upgradeData.yieldLevel
	if yieldLevel >= 5 then
		yieldButton.Text = "Yield Boost\nMAXED (5x)\n---"
		yieldButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	else
		local cost = upgradeData.yieldCosts[yieldLevel]
		yieldButton.Text = "Yield Boost\nLevel " .. yieldLevel .. "/5 (" .. yieldLevel .. "x)\nCost: " .. cost .. " Cannabis"
		yieldButton.BackgroundColor3 = Color3.fromRGB(60, 100, 60)
	end

	-- Plot button
	local maxPlots = upgradeData.maxPlots
	if maxPlots >= 6 then
		plotButton.Text = "Unlock Plot\nMAXED (6/6)\n---"
		plotButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	else
		local cost = upgradeData.plotCosts[maxPlots]
		plotButton.Text = "Unlock Plot\nPlots: " .. maxPlots .. "/6\nCost: " .. cost .. " Cannabis"
		plotButton.BackgroundColor3 = Color3.fromRGB(60, 100, 60)
	end

	-- Autopicker button
	if upgradeData.autopickerEnabled then
		autopickerButton.Text = "Autopicker\nACTIVE!\n---"
		autopickerButton.BackgroundColor3 = Color3.fromRGB(60, 140, 60)
	else
		autopickerButton.Text = "Autopicker\nAuto-collect cannabis leaves!\nCost: " .. upgradeData.autopickerCost .. " Cannabis"
		autopickerButton.BackgroundColor3 = Color3.fromRGB(60, 100, 60)
	end
end

local function updatePlotInfoPanel()
	if not selectedPlotIndex then
		plotInfoPanel.Visible = false
		return
	end

	local maxPlots = upgradeData.maxPlots or 1
	if selectedPlotIndex > maxPlots then
		plotInfoTitle.Text = "Plot " .. selectedPlotIndex .. " (LOCKED)"
		plotInfoText.Text = "Unlock more plots in the shop!"
		plotActionButton.Visible = false
		plotInfoPanel.Visible = true
		return
	end

	local plotData = plotStates[selectedPlotIndex]
	plotInfoTitle.Text = "Plot " .. selectedPlotIndex

	if not plotData or plotData.state == "empty" then
		plotInfoText.Text = "Empty plot\nReady for planting!"
		plotActionButton.Text = "Plant Seed"
		plotActionButton.Visible = true
	elseif plotData.state == "growing" then
		local plantName = plotData.plantType or "Unknown"
		local progress = plotData.currentIteration .. "/" .. plotData.maxIterations
		local water = plotData.waterLevel .. "/" .. plotData.watersNeeded
		plotInfoText.Text = plantName .. "\nGrowth: " .. progress .. "\nWater: " .. water
		plotActionButton.Text = "Water Plant"
		plotActionButton.Visible = true
	elseif plotData.state == "mature" then
		local plantName = plotData.plantType or "Unknown"
		plotInfoText.Text = plantName .. "\nMATURE - Dropping cannabis leaves!\nWalk over them to collect!"
		plotActionButton.Text = "Water Plant"
		plotActionButton.Visible = true
	end

	plotInfoPanel.Visible = true
end

print("[DEBUG 12] Update functions defined")

-- ========================
-- EVENT HANDLERS
-- ========================

-- Shop toggle
shopToggle.MouseButton1Click:Connect(function()
	print("[DEBUG] Shop toggle clicked")
	shopPanel.Visible = not shopPanel.Visible
end)

-- Upgrade buttons
yieldButton.MouseButton1Click:Connect(function()
	print("[DEBUG] Yield button clicked")
	if PurchaseUpgradeEvent then
		PurchaseUpgradeEvent:FireServer("Yield")
	end
end)

plotButton.MouseButton1Click:Connect(function()
	print("[DEBUG] Plot button clicked")
	if PurchaseUpgradeEvent then
		PurchaseUpgradeEvent:FireServer("Plot")
	end
end)

autopickerButton.MouseButton1Click:Connect(function()
	print("[DEBUG] Autopicker button clicked")
	if PurchaseUpgradeEvent then
		PurchaseUpgradeEvent:FireServer("Autopicker")
	end
end)

-- Plot action button
plotActionButton.MouseButton1Click:Connect(function()
	print("[DEBUG] Plot action button clicked")
	if not selectedPlotIndex then return end
	if not PlantSeedEvent or not WaterPlantEvent then return end

	local plotData = plotStates[selectedPlotIndex]
	if not plotData or plotData.state == "empty" then
		PlantSeedEvent:FireServer(selectedPlotIndex)
	else
		WaterPlantEvent:FireServer(selectedPlotIndex)
	end
end)

-- Click detection for plots
mouse.Button1Down:Connect(function()
	local target = mouse.Target
	if not target then return end

	-- Check if clicked on soil
	if target.Name:match("^Soil_") then
		local plotIndex = target:GetAttribute("PlotIndex")
		if plotIndex then
			print("[DEBUG] Clicked soil plot: " .. plotIndex)
			selectedPlotIndex = plotIndex
			updatePlotInfoPanel()
		end
	-- Check if clicked on plant segment
	elseif target.Name == "PlantSegment" then
		local model = target.Parent
		if model and model.Name:match("^CannabisPlant_") then
			local plotIndex = tonumber(model.Name:match("CannabisPlant_(%d+)"))
			if plotIndex and WaterPlantEvent then
				print("[DEBUG] Clicked plant segment, watering plot: " .. plotIndex)
				WaterPlantEvent:FireServer(plotIndex)
			end
		end
	else
		-- Keep current selection visible so core controls remain available.
	end
end)

print("[DEBUG 13] Event handlers connected")

-- ========================
-- INITIALIZE REMOTE EVENTS (after GUI is created)
-- ========================
task.spawn(function()
	print("[DEBUG 14] Starting remote event initialization...")

	-- Wait for remote events from server
	PlantSeedEvent = ReplicatedStorage:WaitForChild("PlantSeed", 10)
	print("[DEBUG 15] PlantSeed event: " .. tostring(PlantSeedEvent))

	WaterPlantEvent = ReplicatedStorage:WaitForChild("WaterPlant", 10)
	print("[DEBUG 16] WaterPlant event: " .. tostring(WaterPlantEvent))

	PurchaseUpgradeEvent = ReplicatedStorage:WaitForChild("PurchaseUpgrade", 10)
	print("[DEBUG 17] PurchaseUpgrade event: " .. tostring(PurchaseUpgradeEvent))

	SyncGameStateEvent = ReplicatedStorage:WaitForChild("SyncGameState", 10)
	print("[DEBUG 18] SyncGameState event: " .. tostring(SyncGameStateEvent))

	CannabisCollectedEvent = ReplicatedStorage:WaitForChild("CannabisCollected", 10)
	print("[DEBUG 18.5] CannabisCollected event: " .. tostring(CannabisCollectedEvent))

	if SyncGameStateEvent then
		SyncGameStateEvent.OnClientEvent:Connect(function(newPlotStates, newUpgradeData)
			print("[DEBUG] Received game state sync from server")
			plotStates = newPlotStates
			upgradeData = newUpgradeData
			updateShopButtons()
			updatePlotInfoPanel()
			updateCannabisObtained()
		end)
		print("[DEBUG 19] SyncGameState listener connected")
	else
		warn("[DEBUG] SyncGameState event not found!")
	end

	if CannabisCollectedEvent then
		CannabisCollectedEvent.OnClientEvent:Connect(function(amount, newBalance, newObtained)
			showCollectPopup(amount)
			if newBalance then
				leafLabel.Text = "Cannabis: " .. newBalance
			end
			if newObtained then
				obtainedLabel.Text = "Obtained: " .. newObtained
			end
		end)
	end

	-- Wait for leaderstats
	print("[DEBUG 20] Waiting for leaderstats...")
	local stats = player:WaitForChild("leaderstats", 10)
	if stats then
		print("[DEBUG 21] leaderstats found")
		local leavesValue = stats:WaitForChild("Cannabis", 10) or stats:WaitForChild("Leaves", 10)
		if leavesValue then
			print("[DEBUG 22] Cannabis value found")
			leavesValue.Changed:Connect(function()
				updateLeafCounter()
			end)
		else
			warn("[DEBUG] Cannabis value not found!")
		end
	else
		warn("[DEBUG] leaderstats not found!")
	end

	local gameState = player:WaitForChild("GameState", 10)
	if gameState then
		local obtainedValue = gameState:WaitForChild("CannabisObtained", 10)
		if obtainedValue then
			obtainedValue.Changed:Connect(function()
				updateCannabisObtained()
			end)
		end
	end
	updateLeafCounter()
	updateCannabisObtained()

	-- Request an initial sync once all remote connections are established
	if SyncGameStateEvent then
		SyncGameStateEvent:FireServer()
	else
		warn("SyncGameState event missing; UI cannot request initial state.")
	end

	print("[DEBUG 23] Cannabis UI Client fully initialized!")
end)

print("[DEBUG FINAL] Cannabis UI Client script completed loading!")
