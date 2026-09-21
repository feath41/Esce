-- CombatSystem.lua
-- Modern Hub Interface (Based on Pithers Hub Design) + Full Combat Auto-Lock Features
-- Protected by pcall, Mobile/Delta & PC Ready

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
    BreakDistance = 100,           -- Jarak batas lepas target (otomatis MaxLockDistance + 20)
    CameraSmoothing = 0.25,        -- Kehalusan gerakan kamera (0.1 halus, 1 instan)
    AutoFaceCharacter = true,      -- Karakter otomatis menghadap musuh
    CharacterFaceSpeed = 0.35,     -- Kecepatan putar badan karakter
    
    TargetPartChoice = "Head",     -- "Head" atau "Torso"
    LockMode = "Distance",         -- "Distance" (Jarak 3D) atau "Cursor" (2D Layar)
    TargetType = "All",            -- "All" (Player + Bot), "NPC" (Hanya Bot), "Player" (Hanya Player)
    TeamCheck = true,              -- true = hanya musuh, false = semua
    TargetSwitchMode = "Dynamic",   -- "Dynamic" = musuh terdekat, "LowestHP" = darah terendah, "Persistent" = sampai mati
    SwitchDistanceMargin = 3,      -- Margin jarak (studs)
    
    -- Konfigurasi Hitbox Visual
    HitboxColor = Color3.fromRGB(255, 45, 75),
    HitboxTransparency = 0.5,
    HitboxOutlineColor = Color3.fromRGB(255, 255, 255),
    
    ToggleKey = Enum.KeyCode.Q,
    SwitchKey = Enum.KeyCode.Tab,
    ToggleUIKey = Enum.KeyCode.RightShift,

    -- Konfigurasi Highlight Visual
    HighlightAllEnabled = false,
    HighlightRadiusX = 300,        -- Radius X: Samping / Kanan-Kiri (studs)
    HighlightRadiusY = 150,        -- Radius Y: Vertikal / Atas-Bawah (studs)
    HighlightRadiusZ = 300,        -- Radius Z: Depan-Belakang (studs)
    HighlightTargetType = "All",   -- "All", "Player", "NPC"
    UnlockedHitboxColor = Color3.fromRGB(255, 220, 0),      -- Kuning untuk target belum di-lock
    UnlockedTransparency = 0.5,
    UnlockedOutlineColor = Color3.fromRGB(255, 255, 255),

    -- Konfigurasi Teleport & Terbang
    FlySpeed = 120,                -- Kecepatan terbang ke target (studs/detik)

    -- Konfigurasi Bullet Tracking & Silent Aim
    BulletTrackingEnabled = false,
    BulletTargetSource = "AimLock", -- "AimLock", "MouseFOV", "Closest"
    BulletTargetPart = "Head",      -- "Head", "Torso", "Auto", "Random"
    BulletHitChance = 100,          -- 1 - 100%
    BulletPrediction = true,        -- true / false
    BulletPredictionFactor = 0.13,  -- Waktu kompensasi delay (lead bullet)
    BulletHomingProjectiles = true, -- Belokkan peluru fisik / projectile di workspace
    BulletUseFOV = true,            -- Batasi peluru dalam FOV
    BulletShowFOVCircle = true,     -- Tampilkan lingkaran FOV
    BulletFOVRadius = 180,          -- Radius lingkaran FOV (pixel)
    BulletFOVCircleColor = Color3.fromRGB(0, 180, 255),
    BulletTracerEnabled = true,     -- Visual laser beam saat tracking
    BulletTracerColor = Color3.fromRGB(0, 225, 255),
    BulletToggleKey = Enum.KeyCode.T,

    -- Konfigurasi Auto Shoot (TriggerBot & Wall Check)
    AutoShootEnabled = false,       -- Menembak otomatis saat musuh di FOV / Aim Lock
    AutoShootWallCheck = true,     -- Cek tembok: hanya tembak jika tidak ada halangan
    AutoShootMode = "All",         -- "All" (Aim Lock + FOV), "FOV", "AimLock"
    AutoShootDelayMs = 100,        -- Jeda tembak (ms): 50 - 500 ms
    AutoShootKey = Enum.KeyCode.G
}

Config.BreakDistance = Config.MaxLockDistance + 20

-- State Sistem
local AutoLockEnabled = false
local CurrentTargetPart = nil
local CurrentTargetChar = nil
local CurrentTargetIsNPC = false

-- Simpan config ke _G untuk akses hook metamethod
_G.FeathCombatConfig = Config

-- ============================================================================
-- PENGATURAN PARENT GUI AMAN
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

-- Bersihkan instance lama jika re-execute
pcall(function()
    if _G.CombatFlyHeartbeat then _G.CombatFlyHeartbeat:Disconnect() _G.CombatFlyHeartbeat = nil end
    if _G.CombatFlyNoclip then _G.CombatFlyNoclip:Disconnect() _G.CombatFlyNoclip = nil end
    if _G.CombatBulletProjectileConn then _G.CombatBulletProjectileConn:Disconnect() _G.CombatBulletProjectileConn = nil end
    local oldGui = SafeParent:FindFirstChild("CombatTargetGui")
    if oldGui then oldGui:Destroy() end
    local oldHighlight = game:FindFirstChild("CombatTargetHitboxHighlight", true)
    if oldHighlight then oldHighlight:Destroy() end
    local oldBox = game:FindFirstChild("CombatTargetHitboxBox", true)
    if oldBox then oldBox:Destroy() end
    for _, v in ipairs(workspace:GetDescendants()) do
        if (v.Name == "CombatUnlockedHighlight" and v:IsA("Highlight")) 
           or (v.Name == "CombatHighlightInfoBB" and v:IsA("BillboardGui")) 
           or (v.Name == "CombatBulletTracer") then
            v:Destroy()
        end
    end
end)

-- ============================================================================
-- PEMBUATAN UI MODERN (PITHERS HUB DESIGN)
-- ============================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CombatTargetGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = SafeParent end)

-- Lingkaran FOV (Field of View) untuk Bullet Tracking
local FOVCircle = Instance.new("Frame")
FOVCircle.Name = "CombatBulletFOVCircle"
FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
FOVCircle.BackgroundTransparency = 1
FOVCircle.Visible = false
FOVCircle.ZIndex = 40
FOVCircle.Parent = ScreenGui

local FOVCorner = Instance.new("UICorner")
FOVCorner.CornerRadius = UDim.new(1, 0)
FOVCorner.Parent = FOVCircle

local FOVStroke = Instance.new("UIStroke")
FOVStroke.Thickness = 1.5
FOVStroke.Color = Config.BulletFOVCircleColor
FOVStroke.Transparency = 0.35
FOVStroke.Parent = FOVCircle

-- 1. Collapsed Bar / Title Bar Only (Non-draggable, stays fixed at top)
local CollapsedBar = Instance.new("Frame")
CollapsedBar.Name = "CollapsedBar"
CollapsedBar.Size = UDim2.new(0, 395, 0, 36)
CollapsedBar.Position = UDim2.new(0.5, -197, 0.05, 0)
CollapsedBar.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
CollapsedBar.BorderSizePixel = 0
CollapsedBar.Visible = false
CollapsedBar.ZIndex = 50
CollapsedBar.Parent = ScreenGui

local ColCorner = Instance.new("UICorner")
ColCorner.CornerRadius = UDim.new(0, 8)
ColCorner.Parent = CollapsedBar

local ColStroke = Instance.new("UIStroke")
ColStroke.Thickness = 1
ColStroke.Color = Color3.fromRGB(40, 45, 60)
ColStroke.Parent = CollapsedBar

local ColIcon = Instance.new("TextLabel")
ColIcon.Size = UDim2.new(0, 24, 0, 24)
ColIcon.Position = UDim2.new(0, 8, 0.5, -12)
ColIcon.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
ColIcon.Text = "⚡"
ColIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
ColIcon.Font = Enum.Font.GothamBold
ColIcon.TextSize = 13
ColIcon.ZIndex = 51
ColIcon.Parent = CollapsedBar

local ColIconCorner = Instance.new("UICorner")
ColIconCorner.CornerRadius = UDim.new(0, 6)
ColIconCorner.Parent = ColIcon

local ColTitle = Instance.new("TextLabel")
ColTitle.Size = UDim2.new(0, 80, 1, 0)
ColTitle.Position = UDim2.new(0, 38, 0, 0)
ColTitle.BackgroundTransparency = 1
ColTitle.Text = "FEATH HUB"
ColTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
ColTitle.Font = Enum.Font.GothamBold
ColTitle.TextSize = 11
ColTitle.TextXAlignment = Enum.TextXAlignment.Left
ColTitle.ZIndex = 51
ColTitle.Parent = CollapsedBar

local ColBadge = Instance.new("TextLabel")
ColBadge.Size = UDim2.new(0, 58, 0, 18)
ColBadge.Position = UDim2.new(0, 122, 0.5, -9)
ColBadge.BackgroundColor3 = Color3.fromRGB(24, 32, 50)
ColBadge.Text = "Collapsed"
ColBadge.TextColor3 = Color3.fromRGB(80, 160, 255)
ColBadge.Font = Enum.Font.GothamMedium
ColBadge.TextSize = 9
ColBadge.ZIndex = 51
ColBadge.Parent = CollapsedBar

local ColBadgeCorner = Instance.new("UICorner")
ColBadgeCorner.CornerRadius = UDim.new(0, 4)
ColBadgeCorner.Parent = ColBadge

-- Tombol Expand ke Main Window
local ExpandBtn = Instance.new("TextButton")
ExpandBtn.Size = UDim2.new(0, 120, 0, 24)
ExpandBtn.Position = UDim2.new(0, 186, 0.5, -12)
ExpandBtn.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
ExpandBtn.Text = "📖 Click to Expand"
ExpandBtn.TextColor3 = Color3.fromRGB(180, 210, 255)
ExpandBtn.Font = Enum.Font.GothamMedium
ExpandBtn.TextSize = 10
ExpandBtn.ZIndex = 51
ExpandBtn.Parent = CollapsedBar

local ExpCorner = Instance.new("UICorner")
ExpCorner.CornerRadius = UDim.new(0, 6)
ExpCorner.Parent = ExpandBtn

-- Tombol Ubah ke Mode Kotak (Mini Draggable Box)
local ToKotakBtn = Instance.new("TextButton")
ToKotakBtn.Size = UDim2.new(0, 52, 0, 24)
ToKotakBtn.Position = UDim2.new(0, 312, 0.5, -12)
ToKotakBtn.BackgroundColor3 = Color3.fromRGB(30, 38, 56)
ToKotakBtn.Text = "⛶ Kotak"
ToKotakBtn.TextColor3 = Color3.fromRGB(120, 200, 255)
ToKotakBtn.Font = Enum.Font.GothamBold
ToKotakBtn.TextSize = 10
ToKotakBtn.ZIndex = 51
ToKotakBtn.Parent = CollapsedBar

local KotakBtnCorner = Instance.new("UICorner")
KotakBtnCorner.CornerRadius = UDim.new(0, 6)
KotakBtnCorner.Parent = ToKotakBtn

-- Tombol Close di Collapsed Bar
local CloseColBtn = Instance.new("TextButton")
CloseColBtn.Size = UDim2.new(0, 20, 0, 24)
CloseColBtn.Position = UDim2.new(1, -26, 0.5, -12)
CloseColBtn.BackgroundTransparency = 1
CloseColBtn.Text = "✕"
CloseColBtn.TextColor3 = Color3.fromRGB(160, 165, 180)
CloseColBtn.Font = Enum.Font.GothamBold
CloseColBtn.TextSize = 12
CloseColBtn.ZIndex = 51
CloseColBtn.Parent = CollapsedBar

-- 2. Mini Kotak Widget (Mode Kotak yang BISA DI-DRAG)
local MiniKotak = Instance.new("Frame")
MiniKotak.Name = "MiniKotak"
MiniKotak.Size = UDim2.new(0, 44, 0, 44)
MiniKotak.Position = UDim2.new(0, 20, 0.5, -22)
MiniKotak.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MiniKotak.BorderSizePixel = 0
MiniKotak.Visible = false
MiniKotak.Active = true
MiniKotak.ZIndex = 60
MiniKotak.Parent = ScreenGui

local MiniKotakCorner = Instance.new("UICorner")
MiniKotakCorner.CornerRadius = UDim.new(0, 10)
MiniKotakCorner.Parent = MiniKotak

local MiniKotakStroke = Instance.new("UIStroke")
MiniKotakStroke.Thickness = 1.5
MiniKotakStroke.Color = Color3.fromRGB(0, 120, 255)
MiniKotakStroke.Parent = MiniKotak

local MiniKotakBtn = Instance.new("TextButton")
MiniKotakBtn.Size = UDim2.new(1, 0, 1, 0)
MiniKotakBtn.BackgroundTransparency = 1
MiniKotakBtn.Text = "⚡"
MiniKotakBtn.TextColor3 = Color3.fromRGB(0, 140, 255)
MiniKotakBtn.Font = Enum.Font.GothamBold
MiniKotakBtn.TextSize = 20
MiniKotakBtn.ZIndex = 61
MiniKotakBtn.Parent = MiniKotak

-- Fitur Smooth Dragging Khusus Mode Kotak (Touch Screen Mobile & Mouse)
local isKotakDragging = false
local isKotakMoved = false
local kotakDragStart = nil
local kotakStartPos = nil

MiniKotak.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isKotakDragging = true
        isKotakMoved = false
        kotakDragStart = input.Position
        kotakStartPos = MiniKotak.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                isKotakDragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isKotakDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - kotakDragStart
        if delta.Magnitude > 5 then
            isKotakMoved = true
        end
        MiniKotak.Position = UDim2.new(
            kotakStartPos.X.Scale,
            kotakStartPos.X.Offset + delta.X,
            kotakStartPos.Y.Scale,
            kotakStartPos.Y.Offset + delta.Y
        )
    end
end)

-- 3. Main Window Frame (520 x 360 px Standard Hub Layout)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 360)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -180)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 1
MainStroke.Color = Color3.fromRGB(40, 45, 60)
MainStroke.Parent = MainFrame

-- Top Bar Header
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 40)
TopBar.BackgroundTransparency = 1
TopBar.Parent = MainFrame

local LogoBadge = Instance.new("TextLabel")
LogoBadge.Size = UDim2.new(0, 24, 0, 24)
LogoBadge.Position = UDim2.new(0, 12, 0, 8)
LogoBadge.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
LogoBadge.Text = "⚡"
LogoBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
LogoBadge.Font = Enum.Font.GothamBold
LogoBadge.TextSize = 13
LogoBadge.Parent = TopBar

local LogoCorner = Instance.new("UICorner")
LogoCorner.CornerRadius = UDim.new(0, 6)
LogoCorner.Parent = LogoBadge

local AppTitle = Instance.new("TextLabel")
AppTitle.Size = UDim2.new(0, 95, 0, 24)
AppTitle.Position = UDim2.new(0, 44, 0, 8)
AppTitle.BackgroundTransparency = 1
AppTitle.Text = "FEATH HUB"
AppTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
AppTitle.Font = Enum.Font.GothamBold
AppTitle.TextSize = 13
AppTitle.TextXAlignment = Enum.TextXAlignment.Left
AppTitle.Parent = TopBar

local VersionBadge = Instance.new("TextLabel")
VersionBadge.Size = UDim2.new(0, 30, 0, 16)
VersionBadge.Position = UDim2.new(0, 142, 0, 12)
VersionBadge.BackgroundTransparency = 1
VersionBadge.Text = "v2.6"
VersionBadge.TextColor3 = Color3.fromRGB(120, 150, 200)
VersionBadge.Font = Enum.Font.Gotham
VersionBadge.TextSize = 11
VersionBadge.TextXAlignment = Enum.TextXAlignment.Left
VersionBadge.Parent = TopBar

local TagBadge = Instance.new("TextLabel")
TagBadge.Size = UDim2.new(0, 62, 0, 18)
TagBadge.Position = UDim2.new(0, 178, 0, 11)
TagBadge.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
TagBadge.Text = "Universal"
TagBadge.TextColor3 = Color3.fromRGB(100, 180, 255)
TagBadge.Font = Enum.Font.GothamMedium
TagBadge.TextSize = 10
TagBadge.Parent = TopBar

