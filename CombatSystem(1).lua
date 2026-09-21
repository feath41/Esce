-- CombatSystem.lua
-- Sistem Continuous Auto-Lock Target (Dropdown UI + Mobile/Delta Ready)

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
    
    -- Pilihan Part Target: "Head" atau "Torso" (RootPart/Torso)
    TargetPartChoice = "Torso",
    
    -- Pilihan Mode Aim: "Distance" (Jarak 3D Terdekat) atau "Cursor" (Terdekat ke Layar/Kursor)
    LockMode = "Distance",
    
    -- Pilihan Target Entity: "All" (Player + Bot), "NPC" (Hanya Bot), "Player" (Hanya Player)
    TargetType = "All",
    
    -- Konfigurasi Hitbox Visual
    HitboxColor = Color3.fromRGB(255, 45, 75),       -- Warna Hitbox (Merah terang)
    HitboxTransparency = 0.5,                        -- Transparansi bagian dalam hitbox
    HitboxOutlineColor = Color3.fromRGB(255, 255, 255), -- Warna outline hitbox
    
    -- Pengaturan Prioritas Target Terdekat Real-Time
    DynamicSwitchCloser = true,    -- Otomatis pindah jika ada musuh yang lebih dekat
    SwitchDistanceMargin = 3,      -- Margin jarak (studs) agar tidak flicker
    
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

-- Bersihkan GUI lama jika script di-execute ulang
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

-- Main Frame (Ukuran dinamis untuk menampung dropdown)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 255, 0, 310)
MainFrame.Position = UDim2.new(0, 20, 0.5, -155)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
MainFrame.BackgroundTransparency = 0.05
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

-- Header Judul
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

-- Target Info Card (Nama, Jarak, HP Bar)
local InfoCard = Instance.new("Frame")
InfoCard.Size = UDim2.new(1, -20, 0, 56)
InfoCard.Position = UDim2.new(0, 10, 0, 36)
InfoCard.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
InfoCard.BorderSizePixel = 0
InfoCard.Parent = MainFrame

local InfoCorner = Instance.new("UICorner")
InfoCorner.CornerRadius = UDim.new(0, 6)
InfoCorner.Parent = InfoCard

local TargetNameLabel = Instance.new("TextLabel")
TargetNameLabel.Size = UDim2.new(1, -12, 0, 18)
TargetNameLabel.Position = UDim2.new(0, 8, 0, 5)
TargetNameLabel.BackgroundTransparency = 1
TargetNameLabel.Text = "Status: Fitur Nonaktif"
TargetNameLabel.TextColor3 = Color3.fromRGB(190, 195, 205)
TargetNameLabel.Font = Enum.Font.GothamMedium
TargetNameLabel.TextSize = 11
TargetNameLabel.TextXAlignment = Enum.TextXAlignment.Left
TargetNameLabel.Parent = InfoCard

local DistanceLabel = Instance.new("TextLabel")
DistanceLabel.Size = UDim2.new(1, -12, 0, 14)
DistanceLabel.Position = UDim2.new(0, 8, 0, 23)
DistanceLabel.BackgroundTransparency = 1
DistanceLabel.Text = "Jarak: --"
DistanceLabel.TextColor3 = Color3.fromRGB(130, 135, 150)
DistanceLabel.Font = Enum.Font.Gotham
DistanceLabel.TextSize = 11
DistanceLabel.TextXAlignment = Enum.TextXAlignment.Left
DistanceLabel.Parent = InfoCard

-- Health Bar Background
local HealthBarBg = Instance.new("Frame")
HealthBarBg.Size = UDim2.new(1, -16, 0, 5)
HealthBarBg.Position = UDim2.new(0, 8, 0, 42)
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
ToggleButton.Size = UDim2.new(0.65, -12, 0, 28)
ToggleButton.Position = UDim2.new(0, 10, 0, 98)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 135, 240)
ToggleButton.Text = "NYALAKAN (Q)"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.TextSize = 11
ToggleButton.BorderSizePixel = 0
ToggleButton.Parent = MainFrame

local ToggleBtnCorner = Instance.new("UICorner")
ToggleBtnCorner.CornerRadius = UDim.new(0, 6)
ToggleBtnCorner.Parent = ToggleButton

-- Tombol Switch Target Manual
local SwitchButton = Instance.new("TextButton")
SwitchButton.Size = UDim2.new(0.35, -4, 0, 28)
SwitchButton.Position = UDim2.new(0.65, 4, 0, 98)
SwitchButton.BackgroundColor3 = Color3.fromRGB(38, 42, 52)
SwitchButton.Text = "NEXT (TAB)"
SwitchButton.TextColor3 = Color3.fromRGB(220, 220, 220)
SwitchButton.Font = Enum.Font.GothamBold
SwitchButton.TextSize = 10
SwitchButton.BorderSizePixel = 0
SwitchButton.Parent = MainFrame

local SwitchBtnCorner = Instance.new("UICorner")
SwitchBtnCorner.CornerRadius = UDim.new(0, 6)
SwitchBtnCorner.Parent = SwitchButton

