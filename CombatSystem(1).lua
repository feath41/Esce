-- CombatSystem.lua
-- Sistem Continuous Auto-Lock Target (Mobile / Delta Executor & Studio Ready)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() or Players.LocalPlayer
local Camera = workspace.CurrentCamera or workspace:WaitForChild("Camera")

-- ============================================================================
-- KONFIGURASI SISTEM
-- ============================================================================
local Config = {
    MaxLockDistance = 80,          -- Jarak maksimal cari musuh (studs)
    BreakDistance = 95,            -- Jarak batas lepas target jika menjauh
    CameraSmoothing = 0.25,        -- Kehalusan gerakan kamera (0.1 halus, 1 instan)
    AutoFaceCharacter = true,      -- Karakter otomatis menghadap musuh
    CharacterFaceSpeed = 0.35,     -- Kecepatan putar badan karakter
    TargetPart = "HumanoidRootPart",
    LockMode = "Distance",         -- "Distance" (terdekat fisik) atau "Cursor" (terdekat layar/kursor)
    
    -- Konfigurasi Target (Player vs Bot/NPC)
    TargetType = "All",            -- "All" (Player & Bot), "NPC" (Hanya Bot), "Player" (Hanya Player)
    
    -- Konfigurasi Hitbox Target
    HitboxColor = Color3.fromRGB(255, 45, 75),       -- Warna Hitbox (Merah terang)
    HitboxTransparency = 0.5,                        -- Transparansi bagian dalam hitbox
    HitboxOutlineColor = Color3.fromRGB(255, 255, 255), -- Warna outline hitbox
    
    ToggleKey = Enum.KeyCode.Q,    -- Tombol Nyala/Mati (Keyboard)
    SwitchKey = Enum.KeyCode.Tab   -- Tombol Manual Switch musuh (Keyboard)
}

-- State Sistem
local AutoLockEnabled = false      -- Fitur ON atau OFF
local CurrentTargetPart = nil
local CurrentTargetChar = nil
local CurrentTargetIsNPC = false

-- ============================================================================
-- PENGATURAN PARENT GUI AMAN (DELTA EXECUTOR & STUDIO)
-- ============================================================================
local function GetSafeGuiParent()
    local targetParent = nil
    pcall(function()
        if typeof(gethui) == "function" then
            targetParent = gethui()
        elseif CoreGui then
            targetParent = CoreGui
        end
    end)
    if not targetParent then
        targetParent = LocalPlayer:WaitForChild("PlayerGui")
    end
    return targetParent
end

local SafeParent = GetSafeGuiParent()

-- Bersihkan GUI & Highlight lama jika script di-execute ulang
pcall(function()
    local oldGui = SafeParent:FindFirstChild("CombatTargetGui")
    if oldGui then oldGui:Destroy() end
    local oldHighlight = game:FindFirstChild("CombatTargetHitboxHighlight", true)
    if oldHighlight then oldHighlight:Destroy() end
    local oldBox = game:FindFirstChild("CombatTargetHitboxBox", true)
    if oldBox then oldBox:Destroy() end
end)

-- ============================================================================
-- PEMBUATAN UI LENGKAP (SCREEN GUI)
-- ============================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CombatTargetGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = SafeParent end)

-- Main HUD Frame (Bisa digeser dengan sentuhan layar HP / mouse)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 245, 0, 225)
MainFrame.Position = UDim2.new(0, 20, 0.5, -112)
MainFrame.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
MainFrame.BackgroundTransparency = 0.08
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 1.5
MainStroke.Color = Color3.fromRGB(55, 60, 75)
MainStroke.Parent = MainFrame

-- Drag System Halus (Mendukung Touch Screen Mobile / Delta)
local function EnableSmoothDrag(frame)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

pcall(function() EnableSmoothDrag(MainFrame) end)

-- Header
local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -20, 0, 26)
TitleLabel.Position = UDim2.new(0, 10, 0, 6)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "⚡ AUTO COMBAT LOCK"
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = MainFrame