local TagCorner = Instance.new("UICorner")
TagCorner.CornerRadius = UDim.new(0, 4)
TagCorner.Parent = TagBadge

-- Tombol Minimize & Close di TopBar
local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 24, 0, 24)
MinBtn.Position = UDim2.new(1, -60, 0, 8)
MinBtn.BackgroundTransparency = 1
MinBtn.Text = "—"
MinBtn.TextColor3 = Color3.fromRGB(180, 185, 200)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 14
MinBtn.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
CloseBtn.Position = UDim2.new(1, -32, 0, 8)
CloseBtn.BackgroundTransparency = 1
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(180, 185, 200)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13
CloseBtn.Parent = TopBar

local TopDivider = Instance.new("Frame")
TopDivider.Size = UDim2.new(1, 0, 0, 1)
TopDivider.Position = UDim2.new(0, 0, 0, 40)
TopDivider.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
TopDivider.BorderSizePixel = 0
TopDivider.Parent = MainFrame

-- Logika Minimize & Restore
MinBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    MiniKotak.Visible = false
    CollapsedBar.Visible = true
end)

ExpandBtn.MouseButton1Click:Connect(function()
    CollapsedBar.Visible = false
    MiniKotak.Visible = false
    MainFrame.Visible = true
end)

ToKotakBtn.MouseButton1Click:Connect(function()
    CollapsedBar.Visible = false
    MiniKotak.Visible = true
end)

CloseColBtn.MouseButton1Click:Connect(function()
    CollapsedBar.Visible = false
end)

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui.Enabled = false
end)

MiniKotakBtn.MouseButton1Click:Connect(function()
    if not isKotakMoved then
        MiniKotak.Visible = false
        MainFrame.Visible = true
    end
end)

-- Sidebar Navigasi Kiri (130px)
local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 130, 1, -41)
Sidebar.Position = UDim2.new(0, 0, 0, 41)
Sidebar.BackgroundColor3 = Color3.fromRGB(18, 20, 27)
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local SideDivider = Instance.new("Frame")
SideDivider.Size = UDim2.new(0, 1, 1, 0)
SideDivider.Position = UDim2.new(1, -1, 0, 0)
SideDivider.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
SideDivider.BorderSizePixel = 0
SideDivider.Parent = Sidebar

-- Status Inject Card di bawah Sidebar
local StatusCard = Instance.new("Frame")
StatusCard.Size = UDim2.new(1, -16, 0, 36)
StatusCard.Position = UDim2.new(0, 8, 1, -44)
StatusCard.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
StatusCard.BorderSizePixel = 0
StatusCard.Parent = Sidebar

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusCard

local DotIndicator = Instance.new("Frame")
DotIndicator.Size = UDim2.new(0, 7, 0, 7)
DotIndicator.Position = UDim2.new(0, 10, 0.5, -3)
DotIndicator.BackgroundColor3 = Color3.fromRGB(0, 230, 120)
DotIndicator.BorderSizePixel = 0
DotIndicator.Parent = StatusCard

local DotCorner = Instance.new("UICorner")
DotCorner.CornerRadius = UDim.new(1, 0)
DotCorner.Parent = DotIndicator

local StatusTitle = Instance.new("TextLabel")
StatusTitle.Size = UDim2.new(1, -26, 0, 12)
StatusTitle.Position = UDim2.new(0, 22, 0, 5)
StatusTitle.BackgroundTransparency = 1
StatusTitle.Text = "STATUS"
StatusTitle.TextColor3 = Color3.fromRGB(120, 130, 150)
StatusTitle.Font = Enum.Font.GothamMedium
StatusTitle.TextSize = 8
StatusTitle.TextXAlignment = Enum.TextXAlignment.Left
StatusTitle.Parent = StatusCard

local StatusVal = Instance.new("TextLabel")
StatusVal.Size = UDim2.new(1, -26, 0, 14)
StatusVal.Position = UDim2.new(0, 22, 0, 17)
StatusVal.BackgroundTransparency = 1
StatusVal.Text = "Injected"
StatusVal.TextColor3 = Color3.fromRGB(0, 230, 120)
StatusVal.Font = Enum.Font.GothamBold
StatusVal.TextSize = 10
StatusVal.TextXAlignment = Enum.TextXAlignment.Left
StatusVal.Parent = StatusCard

-- Content Area (Kanan)
local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, -131, 1, -41)
ContentArea.Position = UDim2.new(0, 131, 0, 41)
ContentArea.BackgroundTransparency = 1
ContentArea.ClipsDescendants = true
ContentArea.Parent = MainFrame

-- Tab Frames
local Tabs = {}

local function CreateTabFrame(name)
    local frame = Instance.new("ScrollingFrame")
    frame.Name = name .. "Tab"
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.ScrollBarThickness = 3
    frame.ScrollBarImageColor3 = Color3.fromRGB(50, 55, 75)
    frame.CanvasSize = UDim2.new(0, 0, 0, 460)
    frame.Visible = false
    frame.Parent = ContentArea
    Tabs[name] = frame
    return frame
end

local MainTab = CreateTabFrame("Main")
local PlayerTab = CreateTabFrame("Player")
local TrackingTab = CreateTabFrame("Tracking")
local VisualTab = CreateTabFrame("Visual")
local SettingsTab = CreateTabFrame("Settings")

-- Sistem Tab Switching Navigasi
local NavButtons = {}
local TabList = {
    { Name = "Main", Icon = "🏠" },
    { Name = "Player", Icon = "👤" },
    { Name = "Tracking", Icon = "🎯" },
    { Name = "Visual", Icon = "👁" },
    { Name = "Settings", Icon = "⚙" }
}

local function SwitchTab(tabName)
    if CloseAllDropdowns then CloseAllDropdowns() end
    for name, f in pairs(Tabs) do
        f.Visible = (name == tabName)
    end
    for name, btn in pairs(NavButtons) do
        local isSelected = (name == tabName)
        btn.BackgroundColor3 = isSelected and Color3.fromRGB(24, 32, 50) or Color3.fromRGB(18, 20, 27)
        btn.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 155, 170)
        local stroke = btn:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = isSelected and Color3.fromRGB(0, 120, 255) or Color3.fromRGB(18, 20, 27)
        end
    end
end

for idx, item in ipairs(TabList) do
    local btn = Instance.new("TextButton")
    btn.Name = item.Name .. "NavBtn"
    btn.Size = UDim2.new(1, -16, 0, 32)
    btn.Position = UDim2.new(0, 8, 0, 10 + (idx - 1) * 36)
    btn.BackgroundColor3 = Color3.fromRGB(18, 20, 27)
    btn.Text = "  " .. item.Icon .. "  " .. item.Name
    btn.TextColor3 = Color3.fromRGB(150, 155, 170)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.BorderSizePixel = 0
    btn.Parent = Sidebar

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Thickness = 1
    btnStroke.Color = Color3.fromRGB(18, 20, 27)
    btnStroke.Parent = btn

    btn.MouseButton1Click:Connect(function()
        SwitchTab(item.Name)
    end)

    NavButtons[item.Name] = btn
end

-- Default Buka Tab Player
SwitchTab("Player")

-- ============================================================================
-- DROPDOWN SYSTEM REUSABLE (UNTUK SEMUA TAB)
-- ============================================================================
local activeDropdownList = nil
local activeDropdownArrow = nil

function CloseAllDropdowns()
    if activeDropdownList then
        activeDropdownList.Visible = false
        activeDropdownList = nil
    end
    if activeDropdownArrow then
        activeDropdownArrow.Text = "▼"
        activeDropdownArrow = nil
    end
end

local function CreateDropdown(parent, labelText, yPos, options, defaultKey, zIndexBase, onSelect)
    local dLabel = Instance.new("TextLabel")
    dLabel.Size = UDim2.new(1, -28, 0, 14)
    dLabel.Position = UDim2.new(0, 14, 0, yPos)
    dLabel.BackgroundTransparency = 1
    dLabel.Text = labelText
    dLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
    dLabel.Font = Enum.Font.GothamMedium
    dLabel.TextSize = 10
    dLabel.TextXAlignment = Enum.TextXAlignment.Left
    dLabel.Parent = parent

    local dButton = Instance.new("TextButton")
    dButton.Size = UDim2.new(1, -28, 0, 26)
    dButton.Position = UDim2.new(0, 14, 0, yPos + 16)
    dButton.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
    dButton.BorderSizePixel = 0
    dButton.Font = Enum.Font.Gotham
    dButton.TextSize = 11
    dButton.TextColor3 = Color3.fromRGB(230, 235, 245)
    dButton.TextXAlignment = Enum.TextXAlignment.Left
    dButton.ZIndex = zIndexBase
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
    arrow.ZIndex = zIndexBase
    arrow.Parent = dButton

    local listFrame = Instance.new("Frame")
    listFrame.Size = UDim2.new(1, -28, 0, #options * 24 + 4)
    listFrame.Position = UDim2.new(0, 14, 0, yPos + 44)
    listFrame.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
    listFrame.BorderSizePixel = 0
    listFrame.Visible = false
    listFrame.ZIndex = zIndexBase + 10
    listFrame.Parent = parent

    local listCorner = Instance.new("UICorner")
    listCorner.CornerRadius = UDim.new(0, 6)
    listCorner.Parent = listFrame

    local listStroke = Instance.new("UIStroke")
    listStroke.Thickness = 1
    listStroke.Color = Color3.fromRGB(60, 65, 80)
    listStroke.Parent = listFrame

    for idx, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, -6, 0, 22)
        optBtn.Position = UDim2.new(0, 3, 0, (idx - 1) * 24 + 2)
        optBtn.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
        optBtn.BackgroundTransparency = 1
        optBtn.Text = "  " .. opt.Name
        optBtn.TextColor3 = Color3.fromRGB(200, 205, 215)
        optBtn.Font = Enum.Font.Gotham
        optBtn.TextSize = 10
        optBtn.TextXAlignment = Enum.TextXAlignment.Left
        optBtn.ZIndex = zIndexBase + 11
        optBtn.Parent = listFrame

        local optCorner = Instance.new("UICorner")
        optCorner.CornerRadius = UDim.new(0, 4)
        optCorner.Parent = optBtn

        if opt.Value == defaultKey then
            dButton.Text = "  " .. opt.Name
            optBtn.TextColor3 = Color3.fromRGB(80, 210, 255)
        end

        optBtn.MouseButton1Click:Connect(function()
            dButton.Text = "  " .. opt.Name
            arrow.Text = "▼"
            listFrame.Visible = false
            activeDropdownList = nil
            activeDropdownArrow = nil

            for _, child in ipairs(listFrame:GetChildren()) do
                if child:IsA("TextButton") then
                    child.TextColor3 = Color3.fromRGB(200, 205, 215)
                end
            end
            optBtn.TextColor3 = Color3.fromRGB(80, 210, 255)

            onSelect(opt.Value)
        end)
    end

    dButton.MouseButton1Click:Connect(function()
        if listFrame.Visible then
            listFrame.Visible = false
            arrow.Text = "▼"
            if activeDropdownList == listFrame then
                activeDropdownList = nil
                activeDropdownArrow = nil
            end
        else
            CloseAllDropdowns()
            listFrame.Visible = true
            arrow.Text = "▲"
            activeDropdownList = listFrame
            activeDropdownArrow = arrow
        end
    end)

    return dButton
end

-- HELPER PEMBUAT SLIDER UMUM (PERSEN, PIXEL, STUDS)
local function CreateGeneralSlider(parent, titleText, yPos, configKey, minVal, maxVal, unitStr, accentColor, onChange)
    local SliderContainer = Instance.new("Frame")
    SliderContainer.Name = "Slider_" .. configKey
    SliderContainer.Size = UDim2.new(1, -28, 0, 48)
    SliderContainer.Position = UDim2.new(0, 14, 0, yPos)
    SliderContainer.BackgroundTransparency = 1
    SliderContainer.Parent = parent

    local SliderTitle = Instance.new("TextLabel")
    SliderTitle.Size = UDim2.new(0.65, 0, 0, 14)
    SliderTitle.Position = UDim2.new(0, 0, 0, 0)
    SliderTitle.BackgroundTransparency = 1
    SliderTitle.Text = titleText
    SliderTitle.TextColor3 = Color3.fromRGB(150, 155, 170)
    SliderTitle.Font = Enum.Font.GothamMedium
    SliderTitle.TextSize = 10
    SliderTitle.TextXAlignment = Enum.TextXAlignment.Left
    SliderTitle.Parent = SliderContainer

    local SliderValueLabel = Instance.new("TextLabel")
    SliderValueLabel.Size = UDim2.new(0.35, 0, 0, 14)
    SliderValueLabel.Position = UDim2.new(0.65, 0, 0, 0)
    SliderValueLabel.BackgroundTransparency = 1
    local fmt = (unitStr == "%" and "%d%%") or (unitStr == "px" and "%d px") or string.format("%%d %s", unitStr or "")
    SliderValueLabel.Text = string.format(fmt, Config[configKey])
    SliderValueLabel.TextColor3 = accentColor or Color3.fromRGB(80, 210, 255)
    SliderValueLabel.Font = Enum.Font.GothamBold
    SliderValueLabel.TextSize = 10
    SliderValueLabel.TextXAlignment = Enum.TextXAlignment.Right
    SliderValueLabel.Parent = SliderContainer

    local SliderBar = Instance.new("Frame")
    SliderBar.Name = "SliderBar"
    SliderBar.Size = UDim2.new(1, 0, 0, 8)
    SliderBar.Position = UDim2.new(0, 0, 0, 20)
    SliderBar.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
    SliderBar.BorderSizePixel = 0
    SliderBar.Parent = SliderContainer

    local SliderBarCorner = Instance.new("UICorner")
    SliderBarCorner.CornerRadius = UDim.new(1, 0)
    SliderBarCorner.Parent = SliderBar

    local SliderFill = Instance.new("Frame")
    local initRatio = math.clamp((Config[configKey] - minVal) / (maxVal - minVal), 0, 1)
    SliderFill.Size = UDim2.new(initRatio, 0, 1, 0)
    SliderFill.BackgroundColor3 = accentColor or Color3.fromRGB(0, 140, 255)
    SliderFill.BorderSizePixel = 0
    SliderFill.Parent = SliderBar

    local SliderFillCorner = Instance.new("UICorner")
    SliderFillCorner.CornerRadius = UDim.new(1, 0)
    SliderFillCorner.Parent = SliderFill

    local SliderKnob = Instance.new("Frame")
    SliderKnob.Size = UDim2.new(0, 16, 0, 16)
    SliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    SliderKnob.Position = UDim2.new(initRatio, 0, 0.5, 0)
    SliderKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    SliderKnob.BorderSizePixel = 0
    SliderKnob.ZIndex = 3
    SliderKnob.Parent = SliderBar

    local KnobCorner = Instance.new("UICorner")
    KnobCorner.CornerRadius = UDim.new(1, 0)
    KnobCorner.Parent = SliderKnob

    local KnobStroke = Instance.new("UIStroke")
    KnobStroke.Thickness = 1.5
    KnobStroke.Color = accentColor or Color3.fromRGB(0, 140, 255)
    KnobStroke.Parent = SliderKnob

    local isSliding = false

    local function UpdateVal(inputX)
        local barAbsolutePos = SliderBar.AbsolutePosition.X
        local barAbsoluteSize = SliderBar.AbsoluteSize.X
        local ratio = math.clamp((inputX - barAbsolutePos) / barAbsoluteSize, 0, 1)

        local newVal = math.floor(minVal + (ratio * (maxVal - minVal)))
        Config[configKey] = newVal

        SliderFill.Size = UDim2.new(ratio, 0, 1, 0)
        SliderKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
        SliderValueLabel.Text = string.format(fmt, newVal)
        if onChange then onChange(newVal) end
    end

    SliderBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isSliding = true
            UpdateVal(input.Position.X)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if isSliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            UpdateVal(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isSliding = false
        end
    end)