-- ============================================================================
-- KOMPONEN DROPDOWN MODULAR
-- ============================================================================
local activeDropdownList = nil

local function CloseAllDropdowns()
    if activeDropdownList then
        activeDropdownList.Visible = false
        activeDropdownList = nil
    end
end

-- Menutup dropdown jika user klik area luar
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        -- Jangan langsung tutup jika user mengeklik tombol dropdown itu sendiri
    end
end)

local function CreateDropdown(parent, labelText, yPos, options, defaultKey, onSelect)
    -- Label Penjelas di Atas Dropdown
    local dLabel = Instance.new("TextLabel")
    dLabel.Size = UDim2.new(1, -20, 0, 14)
    dLabel.Position = UDim2.new(0, 10, 0, yPos)
    dLabel.BackgroundTransparency = 1
    dLabel.Text = labelText
    dLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
    dLabel.Font = Enum.Font.GothamMedium
    dLabel.TextSize = 10
    dLabel.TextXAlignment = Enum.TextXAlignment.Left
    dLabel.Parent = parent

    -- Tombol Header Dropdown
    local dButton = Instance.new("TextButton")
    dButton.Size = UDim2.new(1, -20, 0, 26)
    dButton.Position = UDim2.new(0, 10, 0, yPos + 16)
    dButton.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    dButton.BorderSizePixel = 0
    dButton.Font = Enum.Font.Gotham
    dButton.TextSize = 11
    dButton.TextColor3 = Color3.fromRGB(230, 235, 245)
    dButton.TextXAlignment = Enum.TextXAlignment.Left
    dButton.ZIndex = 2
    dButton.Parent = parent

    local dBtnCorner = Instance.new("UICorner")
    dBtnCorner.CornerRadius = UDim.new(0, 6)
    dBtnCorner.Parent = dButton

    local dBtnStroke = Instance.new("UIStroke")
    dBtnStroke.Thickness = 1
    dBtnStroke.Color = Color3.fromRGB(45, 50, 65)
    dBtnStroke.Parent = dButton

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 20, 1, 0)
    arrow.Position = UDim2.new(1, -25, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "▼"
    arrow.TextColor3 = Color3.fromRGB(140, 145, 160)
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 9
    arrow.ZIndex = 2
    arrow.Parent = dButton

    -- Container List Pilihan (Floating Menu)
    local listFrame = Instance.new("Frame")
    listFrame.Size = UDim2.new(1, -20, 0, #options * 24 + 4)
    listFrame.Position = UDim2.new(0, 10, 0, yPos + 44)
    listFrame.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
    listFrame.BorderSizePixel = 0
    listFrame.Visible = false
    listFrame.ZIndex = 10 -- Always on top of other elements
    listFrame.Parent = parent

    local listCorner = Instance.new("UICorner")
    listCorner.CornerRadius = UDim.new(0, 6)
    listCorner.Parent = listFrame

    local listStroke = Instance.new("UIStroke")
    listStroke.Thickness = 1
    listStroke.Color = Color3.fromRGB(60, 65, 80)
    listStroke.Parent = listFrame

    -- Isi opsi dalam dropdown
    for idx, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, -6, 0, 22)
        optBtn.Position = UDim2.new(0, 3, 0, (idx - 1) * 24 + 2)
        optBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
        optBtn.BackgroundTransparency = 1
        optBtn.Text = "  " .. opt.Name
        optBtn.TextColor3 = Color3.fromRGB(200, 205, 215)
        optBtn.Font = Enum.Font.Gotham
        optBtn.TextSize = 10
        optBtn.TextXAlignment = Enum.TextXAlignment.Left
        optBtn.ZIndex = 11
        optBtn.Parent = listFrame

        local optCorner = Instance.new("UICorner")
        optCorner.CornerRadius = UDim.new(0, 4)
        optCorner.Parent = optBtn

        -- Set label default
        if opt.Value == defaultKey then
            dButton.Text = "  " .. opt.Name
            optBtn.TextColor3 = Color3.fromRGB(80, 210, 255)
        end

        optBtn.MouseButton1Click:Connect(function()
            dButton.Text = "  " .. opt.Name
            arrow.Text = "▼"
            listFrame.Visible = false
            activeDropdownList = nil

            -- Reset warna opsi
            for _, child in ipairs(listFrame:GetChildren()) do
                if child:IsA("TextButton") then
                    child.TextColor3 = Color3.fromRGB(200, 205, 215)
                end
            end
            optBtn.TextColor3 = Color3.fromRGB(80, 210, 255)

            onSelect(opt.Value)
        end)
    end

    -- Toggle dropdown buka/tutup
    dButton.MouseButton1Click:Connect(function()
        if listFrame.Visible then
            listFrame.Visible = false
            arrow.Text = "▼"
            if activeDropdownList == listFrame then
                activeDropdownList = nil
            end
        else
            CloseAllDropdowns()
            listFrame.Visible = true
            arrow.Text = "▲"
            activeDropdownList = listFrame
        end
    end)

    return dButton
end

-- ============================================================================
-- INISIALISASI 3 DROPDOWN
-- ============================================================================

-- 1. Dropdown Target Part (Head / Torso)
CreateDropdown(MainFrame, "TARGET BODY PART:", 132, {
    { Name = "Torso / Badan (HumanoidRootPart)", Value = "Torso" },
    { Name = "Head / Kepala", Value = "Head" }
}, Config.TargetPartChoice, function(val)
    Config.TargetPartChoice = val
    if AutoLockEnabled and CurrentTargetChar then
        -- Update kuncian part target saat ini
        CurrentTargetPart = GetTargetPart(CurrentTargetChar)
    end
end)

-- 2. Dropdown Mode Bidikan (Jarak 3D vs Kursor 2D)
CreateDropdown(MainFrame, "AIM LOCK MODE:", 188, {
    { Name = "Jarak 3D Terdekat (Distance)", Value = "Distance" },
    { Name = "Kursor / Tengah Layar (2D)", Value = "Cursor" }
}, Config.LockMode, function(val)
    Config.LockMode = val
end)

-- 3. Dropdown Tipe Target (Semua / Bot Saja / Player Saja)
CreateDropdown(MainFrame, "TARGET ENTITY FILTER:", 244, {
    { Name = "Semua (Player + Bot / NPC)", Value = "All" },
    { Name = "Hanya Bot / NPC / Monster", Value = "NPC" },
    { Name = "Hanya Pemain Lain (Player)", Value = "Player" }
}, Config.TargetType, function(val)
    Config.TargetType = val
    if AutoLockEnabled then
        local best = FindBestTarget()
        SetTarget(best)
    end
end)

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
-- LOGIKA UTAMA COMBAT DILINDUNGI PCALL
-- ============================================================================

-- Mendapatkan Part Target sesuai pilihan Dropdown ("Head" atau "Torso")
function GetTargetPart(char)
    if not char then return nil end
    
    if Config.TargetPartChoice == "Head" then
        local head = char:FindFirstChild("Head")
        if head and head:IsA("BasePart") then return head end
    end
    
    -- Fallback ke Torso / RootPart
    return char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Head")
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

function FindBestTarget()
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

function SetTarget(entry)
    pcall(function()
        if entry and entry.Part and entry.Character and IsValidEnemy(entry.Character) then
            CurrentTargetChar = entry.Character
            CurrentTargetPart = GetTargetPart(entry.Character)
            CurrentTargetIsNPC = entry.IsNPC

            TargetHighlight.Adornee = entry.Character
            TargetHighlight.Parent = entry.Character

            TargetHitboxBox.Adornee = CurrentTargetPart
            TargetHitboxBox.Parent = CurrentTargetPart
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

            ToggleButton.Text = "NYALAKAN (Q)"
            ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 135, 240)

            TargetNameLabel.Text = "Status: Fitur Nonaktif"
            DistanceLabel.Text = "Jarak: --"
            HealthBarFill.Size = UDim2.new(0, 0, 1, 0)
            return
        end

        ToggleButton.Text = "MATIKAN (Q)"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(220, 45, 65)

        if CurrentTargetChar and IsValidEnemy(CurrentTargetChar) and CurrentTargetPart then
            StatusBadge.Text = "LOCKED"
            StatusBadge.BackgroundColor3 = Color3.fromRGB(230, 45, 70)
            StatusBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
            MainStroke.Color = Color3.fromRGB(230, 45, 70)

            local tag = CurrentTargetIsNPC and "[BOT] " or "[PLAYER] "
            local partTag = Config.TargetPartChoice == "Head" and " (HEAD)" or " (TORSO)"
            TargetNameLabel.Text = tag .. tostring(CurrentTargetChar.Name) .. partTag

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

        -- Cari musuh terbaik/terdekat secara real-time
        local bestTarget = FindBestTarget()

        if not CurrentTargetChar or not CurrentTargetPart or not IsValidEnemy(CurrentTargetChar) then
            SetTarget(bestTarget)
        else
            local curDist = (CurrentTargetPart.Position - myRoot.Position).Magnitude
            if curDist > Config.BreakDistance then
                SetTarget(bestTarget)
            elseif Config.DynamicSwitchCloser and bestTarget and bestTarget.Character ~= CurrentTargetChar then
                local newDist = (bestTarget.Part.Position - myRoot.Position).Magnitude
                if newDist < (curDist - Config.SwitchDistanceMargin) then
                    SetTarget(bestTarget)
                end
            end
        end

        -- Pastikan part yang dibidik selalu sinkron dengan pilihan dropdown
        if CurrentTargetChar and IsValidEnemy(CurrentTargetChar) then
            CurrentTargetPart = GetTargetPart(CurrentTargetChar)
        end

        if CurrentTargetPart and CurrentTargetChar and IsValidEnemy(CurrentTargetChar) then
            -- 1. Camera Tracking (Mengarahkan kamera langsung ke part yang dipilih)
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

print("[AutoCombat] Berhasil di-load! Dropdown siap digunakan.")