-- Status Badge (OFF / SEARCHING / LOCKED)
local StatusBadge = Instance.new("TextLabel")
StatusBadge.Size = UDim2.new(0, 80, 0, 20)
StatusBadge.Position = UDim2.new(1, -90, 0, 9)
StatusBadge.BackgroundColor3 = Color3.fromRGB(50, 52, 65)
StatusBadge.Text = "OFF"
StatusBadge.TextColor3 = Color3.fromRGB(160, 165, 180)
StatusBadge.Font = Enum.Font.GothamBold
StatusBadge.TextSize = 10
StatusBadge.Parent = MainFrame

local BadgeCorner = Instance.new("UICorner")
BadgeCorner.CornerRadius = UDim.new(0, 6)
BadgeCorner.Parent = StatusBadge

-- Target Info Card (Nama, Jarak, Status)
local InfoCard = Instance.new("Frame")
InfoCard.Size = UDim2.new(1, -20, 0, 58)
InfoCard.Position = UDim2.new(0, 10, 0, 38)
InfoCard.BackgroundColor3 = Color3.fromRGB(15, 17, 21)
InfoCard.BorderSizePixel = 0
InfoCard.Parent = MainFrame

local InfoCorner = Instance.new("UICorner")
InfoCorner.CornerRadius = UDim.new(0, 6)
InfoCorner.Parent = InfoCard

local TargetNameLabel = Instance.new("TextLabel")
TargetNameLabel.Size = UDim2.new(1, -12, 0, 18)
TargetNameLabel.Position = UDim2.new(0, 8, 0, 6)
TargetNameLabel.BackgroundTransparency = 1
TargetNameLabel.Text = "Status: Fitur Nonaktif"
TargetNameLabel.TextColor3 = Color3.fromRGB(190, 195, 205)
TargetNameLabel.Font = Enum.Font.GothamMedium
TargetNameLabel.TextSize = 12
TargetNameLabel.TextXAlignment = Enum.TextXAlignment.Left
TargetNameLabel.Parent = InfoCard

local DistanceLabel = Instance.new("TextLabel")
DistanceLabel.Size = UDim2.new(1, -12, 0, 14)
DistanceLabel.Position = UDim2.new(0, 8, 0, 24)
DistanceLabel.BackgroundTransparency = 1
DistanceLabel.Text = "Jarak: --"
DistanceLabel.TextColor3 = Color3.fromRGB(130, 135, 150)
DistanceLabel.Font = Enum.Font.Gotham
DistanceLabel.TextSize = 11
DistanceLabel.TextXAlignment = Enum.TextXAlignment.Left
DistanceLabel.Parent = InfoCard

-- Health Bar Background
local HealthBarBg = Instance.new("Frame")
HealthBarBg.Size = UDim2.new(1, -16, 0, 6)
HealthBarBg.Position = UDim2.new(0, 8, 0, 44)
HealthBarBg.BackgroundColor3 = Color3.fromRGB(35, 38, 48)
HealthBarBg.BorderSizePixel = 0
HealthBarBg.Parent = InfoCard

local HealthBarCorner = Instance.new("UICorner")
HealthBarCorner.CornerRadius = UDim.new(1, 0)
HealthBarCorner.Parent = HealthBarBg

-- Health Bar Fill
local HealthBarFill = Instance.new("Frame")
HealthBarFill.Size = UDim2.new(0, 0, 1, 0)
HealthBarFill.BackgroundColor3 = Color3.fromRGB(50, 205, 120)
HealthBarFill.BorderSizePixel = 0
HealthBarFill.Parent = HealthBarBg

local HealthBarFillCorner = Instance.new("UICorner")
HealthBarFillCorner.CornerRadius = UDim.new(1, 0)
HealthBarFillCorner.Parent = HealthBarFill

-- Tombol Toggle ON/OFF Utama
local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(0.65, -12, 0, 30)
ToggleButton.Position = UDim2.new(0, 10, 0, 102)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 135, 240)
ToggleButton.Text = "NYALAKAN"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.TextSize = 12
ToggleButton.BorderSizePixel = 0
ToggleButton.Parent = MainFrame

