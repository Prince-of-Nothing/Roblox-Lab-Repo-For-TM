--[[
  runnerController.client.luau
  5-Lane Endless Runner - Client Input and UI

  Controls:
    A / Left Arrow    - move left one lane
    D / Right Arrow   - move right one lane
    Space             - jump (clears low barriers)
    S / Down Arrow    - slide (clears high barriers)
    Q                 - ability: phase through obstacles
    E                 - ability: invincibility
    R                 - ability: time slow
    F                 - ability: dash (2 lanes right)

  UI:
    Top-left:    Health and shield indicators
    Top-centre:  Difficulty label
    Top-right:   Ability charge counter
    Bottom-left: Speed multiplier
    Bottom-centre: Distance and score
    Centre:      Biome change notification / milestone banner
    Full-screen: Difficulty selection (before first run)
    Full-screen: Results screen (after run ends)
    Full-screen: Progression hub (between runs)
--]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui

-- Wait for Remotes
local Remotes           = ReplicatedStorage:WaitForChild("Remotes", 30)
local LaneSwitchEvt     = Remotes:WaitForChild("LaneSwitch",       20)
local PlayerJumpEvt     = Remotes:WaitForChild("PlayerJump",       20)
local PlayerSlideEvt    = Remotes:WaitForChild("PlayerSlide",      20)
local UseAbilityEvt     = Remotes:WaitForChild("UseAbility",       20)
local SelectDiffEvt     = Remotes:WaitForChild("SelectDifficulty", 20)
local BuyUpgradeEvt     = Remotes:WaitForChild("BuyUpgrade",       20)
local RequestRunEvt     = Remotes:WaitForChild("RequestRun",       20)
local RunnerAdvanceEvt  = Remotes:WaitForChild("RunnerAdvance",    20)

local SpeedUpdateEvt    = Remotes:WaitForChild("SpeedUpdate",      20)
local MilestoneEvt      = Remotes:WaitForChild("MilestoneUIEvent", 20)
local HealthUpdateEvt   = Remotes:WaitForChild("HealthUpdate",     20)
local ShieldUpdateEvt   = Remotes:WaitForChild("ShieldUpdate",     20)
local AbilityUpdateEvt  = Remotes:WaitForChild("AbilityUpdate",    20)
local RunEndEvt         = Remotes:WaitForChild("RunEnd",           20)
local RunStartEvt       = Remotes:WaitForChild("RunStart",         20)
local BiomeChangeEvt    = Remotes:WaitForChild("BiomeChange",      20)
local CurrencyUpdateEvt = Remotes:WaitForChild("CurrencyUpdate",   20)
local UpgradeResultEvt  = Remotes:WaitForChild("UpgradeResult",    20)
local ObstacleHitEvt    = Remotes:WaitForChild("ObstacleHit",      20)
local AbilityCDEvt      = Remotes:WaitForChild("AbilityCooldown",  20)
local MagnetStatusEvt   = Remotes:WaitForChild("MagnetStatus",     20)

-- Game state
local currentLane       = 3     -- 1-5
local NUM_LANES         = 5
local isRunActive       = false
local currentDifficulty = "normal"
local abilityCooldowns  = {}    -- { abilityName = endTime }
local lastAdvancePos    = nil
local ADVANCE_DIST      = 50

-- Difficulty display names
local DIFF_NAMES = {
    easy="Easy", normal="Normal", medium="Medium", hard="Hard", impossible="Impossible"
}
local DIFF_COLORS = {
    easy      = Color3.fromRGB(80, 200, 80),
    normal    = Color3.fromRGB(80, 150, 255),
    medium    = Color3.fromRGB(255, 180, 50),
    hard      = Color3.fromRGB(255, 80, 80),
    impossible= Color3.fromRGB(200, 50, 200),
}

-- ── Helper: Create ScreenGui ──────────────────────────────────────────────────
local function makeGui(name, resetOnSpawn)
    local gui = playerGui:FindFirstChild(name)
    if not gui then
        gui              = Instance.new("ScreenGui")
        gui.Name         = name
        gui.ResetOnSpawn = (resetOnSpawn == true)
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Parent       = playerGui
    end
    return gui
end

local function makeLabel(parent, name, size, pos, text, textColor, bgColor, bgTrans, font, zIndex)
    local lbl                   = Instance.new("TextLabel")
    lbl.Name                    = name
    lbl.Size                    = size
    lbl.Position                = pos
    lbl.Text                    = text
    lbl.TextColor3              = textColor or Color3.fromRGB(255,255,255)
    lbl.BackgroundColor3        = bgColor   or Color3.fromRGB(0,0,0)
    lbl.BackgroundTransparency  = bgTrans   ~= nil and bgTrans or 0.45
    lbl.TextScaled              = true
    lbl.Font                    = font or Enum.Font.GothamBold
    lbl.ZIndex                  = zIndex or 1
    lbl.Parent                  = parent
    return lbl
end

local function makeButton(parent, name, size, pos, text, bgColor)
    local btn               = Instance.new("TextButton")
    btn.Name                = name
    btn.Size                = size
    btn.Position            = pos
    btn.Text                = text
    btn.TextColor3          = Color3.fromRGB(255,255,255)
    btn.BackgroundColor3    = bgColor or Color3.fromRGB(50,50,50)
    btn.TextScaled          = true
    btn.Font                = Enum.Font.GothamBold
    btn.ZIndex              = 5
    btn.Parent              = parent
    return btn
end

-- ── Main HUD ─────────────────────────────────────────────────────────────────
local hudGui = makeGui("RunnerHUD", false)
hudGui.Enabled = false

-- Health bar (top-left)
local healthFrame = Instance.new("Frame")
healthFrame.Name             = "HealthFrame"
healthFrame.Size             = UDim2.new(0.18, 0, 0.07, 0)
healthFrame.Position         = UDim2.new(0.01, 0, 0.01, 0)
healthFrame.BackgroundColor3 = Color3.fromRGB(0,0,0)
healthFrame.BackgroundTransparency = 0.4
healthFrame.Parent           = hudGui

local healthLabel = makeLabel(healthFrame, "HealthLabel",
    UDim2.new(1,0,0.55,0), UDim2.new(0,0,0,0),
    "HP: ♥ ♥ ♥", Color3.fromRGB(255,80,80), Color3.fromRGB(0,0,0), 1)
local shieldLabel = makeLabel(healthFrame, "ShieldLabel",
    UDim2.new(1,0,0.45,0), UDim2.new(0,0,0.55,0),
    "Shield: 0", Color3.fromRGB(180,220,255), Color3.fromRGB(0,0,0), 1)

-- Difficulty label (top-centre)
local diffLabel = makeLabel(hudGui, "DiffLabel",
    UDim2.new(0.18, 0, 0.05, 0),
    UDim2.new(0.41, 0, 0.01, 0),
    "NORMAL", Color3.fromRGB(80,150,255))

-- Ability charges (top-right)
local abilityLabel = makeLabel(hudGui, "AbilityLabel",
    UDim2.new(0.22, 0, 0.07, 0),
    UDim2.new(0.77, 0, 0.01, 0),
    "Charges: 1\n[Q]Phase [E]Invinc\n[R]Slow [F]Dash",
    Color3.fromRGB(200, 150, 255))

-- Speed (bottom-left)
local speedLabel = makeLabel(hudGui, "SpeedLabel",
    UDim2.new(0.16, 0, 0.06, 0),
    UDim2.new(0.01, 0, 0.88, 0),
    "Speed: 1.0x", Color3.fromRGB(255,255,255))

-- Score + Distance (bottom-centre)
local scoreLabel = makeLabel(hudGui, "ScoreLabel",
    UDim2.new(0.30, 0, 0.06, 0),
    UDim2.new(0.35, 0, 0.88, 0),
    "Score: 0  |  Dist: 0 m", Color3.fromRGB(255,220,100))

-- Controls hint (very bottom)
local hintLabel = makeLabel(hudGui, "HintLabel",
    UDim2.new(0.50, 0, 0.04, 0),
    UDim2.new(0.25, 0, 0.95, 0),
    "A/D - Lane   Space - Jump   S - Slide   Q/E/R/F - Abilities",
    Color3.fromRGB(180,180,180), Color3.fromRGB(0,0,0), 0.7,
    Enum.Font.Gotham)

-- Biome / milestone banner (centre)
local bannerLabel = makeLabel(hudGui, "BannerLabel",
    UDim2.new(0.60, 0, 0.10, 0),
    UDim2.new(0.20, 0, 0.07, 0),
    "", Color3.fromRGB(255,215,0), Color3.fromRGB(0,0,0), 0.35)
bannerLabel.Visible = false

-- Obstacle hit flash (full-screen red)
local hitFlash                      = Instance.new("Frame")
hitFlash.Name                       = "HitFlash"
hitFlash.Size                       = UDim2.new(1,0,1,0)
hitFlash.BackgroundColor3           = Color3.fromRGB(255,0,0)
hitFlash.BackgroundTransparency     = 1
hitFlash.ZIndex                     = 10
hitFlash.Parent                     = hudGui

-- Slide indicator
local slideLabel = makeLabel(hudGui, "SlideLabel",
    UDim2.new(0.12, 0, 0.05, 0),
    UDim2.new(0.44, 0, 0.82, 0),
    "SLIDING", Color3.fromRGB(100,255,200))
slideLabel.Visible = false

-- Ability active labels
local abilActiveLabel = makeLabel(hudGui, "AbilActiveLabel",
    UDim2.new(0.20, 0, 0.05, 0),
    UDim2.new(0.40, 0, 0.76, 0),
    "", Color3.fromRGB(200,150,255))
abilActiveLabel.Visible = false

-- ── Difficulty Selection Screen ───────────────────────────────────────────────
local diffGui = makeGui("DifficultySelect", false)
diffGui.Enabled = true

local diffBg = Instance.new("Frame")
diffBg.Size                  = UDim2.new(1,0,1,0)
diffBg.BackgroundColor3      = Color3.fromRGB(5,5,20)
diffBg.BackgroundTransparency = 0.0
diffBg.ZIndex                = 4
diffBg.Parent                = diffGui

makeLabel(diffBg, "Title",
    UDim2.new(0.8,0,0.12,0), UDim2.new(0.10,0,0.03,0),
    "ENDLESS RUNNER", Color3.fromRGB(255,220,50), Color3.fromRGB(0,0,0), 1,
    Enum.Font.GothamBlack, 5)

makeLabel(diffBg, "Subtitle",
    UDim2.new(0.8,0,0.06,0), UDim2.new(0.10,0,0.16,0),
    "Select Difficulty", Color3.fromRGB(180,180,255), Color3.fromRGB(0,0,0), 1,
    Enum.Font.GothamBold, 5)

local diffDescLabel = makeLabel(diffBg, "DiffDesc",
    UDim2.new(0.80,0,0.07,0), UDim2.new(0.10,0,0.22,0),
    "Choose a difficulty to begin your run", Color3.fromRGB(200,200,200),
    Color3.fromRGB(0,0,0), 1, Enum.Font.Gotham, 5)

local DIFFICULTIES = {
    { id="easy",       label="Easy",       desc="1 obstacle per row, 4 safe lanes. Learn movement and timing.",    color=Color3.fromRGB(80,200,80)   },
    { id="normal",     label="Normal",     desc="2 obstacles per row, 3 safe lanes. Balanced challenge.",           color=Color3.fromRGB(80,150,255)  },
    { id="medium",     label="Medium",     desc="3 obstacles per row, 2 safe lanes. Constant lane switching.",      color=Color3.fromRGB(255,180,50)  },
    { id="hard",       label="Hard",       desc="4 obstacles per row, 1 safe lane. React precisely.",               color=Color3.fromRGB(255,80,80)   },
    { id="impossible", label="IMPOSSIBLE", desc="Full lane blockage! Requires ability timing. Endgame challenge.",  color=Color3.fromRGB(200,50,200)  },
}

for i, diff in ipairs(DIFFICULTIES) do
    local yPos = 0.29 + (i-1) * 0.12
    local btn  = makeButton(diffBg, "DiffBtn_" .. diff.id,
        UDim2.new(0.60,0,0.09,0), UDim2.new(0.20,0,yPos,0),
        diff.label, diff.color)
    btn.ZIndex = 6

    -- Description next to button
    local descLbl = makeLabel(diffBg, "Desc_" .. diff.id,
        UDim2.new(0.60,0,0.05,0), UDim2.new(0.20,0,yPos+0.095,0),
        diff.desc, Color3.fromRGB(180,180,180), Color3.fromRGB(0,0,0), 0.8,
        Enum.Font.Gotham, 5)
    descLbl.Visible = false

    btn.MouseButton1Click:Connect(function()
        currentDifficulty = diff.id
        SelectDiffEvt:FireServer(diff.id)
        RequestRunEvt:FireServer()
        diffGui.Enabled = false
    end)

    btn.MouseEnter:Connect(function()
        descLbl.Visible = true
        diffDescLabel.Text = diff.desc
    end)
    btn.MouseLeave:Connect(function()
        descLbl.Visible = false
    end)
end

-- ── Results Screen ────────────────────────────────────────────────────────────
local resultsGui = makeGui("ResultsScreen", false)
resultsGui.Enabled = false

local resultsBg = Instance.new("Frame")
resultsBg.Size                   = UDim2.new(1,0,1,0)
resultsBg.BackgroundColor3       = Color3.fromRGB(5,5,20)
resultsBg.BackgroundTransparency = 0.1
resultsBg.ZIndex                 = 8
resultsBg.Parent                 = resultsGui

makeLabel(resultsBg, "RunOverTitle",
    UDim2.new(0.70,0,0.12,0), UDim2.new(0.15,0,0.03,0),
    "RUN OVER", Color3.fromRGB(255,80,80), Color3.fromRGB(0,0,0), 1,
    Enum.Font.GothamBlack, 9)

local resultStatsLabel = makeLabel(resultsBg, "StatsLabel",
    UDim2.new(0.70,0,0.45,0), UDim2.new(0.15,0,0.17,0),
    "Loading stats...", Color3.fromRGB(220,220,255), Color3.fromRGB(0,0,0), 0.5,
    Enum.Font.GothamBold, 9)

local retryBtn = makeButton(resultsBg, "RetryBtn",
    UDim2.new(0.35,0,0.09,0), UDim2.new(0.15,0,0.66,0),
    "RETRY SAME DIFFICULTY", Color3.fromRGB(50,180,80))
retryBtn.ZIndex = 9

local changeDiffBtn = makeButton(resultsBg, "ChangeDiffBtn",
    UDim2.new(0.35,0,0.09,0), UDim2.new(0.52,0,0.66,0),
    "CHANGE DIFFICULTY", Color3.fromRGB(80,100,200))
changeDiffBtn.ZIndex = 9

local hubBtn = makeButton(resultsBg, "HubBtn",
    UDim2.new(0.70,0,0.09,0), UDim2.new(0.15,0,0.78,0),
    "PROGRESSION HUB (Spend Currency)", Color3.fromRGB(180,100,50))
hubBtn.ZIndex = 9

-- ── Progression Hub Screen ────────────────────────────────────────────────────
local hubGui = makeGui("ProgressionHub", false)
hubGui.Enabled = false

local hubBg = Instance.new("Frame")
hubBg.Size                   = UDim2.new(1,0,1,0)
hubBg.BackgroundColor3       = Color3.fromRGB(5,5,20)
hubBg.BackgroundTransparency = 0.05
hubBg.ZIndex                 = 8
hubBg.Parent                 = hubGui

makeLabel(hubBg, "HubTitle",
    UDim2.new(0.70,0,0.10,0), UDim2.new(0.15,0,0.01,0),
    "PROGRESSION HUB", Color3.fromRGB(255,200,50), Color3.fromRGB(0,0,0), 1,
    Enum.Font.GothamBlack, 9)

local currencyLabel = makeLabel(hubBg, "CurrencyLabel",
    UDim2.new(0.40,0,0.06,0), UDim2.new(0.30,0,0.11,0),
    "Currency: 0", Color3.fromRGB(255,220,80), Color3.fromRGB(0,0,0), 0.5, Enum.Font.GothamBold, 9)

local UPGRADE_DISPLAY = {
    { id="move_speed",    label="Movement Efficiency",     desc="+Faster lane switching"     },
    { id="ability_cap",   label="Ability Capacity",        desc="+1 ability charge per level"},
    { id="ability_cd",    label="Ability Cooldown",        desc="-15% cooldown per level"    },
    { id="magnet_radius", label="Magnet Radius",           desc="+Item attraction range"     },
    { id="start_slow",    label="Starting Speed Control",  desc="-8% start speed per level"  },
    { id="score_mult",    label="Score Multiplier",        desc="+15% final score per level" },
}

local upgradeBtnRefs = {}

for i, upg in ipairs(UPGRADE_DISPLAY) do
    local col = (i-1) % 3
    local row = math.floor((i-1) / 3)
    local xPos = 0.05 + col * 0.33
    local yPos = 0.20 + row * 0.23

    local frame = Instance.new("Frame")
    frame.Size                  = UDim2.new(0.30, 0, 0.20, 0)
    frame.Position              = UDim2.new(xPos, 0, yPos, 0)
    frame.BackgroundColor3      = Color3.fromRGB(20,20,50)
    frame.BackgroundTransparency = 0.3
    frame.ZIndex                = 9
    frame.Parent                = hubBg

    local nameLbl = makeLabel(frame, "Name",
        UDim2.new(1,0,0.35,0), UDim2.new(0,0,0,0),
        upg.label, Color3.fromRGB(200,200,255), Color3.fromRGB(0,0,0), 1,
        Enum.Font.GothamBold, 10)

    local descLbl = makeLabel(frame, "Desc",
        UDim2.new(1,0,0.25,0), UDim2.new(0,0,0.35,0),
        upg.desc, Color3.fromRGB(160,160,200), Color3.fromRGB(0,0,0), 1,
        Enum.Font.Gotham, 10)

    local levelLbl = makeLabel(frame, "Level",
        UDim2.new(0.5,0,0.25,0), UDim2.new(0,0,0.60,0),
        "Lv 0 / 3", Color3.fromRGB(255,220,80), Color3.fromRGB(0,0,0), 1,
        Enum.Font.Gotham, 10)

    local buyBtn = makeButton(frame, "BuyBtn",
        UDim2.new(0.48,0,0.30,0), UDim2.new(0.50,0,0.62,0),
        "Buy", Color3.fromRGB(50,150,80))
    buyBtn.ZIndex = 11

    upgradeBtnRefs[upg.id] = { levelLbl=levelLbl, buyBtn=buyBtn, frame=frame }

    buyBtn.MouseButton1Click:Connect(function()
        BuyUpgradeEvt:FireServer(upg.id)
    end)
end

local hubBackBtn = makeButton(hubBg, "BackBtn",
    UDim2.new(0.30,0,0.07,0), UDim2.new(0.35,0,0.88,0),
    "BACK TO DIFFICULTY SELECT", Color3.fromRGB(80,80,150))
hubBackBtn.ZIndex = 9

local hubPlayBtn = makeButton(hubBg, "PlayBtn",
    UDim2.new(0.30,0,0.07,0), UDim2.new(0.35,0,0.79,0),
    "START RUN", Color3.fromRGB(80,180,80))
hubPlayBtn.ZIndex = 9

-- ── Run State Tracking ────────────────────────────────────────────────────────
local clientScore    = 0
local clientDist     = 0
local currentHealth  = 3
local maxHealth      = 3
local currentShields = 0
local currentCharges = 1
local currentSpeed   = 1.0
local totalCurrency  = 0

-- ── HUD Update Helpers ────────────────────────────────────────────────────────
local function updateHealthHUD(hp, maxHp, shields)
    local hearts = ""
    for i = 1, maxHp do
        hearts = hearts .. (i <= hp and "♥" or "♡")
        if i < maxHp then hearts = hearts .. " " end
    end
    healthLabel.Text = "HP: " .. hearts
    shieldLabel.Text = "Shield: " .. (shields > 0 and string.rep("🛡 ", shields) or "None")
end

local function updateAbilityHUD(charges)
    local cdInfo = ""
    for name, endTime in pairs(abilityCooldowns) do
        local remaining = endTime - os.clock()
        if remaining > 0 then
            cdInfo = cdInfo .. string.format("[%s CD:%.0fs] ", name:sub(1,3), remaining)
        else
            abilityCooldowns[name] = nil
        end
    end
    abilityLabel.Text = string.format("Charges: %d\n[Q]Phase [E]Invinc [R]Slow [F]Dash\n%s",
        charges, cdInfo ~= "" and cdInfo or "All abilities ready")
end

local function showBanner(text, color, duration)
    bannerLabel.Text    = text
    bannerLabel.TextColor3 = color or Color3.fromRGB(255,215,0)
    bannerLabel.Visible = true
    task.delay(duration or 3, function()
        if bannerLabel.Visible then bannerLabel.Visible = false end
    end)
end

-- ── Input State ───────────────────────────────────────────────────────────────
local keyHeld = {}
local lastLaneSent = 3
local laneSendCooldown = 0
local LANE_SEND_CD = 0.15   -- seconds between lane switch sends to avoid spamming

local function tryLaneSwitch(direction)
    local now = os.clock()
    if now - laneSendCooldown < LANE_SEND_CD then return end
    laneSendCooldown = now

    local newLane = math.clamp(currentLane + direction, 1, NUM_LANES)
    if newLane == currentLane then return end

    currentLane = newLane
    LaneSwitchEvt:FireServer(currentLane)
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local kc = input.KeyCode
    keyHeld[kc] = true

    -- Lane movement (one tap per press)
    if kc == Enum.KeyCode.A or kc == Enum.KeyCode.Left  then tryLaneSwitch(-1) end
    if kc == Enum.KeyCode.D or kc == Enum.KeyCode.Right then tryLaneSwitch(1)  end

    -- Jump
    if kc == Enum.KeyCode.Space then
        PlayerJumpEvt:FireServer()
    end

    -- Slide
    if kc == Enum.KeyCode.S or kc == Enum.KeyCode.Down then
        PlayerSlideEvt:FireServer()
        slideLabel.Visible = true
        task.delay(0.9, function() slideLabel.Visible = false end)
    end

    -- Abilities
    if kc == Enum.KeyCode.Q then
        UseAbilityEvt:FireServer("phase")
        abilActiveLabel.Text    = "PHASING"
        abilActiveLabel.TextColor3 = Color3.fromRGB(200,150,255)
        abilActiveLabel.Visible = true
        task.delay(2, function() abilActiveLabel.Visible = false end)
    elseif kc == Enum.KeyCode.E then
        UseAbilityEvt:FireServer("invincibility")
        abilActiveLabel.Text    = "INVINCIBLE"
        abilActiveLabel.TextColor3 = Color3.fromRGB(255,220,80)
        abilActiveLabel.Visible = true
        task.delay(3, function() abilActiveLabel.Visible = false end)
    elseif kc == Enum.KeyCode.R then
        UseAbilityEvt:FireServer("timeslow")
        abilActiveLabel.Text    = "TIME SLOW"
        abilActiveLabel.TextColor3 = Color3.fromRGB(80,200,255)
        abilActiveLabel.Visible = true
        task.delay(4, function() abilActiveLabel.Visible = false end)
    elseif kc == Enum.KeyCode.F then
        UseAbilityEvt:FireServer("dash")
        abilActiveLabel.Text    = "DASH!"
        abilActiveLabel.TextColor3 = Color3.fromRGB(255,150,80)
        abilActiveLabel.Visible = true
        task.delay(0.5, function() abilActiveLabel.Visible = false end)
        -- Update local lane after dash (+2)
        currentLane = math.clamp(currentLane + 2, 1, NUM_LANES)
    end
end)