end

-- ============================================================================
-- 1. ISI TAB MAIN (DEVELOPER PROFILE / CREATED BY FEATH)
-- ============================================================================
-- ============================================================================
-- 1. ISI TAB MAIN (DEVELOPER PROFILE + TELEPORT & TERBANG)
-- ============================================================================
MainTab.CanvasSize = UDim2.new(0, 0, 0, 335)

local ProfileCard = Instance.new("Frame")
ProfileCard.Size = UDim2.new(1, -28, 0, 84)
ProfileCard.Position = UDim2.new(0, 14, 0, 10)
ProfileCard.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
ProfileCard.BorderSizePixel = 0
ProfileCard.Parent = MainTab

local ProfCorner = Instance.new("UICorner")
ProfCorner.CornerRadius = UDim.new(0, 8)
ProfCorner.Parent = ProfileCard

local ProfStroke = Instance.new("UIStroke")
ProfStroke.Thickness = 1
ProfStroke.Color = Color3.fromRGB(45, 55, 80)
ProfStroke.Parent = ProfileCard

local AvatarCircle = Instance.new("ImageLabel")
AvatarCircle.Size = UDim2.new(0, 48, 0, 48)
AvatarCircle.Position = UDim2.new(0, 14, 0.5, -24)
AvatarCircle.BackgroundColor3 = Color3.fromRGB(28, 35, 52)
AvatarCircle.Image = "rbxassetid://10903333338" -- Default stylish icon avatar
AvatarCircle.BorderSizePixel = 0
AvatarCircle.Parent = ProfileCard

local AvCorner = Instance.new("UICorner")
AvCorner.CornerRadius = UDim.new(1, 0)
AvCorner.Parent = AvatarCircle

local DevName = Instance.new("TextLabel")
DevName.Size = UDim2.new(0, 200, 0, 18)
DevName.Position = UDim2.new(0, 72, 0, 14)
DevName.BackgroundTransparency = 1
DevName.Text = "Created by feath"
DevName.TextColor3 = Color3.fromRGB(255, 255, 255)
DevName.Font = Enum.Font.GothamBold
DevName.TextSize = 13
DevName.TextXAlignment = Enum.TextXAlignment.Left
DevName.Parent = ProfileCard

local DevRole = Instance.new("TextLabel")
DevRole.Size = UDim2.new(0, 200, 0, 14)
DevRole.Position = UDim2.new(0, 72, 0, 34)
DevRole.BackgroundTransparency = 1
DevRole.Text = "Developer • Combat System Suite"
DevRole.TextColor3 = Color3.fromRGB(80, 210, 255)
DevRole.Font = Enum.Font.GothamMedium
DevRole.TextSize = 10
DevRole.TextXAlignment = Enum.TextXAlignment.Left
DevRole.Parent = ProfileCard

local DevBadge = Instance.new("TextLabel")
DevBadge.Size = UDim2.new(0, 75, 0, 16)
DevBadge.Position = UDim2.new(0, 72, 0, 52)
DevBadge.BackgroundColor3 = Color3.fromRGB(30, 42, 68)
DevBadge.Text = "VERIFIED DEV"
DevBadge.TextColor3 = Color3.fromRGB(120, 180, 255)
DevBadge.Font = Enum.Font.GothamBold
DevBadge.TextSize = 9
DevBadge.Parent = ProfileCard

local DevBadgeCorner = Instance.new("UICorner")
DevBadgeCorner.CornerRadius = UDim.new(0, 4)
DevBadgeCorner.Parent = DevBadge

-- Header Section: TELEPORT & TERBANG KE TARGET
local TPSectionTitle = Instance.new("TextLabel")
TPSectionTitle.Size = UDim2.new(1, -28, 0, 16)
TPSectionTitle.Position = UDim2.new(0, 14, 0, 102)
TPSectionTitle.BackgroundTransparency = 1
TPSectionTitle.Text = "TELEPORT & TERBANG KE TARGET (PLAYER / BOT):"
TPSectionTitle.TextColor3 = Color3.fromRGB(80, 210, 255)
TPSectionTitle.Font = Enum.Font.GothamBold
TPSectionTitle.TextSize = 10
TPSectionTitle.TextXAlignment = Enum.TextXAlignment.Left
TPSectionTitle.Parent = MainTab

-- Label Dropdown Nickname & Tombol Scan Ulang
local TPDropdownLabel = Instance.new("TextLabel")
TPDropdownLabel.Size = UDim2.new(0.65, 0, 0, 14)
TPDropdownLabel.Position = UDim2.new(0, 14, 0, 122)
TPDropdownLabel.BackgroundTransparency = 1
TPDropdownLabel.Text = "PILIH TARGET (NICKNAME):"
TPDropdownLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
TPDropdownLabel.Font = Enum.Font.GothamMedium
TPDropdownLabel.TextSize = 10
TPDropdownLabel.TextXAlignment = Enum.TextXAlignment.Left
TPDropdownLabel.Parent = MainTab

local TPScanBtn = Instance.new("TextButton")
TPScanBtn.Size = UDim2.new(0.35, -28, 0, 16)
TPScanBtn.Position = UDim2.new(0.65, 14, 0, 121)
TPScanBtn.BackgroundColor3 = Color3.fromRGB(28, 34, 48)
TPScanBtn.BorderSizePixel = 0
TPScanBtn.Text = "🔄 SCAN ULANG"
TPScanBtn.TextColor3 = Color3.fromRGB(90, 200, 255)
TPScanBtn.Font = Enum.Font.GothamBold
TPScanBtn.TextSize = 9
TPScanBtn.Parent = MainTab

local TPScanCorner = Instance.new("UICorner")
TPScanCorner.CornerRadius = UDim.new(0, 4)
TPScanCorner.Parent = TPScanBtn

local TPScanStroke = Instance.new("UIStroke")
TPScanStroke.Thickness = 1
TPScanStroke.Color = Color3.fromRGB(45, 55, 75)
TPScanStroke.Parent = TPScanBtn

-- Dropdown Button Target Nickname
local TPDropdownBtn = Instance.new("TextButton")
TPDropdownBtn.Size = UDim2.new(1, -28, 0, 26)
TPDropdownBtn.Position = UDim2.new(0, 14, 0, 140)
TPDropdownBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
TPDropdownBtn.BorderSizePixel = 0
TPDropdownBtn.Font = Enum.Font.Gotham
TPDropdownBtn.TextSize = 10
TPDropdownBtn.TextColor3 = Color3.fromRGB(230, 235, 245)
TPDropdownBtn.TextXAlignment = Enum.TextXAlignment.Left
TPDropdownBtn.Text = "  ⭐ [Target Terdekat (Auto)]"
TPDropdownBtn.ZIndex = 20
TPDropdownBtn.Parent = MainTab

local TPDropdownCorner = Instance.new("UICorner")
TPDropdownCorner.CornerRadius = UDim.new(0, 6)
TPDropdownCorner.Parent = TPDropdownBtn

local TPDropdownStroke = Instance.new("UIStroke")
TPDropdownStroke.Thickness = 1
TPDropdownStroke.Color = Color3.fromRGB(45, 50, 65)
TPDropdownStroke.Parent = TPDropdownBtn

local TPArrow = Instance.new("TextLabel")
TPArrow.Size = UDim2.new(0, 20, 1, 0)
TPArrow.Position = UDim2.new(1, -25, 0, 0)
TPArrow.BackgroundTransparency = 1
TPArrow.Text = "▼"
TPArrow.TextColor3 = Color3.fromRGB(140, 145, 160)
TPArrow.Font = Enum.Font.GothamBold
TPArrow.TextSize = 9
TPArrow.ZIndex = 20
TPArrow.Parent = TPDropdownBtn

-- Dropdown List (ScrollingFrame)
local TPListFrame = Instance.new("ScrollingFrame")
TPListFrame.Size = UDim2.new(1, -28, 0, 120)
TPListFrame.Position = UDim2.new(0, 14, 0, 168)
TPListFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
TPListFrame.BorderSizePixel = 0
TPListFrame.ScrollBarThickness = 3
TPListFrame.ScrollBarImageColor3 = Color3.fromRGB(60, 70, 95)
TPListFrame.Visible = false
TPListFrame.ZIndex = 35
TPListFrame.Parent = MainTab

local TPListCorner = Instance.new("UICorner")
TPListCorner.CornerRadius = UDim.new(0, 6)
TPListCorner.Parent = TPListFrame

local TPListStroke = Instance.new("UIStroke")
TPListStroke.Thickness = 1
TPListStroke.Color = Color3.fromRGB(60, 65, 80)
TPListStroke.Parent = TPListFrame

-- Slider Kecepatan Terbang (Fly Speed Slider)
local FlySliderContainer = Instance.new("Frame")
FlySliderContainer.Name = "Slider_FlySpeed"
FlySliderContainer.Size = UDim2.new(1, -28, 0, 48)
FlySliderContainer.Position = UDim2.new(0, 14, 0, 174)
FlySliderContainer.BackgroundTransparency = 1
FlySliderContainer.Parent = MainTab

local FlySliderTitle = Instance.new("TextLabel")
FlySliderTitle.Size = UDim2.new(0.65, 0, 0, 14)
FlySliderTitle.Position = UDim2.new(0, 0, 0, 0)
FlySliderTitle.BackgroundTransparency = 1
FlySliderTitle.Text = "KECEPATAN TERBANG:"
FlySliderTitle.TextColor3 = Color3.fromRGB(150, 155, 170)
FlySliderTitle.Font = Enum.Font.GothamMedium
FlySliderTitle.TextSize = 10
FlySliderTitle.TextXAlignment = Enum.TextXAlignment.Left
FlySliderTitle.Parent = FlySliderContainer

local FlySliderValLabel = Instance.new("TextLabel")
FlySliderValLabel.Size = UDim2.new(0.35, 0, 0, 14)
FlySliderValLabel.Position = UDim2.new(0.65, 0, 0, 0)
FlySliderValLabel.BackgroundTransparency = 1
FlySliderValLabel.Text = string.format("%d studs/s", Config.FlySpeed)
FlySliderValLabel.TextColor3 = Color3.fromRGB(0, 185, 255)
FlySliderValLabel.Font = Enum.Font.GothamBold
FlySliderValLabel.TextSize = 10
FlySliderValLabel.TextXAlignment = Enum.TextXAlignment.Right
FlySliderValLabel.Parent = FlySliderContainer

local FlySliderBar = Instance.new("Frame")
FlySliderBar.Name = "SliderBar"
FlySliderBar.Size = UDim2.new(1, 0, 0, 8)
FlySliderBar.Position = UDim2.new(0, 0, 0, 20)
FlySliderBar.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
FlySliderBar.BorderSizePixel = 0
FlySliderBar.Parent = FlySliderContainer

local FlyBarCorner = Instance.new("UICorner")
FlyBarCorner.CornerRadius = UDim.new(1, 0)
FlyBarCorner.Parent = FlySliderBar

local FlySliderFill = Instance.new("Frame")
local initFlyRatio = math.clamp((Config.FlySpeed - 20) / (350 - 20), 0, 1)
FlySliderFill.Size = UDim2.new(initFlyRatio, 0, 1, 0)
FlySliderFill.BackgroundColor3 = Color3.fromRGB(0, 185, 255)
FlySliderFill.BorderSizePixel = 0
FlySliderFill.Parent = FlySliderBar

local FlyFillCorner = Instance.new("UICorner")
FlyFillCorner.CornerRadius = UDim.new(1, 0)
FlyFillCorner.Parent = FlySliderFill

local FlySliderKnob = Instance.new("Frame")
FlySliderKnob.Size = UDim2.new(0, 16, 0, 16)
FlySliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
FlySliderKnob.Position = UDim2.new(initFlyRatio, 0, 0.5, 0)
FlySliderKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
FlySliderKnob.BorderSizePixel = 0
FlySliderKnob.ZIndex = 3
FlySliderKnob.Parent = FlySliderBar

local FlyKnobCorner = Instance.new("UICorner")
FlyKnobCorner.CornerRadius = UDim.new(1, 0)
FlyKnobCorner.Parent = FlySliderKnob

local FlyKnobStroke = Instance.new("UIStroke")
FlyKnobStroke.Thickness = 1.5
FlyKnobStroke.Color = Color3.fromRGB(0, 185, 255)
FlyKnobStroke.Parent = FlySliderKnob

local isFlySliding = false
local function UpdateFlySlider(inputX)
    local barAbsolutePos = FlySliderBar.AbsolutePosition.X
    local barAbsoluteSize = FlySliderBar.AbsoluteSize.X
    local ratio = math.clamp((inputX - barAbsolutePos) / barAbsoluteSize, 0, 1)
    local newVal = math.floor(20 + (ratio * (350 - 20)))
    Config.FlySpeed = newVal
    FlySliderFill.Size = UDim2.new(ratio, 0, 1, 0)
    FlySliderKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
    FlySliderValLabel.Text = string.format("%d studs/s", newVal)
end

FlySliderBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isFlySliding = true
        UpdateFlySlider(input.Position.X)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isFlySliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        UpdateFlySlider(input.Position.X)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isFlySliding = false
    end
end)

-- Tombol Teleport & Terbang
local TPButton = Instance.new("TextButton")
TPButton.Size = UDim2.new(0.5, -18, 0, 32)
TPButton.Position = UDim2.new(0, 14, 0, 230)
TPButton.BackgroundColor3 = Color3.fromRGB(0, 135, 240)
TPButton.Text = "⚡ TELEPORT"
TPButton.TextColor3 = Color3.fromRGB(255, 255, 255)
TPButton.Font = Enum.Font.GothamBold
TPButton.TextSize = 11
TPButton.BorderSizePixel = 0
TPButton.Parent = MainTab

local TPBtnCorner = Instance.new("UICorner")
TPBtnCorner.CornerRadius = UDim.new(0, 6)
TPBtnCorner.Parent = TPButton

local FlyButton = Instance.new("TextButton")
FlyButton.Size = UDim2.new(0.5, -18, 0, 32)
FlyButton.Position = UDim2.new(0.5, 4, 0, 230)
FlyButton.BackgroundColor3 = Color3.fromRGB(30, 150, 90)
FlyButton.Text = "🚀 TERBANG"
FlyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
FlyButton.Font = Enum.Font.GothamBold
FlyButton.TextSize = 11
FlyButton.BorderSizePixel = 0
FlyButton.Parent = MainTab

local FlyBtnCorner = Instance.new("UICorner")
FlyBtnCorner.CornerRadius = UDim.new(0, 6)
FlyBtnCorner.Parent = FlyButton

-- Status Info Card
local TPStatusCard = Instance.new("Frame")
TPStatusCard.Size = UDim2.new(1, -28, 0, 32)
TPStatusCard.Position = UDim2.new(0, 14, 0, 270)
TPStatusCard.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
TPStatusCard.BorderSizePixel = 0
TPStatusCard.Parent = MainTab

local TPStatusCorner = Instance.new("UICorner")
TPStatusCorner.CornerRadius = UDim.new(0, 6)
TPStatusCorner.Parent = TPStatusCard

local TPStatusStroke = Instance.new("UIStroke")
TPStatusStroke.Thickness = 1
TPStatusStroke.Color = Color3.fromRGB(35, 40, 55)
TPStatusStroke.Parent = TPStatusCard

local TPStatusLabel = Instance.new("TextLabel")
TPStatusLabel.Size = UDim2.new(1, -16, 1, 0)
TPStatusLabel.Position = UDim2.new(0, 8, 0, 0)
TPStatusLabel.BackgroundTransparency = 1
TPStatusLabel.Text = "Status: Siap (Pilih nickname target di atas)"
TPStatusLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
TPStatusLabel.Font = Enum.Font.Gotham
TPStatusLabel.TextSize = 10
TPStatusLabel.TextWrapped = true
TPStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
TPStatusLabel.Parent = TPStatusCard

-- ============================================================================
-- 2. ISI TAB VISUAL (ENTITY HIGHLIGHT SYSTEM)
-- ============================================================================
VisualTab.CanvasSize = UDim2.new(0, 0, 0, 360)