local ToggleBtnCorner = Instance.new("UICorner")
ToggleBtnCorner.CornerRadius = UDim.new(0, 6)
ToggleBtnCorner.Parent = ToggleButton

-- Tombol Switch Target Manual
local SwitchButton = Instance.new("TextButton")
SwitchButton.Size = UDim2.new(0.35, -4, 0, 30)
SwitchButton.Position = UDim2.new(0.65, 4, 0, 102)
SwitchButton.BackgroundColor3 = Color3.fromRGB(42, 45, 56)
SwitchButton.Text = "NEXT"
SwitchButton.TextColor3 = Color3.fromRGB(220, 220, 220)
SwitchButton.Font = Enum.Font.GothamBold
SwitchButton.TextSize = 11
SwitchButton.BorderSizePixel = 0
SwitchButton.Parent = MainFrame

local SwitchBtnCorner = Instance.new("UICorner")
SwitchBtnCorner.CornerRadius = UDim.new(0, 6)
SwitchBtnCorner.Parent = SwitchButton

-- Tombol Toggle Mode Pencarian (Jarak vs Layar)
local ModeButton = Instance.new("TextButton")
ModeButton.Size = UDim2.new(1, -20, 0, 26)
ModeButton.Position = UDim2.new(0, 10, 0, 138)
ModeButton.BackgroundColor3 = Color3.fromRGB(30, 33, 42)
ModeButton.Text = "Mode: Jarak Fisik Terdekat [3D]"
ModeButton.TextColor3 = Color3.fromRGB(180, 185, 200)
ModeButton.Font = Enum.Font.GothamMedium
ModeButton.TextSize = 11
ModeButton.BorderSizePixel = 0
ModeButton.Parent = MainFrame

local ModeBtnCorner = Instance.new("UICorner")
ModeBtnCorner.CornerRadius = UDim.new(0, 6)
ModeBtnCorner.Parent = ModeButton

-- Tombol Filter Target (Semua / Bot Saja / Player Saja)
local TargetTypeButton = Instance.new("TextButton")
TargetTypeButton.Size = UDim2.new(1, -20, 0, 26)
TargetTypeButton.Position = UDim2.new(0, 10, 0, 170)
TargetTypeButton.BackgroundColor3 = Color3.fromRGB(30, 33, 42)
TargetTypeButton.Text = "Target: Player + Bot / NPC"
TargetTypeButton.TextColor3 = Color3.fromRGB(80, 210, 255)
TargetTypeButton.Font = Enum.Font.GothamMedium
TargetTypeButton.TextSize = 11
TargetTypeButton.BorderSizePixel = 0
TargetTypeButton.Parent = MainFrame

local TargetTypeCorner = Instance.new("UICorner")
TargetTypeCorner.CornerRadius = UDim.new(0, 6)
TargetTypeCorner.Parent = TargetTypeButton

-- ============================================================================
-- HITBOX VISUAL SYSTEM (HIGHLIGHT + SELECTIONBOX)
-- ============================================================================

local TargetHighlight = Instance.new("Highlight")
TargetHighlight.Name = "CombatTargetHitboxHighlight"
TargetHighlight.FillColor = Config.HitboxColor
TargetHighlight.FillTransparency = Config.HitboxTransparency
TargetHighlight.OutlineColor = Config.HitboxOutlineColor
TargetHighlight.OutlineTransparency = 0.1
TargetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

local TargetHitboxBox = Instance.new("SelectionBox")
TargetHitboxBox.Name = "CombatTargetHitboxBox"
TargetHitboxBox.Color3 = Config.HitboxColor
TargetHitboxBox.SurfaceColor3 = Config.HitboxColor
TargetHitboxBox.SurfaceTransparency = 0.65
TargetHitboxBox.LineThickness = 0.05