UserInputService.InputEnded:Connect(function(input, _)
    keyHeld[input.KeyCode] = nil
end)

-- ── Distance-based RunnerAdvance ───────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not isRunActive then return end
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
        RunnerAdvanceEvt:FireServer()
    end
end)

-- ── Server Event Handlers ─────────────────────────────────────────────────────

RunStartEvt.OnClientEvent:Connect(function(difficulty)
    isRunActive       = true
    currentLane       = 3
    clientScore       = 0
    clientDist        = 0
    currentDifficulty = difficulty or "normal"
    abilityCooldowns  = {}
    lastAdvancePos    = nil

    hudGui.Enabled     = true
    resultsGui.Enabled = false
    diffGui.Enabled    = false
    hubGui.Enabled     = false

    local diffColor = DIFF_COLORS[difficulty] or Color3.fromRGB(200,200,200)
    diffLabel.Text       = (DIFF_NAMES[difficulty] or difficulty):upper()
    diffLabel.TextColor3 = diffColor

    updateHealthHUD(3, 3, 0)
    updateAbilityHUD(1)

    showBanner("RUN STARTED  |  " .. (DIFF_NAMES[difficulty] or difficulty):upper(),
               diffColor, 2.5)
end)

SpeedUpdateEvt.OnClientEvent:Connect(function(mult)
    currentSpeed = mult
    speedLabel.Text = string.format("Speed: %.1fx", mult)
end)