local VisualSectionTitle = Instance.new("TextLabel")
VisualSectionTitle.Size = UDim2.new(1, -28, 0, 18)
VisualSectionTitle.Position = UDim2.new(0, 14, 0, 10)
VisualSectionTitle.BackgroundTransparency = 1
VisualSectionTitle.Text = "ENTITY HIGHLIGHT VISUALS"
VisualSectionTitle.TextColor3 = Color3.fromRGB(120, 130, 150)
VisualSectionTitle.Font = Enum.Font.GothamBold
VisualSectionTitle.TextSize = 10
VisualSectionTitle.TextXAlignment = Enum.TextXAlignment.Left
VisualSectionTitle.Parent = VisualTab

-- Kartu Informasi Warna Highlight
local LegendCard = Instance.new("Frame")
LegendCard.Size = UDim2.new(1, -28, 0, 50)
LegendCard.Position = UDim2.new(0, 14, 0, 30)
LegendCard.BackgroundColor3 = Color3.fromRGB(18, 21, 29)
LegendCard.BorderSizePixel = 0
LegendCard.Parent = VisualTab

local LegendCorner = Instance.new("UICorner")
LegendCorner.CornerRadius = UDim.new(0, 6)
LegendCorner.Parent = LegendCard

local LegendStroke = Instance.new("UIStroke")
LegendStroke.Thickness = 1
LegendStroke.Color = Color3.fromRGB(35, 40, 55)
LegendStroke.Parent = LegendCard

local LockDesc = Instance.new("TextLabel")
LockDesc.Size = UDim2.new(1, -16, 0, 18)
LockDesc.Position = UDim2.new(0, 10, 0, 6)
LockDesc.BackgroundTransparency = 1
LockDesc.Text = "🔴 Target Lock (Aim Lock) : Warna Merah"
LockDesc.TextColor3 = Color3.fromRGB(255, 90, 110)
LockDesc.Font = Enum.Font.GothamMedium
LockDesc.TextSize = 10
LockDesc.TextXAlignment = Enum.TextXAlignment.Left
LockDesc.Parent = LegendCard

local UnlockedDesc = Instance.new("TextLabel")
UnlockedDesc.Size = UDim2.new(1, -16, 0, 18)
UnlockedDesc.Position = UDim2.new(0, 10, 0, 26)
UnlockedDesc.BackgroundTransparency = 1
UnlockedDesc.Text = "🟡 Target Sekitar (Unlocked) : Warna Kuning"
UnlockedDesc.TextColor3 = Color3.fromRGB(255, 225, 80)
UnlockedDesc.Font = Enum.Font.GothamMedium
UnlockedDesc.TextSize = 10
UnlockedDesc.TextXAlignment = Enum.TextXAlignment.Left
UnlockedDesc.Parent = LegendCard

-- Dropdown Filter Target di Tab Visual
CreateDropdown(VisualTab, "TARGET HIGHLIGHT FILTER:", 86, {
    { Name = "Semua (Player & NPC)", Value = "All" },
    { Name = "Player Saja", Value = "Player" },
    { Name = "Bot / NPC Saja", Value = "NPC" }
}, Config.HighlightTargetType, 20, function(val)
    Config.HighlightTargetType = val
end)

-- Tombol Toggle Highlight ON/OFF
local HighlightToggleBtn = Instance.new("TextButton")
HighlightToggleBtn.Size = UDim2.new(1, -28, 0, 32)
HighlightToggleBtn.Position = UDim2.new(0, 14, 0, 140)
HighlightToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
HighlightToggleBtn.Text = "AKTIFKAN HIGHLIGHT (OFF)"
HighlightToggleBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
HighlightToggleBtn.Font = Enum.Font.GothamBold
HighlightToggleBtn.TextSize = 11
HighlightToggleBtn.BorderSizePixel = 0
HighlightToggleBtn.ZIndex = 2
HighlightToggleBtn.Parent = VisualTab

local HLToggleCorner = Instance.new("UICorner")
HLToggleCorner.CornerRadius = UDim.new(0, 6)
HLToggleCorner.Parent = HighlightToggleBtn

local HLToggleStroke = Instance.new("UIStroke")
HLToggleStroke.Thickness = 1
HLToggleStroke.Color = Color3.fromRGB(50, 58, 76)
HLToggleStroke.Parent = HighlightToggleBtn

HighlightToggleBtn.MouseButton1Click:Connect(function()
    Config.HighlightAllEnabled = not Config.HighlightAllEnabled
    if Config.HighlightAllEnabled then
        HighlightToggleBtn.Text = "MATIKAN HIGHLIGHT (ON)"
        HighlightToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
        HighlightToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        HLToggleStroke.Color = Color3.fromRGB(0, 220, 150)
    else
        HighlightToggleBtn.Text = "AKTIFKAN HIGHLIGHT (OFF)"
        HighlightToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
        HighlightToggleBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
        HLToggleStroke.Color = Color3.fromRGB(50, 58, 76)
    end
end)

-- Helper Pembuat Slider Sumbu X, Y, Z di Tab Visual
local function CreateAxisSlider(parent, titleText, yPos, configKey, minVal, maxVal, accentColor)
    CreateGeneralSlider(parent, titleText, yPos, configKey, minVal, maxVal, "studs", accentColor)
end

CreateAxisSlider(VisualTab, "RADIUS X (KANAN - KIRI):", 182, "HighlightRadiusX", 20, 1500, Color3.fromRGB(255, 120, 80))
CreateAxisSlider(VisualTab, "RADIUS Y (ATAS - BAWAH):", 236, "HighlightRadiusY", 20, 1000, Color3.fromRGB(80, 220, 150))
CreateAxisSlider(VisualTab, "RADIUS Z (DEPAN - BELAKANG):", 290, "HighlightRadiusZ", 20, 1500, Color3.fromRGB(80, 190, 255))

-- ============================================================================
-- 3. ISI TAB TRACKING (BULLET TRACKING & SILENT AIM)
-- ============================================================================
TrackingTab.CanvasSize = UDim2.new(0, 0, 0, 785)

local TrackingSectionTitle = Instance.new("TextLabel")
TrackingSectionTitle.Size = UDim2.new(1, -28, 0, 18)
TrackingSectionTitle.Position = UDim2.new(0, 14, 0, 10)
TrackingSectionTitle.BackgroundTransparency = 1
TrackingSectionTitle.Text = "BULLET TRACKING & SILENT AIM"
TrackingSectionTitle.TextColor3 = Color3.fromRGB(120, 130, 150)
TrackingSectionTitle.Font = Enum.Font.GothamBold
TrackingSectionTitle.TextSize = 10
TrackingSectionTitle.TextXAlignment = Enum.TextXAlignment.Left
TrackingSectionTitle.Parent = TrackingTab

-- Info Card Tracking
local TrackingInfoCard = Instance.new("Frame")
TrackingInfoCard.Size = UDim2.new(1, -28, 0, 54)
TrackingInfoCard.Position = UDim2.new(0, 14, 0, 30)
TrackingInfoCard.BackgroundColor3 = Color3.fromRGB(18, 21, 29)
TrackingInfoCard.BorderSizePixel = 0
TrackingInfoCard.Parent = TrackingTab

local TrackingInfoCorner = Instance.new("UICorner")
TrackingInfoCorner.CornerRadius = UDim.new(0, 6)
TrackingInfoCorner.Parent = TrackingInfoCard

local TrackingInfoStroke = Instance.new("UIStroke")
TrackingInfoStroke.Thickness = 1
TrackingInfoStroke.Color = Color3.fromRGB(35, 40, 55)
TrackingInfoStroke.Parent = TrackingInfoCard

local TrackingStatusLabel = Instance.new("TextLabel")
TrackingStatusLabel.Size = UDim2.new(1, -120, 0, 16)
TrackingStatusLabel.Position = UDim2.new(0, 10, 0, 7)
TrackingStatusLabel.BackgroundTransparency = 1
TrackingStatusLabel.Text = "Status: Fitur Nonaktif"
TrackingStatusLabel.TextColor3 = Color3.fromRGB(160, 165, 180)
TrackingStatusLabel.Font = Enum.Font.GothamMedium
TrackingStatusLabel.TextSize = 11
TrackingStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
TrackingStatusLabel.Parent = TrackingInfoCard

local TrackingTargetLabel = Instance.new("TextLabel")
TrackingTargetLabel.Size = UDim2.new(1, -16, 0, 14)
TrackingTargetLabel.Position = UDim2.new(0, 10, 0, 27)
TrackingTargetLabel.BackgroundTransparency = 1
TrackingTargetLabel.Text = "Target: Menunggu tembakan / Aim Lock..."
TrackingTargetLabel.TextColor3 = Color3.fromRGB(130, 135, 150)
TrackingTargetLabel.Font = Enum.Font.Gotham
TrackingTargetLabel.TextSize = 10
TrackingTargetLabel.TextXAlignment = Enum.TextXAlignment.Left
TrackingTargetLabel.Parent = TrackingInfoCard

local TrackingMethodBadge = Instance.new("TextLabel")
TrackingMethodBadge.Size = UDim2.new(0, 105, 0, 14)
TrackingMethodBadge.Position = UDim2.new(1, -112, 0, 8)
TrackingMethodBadge.BackgroundTransparency = 1
TrackingMethodBadge.Text = "Silent Aim + Homing"
TrackingMethodBadge.TextColor3 = Color3.fromRGB(0, 180, 255)
TrackingMethodBadge.Font = Enum.Font.GothamBold
TrackingMethodBadge.TextSize = 9
TrackingMethodBadge.TextXAlignment = Enum.TextXAlignment.Right
TrackingMethodBadge.Parent = TrackingInfoCard

-- Tombol Toggle Tracking ON/OFF
local TrackingToggleButton = Instance.new("TextButton")
TrackingToggleButton.Size = UDim2.new(1, -28, 0, 30)
TrackingToggleButton.Position = UDim2.new(0, 14, 0, 92)
TrackingToggleButton.BackgroundColor3 = Color3.fromRGB(0, 135, 240)
TrackingToggleButton.Text = "NYALAKAN TRACKING (T)"
TrackingToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
TrackingToggleButton.Font = Enum.Font.GothamBold
TrackingToggleButton.TextSize = 11
TrackingToggleButton.BorderSizePixel = 0
TrackingToggleButton.Parent = TrackingTab

local TrackingToggleCorner = Instance.new("UICorner")
TrackingToggleCorner.CornerRadius = UDim.new(0, 6)
TrackingToggleCorner.Parent = TrackingToggleButton

-- Dropdowns di Tab Tracking
CreateDropdown(TrackingTab, "BULLET TARGET SOURCE:", 130, {
    { Name = "Ikuti Target Aim Lock (Tab Player)", Value = "AimLock" },
    { Name = "Musuh Terdekat dalam FOV Kursor", Value = "MouseFOV" },
    { Name = "Musuh Terdekat Bebas (3D Closest)", Value = "Closest" }
}, Config.BulletTargetSource, 35, function(val)
    Config.BulletTargetSource = val
end)

CreateDropdown(TrackingTab, "TARGET BODY PART:", 182, {
    { Name = "Head / Kepala (Headshot)", Value = "Head" },
    { Name = "Torso / Badan (HumanoidRootPart)", Value = "Torso" },
    { Name = "Auto (Ikuti Target Part Tab Player)", Value = "Auto" },
    { Name = "Random (Acak Kepala / Badan)", Value = "Random" }
}, Config.BulletTargetPart, 30, function(val)
    Config.BulletTargetPart = val
end)

CreateDropdown(TrackingTab, "PREDICTION (LEAD TARGET):", 234, {
    { Name = "Aktif (Kompensasi Kecepatan Musuh)", Value = true },
    { Name = "Nonaktif (Tepat di Posisi Part)", Value = false }
}, Config.BulletPrediction, 25, function(val)
    Config.BulletPrediction = val
end)

CreateDropdown(TrackingTab, "HOMING PROJECTILES (BELOKKAN PELURU):", 286, {
    { Name = "Aktif (Belokkan Peluru Fisik & FastCast)", Value = true },
    { Name = "Nonaktif (Hanya Raycast & Silent Aim)", Value = false }
}, Config.BulletHomingProjectiles, 20, function(val)
    Config.BulletHomingProjectiles = val
end)

CreateDropdown(TrackingTab, "FOV CIRCLE (LINGKARAN TARGET):", 338, {
    { Name = "Tampilkan Lingkaran FOV [Aktif]", Value = true },
    { Name = "Sembunyikan Lingkaran FOV [Nonaktif]", Value = false }
}, Config.BulletShowFOVCircle, 15, function(val)
    Config.BulletShowFOVCircle = val
end)

CreateDropdown(TrackingTab, "BULLET TRACER VISUAL:", 390, {
    { Name = "Laser Tracer [Aktif]", Value = true },
    { Name = "Laser Tracer [Nonaktif]", Value = false }
}, Config.BulletTracerEnabled, 10, function(val)
    Config.BulletTracerEnabled = val
end)

-- Sliders di Tab Tracking
CreateGeneralSlider(TrackingTab, "HIT CHANCE (AKURASI):", 444, "BulletHitChance", 1, 100, "%", Color3.fromRGB(0, 215, 160))
CreateGeneralSlider(TrackingTab, "FOV RADIUS (PIXEL):", 498, "BulletFOVRadius", 40, 600, "px", Color3.fromRGB(0, 180, 255))

-- Sub-Section: AUTO SHOOT (TRIGGERBOT & WALL CHECK)
local AutoShootSectionTitle = Instance.new("TextLabel")
AutoShootSectionTitle.Size = UDim2.new(1, -28, 0, 18)
AutoShootSectionTitle.Position = UDim2.new(0, 14, 0, 552)
AutoShootSectionTitle.BackgroundTransparency = 1
AutoShootSectionTitle.Text = "AUTO SHOOT (TRIGGERBOT & WALL CHECK)"
AutoShootSectionTitle.TextColor3 = Color3.fromRGB(120, 130, 150)
AutoShootSectionTitle.Font = Enum.Font.GothamBold
AutoShootSectionTitle.TextSize = 10
AutoShootSectionTitle.TextXAlignment = Enum.TextXAlignment.Left
AutoShootSectionTitle.Parent = TrackingTab

local AutoShootToggleBtn = Instance.new("TextButton")
AutoShootToggleBtn.Size = UDim2.new(1, -28, 0, 30)
AutoShootToggleBtn.Position = UDim2.new(0, 14, 0, 574)
AutoShootToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
AutoShootToggleBtn.Text = "AUTO SHOOT: OFF (G)"
AutoShootToggleBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
AutoShootToggleBtn.Font = Enum.Font.GothamBold
AutoShootToggleBtn.TextSize = 11
AutoShootToggleBtn.BorderSizePixel = 0
AutoShootToggleBtn.Parent = TrackingTab

local AutoShootToggleCorner = Instance.new("UICorner")
AutoShootToggleCorner.CornerRadius = UDim.new(0, 6)
AutoShootToggleCorner.Parent = AutoShootToggleBtn

local AutoShootToggleStroke = Instance.new("UIStroke")
AutoShootToggleStroke.Thickness = 1
AutoShootToggleStroke.Color = Color3.fromRGB(50, 58, 76)
AutoShootToggleStroke.Parent = AutoShootToggleBtn

CreateDropdown(TrackingTab, "AUTO SHOOT TRIGGER MODE:", 612, {
    { Name = "Semua (Aim Lock + Lingkaran FOV)", Value = "All" },
    { Name = "Hanya Lingkaran FOV (Kursor)", Value = "FOV" },
    { Name = "Hanya Aim Lock (Locked Target)", Value = "AimLock" }
}, Config.AutoShootMode, 8, function(val)
    Config.AutoShootMode = val
end)

CreateDropdown(TrackingTab, "WALL CHECK (CEK TEMBOK):", 664, {
    { Name = "Aktif (Hanya Tembak Jika Terlihat Bebas)", Value = true },
    { Name = "Nonaktif (Tembus Pandang / Tembak Terus)", Value = false }
}, Config.AutoShootWallCheck, 5, function(val)
    Config.AutoShootWallCheck = val
end)