-- ============================================================================
-- LOGIKA UTAMA COMBAT (PLAYER & BOT SUPPORT) DILINDUNGI PCALL
-- ============================================================================

local function GetTargetPart(char)
    if not char then return nil end
    return char:FindFirstChild(Config.TargetPart) 
        or char:FindFirstChild("HumanoidRootPart") 
        or char:FindFirstChild("Torso") 
        or char:FindFirstChild("UpperTorso")
end

local function IsPlayerCharacter(char)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == char then
            return true, p
        end
    end
    return false, nil
end

local function IsValidEnemy(char)
    local success, result = pcall(function()
        if not char or not char.Parent then return false end
        if char == LocalPlayer.Character then return false end

        local hum = char:FindFirstChildOfClass("Humanoid")
        local root = GetTargetPart(char)
        return hum ~= nil and hum.Health > 0 and root ~= nil and root:IsA("BasePart")
    end)
    return success and result == true
end

local function GetEnemiesSortedByDistance()
    local enemies = {}
    local checked = {}

    pcall(function()
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local myRoot = GetTargetPart(myChar)
        if not myRoot then return end
        local myPos = myRoot.Position

        local function ConsiderModel(model)
            if not model or not model:IsA("Model") or checked[model] then return end
            checked[model] = true

            if model ~= myChar and IsValidEnemy(model) then
                local isPlayer, playerObj = IsPlayerCharacter(model)
                local allowed = false

                if Config.TargetType == "All" then
                    allowed = true
                elseif Config.TargetType == "NPC" and not isPlayer then
                    allowed = true
                elseif Config.TargetType == "Player" and isPlayer then
                    allowed = true
                end

                if allowed then
                    local root = GetTargetPart(model)
                    if root then
                        local dist = (root.Position - myPos).Magnitude
                        if dist <= Config.MaxLockDistance then
                            table.insert(enemies, {
                                Character = model,
                                Part = root,
                                Distance = dist,
                                IsNPC = not isPlayer,
                                Name = isPlayer and playerObj.DisplayName or model.Name
                            })
                        end
                    end
                end
            end
        end

        -- 1. Scan Player
        if Config.TargetType == "All" or Config.TargetType == "Player" then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    ConsiderModel(p.Character)
                end
            end
        end

        -- 2. Scan Bot/NPC di Workspace
        if Config.TargetType == "All" or Config.TargetType == "NPC" then
            for _, child in ipairs(workspace:GetChildren()) do
                if child:IsA("Model") then
                    ConsiderModel(child)
                elseif child:IsA("Folder") or child:IsA("Model") then
                    local lowerName = string.lower(child.Name)
                    if string.find(lowerName, "npc") or string.find(lowerName, "enemi") 
                       or string.find(lowerName, "mob") or string.find(lowerName, "bot") 
                       or string.find(lowerName, "monster") or string.find(lowerName, "zombie") 
                       or string.find(lowerName, "entity") or string.find(lowerName, "creature") then
                        for _, sub in ipairs(child:GetChildren()) do
                            if sub:IsA("Model") then
                                ConsiderModel(sub)
                            end
                        end
                    end
                end
            end
        end

        table.sort(enemies, function(a, b)
            return a.Distance < b.Distance
        end)
    end)

    return enemies
end

local function FindBestTarget()
    local best = nil

    pcall(function()
        local enemies = GetEnemiesSortedByDistance()
        if #enemies == 0 then return end

        if Config.LockMode == "Distance" then
            best = enemies[1]
        else
            local mousePos = UserInputService:GetMouseLocation()
            local shortestScreenDist = math.huge

            for _, entry in ipairs(enemies) do
                local screenPos, onScreen = Camera:WorldToViewportPoint(entry.Part.Position)
                if onScreen then
                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if screenDist < shortestScreenDist then
                        shortestScreenDist = screenDist
                        best = entry
                    end
                end
            end

            if not best then
                best = enemies[1]
            end
        end
    end)

    return best
end