HealthUpdateEvt.OnClientEvent:Connect(function(hp, maxHp)
    currentHealth = hp
    maxHealth     = maxHp
    updateHealthHUD(hp, maxHp, currentShields)
    -- Flash red on damage
    hitFlash.BackgroundTransparency = 0.3
    task.delay(0.2, function() hitFlash.BackgroundTransparency = 1 end)
end)

ShieldUpdateEvt.OnClientEvent:Connect(function(shields)
    currentShields = shields
    updateHealthHUD(currentHealth, maxHealth, shields)
end)

AbilityUpdateEvt.OnClientEvent:Connect(function(charges)
    currentCharges = charges
    updateAbilityHUD(charges)
end)

AbilityCDEvt.OnClientEvent:Connect(function(abilityName, cd)
    abilityCooldowns[abilityName] = os.clock() + cd
    updateAbilityHUD(currentCharges)
end)

MilestoneEvt.OnClientEvent:Connect(function(distance)
    clientDist = distance
    scoreLabel.Text = string.format("Score: %d  |  Dist: %d m", clientScore, clientDist)
    showBanner(string.format("MILESTONE: %d m reached!", distance),
               Color3.fromRGB(255,215,0), 3)
end)

BiomeChangeEvt.OnClientEvent:Connect(function(biomeName)
    showBanner("Entering: " .. biomeName, Color3.fromRGB(150,255,200), 3)
end)