CreateGeneralSlider(TrackingTab, "DELAY TEMBAKAN (COOLDOWN):", 718, "AutoShootDelayMs", 50, 500, "ms", Color3.fromRGB(255, 140, 60))

-- ============================================================================
-- 4. ISI TAB SETTINGS (PANDUAN KONTROL & PENGATURAN UMUM)
-- ============================================================================
SettingsTab.CanvasSize = UDim2.new(0, 0, 0, 350)

local SettingsTitle = Instance.new("TextLabel")
SettingsTitle.Size = UDim2.new(1, -28, 0, 18)
SettingsTitle.Position = UDim2.new(0, 14, 0, 10)
SettingsTitle.BackgroundTransparency = 1
SettingsTitle.Text = "PANDUAN KONTROL & KEYBINDS"
SettingsTitle.TextColor3 = Color3.fromRGB(120, 130, 150)
SettingsTitle.Font = Enum.Font.GothamBold
SettingsTitle.TextSize = 10
SettingsTitle.TextXAlignment = Enum.TextXAlignment.Left
SettingsTitle.Parent = SettingsTab

local KeybindsCard = Instance.new("Frame")
KeybindsCard.Size = UDim2.new(1, -28, 0, 188)
KeybindsCard.Position = UDim2.new(0, 14, 0, 32)
KeybindsCard.BackgroundColor3 = Color3.fromRGB(18, 21, 29)
KeybindsCard.BorderSizePixel = 0
KeybindsCard.Parent = SettingsTab

local KeyCorner = Instance.new("UICorner")
KeyCorner.CornerRadius = UDim.new(0, 6)
KeyCorner.Parent = KeybindsCard

local KeyStroke = Instance.new("UIStroke")
KeyStroke.Thickness = 1
KeyStroke.Color = Color3.fromRGB(35, 40, 55)
KeyStroke.Parent = KeybindsCard

local keyItems = {
    { Key = "[ Q ]", Desc = "Nyalakan / Matikan Auto Aim Lock (Kamera & Karakter)" },
    { Key = "[ TAB ]", Desc = "Ganti Target Terdekat Berikutnya (Next Target)" },
    { Key = "[ T ]", Desc = "Nyalakan / Matikan Bullet Tracking (Silent Aim & Homing)" },
    { Key = "[ G ]", Desc = "Nyalakan / Matikan Auto Shoot (TriggerBot & Wall Check)" },
    { Key = "[ R-Shift ]", Desc = "Buka / Tutup Antarmuka Feath Hub GUI" },
    { Key = "[ Drag ]", Desc = "Geser Jendela Hub di Layar (PC & Mobile / Delta)" }
}

for idx, item in ipairs(keyItems) do
    local kLabel = Instance.new("TextLabel")
    kLabel.Size = UDim2.new(0, 68, 0, 22)
    kLabel.Position = UDim2.new(0, 10, 0, 8 + (idx - 1) * 28)
    kLabel.BackgroundColor3 = Color3.fromRGB(28, 32, 45)
    kLabel.Text = item.Key
    kLabel.TextColor3 = Color3.fromRGB(80, 210, 255)
    kLabel.Font = Enum.Font.GothamBold
    kLabel.TextSize = 10
    kLabel.Parent = KeybindsCard

    local kc = Instance.new("UICorner")
    kc.CornerRadius = UDim.new(0, 4)
    kc.Parent = kLabel

    local dLabel = Instance.new("TextLabel")
    dLabel.Size = UDim2.new(1, -90, 0, 22)
    dLabel.Position = UDim2.new(0, 86, 0, 8 + (idx - 1) * 28)
    dLabel.BackgroundTransparency = 1
    dLabel.Text = item.Desc
    dLabel.TextColor3 = Color3.fromRGB(190, 195, 205)
    dLabel.Font = Enum.Font.Gotham
    dLabel.TextSize = 10
    dLabel.TextXAlignment = Enum.TextXAlignment.Left
    dLabel.Parent = KeybindsCard
end

-- Info Versi & Support Card
local AboutCard = Instance.new("Frame")
AboutCard.Size = UDim2.new(1, -28, 0, 68)
AboutCard.Position = UDim2.new(0, 14, 0, 230)
AboutCard.BackgroundColor3 = Color3.fromRGB(18, 21, 29)
AboutCard.BorderSizePixel = 0
AboutCard.Parent = SettingsTab

local AboutCorner = Instance.new("UICorner")
AboutCorner.CornerRadius = UDim.new(0, 6)
AboutCorner.Parent = AboutCard

local AboutStroke = Instance.new("UIStroke")
AboutStroke.Thickness = 1
AboutStroke.Color = Color3.fromRGB(35, 40, 55)
AboutStroke.Parent = AboutCard

local AboutTitle = Instance.new("TextLabel")
AboutTitle.Size = UDim2.new(1, -20, 0, 18)
AboutTitle.Position = UDim2.new(0, 10, 0, 8)
AboutTitle.BackgroundTransparency = 1
AboutTitle.Text = "FEATH COMBAT SUITE v2.6"
AboutTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
AboutTitle.Font = Enum.Font.GothamBold
AboutTitle.TextSize = 11
AboutTitle.TextXAlignment = Enum.TextXAlignment.Left
AboutTitle.Parent = AboutCard

local AboutDesc = Instance.new("TextLabel")
AboutDesc.Size = UDim2.new(1, -20, 0, 32)
AboutDesc.Position = UDim2.new(0, 10, 0, 28)
AboutDesc.BackgroundTransparency = 1
AboutDesc.Text = "Dilengkapi Full Silent Aim, Auto Shoot (Wall Check), Homing, Raycast Hook, & FOV Circle."
AboutDesc.TextColor3 = Color3.fromRGB(130, 135, 150)
AboutDesc.Font = Enum.Font.Gotham
AboutDesc.TextSize = 9
AboutDesc.TextWrapped = true
AboutDesc.TextXAlignment = Enum.TextXAlignment.Left
AboutDesc.Parent = AboutCard

-- ============================================================================
-- 3. ISI TAB PLAYER (SELURUH FUNGSI COMBAT LAMA DITEMPATKAN DI SINI)
-- ============================================================================

-- Section Title
local SectionTitle = Instance.new("TextLabel")
SectionTitle.Size = UDim2.new(1, -28, 0, 18)
SectionTitle.Position = UDim2.new(0, 14, 0, 10)
SectionTitle.BackgroundTransparency = 1
SectionTitle.Text = "COMBAT AUTO-LOCK CONTROLS"
SectionTitle.TextColor3 = Color3.fromRGB(120, 130, 150)
SectionTitle.Font = Enum.Font.GothamBold
SectionTitle.TextSize = 10
SectionTitle.TextXAlignment = Enum.TextXAlignment.Left
SectionTitle.Parent = PlayerTab

-- Target Info Card (Nama, Jarak, HP Bar)
local InfoCard = Instance.new("Frame")
InfoCard.Size = UDim2.new(1, -28, 0, 54)
InfoCard.Position = UDim2.new(0, 14, 0, 32)
InfoCard.BackgroundColor3 = Color3.fromRGB(18, 21, 29)
InfoCard.BorderSizePixel = 0
InfoCard.Parent = PlayerTab

local InfoCorner = Instance.new("UICorner")
InfoCorner.CornerRadius = UDim.new(0, 6)
InfoCorner.Parent = InfoCard

local TargetNameLabel = Instance.new("TextLabel")
TargetNameLabel.Size = UDim2.new(1, -12, 0, 16)
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
DistanceLabel.Position = UDim2.new(0, 8, 0, 21)
DistanceLabel.BackgroundTransparency = 1
DistanceLabel.Text = "Jarak: --"
DistanceLabel.TextColor3 = Color3.fromRGB(130, 135, 150)
DistanceLabel.Font = Enum.Font.Gotham
DistanceLabel.TextSize = 10
DistanceLabel.TextXAlignment = Enum.TextXAlignment.Left
DistanceLabel.Parent = InfoCard

local HealthBarBg = Instance.new("Frame")
HealthBarBg.Size = UDim2.new(1, -16, 0, 5)
HealthBarBg.Position = UDim2.new(0, 8, 0, 40)
HealthBarBg.BackgroundColor3 = Color3.fromRGB(30, 34, 44)
HealthBarBg.BorderSizePixel = 0
HealthBarBg.Parent = InfoCard

local HealthBarCorner = Instance.new("UICorner")
HealthBarCorner.CornerRadius = UDim.new(1, 0)
HealthBarCorner.Parent = HealthBarBg

local HealthBarFill = Instance.new("Frame")
HealthBarFill.Size = UDim2.new(0, 0, 1, 0)
HealthBarFill.BackgroundColor3 = Color3.fromRGB(50, 205, 120)
HealthBarFill.BorderSizePixel = 0
HealthBarFill.Parent = HealthBarBg

local HealthBarFillCorner = Instance.new("UICorner")
HealthBarFillCorner.CornerRadius = UDim.new(1, 0)
HealthBarFillCorner.Parent = HealthBarFill

-- Tombol Toggle ON/OFF Utama & Switch Target
local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(0.68, -6, 0, 30)
ToggleButton.Position = UDim2.new(0, 14, 0, 94)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 135, 240)
ToggleButton.Text = "NYALAKAN (Q)"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.TextSize = 11
ToggleButton.BorderSizePixel = 0
ToggleButton.Parent = PlayerTab

local ToggleBtnCorner = Instance.new("UICorner")
ToggleBtnCorner.CornerRadius = UDim.new(0, 6)
ToggleBtnCorner.Parent = ToggleButton

local SwitchButton = Instance.new("TextButton")
SwitchButton.Size = UDim2.new(0.32, -22, 0, 30)
SwitchButton.Position = UDim2.new(0.68, 14, 0, 94)
SwitchButton.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
SwitchButton.Text = "NEXT (TAB)"
SwitchButton.TextColor3 = Color3.fromRGB(220, 220, 220)
SwitchButton.Font = Enum.Font.GothamBold
SwitchButton.TextSize = 10
SwitchButton.BorderSizePixel = 0
SwitchButton.Parent = PlayerTab

local SwitchBtnCorner = Instance.new("UICorner")
SwitchBtnCorner.CornerRadius = UDim.new(0, 6)
SwitchBtnCorner.Parent = SwitchButton

-- ============================================================================
-- DROPDOWNS DI TAB PLAYER
-- ============================================================================


-- Inisialisasi 5 Dropdown di Tab Player
CreateDropdown(PlayerTab, "TARGET BODY PART:", 132, {
    { Name = "Head / Kepala", Value = "Head" },
    { Name = "Torso / Badan (HumanoidRootPart)", Value = "Torso" }
}, Config.TargetPartChoice, 20, function(val)
    Config.TargetPartChoice = val
    if AutoLockEnabled and CurrentTargetChar then
        CurrentTargetPart = GetTargetPart(CurrentTargetChar)
    end
end)

CreateDropdown(PlayerTab, "TARGET SWITCH BEHAVIOR:", 184, {
    { Name = "Auto Ganti (Musuh Terdekat)", Value = "Dynamic" },
    { Name = "Auto Ganti (HP / Darah Terendah)", Value = "LowestHP" },
    { Name = "Menetap (Kunci Sampai Target Mati)", Value = "Persistent" }
}, Config.TargetSwitchMode, 16, function(val)
    Config.TargetSwitchMode = val
    if AutoLockEnabled then
        local best = FindBestTarget()
        if best then SetTarget(best) end
    end
end)

CreateDropdown(PlayerTab, "AIM LOCK MODE:", 236, {
    { Name = "Jarak 3D Terdekat (Distance)", Value = "Distance" },
    { Name = "Kursor / Tengah Layar (2D)", Value = "Cursor" }
}, Config.LockMode, 12, function(val)
    Config.LockMode = val
end)

CreateDropdown(PlayerTab, "TARGET ENTITY FILTER:", 288, {
    { Name = "Semua (Player + Bot / NPC)", Value = "All" },
    { Name = "Hanya Bot / NPC / Monster", Value = "NPC" },
    { Name = "Hanya Pemain Lain (Player)", Value = "Player" }
}, Config.TargetType, 8, function(val)
    Config.TargetType = val
    if AutoLockEnabled then
        local best = FindBestTarget()
        SetTarget(best)
    end
end)

CreateDropdown(PlayerTab, "TEAM FILTER (TEAM CHECK):", 340, {
    { Name = "Hanya Musuh (Beda Team) [Aktif]", Value = true },
    { Name = "Bebas / Semua Team [Nonaktif]", Value = false }
}, Config.TeamCheck, 4, function(val)
    Config.TeamCheck = val
    if AutoLockEnabled then
        local best = FindBestTarget()
        SetTarget(best)
    end
end)

-- ============================================================================
-- SLIDER PENGATUR JARAK DETEKSI DI TAB PLAYER
-- ============================================================================
local MinDistance = 20
local MaxDistance = 300

local SliderContainer = Instance.new("Frame")
SliderContainer.Name = "SliderContainer"
SliderContainer.Size = UDim2.new(1, -28, 0, 48)
SliderContainer.Position = UDim2.new(0, 14, 0, 396)
SliderContainer.BackgroundTransparency = 1
SliderContainer.Parent = PlayerTab

local SliderTitle = Instance.new("TextLabel")
SliderTitle.Size = UDim2.new(0.6, 0, 0, 14)
SliderTitle.Position = UDim2.new(0, 0, 0, 0)
SliderTitle.BackgroundTransparency = 1
SliderTitle.Text = "JARAK DETEKSI (STUDS):"
SliderTitle.TextColor3 = Color3.fromRGB(150, 155, 170)
SliderTitle.Font = Enum.Font.GothamMedium
SliderTitle.TextSize = 10
SliderTitle.TextXAlignment = Enum.TextXAlignment.Left
SliderTitle.Parent = SliderContainer

local SliderValueLabel = Instance.new("TextLabel")
SliderValueLabel.Size = UDim2.new(0.4, 0, 0, 14)
SliderValueLabel.Position = UDim2.new(0.6, 0, 0, 0)
SliderValueLabel.BackgroundTransparency = 1
SliderValueLabel.Text = string.format("%d studs (Break: %d)", Config.MaxLockDistance, Config.BreakDistance)
SliderValueLabel.TextColor3 = Color3.fromRGB(80, 210, 255)
SliderValueLabel.Font = Enum.Font.GothamBold
SliderValueLabel.TextSize = 10
SliderValueLabel.TextXAlignment = Enum.TextXAlignment.Right
SliderValueLabel.Parent = SliderContainer

local SliderBar = Instance.new("Frame")
SliderBar.Name = "SliderBar"
SliderBar.Size = UDim2.new(1, 0, 0, 8)
SliderBar.Position = UDim2.new(0, 0, 0, 20)
SliderBar.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
SliderBar.BorderSizePixel = 0
SliderBar.Parent = SliderContainer

local SliderBarCorner = Instance.new("UICorner")
SliderBarCorner.CornerRadius = UDim.new(1, 0)
SliderBarCorner.Parent = SliderBar

local SliderFill = Instance.new("Frame")
SliderFill.Name = "SliderFill"
local initialRatio = math.clamp((Config.MaxLockDistance - MinDistance) / (MaxDistance - MinDistance), 0, 1)
SliderFill.Size = UDim2.new(initialRatio, 0, 1, 0)
SliderFill.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
SliderFill.BorderSizePixel = 0
SliderFill.Parent = SliderBar

local SliderFillCorner = Instance.new("UICorner")
SliderFillCorner.CornerRadius = UDim.new(1, 0)
SliderFillCorner.Parent = SliderFill

local SliderKnob = Instance.new("Frame")
SliderKnob.Name = "SliderKnob"
SliderKnob.Size = UDim2.new(0, 16, 0, 16)
SliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
SliderKnob.Position = UDim2.new(initialRatio, 0, 0.5, 0)
SliderKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
SliderKnob.BorderSizePixel = 0
SliderKnob.ZIndex = 3
SliderKnob.Parent = SliderBar