local function SetTarget(entry)
    pcall(function()
        if entry and entry.Part and entry.Character and IsValidEnemy(entry.Character) then
            CurrentTargetChar = entry.Character
            CurrentTargetPart = entry.Part
            CurrentTargetIsNPC = entry.IsNPC

            TargetHighlight.Adornee = entry.Character
            TargetHighlight.Parent = entry.Character

            TargetHitboxBox.Adornee = entry.Part
            TargetHitboxBox.Parent = entry.Part
        else
            CurrentTargetChar = nil
            CurrentTargetPart = nil
            CurrentTargetIsNPC = false

            TargetHighlight.Adornee = nil
            TargetHighlight.Parent = nil

            TargetHitboxBox.Adornee = nil
            TargetHitboxBox.Parent = nil
        end
    end)
end

local function UpdateUI()
    pcall(function()
        if not AutoLockEnabled then
            StatusBadge.Text = "OFF"
            StatusBadge.BackgroundColor3 = Color3.fromRGB(50, 52, 65)
            StatusBadge.TextColor3 = Color3.fromRGB(160, 165, 180)
            MainStroke.Color = Color3.fromRGB(55, 60, 75)

            ToggleButton.Text = "NYALAKAN"
            ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 135, 240)

            TargetNameLabel.Text = "Status: Fitur Nonaktif"
            DistanceLabel.Text = "Jarak: --"
            HealthBarFill.Size = UDim2.new(0, 0, 1, 0)
            return
        end

        ToggleButton.Text = "MATIKAN"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(220, 45, 65)

        if CurrentTargetChar and IsValidEnemy(CurrentTargetChar) and CurrentTargetPart then
            StatusBadge.Text = "LOCKED"
            StatusBadge.BackgroundColor3 = Color3.fromRGB(230, 45, 70)
            StatusBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
            MainStroke.Color = Color3.fromRGB(230, 45, 70)

            local tag = CurrentTargetIsNPC and "[BOT] " or "[PLAYER] "
            TargetNameLabel.Text = tag .. tostring(CurrentTargetChar.Name)

            local hum = CurrentTargetChar:FindFirstChildOfClass("Humanoid")
            local myChar = LocalPlayer.Character
            local myRoot = GetTargetPart(myChar)

            if hum and myRoot and CurrentTargetPart then
                local dist = math.floor((CurrentTargetPart.Position - myRoot.Position).Magnitude)
                DistanceLabel.Text = string.format("Jarak: %d studs | HP: %d/%d", dist, math.floor(hum.Health), math.floor(hum.MaxHealth))

                local healthRatio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                HealthBarFill.Size = UDim2.new(healthRatio, 0, 1, 0)
                if healthRatio > 0.5 then
                    HealthBarFill.BackgroundColor3 = Color3.fromRGB(50, 205, 120)
                elseif healthRatio > 0.25 then
                    HealthBarFill.BackgroundColor3 = Color3.fromRGB(240, 175, 45)
                else
                    HealthBarFill.BackgroundColor3 = Color3.fromRGB(235, 50, 50)
                end
            end
        else
            StatusBadge.Text = "MENCARI..."
            StatusBadge.BackgroundColor3 = Color3.fromRGB(220, 150, 30)
            StatusBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
            MainStroke.Color = Color3.fromRGB(220, 150, 30)

            TargetNameLabel.Text = "Status: Mencari target terdekat..."
            DistanceLabel.Text = "Jarak: Menunggu musuh..."
            HealthBarFill.Size = UDim2.new(0, 0, 1, 0)
        end
    end)
end

local function ToggleAutoLock()
    pcall(function()
        AutoLockEnabled = not AutoLockEnabled

        if AutoLockEnabled then
            local best = FindBestTarget()
            SetTarget(best)
        else
            SetTarget(nil)
        end

        UpdateUI()
    end)
end