ObstacleHitEvt.OnClientEvent:Connect(function(obsType)
    showBanner("HIT: " .. obsType:gsub("_", " "):upper(), Color3.fromRGB(255,80,80), 1.5)
end)

MagnetStatusEvt.OnClientEvent:Connect(function(active, duration)
    if active then
        showBanner(string.format("MAGNET ACTIVE  (%ds)", duration or 10),
                   Color3.fromRGB(80,150,255), (duration or 10))
    end
end)

RunEndEvt.OnClientEvent:Connect(function(data)
    isRunActive = false
    hudGui.Enabled = false

    -- Update total currency display
    totalCurrency = data.totalCurrency or 0

    local statsText = string.format(
        "Difficulty:   %s\n\n" ..
        "Distance:     %d m\n" ..
        "Score:        %d\n" ..
        "Coins:        %d  |  Data Cubes: %d\n" ..
        "Time Survived: %d s\n" ..
        "No-Hit Bonus: +%d\n\n" ..
        "Total Currency: %d  (earned: %d)",
        (DIFF_NAMES[data.difficulty] or data.difficulty or "?"):upper(),
        data.distance or 0,
        data.score    or 0,
        data.coins    or 0, data.dataCubes  or 0,
        data.timeSurvived or 0,
        data.noHitBonus   or 0,
        data.totalCurrency or 0,
        (data.coins or 0) + (data.dataCubes or 0) * 5
    )
    resultStatsLabel.Text = statsText
    resultsGui.Enabled    = true
end)