local KnobCorner = Instance.new("UICorner")
KnobCorner.CornerRadius = UDim.new(1, 0)
KnobCorner.Parent = SliderKnob

local KnobStroke = Instance.new("UIStroke")
KnobStroke.Thickness = 1.5
KnobStroke.Color = Color3.fromRGB(0, 140, 255)
KnobStroke.Parent = SliderKnob

local isSliding = false

local function UpdateSlider(inputX)
    local barAbsolutePos = SliderBar.AbsolutePosition.X
    local barAbsoluteSize = SliderBar.AbsoluteSize.X
    local ratio = math.clamp((inputX - barAbsolutePos) / barAbsoluteSize, 0, 1)
    
    local newDistance = math.floor(MinDistance + (ratio * (MaxDistance - MinDistance)))
    Config.MaxLockDistance = newDistance
    Config.BreakDistance = newDistance + 20
    
    SliderFill.Size = UDim2.new(ratio, 0, 1, 0)
    SliderKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
    SliderValueLabel.Text = string.format("%d studs (Break: %d)", newDistance, Config.BreakDistance)
end

SliderBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isSliding = true
        UpdateSlider(input.Position.X)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isSliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        UpdateSlider(input.Position.X)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isSliding = false
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

local UnlockedHighlights = {} -- [Character] = HighlightInstance (Kuning untuk target belum di-lock)
local HighlightInfoBillboards = {} -- [Character] = BillboardGui (Informasi nickname, darah, jarak)

-- ============================================================================
-- LOGIKA UTAMA COMBAT DILINDUNGI PCALL
-- ============================================================================

function GetTargetPart(char)
    if not char then return nil end
    
    if Config.TargetPartChoice == "Head" then
        local head = char:FindFirstChild("Head")
        if head and head:IsA("BasePart") then return head end
    end
    
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

local function IsSameTeam(player)
    if not player or player == LocalPlayer then return true end
    
    if LocalPlayer.Team ~= nil and player.Team ~= nil then
        return LocalPlayer.Team == player.Team
    end
    
    if LocalPlayer.TeamColor ~= nil and player.TeamColor ~= nil then
        return LocalPlayer.TeamColor == player.TeamColor
    end
    
    return false
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
                
                if isPlayer and Config.TeamCheck and IsSameTeam(playerObj) then
                    return
                end

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
                            local hum = model:FindFirstChildOfClass("Humanoid")
                            table.insert(enemies, {
                                Character = model,
                                Part = root,
                                Distance = dist,
                                IsNPC = not isPlayer,
                                Name = isPlayer and playerObj.DisplayName or model.Name,
                                Humanoid = hum,
                                Health = hum and hum.Health or 100
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

        if Config.TargetSwitchMode == "LowestHP" then
            local lowestHP = math.huge
            local shortestDist = math.huge

            for _, entry in ipairs(enemies) do
                local hp = entry.Health or math.huge
                if hp < lowestHP then
                    lowestHP = hp
                    shortestDist = entry.Distance
                    best = entry
                elseif math.abs(hp - lowestHP) < 0.5 and entry.Distance < shortestDist then
                    shortestDist = entry.Distance
                    best = entry
                end
            end
        elseif Config.LockMode == "Distance" then
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

            -- Bersihkan highlight kuning dari target yang dikunci agar menjadi merah
            if UnlockedHighlights[entry.Character] then
                pcall(function() UnlockedHighlights[entry.Character]:Destroy() end)
                UnlockedHighlights[entry.Character] = nil
            end

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

-- ============================================================================
-- LOGIKA UTAMA BULLET TRACKING & SILENT AIM
-- ============================================================================
function GetBulletTarget()
    local cfg = _G.FeathCombatConfig or Config
    if not cfg or not cfg.BulletTrackingEnabled then return nil, nil end

    local targetPart = nil
    local targetChar = nil

    local function ResolvePart(model)
        if not model then return nil end
        if cfg.BulletTargetPart == "Head" then
            local h = model:FindFirstChild("Head")
            if h and h:IsA("BasePart") then return h end
        elseif cfg.BulletTargetPart == "Torso" then
            local t = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
            if t and t:IsA("BasePart") then return t end
        elseif cfg.BulletTargetPart == "Random" then
            local candidates = {}
            local h = model:FindFirstChild("Head")
            if h and h:IsA("BasePart") then table.insert(candidates, h) end
            local t = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
            if t and t:IsA("BasePart") then table.insert(candidates, t) end
            if #candidates > 0 then return candidates[math.random(1, #candidates)] end
        end
        return GetTargetPart(model)
    end

    -- 1. Mode AimLock
    if cfg.BulletTargetSource == "AimLock" then
        if CurrentTargetChar and IsValidEnemy(CurrentTargetChar) then
            local part = ResolvePart(CurrentTargetChar)
            if part then
                if cfg.BulletUseFOV then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                    local mousePos = UserInputService:GetMouseLocation()
                    local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if onScreen and dist2D <= cfg.BulletFOVRadius then
                        targetPart = part
                        targetChar = CurrentTargetChar
                    end
                else
                    targetPart = part
                    targetChar = CurrentTargetChar
                end
            end
        end
    end

    -- 2. Fallback / Mode MouseFOV & Closest
    if not targetPart then
        local enemies = GetEnemiesSortedByDistance()
        local mousePos = UserInputService:GetMouseLocation()
        local bestCandidate = nil
        local bestMetric = math.huge

        for _, entry in ipairs(enemies) do
            local model = entry.Character
            local part = ResolvePart(model)
            if part then
                if cfg.BulletTargetSource == "Closest" and not cfg.BulletUseFOV then
                    if entry.Distance < bestMetric then
                        bestMetric = entry.Distance
                        bestCandidate = { Model = model, Part = part }
                    end
                else
                    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen then
                        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                        if (not cfg.BulletUseFOV or screenDist <= cfg.BulletFOVRadius) and screenDist < bestMetric then
                            bestMetric = screenDist
                            bestCandidate = { Model = model, Part = part }
                        end
                    end
                end
            end
        end

        if bestCandidate then
            targetChar = bestCandidate.Model
            targetPart = bestCandidate.Part
        end
    end

    if not targetPart or not targetPart:IsA("BasePart") then
        return nil, nil
    end

    local targetPos = targetPart.Position
    if cfg.BulletPrediction then
        local vel = Vector3.zero
        pcall(function()
            vel = targetPart.AssemblyLinearVelocity
        end)
        local predFactor = cfg.BulletPredictionFactor or 0.13
        targetPos = targetPos + (vel * predFactor)
    end

    return targetPart, targetPos
end

function CreateBulletTracer(fromPos, toPos)
    local cfg = _G.FeathCombatConfig or Config
    if not cfg or not cfg.BulletTracerEnabled then return end
    task.spawn(function()
        pcall(function()
            local dist = (toPos - fromPos).Magnitude
            if dist < 1 or dist > 2500 then return end
            local tracer = Instance.new("Part")
            tracer.Name = "CombatBulletTracer"
            tracer.Anchored = true
            tracer.CanCollide = false
            tracer.CastShadow = false
            tracer.Material = Enum.Material.Neon
            tracer.Color = cfg.BulletTracerColor or Color3.fromRGB(0, 225, 255)
            tracer.Size = Vector3.new(0.08, 0.08, dist)
            tracer.CFrame = CFrame.lookAt(fromPos, toPos) * CFrame.new(0, 0, -dist / 2)
            tracer.Parent = workspace

            local tween = TweenService:Create(tracer, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = 1,
                Size = Vector3.new(0.01, 0.01, dist)
            })
            tween:Play()
            tween.Completed:Connect(function()
                tracer:Destroy()
            end)
            task.delay(0.5, function()
                if tracer and tracer.Parent then tracer:Destroy() end
            end)
        end)
    end)
end

function ToggleBulletTracking()
    pcall(function()
        Config.BulletTrackingEnabled = not Config.BulletTrackingEnabled
        _G.FeathCombatConfig = Config
        UpdateUI()
    end)
end

-- Pasang fungsi ke _G untuk delegasi hook metamethod
_G.FeathGetBulletTarget = GetBulletTarget
_G.FeathCreateBulletTracer = CreateBulletTracer

-- Inisialisasi Hooking Metamethod (Silent Aim)
pcall(function()
    if typeof(hookmetamethod) == "function" and typeof(getnamecallmethod) == "function" then
        if not _G.FeathMetamethodsHooked then
            _G.FeathMetamethodsHooked = true

            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local method = getnamecallmethod()
                local cfg = _G.FeathCombatConfig
                if cfg and cfg.BulletTrackingEnabled and (not checkcaller or not checkcaller()) then
                    if (method == "Raycast" and self == workspace)
                        or method == "FindPartOnRay"
                        or method == "FindPartOnRayWithIgnoreList"
                        or method == "FindPartOnRayWithWhitelist" then

                        local hitChance = cfg.BulletHitChance or 100
                        if math.random(1, 100) <= hitChance then
                            local fn = _G.FeathGetBulletTarget
                            local targetPart, targetPos = fn and fn()
                            if targetPart and targetPos then
                                local args = {...}
                                if method == "Raycast" then
                                    local origin = args[1]
                                    local dir = args[2]
                                    if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" then
                                        local mag = math.max(dir.Magnitude, 1000)
                                        args[2] = (targetPos - origin).Unit * mag
                                        if _G.FeathCreateBulletTracer then
                                            _G.FeathCreateBulletTracer(origin, targetPos)
                                        end
                                        return oldNamecall(self, table.unpack(args))
                                    end
                                else
                                    local ray = args[1]
                                    if typeof(ray) == "Ray" then
                                        local mag = math.max(ray.Direction.Magnitude, 1000)
                                        local newDir = (targetPos - ray.Origin).Unit * mag
                                        args[1] = Ray.new(ray.Origin, newDir)
                                        if _G.FeathCreateBulletTracer then
                                            _G.FeathCreateBulletTracer(ray.Origin, targetPos)
                                        end
                                        return oldNamecall(self, table.unpack(args))
                                    end
                                end
                            end
                        end
                    end
                end
                return oldNamecall(self, ...)
            end))

            local oldIndex
            oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
                local cfg = _G.FeathCombatConfig
                if cfg and cfg.BulletTrackingEnabled and (not checkcaller or not checkcaller()) then
                    local ok, isMouse = pcall(function() return typeof(self) == "Instance" and self:IsA("Mouse") end)
                    if ok and isMouse then
                        if key == "Hit" or key == "Target" then
                            local hitChance = cfg.BulletHitChance or 100
                            if math.random(1, 100) <= hitChance then
                                local fn = _G.FeathGetBulletTarget
                                local targetPart, targetPos = fn and fn()
                                if targetPart and targetPos then
                                    if key == "Hit" then
                                        if _G.FeathCreateBulletTracer then
                                            local camPos = Camera and Camera.CFrame.Position or targetPos
                                            _G.FeathCreateBulletTracer(camPos, targetPos)
                                        end
                                        return CFrame.new(targetPos)
                                    elseif key == "Target" then
                                        return targetPart
                                    end
                                end
                            end
                        end
                    end
                end
                return oldIndex(self, key)
            end))
        end
    end
end)

-- Homing Projectiles (Peluru Fisik & FastCast di Workspace)
local function MonitorProjectile(obj)
    local cfg = _G.FeathCombatConfig or Config
    if not cfg or not cfg.BulletTrackingEnabled or not cfg.BulletHomingProjectiles then return end
    if not obj or not obj:IsA("BasePart") then return end

    local myChar = LocalPlayer.Character
    if not myChar then return end
    if obj:IsDescendantOf(myChar) then return end
    if obj.Name == "CombatBulletTracer" or obj.Name == "CombatTargetHitboxBox" or obj.Name == "CombatTargetHitboxHighlight" then return end

    local lowerName = string.lower(obj.Name)
    local isProjectileName = string.find(lowerName, "bullet") or string.find(lowerName, "projectile")
        or string.find(lowerName, "missile") or string.find(lowerName, "rocket")
        or string.find(lowerName, "arrow") or string.find(lowerName, "laser")
        or string.find(lowerName, "pellet") or string.find(lowerName, "tracer")
        or string.find(lowerName, "plasma") or string.find(lowerName, "shot")
        or string.find(lowerName, "fastcast") or string.find(lowerName, "bolt")

    local myRoot = GetTargetPart(myChar)
    if not myRoot then return end
    local distFromPlayer = (obj.Position - myRoot.Position).Magnitude

    if isProjectileName or (distFromPlayer <= 16 and not obj.Anchored and obj.Size.Magnitude < 8) then
        local hitChance = cfg.BulletHitChance or 100
        if math.random(1, 100) > hitChance then return end

        local fn = _G.FeathGetBulletTarget or GetBulletTarget
        local targetPart, targetPos = fn and fn()
        if not targetPart or not targetPos then return end

        local connection
        local startTime = tick()
        connection = RunService.Heartbeat:Connect(function(dt)
            if not obj or not obj.Parent or (tick() - startTime > 3.5) then
                if connection then connection:Disconnect() connection = nil end
                return
            end

            local tPart, tPos = fn and fn()
            if not tPart or not tPos then
                if connection then connection:Disconnect() connection = nil end
                return
            end

            local diff = tPos - obj.Position
            local dist = diff.Magnitude
            if dist < 2.5 then
                if connection then connection:Disconnect() connection = nil end
                return
            end

            local currentVel = obj.AssemblyLinearVelocity
            local currentSpeed = currentVel.Magnitude
            if currentSpeed < 30 then currentSpeed = 250 end

            pcall(function()
                obj.AssemblyLinearVelocity = diff.Unit * currentSpeed
                obj.CFrame = CFrame.lookAt(obj.Position, tPos)
            end)
        end)
    end
end

_G.CombatBulletProjectileConn = workspace.DescendantAdded:Connect(function(descendant)
    pcall(function()
        MonitorProjectile(descendant)
    end)
end)

-- ============================================================================
-- LOGIKA AUTO SHOOT (TRIGGERBOT DENGAN WALL CHECK)
-- ============================================================================
function IsTargetVisible(targetPart)
    if not targetPart or not targetPart:IsA("BasePart") then return false end
    local myChar = LocalPlayer.Character
    if not myChar then return false end

    local origin = Camera and Camera.CFrame.Position
    if not origin then
        local myHead = myChar:FindFirstChild("Head") or GetTargetPart(myChar)
        if not myHead then return false end
        origin = myHead.Position
    end

    local targetPos = targetPart.Position
    local direction = targetPos - origin
    local dist = direction.Magnitude
    if dist < 0.5 then return true end

    local targetModel = targetPart.Parent

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {
        myChar,
        targetModel,
        Camera
    }
    rayParams.IgnoreWater = true

    local hit = workspace:Raycast(origin, direction, rayParams)
    if hit and hit.Instance and not hit.Instance:IsDescendantOf(targetModel) and not hit.Instance:IsDescendantOf(myChar) then
        if hit.Instance.CanCollide == false and hit.Instance.Transparency > 0.5 then
            return true
        end
        return false -- Terhalang tembok/rintangan
    end

    return true
end

function GetAutoShootTarget()
    local myChar = LocalPlayer.Character
    if not myChar then return nil end

    -- 1. Mode AimLock / All: Cek apakah target yang sedang di-lock terlihat bebas
    if (Config.AutoShootMode == "All" or Config.AutoShootMode == "AimLock") and AutoLockEnabled then
        if CurrentTargetChar and IsValidEnemy(CurrentTargetChar) and CurrentTargetPart then
            if not Config.AutoShootWallCheck or IsTargetVisible(CurrentTargetPart) then
                return CurrentTargetPart
            end
        end
    end

    -- 2. Mode FOV / All: Cek musuh di dalam lingkaran FOV
    if Config.AutoShootMode == "All" or Config.AutoShootMode == "FOV" then
        local enemies = GetEnemiesSortedByDistance()
        local mousePos = UserInputService:GetMouseLocation()

        for _, entry in ipairs(enemies) do
            local model = entry.Character
            local part = nil
            if Config.BulletTargetPart == "Head" then
                part = model:FindFirstChild("Head") or entry.Part
            elseif Config.BulletTargetPart == "Torso" then
                part = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso") or entry.Part
            else
                part = entry.Part
            end

            if part and part:IsA("BasePart") then
                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if screenDist <= Config.BulletFOVRadius then
                        if not Config.AutoShootWallCheck or IsTargetVisible(part) then
                            return part
                        end
                    end
                end
            end
        end
    end

    return nil