local function SwitchTarget()
    pcall(function()
        if not AutoLockEnabled then return end
        local enemies = GetEnemiesSortedByDistance()
        if #enemies <= 1 then return end

        for i, entry in ipairs(enemies) do
            if entry.Character == CurrentTargetChar then
                local nextIdx = (i % #enemies) + 1
                SetTarget(enemies[nextIdx])
                UpdateUI()
                return
            end
        end

        SetTarget(enemies[1])
        UpdateUI()
    end)
end

-- Event Listeners (Tombol UI)
ToggleButton.MouseButton1Click:Connect(function()
    pcall(ToggleAutoLock)
end)

SwitchButton.MouseButton1Click:Connect(function()
    pcall(SwitchTarget)
end)

ModeButton.MouseButton1Click:Connect(function()
    pcall(function()
        if Config.LockMode == "Distance" then
            Config.LockMode = "Cursor"
            ModeButton.Text = "Mode: Kursor / Layar [2D]"
        else
            Config.LockMode = "Distance"
            ModeButton.Text = "Mode: Jarak Fisik Terdekat [3D]"
        end
    end)
end)

TargetTypeButton.MouseButton1Click:Connect(function()
    pcall(function()
        if Config.TargetType == "All" then
            Config.TargetType = "NPC"
            TargetTypeButton.Text = "Target: Hanya Bot / NPC"
            TargetTypeButton.TextColor3 = Color3.fromRGB(255, 175, 50)
        elseif Config.TargetType == "NPC" then
            Config.TargetType = "Player"
            TargetTypeButton.Text = "Target: Hanya Player"
            TargetTypeButton.TextColor3 = Color3.fromRGB(255, 100, 120)
        else
            Config.TargetType == "All"
            TargetTypeButton.Text = "Target: Player + Bot / NPC"
            TargetTypeButton.TextColor3 = Color3.fromRGB(80, 210, 255)
        end

        if AutoLockEnabled then
            local best = FindBestTarget()
            SetTarget(best)
        end
    end)
end)

-- Keyboard Event (Jika pakai keyboard / emulator)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    pcall(function()
        if input.KeyCode == Config.ToggleKey then
            ToggleAutoLock()
        elseif input.KeyCode == Config.SwitchKey then
            SwitchTarget()
        end
    end)
end)

-- Loop Utama RenderStepped
RunService.RenderStepped:Connect(function(dt)
    pcall(function()
        UpdateUI()

        if not AutoLockEnabled then return end

        local myChar = LocalPlayer.Character
        local myRoot = GetTargetPart(myChar)
        if not myRoot then return end

        local targetNeedsRefresh = false

        if not CurrentTargetChar or not CurrentTargetPart or not IsValidEnemy(CurrentTargetChar) then
            targetNeedsRefresh = true
        else
            local distance = (CurrentTargetPart.Position - myRoot.Position).Magnitude
            if distance > Config.BreakDistance then
                targetNeedsRefresh = true
            end
        end

        if targetNeedsRefresh then
            local newTarget = FindBestTarget()
            SetTarget(newTarget)
        end

        if CurrentTargetPart and CurrentTargetChar and IsValidEnemy(CurrentTargetChar) then
            -- 1. Camera Tracking
            local camPos = Camera.CFrame.Position
            local targetPos = CurrentTargetPart.Position

            if (targetPos - camPos).Magnitude > 0.01 then
                local targetCamCFrame = CFrame.new(camPos, targetPos)
                Camera.CFrame = Camera.CFrame:Lerp(targetCamCFrame, Config.CameraSmoothing)
            end

            -- 2. Hadap Karakter ke Musuh/Bot
            if Config.AutoFaceCharacter then
                local lookVector = Vector3.new(targetPos.X, myRoot.Position.Y, targetPos.Z)
                if (lookVector - myRoot.Position).Magnitude > 0.01 then
                    local targetCharCFrame = CFrame.new(myRoot.Position, lookVector)
                    myRoot.CFrame = myRoot.CFrame:Lerp(targetCharCFrame, Config.CharacterFaceSpeed)
                end
            end
        end
    end)
end)

print("[AutoCombat] Berhasil di-load! Gunakan tombol UI untuk mengaktifkan.")
