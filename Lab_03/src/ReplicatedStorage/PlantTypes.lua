-- PlantTypes.lua
-- ModuleScript defining 5 cannabis plant varieties with unique L-system rules

local PlantTypes = {}

PlantTypes.Types = {
	Indica = {
		name = "Indica",
		color = Color3.fromRGB(34, 100, 34),
		leafColor = Color3.fromRGB(50, 150, 50),
		rule = "F[+F&F]F[-F^F]F",
		angle = 25,
		segmentLength = 0.18,
		maxIterations = 5,
		leafDropInterval = 8,
		leavesPerDrop = 1,
		description = "Dense, bushy plant. Reliable yield.",
	},

	Sativa = {
		name = "Sativa",
		color = Color3.fromRGB(60, 180, 60),
		leafColor = Color3.fromRGB(80, 200, 80),
		rule = "FF[+F][-F][&F][^F]",
		angle = 30,
		segmentLength = 0.25,
		maxIterations = 5,
		leafDropInterval = 10,
		leavesPerDrop = 2,
		description = "Tall and stretchy. High yield per drop.",
	},

	Hybrid = {
		name = "Hybrid",
		color = Color3.fromRGB(50, 140, 50),
		leafColor = Color3.fromRGB(70, 170, 70),
		rule = "F[+F]F[-F&F][^F]",
		angle = 28,
		segmentLength = 0.2,
		maxIterations = 5,
		leafDropInterval = 9,
		leavesPerDrop = 1,
		description = "Balanced growth and yield.",
	},

	PurpleKush = {
		name = "Purple Kush",
		color = Color3.fromRGB(100, 50, 120),
		leafColor = Color3.fromRGB(130, 70, 150),
		rule = "F[+F&F][-F^F]F[+F][-F]",
		angle = 22,
		segmentLength = 0.15,
		maxIterations = 6,
		leafDropInterval = 12,
		leavesPerDrop = 3,
		description = "Rare purple variety. Slow but valuable.",
	},

	AutoFlower = {
		name = "Auto Flower",
		color = Color3.fromRGB(80, 160, 80),
		leafColor = Color3.fromRGB(100, 180, 100),
		rule = "F[+F][&F]F",
		angle = 35,
		segmentLength = 0.22,
		maxIterations = 4,
		leafDropInterval = 5,
		leavesPerDrop = 1,
		description = "Fast growing, quick harvest cycles.",
	},
}

-- List of type names for random selection
PlantTypes.TypeNames = {"Indica", "Sativa", "Hybrid", "PurpleKush", "AutoFlower"}

-- Get a random plant type (20% chance each)
function PlantTypes.getRandomType()
	local typeName = PlantTypes.TypeNames[math.random(1, 5)]
	return PlantTypes.Types[typeName]
end

-- Get a specific plant type by name
function PlantTypes.getType(name)
	return PlantTypes.Types[name]
end

return PlantTypes