end

local lastAutoShootTick = 0
function TriggerShoot()
    local now = tick()
    local delayTime = (Config.AutoShootDelayMs or 100) / 1000
    if now - lastAutoShootTick < delayTime then
        return
    end
    lastAutoShootTick = now

    pcall(function()
        -- 1. Aktivasi senjata Tool di karakter
        local myChar = LocalPlayer.Character
        local tool = myChar and myChar:FindFirstChildOfClass("Tool")
        if tool then
            tool:Activate()
        end

        -- 2. Simulasi klik mouse untuk senjata berbasis event input
        if typeof(mouse1click) == "function" then
            mouse1click()
        elseif typeof(mouse1press) == "function" and typeof(mouse1release) == "function" then
            mouse1press()
            task.delay(0.02, function() pcall(mouse1release) end)
        else
            local vu = game:GetService("VirtualUser")
            if vu then
                vu:CaptureController()
                vu:Button1Down(Vector2.new(0, 0))
                task.delay(0.02, function()
                    pcall(function() vu:Button1Up(Vector2.new(0, 0)) end)
                end)
            end
        end
    end)
end

function ToggleAutoShoot()
    pcall(function()
        Config.AutoShootEnabled = not Config.AutoShootEnabled
        _G.FeathCombatConfig = Config
        UpdateUI()
    end)
end

local function UpdateUI()
    pcall(function()
        -- 1. Status Indicator Sidebar
        if AutoLockEnabled then
            if CurrentTargetChar and IsValidEnemy(CurrentTargetChar) and CurrentTargetPart then
                StatusVal.Text = "Locked"
                StatusVal.TextColor3 = Color3.fromRGB(255, 60, 80)
                DotIndicator.BackgroundColor3 = Color3.fromRGB(255, 60, 80)
            else
                StatusVal.Text = "Searching"
                StatusVal.TextColor3 = Color3.fromRGB(220, 160, 30)
                DotIndicator.BackgroundColor3 = Color3.fromRGB(220, 160, 30)
            end
        elseif Config.AutoShootEnabled then
            StatusVal.Text = "AutoShoot"
            StatusVal.TextColor3 = Color3.fromRGB(50, 225, 120)
            DotIndicator.BackgroundColor3 = Color3.fromRGB(50, 225, 120)
        elseif Config.BulletTrackingEnabled then
            StatusVal.Text = "Tracking"
            StatusVal.TextColor3 = Color3.fromRGB(0, 180, 255)
            DotIndicator.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
        else
            StatusVal.Text = "Idle"
            StatusVal.TextColor3 = Color3.fromRGB(160, 165, 180)
            DotIndicator.BackgroundColor3 = Color3.fromRGB(120, 130, 150)
        end

        -- 2. Update Tab Player UI (Aim Lock)
        if not AutoLockEnabled then
            ToggleButton.Text = "NYALAKAN (Q)"
            ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 135, 240)

            TargetNameLabel.Text = "Status: Fitur Nonaktif"
            DistanceLabel.Text = "Jarak: --"
            HealthBarFill.Size = UDim2.new(0, 0, 1, 0)
        else
            ToggleButton.Text = "MATIKAN (Q)"
            ToggleButton.BackgroundColor3 = Color3.fromRGB(220, 45, 65)

            if CurrentTargetChar and IsValidEnemy(CurrentTargetChar) and CurrentTargetPart then
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
                TargetNameLabel.Text = "Status: Mencari target terdekat..."
                DistanceLabel.Text = "Jarak: Menunggu musuh..."
                HealthBarFill.Size = UDim2.new(0, 0, 1, 0)
            end
        end

        -- 3. Update Tab Tracking UI (Bullet Tracking)
        if not Config.BulletTrackingEnabled then
            TrackingToggleButton.Text = "NYALAKAN TRACKING (T)"
            TrackingToggleButton.BackgroundColor3 = Color3.fromRGB(0, 135, 240)
            TrackingStatusLabel.Text = "Status: Fitur Nonaktif"
            TrackingStatusLabel.TextColor3 = Color3.fromRGB(160, 165, 180)
            TrackingTargetLabel.Text = "Target: --"
            TrackingTargetLabel.TextColor3 = Color3.fromRGB(130, 135, 150)
        else
            TrackingToggleButton.Text = "MATIKAN TRACKING (T)"
            TrackingToggleButton.BackgroundColor3 = Color3.fromRGB(220, 45, 65)

            local tPart, _ = GetBulletTarget()
            if tPart and tPart.Parent then
                local tChar = tPart.Parent
                local isNPC = not Players:GetPlayerFromCharacter(tChar)
                local tag = isNPC and "[BOT] " or "[PLAYER] "
                local partName = string.upper(tPart.Name)

                TrackingStatusLabel.Text = "Status: Tracking Aktif (Target Locked)"
                TrackingStatusLabel.TextColor3 = Color3.fromRGB(50, 225, 120)
                TrackingTargetLabel.Text = string.format("Target: %s%s (%s)", tag, tChar.Name, partName)
                TrackingTargetLabel.TextColor3 = Color3.fromRGB(80, 210, 255)
            else
                TrackingStatusLabel.Text = "Status: Tracking Aktif (Mencari Target...)"
                TrackingStatusLabel.TextColor3 = Color3.fromRGB(240, 175, 45)
                TrackingTargetLabel.Text = "Target: Arahkan kursor ke musuh di dalam FOV"
                TrackingTargetLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
            end
        end

        -- 4. Update Tab Tracking UI (Auto Shoot)
        if not Config.AutoShootEnabled then
            AutoShootToggleBtn.Text = "AUTO SHOOT: OFF (G)"
            AutoShootToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
            AutoShootToggleBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
            AutoShootToggleStroke.Color = Color3.fromRGB(50, 58, 76)
        else
            AutoShootToggleBtn.Text = "AUTO SHOOT: ON (G)"
            AutoShootToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
            AutoShootToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            AutoShootToggleStroke.Color = Color3.fromRGB(0, 220, 150)
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

-- ============================================================================
-- SISTEM HIGHLIGHT KUNING UNTUK TARGET BELUM DI-LOCK
-- ============================================================================
local function ClearUnlockedHighlights()
    for char, hl in pairs(UnlockedHighlights) do
        pcall(function() hl:Destroy() end)
    end
    table.clear(UnlockedHighlights)
    for char, bb in pairs(HighlightInfoBillboards) do
        pcall(function() bb:Destroy() end)
    end
    table.clear(HighlightInfoBillboards)
end

local function UpdateOrCreateInfoBB(model, nameStr, hum, dist, isLocked)
    local bb = HighlightInfoBillboards[model]
    local label = bb and bb:FindFirstChild("InfoLabel")

    local hpVal = hum and math.max(0, math.floor(hum.Health)) or 0
    local maxHpVal = hum and math.floor(hum.MaxHealth) or 100
    local hpStr
    if maxHpVal > 0 and maxHpVal ~= 100 then
        hpStr = string.format("[%d/%d HP]", hpVal, maxHpVal)
    else
        hpStr = string.format("[%d HP]", hpVal)
    end

    local textContent = string.format("[%s]\n%s\n[%d studs]", nameStr, hpStr, math.floor(dist))
    local textColor = isLocked and Color3.fromRGB(255, 75, 75) or Color3.fromRGB(255, 230, 80)

    if not bb or not bb.Parent or not label then
        local attachPart = model:FindFirstChild("Head") or GetTargetPart(model)
        if not attachPart then return end

        bb = Instance.new("BillboardGui")
        bb.Name = "CombatHighlightInfoBB"
        bb.Adornee = attachPart
        bb.Size = UDim2.new(0, 150, 0, 48)
        bb.StudsOffset = Vector3.new(0, 2.6, 0)
        bb.AlwaysOnTop = true
        bb.ResetOnSpawn = false
        bb.MaxDistance = 1500

        label = Instance.new("TextLabel")
        label.Name = "InfoLabel"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = textColor
        label.TextStrokeTransparency = 0.25
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 10
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.Text = textContent
        label.Parent = bb

        pcall(function() bb.Parent = model end)
        HighlightInfoBillboards[model] = bb
    else
        label.Text = textContent
        label.TextColor3 = textColor
    end
end

local function UpdateVisualHighlights()
    if not Config.HighlightAllEnabled then
        if next(UnlockedHighlights) ~= nil or next(HighlightInfoBillboards) ~= nil then
            ClearUnlockedHighlights()
        end
        return
    end

    local myChar = LocalPlayer.Character
    if not myChar then
        ClearUnlockedHighlights()
        return
    end
    local myRoot = GetTargetPart(myChar)
    if not myRoot then
        ClearUnlockedHighlights()
        return
    end

    local myPos = myRoot.Position
    local candidates = {}
    local checked = {}

    local function EvaluateModel(model)
        if not model or not model:IsA("Model") or model == myChar or checked[model] then return end
        checked[model] = true

        if not IsValidEnemy(model) then return end

        local isPlayer, playerObj = IsPlayerCharacter(model)
        if isPlayer and Config.TeamCheck and IsSameTeam(playerObj) then return end

        local allowed = false
        if Config.HighlightTargetType == "All" then
            allowed = true
        elseif Config.HighlightTargetType == "NPC" and not isPlayer then
            allowed = true
        elseif Config.HighlightTargetType == "Player" and isPlayer then
            allowed = true
        end

        if not allowed then return end

        local root = GetTargetPart(model)
        if not root then return end

        local targetPos = root.Position
        local diffX = math.abs(targetPos.X - myPos.X)
        local diffY = math.abs(targetPos.Y - myPos.Y)
        local diffZ = math.abs(targetPos.Z - myPos.Z)

        if diffX <= Config.HighlightRadiusX and diffY <= Config.HighlightRadiusY and diffZ <= Config.HighlightRadiusZ then
            local dist = (targetPos - myPos).Magnitude
            local charName = isPlayer and (playerObj.DisplayName ~= "" and playerObj.DisplayName or playerObj.Name) or model.Name
            table.insert(candidates, {
                Model = model,
                Distance = dist,
                Name = charName,
                Humanoid = model:FindFirstChildOfClass("Humanoid")
            })
        end
    end

    -- 1. Scan Players
    if Config.HighlightTargetType == "All" or Config.HighlightTargetType == "Player" then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                EvaluateModel(p.Character)
            end
        end
    end

    -- 2. Scan NPCs di Workspace (Top-level & Folder)
    if Config.HighlightTargetType == "All" or Config.HighlightTargetType == "NPC" then
        for _, child in ipairs(workspace:GetChildren()) do
            if child:IsA("Model") then
                EvaluateModel(child)
            elseif child:IsA("Folder") or child:IsA("Model") then
                local lowerName = string.lower(child.Name)
                if string.find(lowerName, "npc") or string.find(lowerName, "enemi") 
                   or string.find(lowerName, "mob") or string.find(lowerName, "bot") 
                   or string.find(lowerName, "monster") or string.find(lowerName, "zombie") 
                   or string.find(lowerName, "entity") or string.find(lowerName, "dummy")
                   or string.find(lowerName, "creature") or string.find(lowerName, "spawn") then
                    for _, sub in ipairs(child:GetChildren()) do
                        if sub:IsA("Model") then
                            EvaluateModel(sub)
                        end
                    end
                end
            end
        end
    end

    -- Sortir dari yang terdekat
    table.sort(candidates, function(a, b)
        return a.Distance < b.Distance
    end)

    local seen = {}
    local MAX_HIGHLIGHTS = 28
    local count = 0

    for _, entry in ipairs(candidates) do
        if count >= MAX_HIGHLIGHTS then break end
        local model = entry.Model
        seen[model] = true
        count = count + 1

        local isLocked = (model == CurrentTargetChar and AutoLockEnabled)

        -- Tampilkan info teks [nickname] [health] [... studs]
        UpdateOrCreateInfoBB(model, entry.Name, entry.Humanoid, entry.Distance, isLocked)

        -- Jika target ini sedang di-lock (berwarna merah), jangan beri highlight kuning
        if isLocked then
            if UnlockedHighlights[model] then
                pcall(function() UnlockedHighlights[model]:Destroy() end)
                UnlockedHighlights[model] = nil
            end
        else
            -- Target belum di-lock: Berikan highlight kuning
            local hl = UnlockedHighlights[model]
            if not hl or not hl.Parent then
                hl = Instance.new("Highlight")
                hl.Name = "CombatUnlockedHighlight"
                hl.FillColor = Config.UnlockedHitboxColor
                hl.FillTransparency = Config.UnlockedTransparency
                hl.OutlineColor = Config.UnlockedOutlineColor
                hl.OutlineTransparency = 0.2
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Adornee = model
                pcall(function() hl.Parent = model end)
                UnlockedHighlights[model] = hl
            else
                hl.Adornee = model
                hl.FillColor = Config.UnlockedHitboxColor
                hl.Enabled = true
            end
        end
    end

    -- Hapus highlight yang sudah tidak terlihat / di luar jangkauan
    for char, hl in pairs(UnlockedHighlights) do
        if not seen[char] or not char.Parent then
            pcall(function() hl:Destroy() end)
            UnlockedHighlights[char] = nil
        end
    end

    -- Hapus info billboard yang sudah tidak terlihat / di luar jangkauan
    for char, bb in pairs(HighlightInfoBillboards) do
        if not seen[char] or not char.Parent then
            pcall(function() bb:Destroy() end)
            HighlightInfoBillboards[char] = nil
        end
    end
end

-- ============================================================================
-- LOGIKA TELEPORT & TERBANG KE TARGET (TAB MAIN)
-- ============================================================================
local SelectedTPModel = nil
local SelectedTPName = "Auto"
local SelectedTPMode = "Auto" -- "Auto", "LowestHP", "Specific"
local FlyActive = false
local FlyHeartbeatConn = nil
local FlyNoclipConn = nil

local function StopFly(customStatus, statusColor)
    FlyActive = false
    if FlyHeartbeatConn then
        FlyHeartbeatConn:Disconnect()
        FlyHeartbeatConn = nil
    end
    if FlyNoclipConn then
        FlyNoclipConn:Disconnect()
        FlyNoclipConn = nil
    end
    _G.CombatFlyHeartbeat = nil
    _G.CombatFlyNoclip = nil

    FlyButton.Text = "🚀 TERBANG"
    FlyButton.BackgroundColor3 = Color3.fromRGB(30, 150, 90)
    if customStatus then
        TPStatusLabel.Text = customStatus
        TPStatusLabel.TextColor3 = statusColor or Color3.fromRGB(220, 220, 150)
    end
end

local function ScanTargetsForTP()
    local list = {}
    local myChar = LocalPlayer.Character
    if not myChar then return list end
    local myRoot = GetTargetPart(myChar)
    if not myRoot then return list end

    local myPos = myRoot.Position
    local checked = {}

    local function Evaluate(model)
        if not model or not model:IsA("Model") or model == myChar or checked[model] then return end
        checked[model] = true

        if not IsValidEnemy(model) then return end

        local isPlayer, playerObj = IsPlayerCharacter(model)
        if isPlayer and Config.TeamCheck and IsSameTeam(playerObj) then return end

        local root = GetTargetPart(model)
        if not root then return end

        local dist = (root.Position - myPos).Magnitude
        local displayName = isPlayer and (playerObj.DisplayName ~= "" and playerObj.DisplayName or playerObj.Name) or model.Name
        local hum = model:FindFirstChildOfClass("Humanoid")
        local hp = hum and math.floor(hum.Health) or 0
        local maxHp = hum and math.floor(hum.MaxHealth) or 100

        table.insert(list, {
            Model = model,
            Root = root,
            Distance = dist,
            IsPlayer = isPlayer,
            Nickname = displayName,
            Humanoid = hum,
            Health = hp,
            MaxHealth = maxHp
        })
    end

    -- 1. Scan Player
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            Evaluate(p.Character)
        end
    end

    -- 2. Scan NPC / Bot di Workspace
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") then
            Evaluate(child)
        elseif child:IsA("Folder") or child:IsA("Model") then
            local lowerName = string.lower(child.Name)
            if string.find(lowerName, "npc") or string.find(lowerName, "enemi") 
               or string.find(lowerName, "mob") or string.find(lowerName, "bot") 
               or string.find(lowerName, "monster") or string.find(lowerName, "zombie") 
               or string.find(lowerName, "entity") or string.find(lowerName, "dummy")
               or string.find(lowerName, "creature") or string.find(lowerName, "spawn") then
                for _, sub in ipairs(child:GetChildren()) do
                    if sub:IsA("Model") then
                        Evaluate(sub)
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return a.Distance < b.Distance
    end)

    return list