CurrencyUpdateEvt.OnClientEvent:Connect(function(amount)
    totalCurrency = amount
    currencyLabel.Text = "Currency: " .. amount
end)

UpgradeResultEvt.OnClientEvent:Connect(function(success, idOrMsg, level, nextCost, maxLevel, name, desc)
    if success == "info" then
        -- Info update from ProgressionHub
        local upgradeId = idOrMsg
        local ref = upgradeBtnRefs[upgradeId]
        if ref then
            ref.levelLbl.Text = string.format("Lv %d / %d", level or 0, maxLevel or 3)
            local cost = nextCost or 999
            if (level or 0) >= (maxLevel or 3) then
                ref.buyBtn.Text              = "MAX"
                ref.buyBtn.BackgroundColor3  = Color3.fromRGB(100,100,100)
                ref.buyBtn.Active            = false
            else
                ref.buyBtn.Text              = "Buy (" .. cost .. ")"
                ref.buyBtn.BackgroundColor3  = Color3.fromRGB(50,150,80)
            end
        end
    elseif success == true then
        -- Successful purchase
        local upgradeId = idOrMsg
        local ref = upgradeBtnRefs[upgradeId]
        if ref then
            ref.levelLbl.Text = string.format("Lv %d / %d", level or 0, maxLevel or 3)
            if (level or 0) >= (maxLevel or 3) then
                ref.buyBtn.Text             = "MAX"
                ref.buyBtn.BackgroundColor3 = Color3.fromRGB(100,100,100)
            else
                ref.buyBtn.Text = "Buy (" .. (nextCost or "?") .. ")"
            end
        end
        showBanner("Upgrade purchased!", Color3.fromRGB(80,255,80), 2)
    else
        showBanner("Purchase failed: " .. tostring(idOrMsg), Color3.fromRGB(255,80,80), 2)
    end
end)

