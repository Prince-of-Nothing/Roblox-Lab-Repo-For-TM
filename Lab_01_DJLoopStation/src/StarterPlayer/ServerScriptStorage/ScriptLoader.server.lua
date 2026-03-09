-- ScriptLoader.server.lua
-- Place this in ServerScriptService.
-- Ensures BeatController → FeedbackSystem → PadManager load in order.
-- Move the other three .server.lua files into a folder called "DJScripts" inside ServerScriptService
-- and set them to DISABLED (uncheck Enabled in properties).

local SSS = game:GetService("ServerScriptService")
local folder = SSS:WaitForChild("DJScripts")

local function run(name)
	local script = folder:FindFirstChild(name)
	if script and script:IsA("ModuleScript") then
		require(script)
	end
end

-- If using ModuleScripts:
-- run("BeatController")
-- run("FeedbackSystem")
-- run("PadManager")

-- If using regular Scripts (simpler approach):
-- Just rename them with number prefixes so they sort alphabetically:
--   1_BeatController.server.lua
--   2_FeedbackSystem.server.lua
--   3_PadManager.server.lua