end

local function PopulateTPDropdown()
    for _, c in ipairs(TPListFrame:GetChildren()) do
        if c:IsA("TextButton") then
            c:Destroy()
        end
    end

    local targets = ScanTargetsForTP()
    local options = {}

    -- Option 1: Terdekat (Auto)
    table.insert(options, {
        Label = "⭐ [Target Terdekat (Auto)]",
        Nickname = "⭐ [Target Terdekat (Auto)]",
        Model = nil,
        Mode = "Auto"
    })

    -- Option 2: HP Terendah (Auto)
    table.insert(options, {
        Label = "🩸 [Target HP Terendah (Auto)]",
        Nickname = "🩸 [Target HP Terendah (Auto)]",
        Model = nil,
        Mode = "LowestHP"
    })

    -- List target spesifik berdasarkan nickname
    for _, t in ipairs(targets) do
        local prefix = t.IsPlayer and "👤 " or "🤖 "
        local labelText = string.format("%s%s (%d HP | %d studs)", prefix, t.Nickname, t.Health, math.floor(t.Distance))
        table.insert(options, {
            Label = labelText,
            Nickname = prefix .. t.Nickname,
            Model = t.Model,
            Mode = "Specific"
        })
    end

    local itemHeight = 24
    TPListFrame.CanvasSize = UDim2.new(0, 0, 0, #options * itemHeight + 4)
    TPListFrame.Size = UDim2.new(1, -28, 0, math.clamp(#options * itemHeight + 6, 32, 130))

    for idx, opt in ipairs(options) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -6, 0, itemHeight - 2)
        btn.Position = UDim2.new(0, 3, 0, (idx - 1) * itemHeight + 2)
        btn.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
        btn.BackgroundTransparency = 1
        btn.Text = "  " .. opt.Label
        
        local isSelected = false
        if opt.Mode == "Auto" and SelectedTPMode == "Auto" then
            isSelected = true
        elseif opt.Mode == "LowestHP" and SelectedTPMode == "LowestHP" then
            isSelected = true
        elseif opt.Mode == "Specific" and opt.Model == SelectedTPModel then
            isSelected = true
        end

        btn.TextColor3 = isSelected and Color3.fromRGB(80, 210, 255) or Color3.fromRGB(200, 205, 215)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 10
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.ZIndex = 36
        btn.Parent = TPListFrame

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 4)
        c.Parent = btn

        btn.MouseButton1Click:Connect(function()
            if opt.Mode == "Auto" then
                SelectedTPModel = nil
                SelectedTPName = "Auto"
                SelectedTPMode = "Auto"
                TPDropdownBtn.Text = "  ⭐ [Target Terdekat (Auto)]"
                TPStatusLabel.Text = "Mode Auto: Target terdekat akan dipilih saat aksi"
                TPStatusLabel.TextColor3 = Color3.fromRGB(80, 210, 255)
            elseif opt.Mode == "LowestHP" then
                SelectedTPModel = nil
                SelectedTPName = "LowestHP"
                SelectedTPMode = "LowestHP"
                TPDropdownBtn.Text = "  🩸 [Target HP Terendah (Auto)]"
                TPStatusLabel.Text = "Mode HP Terendah: Target darah paling sedikit akan dipilih saat aksi"
                TPStatusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
            else
                SelectedTPModel = opt.Model
                SelectedTPName = opt.Nickname
                SelectedTPMode = "Specific"
                TPDropdownBtn.Text = "  " .. opt.Nickname
                TPStatusLabel.Text = "Target dipilih: " .. opt.Nickname
                TPStatusLabel.TextColor3 = Color3.fromRGB(80, 210, 255)
            end

            TPListFrame.Visible = false
            TPArrow.Text = "▼"
            activeDropdownList = nil
            activeDropdownArrow = nil
        end)
    end
end

local function ResolveActiveTarget()
    if SelectedTPMode == "Specific" and SelectedTPModel and SelectedTPModel.Parent and IsValidEnemy(SelectedTPModel) then
        local isPlayer, playerObj = IsPlayerCharacter(SelectedTPModel)
        local dName = isPlayer and (playerObj.DisplayName ~= "" and playerObj.DisplayName or playerObj.Name) or SelectedTPModel.Name
        local hum = SelectedTPModel:FindFirstChildOfClass("Humanoid")
        local hp = hum and math.floor(hum.Health) or 0
        return SelectedTPModel, dName, hp
    end

    local targets = ScanTargetsForTP()
    if #targets == 0 then
        return nil, nil, nil
    end

    if SelectedTPMode == "LowestHP" then
        local lowestTarget = targets[1]
        for _, t in ipairs(targets) do
            if t.Health < lowestTarget.Health then
                lowestTarget = t
            elseif math.abs(t.Health - lowestTarget.Health) < 0.5 and t.Distance < lowestTarget.Distance then
                lowestTarget = t
            end
        end
        return lowestTarget.Model, lowestTarget.Nickname, lowestTarget.Health
    end

    -- Default: Auto Terdekat
    return targets[1].Model, targets[1].Nickname, targets[1].Health
end

local function ExecuteTeleport()
    local targetModel, targetName, targetHp = ResolveActiveTarget()
    if not targetModel then
        TPStatusLabel.Text = "Target tidak ditemukan / tidak ada di sekitar!"
        TPStatusLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
        return
    end

    local myChar = LocalPlayer.Character
    if not myChar then return end
    local myRoot = GetTargetPart(myChar)
    local tRoot = GetTargetPart(targetModel)
    if not myRoot or not tRoot then return end

    -- Reset kecepatan physics agar karakter tidak terlempar
    pcall(function()
        myRoot.AssemblyLinearVelocity = Vector3.zero
        myRoot.AssemblyAngularVelocity = Vector3.zero
    end)

    -- Tempatkan karakter di posisi aman menghadap target
    local destCF = tRoot.CFrame * CFrame.new(0, 2.5, 3.5)
    myRoot.CFrame = destCF

    local hpInfo = targetHp and (" [" .. targetHp .. " HP]") or ""
    TPStatusLabel.Text = "Teleport berhasil ke: " .. targetName .. hpInfo
    TPStatusLabel.TextColor3 = Color3.fromRGB(50, 225, 120)
end

local function ToggleFly()
    if FlyActive then
        StopFly("Penerbangan dibatalkan oleh pengguna", Color3.fromRGB(220, 220, 150))
        return
    end

    local targetModel, targetName, targetHp = ResolveActiveTarget()
    if not targetModel then
        TPStatusLabel.Text = "Target tidak ditemukan untuk terbang!"
        TPStatusLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
        return
    end

    FlyActive = true
    FlyButton.Text = "⏹ STOP TERBANG"
    FlyButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
    local hpInfo = targetHp and (" [" .. targetHp .. " HP]") or ""
    TPStatusLabel.Text = "Terbang ke: " .. targetName .. hpInfo .. "..."
    TPStatusLabel.TextColor3 = Color3.fromRGB(80, 210, 255)

    -- Aktifkan Noclip agar karakter tidak nyangkut dinding/bangunan
    FlyNoclipConn = RunService.Stepped:Connect(function()
        local c = LocalPlayer.Character
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then
                    p.CanCollide = false
                end
            end
        end
    end)
    _G.CombatFlyNoclip = FlyNoclipConn

    FlyHeartbeatConn = RunService.Heartbeat:Connect(function(dt)
        local myChar = LocalPlayer.Character
        if not myChar or not myChar.Parent then
            StopFly()
            return
        end
        local myRoot = GetTargetPart(myChar)
        if not myRoot then
            StopFly()
            return
        end

        if not targetModel or not targetModel.Parent or not IsValidEnemy(targetModel) then
            StopFly("Target hilang atau telah mati!", Color3.fromRGB(255, 85, 85))
            return
        end

        local tRoot = GetTargetPart(targetModel)
        if not tRoot then
            StopFly()
            return
        end

        local targetPos = tRoot.Position + Vector3.new(0, 2, 0)
        local diff = targetPos - myRoot.Position
        local dist = diff.Magnitude

        if dist <= 4.5 then
            StopFly("Sampai di target: " .. targetName, Color3.fromRGB(50, 225, 120))
            return
        end

        local step = math.min(dist, Config.FlySpeed * dt)
        local nextPos = myRoot.Position + (diff.Unit * step)

        pcall(function()
            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.AssemblyAngularVelocity = Vector3.zero
            myRoot.CFrame = CFrame.lookAt(nextPos, targetPos)
        end)

        TPStatusLabel.Text = string.format("Terbang ke [%s] (%.0f studs | Speed: %d)", targetName, dist, Config.FlySpeed)
    end)
    _G.CombatFlyHeartbeat = FlyHeartbeatConn
end

-- Event Listeners Tombol Teleport & Terbang di Tab Main
TPScanBtn.MouseButton1Click:Connect(function()
    pcall(function()
        PopulateTPDropdown()
        TPStatusLabel.Text = "Target berhasil di-scan ulang!"
        TPStatusLabel.TextColor3 = Color3.fromRGB(80, 210, 255)
    end)
end)

TPDropdownBtn.MouseButton1Click:Connect(function()
    if TPListFrame.Visible then
        TPListFrame.Visible = false
        TPArrow.Text = "▼"
        if activeDropdownList == TPListFrame then
            activeDropdownList = nil
            activeDropdownArrow = nil
        end
    else
        CloseAllDropdowns()
        PopulateTPDropdown()
        TPListFrame.Visible = true
        TPArrow.Text = "▲"
        activeDropdownList = TPListFrame
        activeDropdownArrow = TPArrow
    end
end)

TPButton.MouseButton1Click:Connect(function()
    pcall(ExecuteTeleport)
end)

FlyButton.MouseButton1Click:Connect(function()
    pcall(ToggleFly)
end)

LocalPlayer.CharacterAdded:Connect(function()
    StopFly()
end)

-- Event Listeners (Tombol UI)
ToggleButton.MouseButton1Click:Connect(function()
    pcall(ToggleAutoLock)
end)

SwitchButton.MouseButton1Click:Connect(function()
    pcall(SwitchTarget)
end)

TrackingToggleButton.MouseButton1Click:Connect(function()
    pcall(ToggleBulletTracking)
end)

AutoShootToggleBtn.MouseButton1Click:Connect(function()
    pcall(ToggleAutoShoot)
end)

-- Keyboard Event
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    pcall(function()
        if input.KeyCode == Config.ToggleKey then
            ToggleAutoLock()
        elseif input.KeyCode == Config.SwitchKey then
            SwitchTarget()
        elseif input.KeyCode == Config.BulletToggleKey then
            ToggleBulletTracking()
        elseif input.KeyCode == Config.AutoShootKey then
            ToggleAutoShoot()
        elseif input.KeyCode == Config.ToggleUIKey then
            if MainFrame.Visible then
                MainFrame.Visible = false
                CollapsedBar.Visible = false
                MiniKotak.Visible = false
            else
                MainFrame.Visible = true
                CollapsedBar.Visible = false
                MiniKotak.Visible = false
            end
        end
    end)
end)

-- Loop Utama RenderStepped
RunService.RenderStepped:Connect(function(dt)
    pcall(function()
        UpdateUI()
        UpdateVisualHighlights()

        -- Update Tampilan Lingkaran FOV (Field of View)
        local shouldShowFOV = (Config.BulletTrackingEnabled or Config.AutoShootEnabled) and Config.BulletShowFOVCircle and Config.BulletUseFOV
        if shouldShowFOV then
            local mousePos = UserInputService:GetMouseLocation()
            local diameter = Config.BulletFOVRadius * 2
            FOVCircle.Size = UDim2.new(0, diameter, 0, diameter)
            FOVCircle.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)

            local shootTarget = Config.AutoShootEnabled and GetAutoShootTarget()
            local tPart, _ = GetBulletTarget()
            if shootTarget then
                FOVStroke.Color = Color3.fromRGB(50, 225, 120) -- Hijau: Siap Tembak
                FOVStroke.Transparency = 0.15
            elseif tPart then
                if Config.AutoShootWallCheck and not IsTargetVisible(tPart) then
                    FOVStroke.Color = Color3.fromRGB(245, 155, 40) -- Oranye: Terhalang Tembok
                    FOVStroke.Transparency = 0.25
                else
                    FOVStroke.Color = Color3.fromRGB(255, 60, 80) -- Merah: Target Terkunci
                    FOVStroke.Transparency = 0.2
                end
            else
                FOVStroke.Color = Config.BulletFOVCircleColor
                FOVStroke.Transparency = 0.4
            end
            FOVCircle.Visible = true
        else
            FOVCircle.Visible = false
        end

        -- Evaluasi Auto Shoot (TriggerBot dengan Wall Check)
        if Config.AutoShootEnabled then
            local shootTarget = GetAutoShootTarget()
            if shootTarget then
                TriggerShoot()
            end
        end

        if not AutoLockEnabled then return end

        local myChar = LocalPlayer.Character
        local myRoot = GetTargetPart(myChar)
        if not myRoot then return end

        -- Evaluasi Pergantian Target
        if Config.TargetSwitchMode == "Dynamic" then
            local bestTarget = FindBestTarget()

            if not CurrentTargetChar or not CurrentTargetPart or not IsValidEnemy(CurrentTargetChar) then
                SetTarget(bestTarget)
            else
                local curDist = (CurrentTargetPart.Position - myRoot.Position).Magnitude
                if curDist > Config.BreakDistance then
                    SetTarget(bestTarget)
                elseif bestTarget and bestTarget.Character ~= CurrentTargetChar then
                    local newDist = (bestTarget.Part.Position - myRoot.Position).Magnitude
                    if newDist < (curDist - Config.SwitchDistanceMargin) then
                        SetTarget(bestTarget)
                    end
                end
            end
        elseif Config.TargetSwitchMode == "LowestHP" then
            local bestTarget = FindBestTarget()

            if not CurrentTargetChar or not CurrentTargetPart or not IsValidEnemy(CurrentTargetChar) then
                SetTarget(bestTarget)
            else
                local curDist = (CurrentTargetPart.Position - myRoot.Position).Magnitude
                if curDist > Config.BreakDistance then
                    SetTarget(bestTarget)
                elseif bestTarget and bestTarget.Character ~= CurrentTargetChar then
                    local curHum = CurrentTargetChar:FindFirstChildOfClass("Humanoid")
                    local curHP = curHum and curHum.Health or math.huge
                    local newHP = bestTarget.Health or math.huge

                    -- Ganti target jika ada musuh dengan HP lebih rendah di dalam radius
                    if newHP < (curHP - 2) then
                        SetTarget(bestTarget)
                    end
                end
            end
        else
            if not CurrentTargetChar or not CurrentTargetPart or not IsValidEnemy(CurrentTargetChar) then
                local bestTarget = FindBestTarget()
                SetTarget(bestTarget)
            else
                local curDist = (CurrentTargetPart.Position - myRoot.Position).Magnitude
                if curDist > Config.BreakDistance then
                    local bestTarget = FindBestTarget()
                    SetTarget(bestTarget)
                end
            end
        end

        if CurrentTargetChar and IsValidEnemy(CurrentTargetChar) then
            CurrentTargetPart = GetTargetPart(CurrentTargetChar)
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

print("[FeathHub] Loaded! UI baru bergaya Pithers Hub siap digunakan.")