-- ── Button Callbacks ──────────────────────────────────────────────────────────
retryBtn.MouseButton1Click:Connect(function()
    resultsGui.Enabled = false
    SelectDiffEvt:FireServer(currentDifficulty)
    RequestRunEvt:FireServer()
end)

changeDiffBtn.MouseButton1Click:Connect(function()
    resultsGui.Enabled = false
    diffGui.Enabled    = true
end)

hubBtn.MouseButton1Click:Connect(function()
    resultsGui.Enabled = false
    hubGui.Enabled     = true
    currencyLabel.Text = "Currency: " .. totalCurrency
end)

hubBackBtn.MouseButton1Click:Connect(function()
    hubGui.Enabled  = false
    diffGui.Enabled = true
end)

hubPlayBtn.MouseButton1Click:Connect(function()
    hubGui.Enabled = false
    SelectDiffEvt:FireServer(currentDifficulty)
    RequestRunEvt:FireServer()
end)

-- ── Initialise HUD on load ────────────────────────────────────────────────────
task.spawn(function()
    task.wait(1)
    updateHealthHUD(3, 3, 0)
    updateAbilityHUD(1)
    speedLabel.Text = "Speed: 1.0x"
    scoreLabel.Text = "Score: 0  |  Dist: 0 m"
end)

-- ── Score Update via Distance Tracking ───────────────────────────────────────
-- Update scoreLabel every heartbeat when run is active
RunService.Heartbeat:Connect(function()
    if not isRunActive then return end
    local char = player.Character
    if not char then return end
    local ls = player:FindFirstChild("leaderstats")
    if ls then
        local scoreVal = ls:FindFirstChild("Score")
        local distVal  = ls:FindFirstChild("Distance")
        local coinsVal = ls:FindFirstChild("Coins")
        if scoreVal and distVal then
            scoreLabel.Text = string.format("Score: %d  |  Dist: %d m",
                scoreVal.Value, distVal.Value)
        end
    end
end)

print("[runnerController] Client script loaded.")
