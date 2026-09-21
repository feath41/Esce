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
    TargetSwitchMode = "Dynamic",   -- "Dynamic" = ganti ke yang lebih dekat, "Persistent" = sampai mati
    SwitchDistanceMargin = 3,      -- Margin jarak (studs)
    
    -- Konfigurasi Hitbox Visual
    HitboxColor = Color3.fromRGB(255, 45, 75),
    HitboxTransparency = 0.5,
    HitboxOutlineColor = Color3.fromRGB(255, 255, 255),
    
    ToggleKey = Enum.KeyCode.Q,
    SwitchKey = Enum.KeyCode.Tab,
    ToggleUIKey = Enum.KeyCode.RightShift,

    -- Konfigurasi ESP Billboard
    ESPEnabled = false,
    ESPTargetFilter = "All",       -- "All", "Player", "Bot", "Entity"
    ESPShowName = true,
    ESPShowDistance = true,
    ESPShowHealth = true,
    ESPTextSize = 13,
    ESPPlayerColor = Color3.fromRGB(0, 255, 140),
    ESPNPCColor = Color3.fromRGB(255, 60, 60),
    ESPEntityColor = Color3.fromRGB(255, 170, 0),
    ESPMaxDistance = 1000
}

Config.BreakDistance = Config.MaxLockDistance + 20

-- State Sistem
local AutoLockEnabled = false
local CurrentTargetPart = nil
local CurrentTargetChar = nil
local CurrentTargetIsNPC = false

-- Forward declaration fungsi ESP
local RefreshESP = nil
local ClearAllESP = nil

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
    local oldGui = SafeParent:FindFirstChild("CombatTargetGui")
    if oldGui then oldGui:Destroy() end
    local oldHighlight = game:FindFirstChild("CombatTargetHitboxHighlight", true)
    if oldHighlight then oldHighlight:Destroy() end
    local oldBox = game:FindFirstChild("CombatTargetHitboxBox", true)
    if oldBox then oldBox:Destroy() end
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.Name == "ESP_Billboard" and v:IsA("BillboardGui") then
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
VersionBadge.Text = "v2.4"
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

-- Dragging MainFrame (Mouse & Touch di Delta Mobile)
local isMainDragging = false
local mainDragStart = nil
local mainStartPos = nil

TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isMainDragging = true
        mainDragStart = input.Position
        mainStartPos = MainFrame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                isMainDragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isMainDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - mainDragStart
        MainFrame.Position = UDim2.new(
            mainStartPos.X.Scale,
            mainStartPos.X.Offset + delta.X,
            mainStartPos.Y.Scale,
            mainStartPos.Y.Offset + delta.Y
        )
    end
end)

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
local VisualTab = CreateTabFrame("Visual")
local SettingsTab = CreateTabFrame("Settings")

-- Sistem Tab Switching Navigasi
local NavButtons = {}
local TabList = {
    { Name = "Main", Icon = "🏠" },
    { Name = "Player", Icon = "👤" },
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
    btn.Position = UDim2.new(0, 8, 0, 12 + (idx - 1) * 38)
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

function CloseAllDropdowns()
    if activeDropdownList then
        activeDropdownList.Visible = false
        activeDropdownList = nil
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
-- 1. ISI TAB MAIN (DEVELOPER PROFILE / CREATED BY FEATH)
-- ============================================================================
local ProfileCard = Instance.new("Frame")
ProfileCard.Size = UDim2.new(1, -28, 0, 100)
ProfileCard.Position = UDim2.new(0, 14, 0, 14)
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
AvatarCircle.Size = UDim2.new(0, 54, 0, 54)
AvatarCircle.Position = UDim2.new(0, 16, 0.5, -27)
AvatarCircle.BackgroundColor3 = Color3.fromRGB(28, 35, 52)
AvatarCircle.Image = "rbxassetid://10903333338" -- Default stylish icon avatar
AvatarCircle.BorderSizePixel = 0
AvatarCircle.Parent = ProfileCard

local AvCorner = Instance.new("UICorner")
AvCorner.CornerRadius = UDim.new(1, 0)
AvCorner.Parent = AvatarCircle

local DevName = Instance.new("TextLabel")
DevName.Size = UDim2.new(0, 200, 0, 20)
DevName.Position = UDim2.new(0, 82, 0, 22)
DevName.BackgroundTransparency = 1
DevName.Text = "Created by feath"
DevName.TextColor3 = Color3.fromRGB(255, 255, 255)
DevName.Font = Enum.Font.GothamBold
DevName.TextSize = 14
DevName.TextXAlignment = Enum.TextXAlignment.Left
DevName.Parent = ProfileCard

local DevRole = Instance.new("TextLabel")
DevRole.Size = UDim2.new(0, 200, 0, 16)
DevRole.Position = UDim2.new(0, 82, 0, 44)
DevRole.BackgroundTransparency = 1
DevRole.Text = "Developer • Combat System Suite"
DevRole.TextColor3 = Color3.fromRGB(80, 210, 255)
DevRole.Font = Enum.Font.GothamMedium
DevRole.TextSize = 11
DevRole.TextXAlignment = Enum.TextXAlignment.Left
DevRole.Parent = ProfileCard

local DevBadge = Instance.new("TextLabel")
DevBadge.Size = UDim2.new(0, 75, 0, 18)
DevBadge.Position = UDim2.new(0, 82, 0, 64)
DevBadge.BackgroundColor3 = Color3.fromRGB(30, 42, 68)
DevBadge.Text = "VERIFIED DEV"
DevBadge.TextColor3 = Color3.fromRGB(120, 180, 255)
DevBadge.Font = Enum.Font.GothamBold
DevBadge.TextSize = 9
DevBadge.Parent = ProfileCard

local DevBadgeCorner = Instance.new("UICorner")
DevBadgeCorner.CornerRadius = UDim.new(0, 4)
DevBadgeCorner.Parent = DevBadge

-- Info Tambahan di Tab Main
local HubInfo = Instance.new("TextLabel")
HubInfo.Size = UDim2.new(1, -28, 0, 40)
HubInfo.Position = UDim2.new(0, 14, 0, 126)
HubInfo.BackgroundTransparency = 1
HubInfo.Text = "Selamat datang di Feath Hub. Buka tab 'Player' untuk mengontrol sistem Auto-Lock Combat, pengaturan jarak, dan opsi penargetan."
HubInfo.TextColor3 = Color3.fromRGB(150, 155, 170)
HubInfo.Font = Enum.Font.Gotham
HubInfo.TextSize = 11
HubInfo.TextWrapped = true
HubInfo.TextXAlignment = Enum.TextXAlignment.Left
HubInfo.Parent = MainTab

-- ============================================================================
-- 2. ISI TAB VISUAL (ESP BILLBOARD & TARGET FILTER)
-- ============================================================================
VisualTab.CanvasSize = UDim2.new(0, 0, 0, 260)

local VisualSectionTitle = Instance.new("TextLabel")
VisualSectionTitle.Size = UDim2.new(1, -28, 0, 18)
VisualSectionTitle.Position = UDim2.new(0, 14, 0, 10)
VisualSectionTitle.BackgroundTransparency = 1
VisualSectionTitle.Text = "ESP BILLBOARD SETTINGS"
VisualSectionTitle.TextColor3 = Color3.fromRGB(120, 130, 150)
VisualSectionTitle.Font = Enum.Font.GothamBold
VisualSectionTitle.TextSize = 10
VisualSectionTitle.TextXAlignment = Enum.TextXAlignment.Left
VisualSectionTitle.Parent = VisualTab

-- Dropdown di atas tombol: Pilih Target (Player, Bot, Entity, Semua)
CreateDropdown(VisualTab, "TARGET ESP FILTER:", 32, {
    { Name = "Semua (Player, Bot, Entity)", Value = "All" },
    { Name = "Player Saja", Value = "Player" },
    { Name = "Bot / NPC Saja", Value = "Bot" },
    { Name = "Entity Saja", Value = "Entity" }
}, Config.ESPTargetFilter, 25, function(val)
    Config.ESPTargetFilter = val
    if Config.ESPEnabled and RefreshESP then
        RefreshESP()
    end
end)

-- Tombol Trigger ESP (Di Bawah Dropdown)
local ESPToggleBtn = Instance.new("TextButton")
ESPToggleBtn.Size = UDim2.new(1, -28, 0, 32)
ESPToggleBtn.Position = UDim2.new(0, 14, 0, 86)
ESPToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
ESPToggleBtn.Text = "AKTIFKAN ESP (OFF)"
ESPToggleBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
ESPToggleBtn.Font = Enum.Font.GothamBold
ESPToggleBtn.TextSize = 11
ESPToggleBtn.BorderSizePixel = 0
ESPToggleBtn.ZIndex = 2
ESPToggleBtn.Parent = VisualTab

local ESPToggleCorner = Instance.new("UICorner")
ESPToggleCorner.CornerRadius = UDim.new(0, 6)
ESPToggleCorner.Parent = ESPToggleBtn

local ESPToggleStroke = Instance.new("UIStroke")
ESPToggleStroke.Thickness = 1
ESPToggleStroke.Color = Color3.fromRGB(50, 58, 76)
ESPToggleStroke.Parent = ESPToggleBtn

ESPToggleBtn.MouseButton1Click:Connect(function()
    Config.ESPEnabled = not Config.ESPEnabled
    if Config.ESPEnabled then
        ESPToggleBtn.Text = "MATIKAN ESP (ON)"
        ESPToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
        ESPToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        ESPToggleStroke.Color = Color3.fromRGB(0, 220, 150)
        if RefreshESP then RefreshESP() end
    else
        ESPToggleBtn.Text = "AKTIFKAN ESP (OFF)"
        ESPToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
        ESPToggleBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
        ESPToggleStroke.Color = Color3.fromRGB(50, 58, 76)
        if ClearAllESP then ClearAllESP() end
    end
end)

-- Elemen Tampilan ESP (Health, Jarak, Nama)
local DispTitle = Instance.new("TextLabel")
DispTitle.Size = UDim2.new(1, -28, 0, 16)
DispTitle.Position = UDim2.new(0, 14, 0, 128)
DispTitle.BackgroundTransparency = 1
DispTitle.Text = "ELEMEN TAMPILAN ESP:"
DispTitle.TextColor3 = Color3.fromRGB(120, 130, 150)
DispTitle.Font = Enum.Font.GothamBold
DispTitle.TextSize = 10
DispTitle.TextXAlignment = Enum.TextXAlignment.Left
DispTitle.Parent = VisualTab

local function CreateESPDisplayToggle(yPos, labelText, configKey)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -28, 0, 24)
    btn.Position = UDim2.new(0, 14, 0, yPos)
    btn.BackgroundColor3 = Config[configKey] and Color3.fromRGB(24, 38, 55) or Color3.fromRGB(22, 25, 33)
    btn.Text = "  " .. labelText .. ": " .. (Config[configKey] and "ON" or "OFF")
    btn.TextColor3 = Config[configKey] and Color3.fromRGB(80, 210, 255) or Color3.fromRGB(140, 145, 160)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 10
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.BorderSizePixel = 0
    btn.Parent = VisualTab

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = Config[configKey] and Color3.fromRGB(0, 120, 255) or Color3.fromRGB(40, 45, 60)
    stroke.Parent = btn

    btn.MouseButton1Click:Connect(function()
        Config[configKey] = not Config[configKey]
        btn.Text = "  " .. labelText .. ": " .. (Config[configKey] and "ON" or "OFF")
        btn.BackgroundColor3 = Config[configKey] and Color3.fromRGB(24, 38, 55) or Color3.fromRGB(22, 25, 33)
        btn.TextColor3 = Config[configKey] and Color3.fromRGB(80, 210, 255) or Color3.fromRGB(140, 145, 160)
        stroke.Color = Config[configKey] and Color3.fromRGB(0, 120, 255) or Color3.fromRGB(40, 45, 60)
        if Config.ESPEnabled and RefreshESP then
            RefreshESP()
        end
    end)
    return btn
end

CreateESPDisplayToggle(148, "Health Bar & Status", "ESPShowHealth")
CreateESPDisplayToggle(178, "Jarak / Distance Label", "ESPShowDistance")
CreateESPDisplayToggle(208, "Nama Target & Role", "ESPShowName")

local EmptySettingsLabel = Instance.new("TextLabel")
EmptySettingsLabel.Size = UDim2.new(1, 0, 1, 0)
EmptySettingsLabel.BackgroundTransparency = 1
EmptySettingsLabel.Text = "Pengaturan Umum (Kosong)."
EmptySettingsLabel.TextColor3 = Color3.fromRGB(100, 105, 120)
EmptySettingsLabel.Font = Enum.Font.GothamMedium
EmptySettingsLabel.TextSize = 12
EmptySettingsLabel.Parent = SettingsTab

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
    { Name = "Auto Ganti (Jika Ada Musuh Lebih Dekat)", Value = "Dynamic" },
    { Name = "Menetap (Kunci Sampai Target Mati)", Value = "Persistent" }
}, Config.TargetSwitchMode, 16, function(val)
    Config.TargetSwitchMode = val
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
            StatusVal.Text = "Idle"
            StatusVal.TextColor3 = Color3.fromRGB(160, 165, 180)
            DotIndicator.BackgroundColor3 = Color3.fromRGB(120, 130, 150)

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
            StatusVal.Text = "Locked"
            StatusVal.TextColor3 = Color3.fromRGB(255, 60, 80)
            DotIndicator.BackgroundColor3 = Color3.fromRGB(255, 60, 80)

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
            StatusVal.Text = "Searching"
            StatusVal.TextColor3 = Color3.fromRGB(220, 160, 30)
            DotIndicator.BackgroundColor3 = Color3.fromRGB(220, 160, 30)

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

-- ============================================================================
-- ESP BILLBOARD SYSTEM (DELTA, CODEX, ARCEUS & PC READY)
-- ============================================================================
local ESPObjects = {} -- [Model] = espData

function ClearAllESP()
    for model in pairs(ESPObjects) do
        if ESPObjects[model] then
            pcall(function()
                if ESPObjects[model].Billboard then
                    ESPObjects[model].Billboard:Destroy()
                end
            end)
            ESPObjects[model] = nil
        end
    end
end

local function RemoveESP(model)
    if ESPObjects[model] then
        pcall(function()
            if ESPObjects[model].Billboard then
                ESPObjects[model].Billboard:Destroy()
            end
        end)
        ESPObjects[model] = nil
    end
end

local function CreateESP(model, color, displayName)
    if not model or not model.Parent then return nil end
    if ESPObjects[model] then return ESPObjects[model] end

    local head = model:FindFirstChild("Head") 
        or model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("UpperTorso")
        or model.PrimaryPart

    if not head or not head:IsA("BasePart") then return nil end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Billboard"
    billboard.Adornee = head
    billboard.Size = UDim2.new(0, 200, 0, 60)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = Config.ESPMaxDistance
    pcall(function() billboard.Parent = head end)

    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundTransparency = 1
    container.Parent = billboard

    local box = Instance.new("Frame")
    box.Name = "Box"
    box.AnchorPoint = Vector2.new(0.5, 0.5)
    box.Position = UDim2.new(0.5, 0, 0.5, 0)
    box.Size = UDim2.new(0, 60, 0, 90)
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 2
    box.BorderColor3 = color
    box.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = box

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.AnchorPoint = Vector2.new(0.5, 1)
    nameLabel.Position = UDim2.new(0.5, 0, 0, -4)
    nameLabel.Size = UDim2.new(1, 0, 0, 16)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = displayName
    nameLabel.TextColor3 = color
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.TextScaled = false
    nameLabel.TextSize = Config.ESPTextSize
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Visible = Config.ESPShowName
    nameLabel.Parent = container

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistanceLabel"
    distLabel.AnchorPoint = Vector2.new(0.5, 0)
    distLabel.Position = UDim2.new(0.5, 0, 1, 4)
    distLabel.Size = UDim2.new(1, 0, 0, 14)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = "[0 m]"
    distLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    distLabel.TextStrokeTransparency = 0
    distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    distLabel.TextSize = Config.ESPTextSize - 2
    distLabel.Font = Enum.Font.GothamBold
    distLabel.Visible = Config.ESPShowDistance
    distLabel.Parent = container

    local healthBg = Instance.new("Frame")
    healthBg.Name = "HealthBg"
    healthBg.AnchorPoint = Vector2.new(1, 0.5)
    healthBg.Position = UDim2.new(0, -4, 0.5, 0)
    healthBg.Size = UDim2.new(0, 4, 0.8, 0)
    healthBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    healthBg.BorderSizePixel = 0
    healthBg.Visible = Config.ESPShowHealth
    healthBg.Parent = container

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 2)
    bgCorner.Parent = healthBg

    local healthFill = Instance.new("Frame")
    healthFill.Name = "HealthFill"
    healthFill.AnchorPoint = Vector2.new(0, 1)
    healthFill.Position = UDim2.new(0, 0, 1, 0)
    healthFill.Size = UDim2.new(1, 0, 1, 0)
    healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    healthFill.BorderSizePixel = 0
    healthFill.Parent = healthBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 2)
    fillCorner.Parent = healthFill

    local espData = {
        Billboard = billboard,
        Head = head,
        Model = model,
        Box = box,
        NameLabel = nameLabel,
        DistanceLabel = distLabel,
        HealthBg = healthBg,
        HealthFill = healthFill,
        Color = color
    }

    ESPObjects[model] = espData
    return espData
end

local function UpdateESP(espData)
    local model = espData.Model
    local head = espData.Head

    if not model or not model.Parent or not head or not head.Parent then
        return false
    end

    if espData.Billboard.Adornee ~= head then
        espData.Billboard.Adornee = head
    end

    espData.NameLabel.Visible = Config.ESPShowName

    if Config.ESPShowDistance then
        local distance = (Camera.CFrame.Position - head.Position).Magnitude
        espData.DistanceLabel.Text = string.format("[%d m]", math.floor(distance))
        espData.DistanceLabel.Visible = true
    else
        espData.DistanceLabel.Visible = false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if Config.ESPShowHealth and humanoid and humanoid.MaxHealth > 0 then
        local pct = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
        espData.HealthFill.Size = UDim2.new(1, 0, pct, 0)
        espData.HealthBg.Visible = true

        if pct > 0.5 then
            espData.HealthFill.BackgroundColor3 = Color3.fromRGB(
                math.floor(255 * (1 - pct) * 2), 255, 0)
        else
            espData.HealthFill.BackgroundColor3 = Color3.fromRGB(
                255, math.floor(255 * pct * 2), 0)
        end
    else
        espData.HealthBg.Visible = false
    end

    return true
end

local function SetupPlayerESP(player)
    if player == LocalPlayer then return end
    if not Config.ESPEnabled then return end
    if Config.ESPTargetFilter ~= "All" and Config.ESPTargetFilter ~= "Player" then return end

    local function onCharacter(char)
        if not char then return end
        char:WaitForChild("Humanoid", 5)
        char:WaitForChild("HumanoidRootPart", 5)
        task.wait(0.2)

        RemoveESP(char)
        if Config.ESPEnabled and (Config.ESPTargetFilter == "All" or Config.ESPTargetFilter == "Player") then
            CreateESP(char, Config.ESPPlayerColor, player.DisplayName .. " (@" .. player.Name .. ")")
        end
    end

    if player.Character then
        task.spawn(onCharacter, player.Character)
    end
    player.CharacterAdded:Connect(onCharacter)
end

local function SetupNPCESP(model)
    if not Config.ESPEnabled then return end
    if not model or not model:IsA("Model") then return end
    if not model:FindFirstChildOfClass("Humanoid") then return end
    if IsPlayerCharacter(model) then return end
    if ESPObjects[model] then return end

    local nameLower = string.lower(model.Name)
    local isBot = false
    if nameLower:find("npc") or nameLower:find("dummy")
       or nameLower:find("enemy") or nameLower:find("guard")
       or nameLower:find("bot") or nameLower:find("mob")
       or nameLower:find("monster") then
        isBot = true
    end

    local allowed = false
    local color = Config.ESPNPCColor
    local displayName = "[NPC] " .. model.Name

    if isBot then
        if Config.ESPTargetFilter == "All" or Config.ESPTargetFilter == "Bot" then
            allowed = true
            color = Config.ESPNPCColor
            displayName = "[NPC] " .. model.Name
        end
    else
        if Config.ESPTargetFilter == "All" or Config.ESPTargetFilter == "Entity" then
            allowed = true
            color = Config.ESPEntityColor
            displayName = "[ENTITY] " .. model.Name
        end
    end

    if allowed then
        CreateESP(model, color, displayName)
    end
end

local function ScanAllESP()
    if not Config.ESPEnabled then return end

    if Config.ESPTargetFilter == "All" or Config.ESPTargetFilter == "Player" then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                CreateESP(plr.Character, Config.ESPPlayerColor, plr.DisplayName .. " (@" .. plr.Name .. ")")
            end
        end
    end

    if Config.ESPTargetFilter == "All" or Config.ESPTargetFilter == "Bot" or Config.ESPTargetFilter == "Entity" then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
                if not IsPlayerCharacter(obj) then
                    SetupNPCESP(obj)
                end
            end
        end
    end
end

function RefreshESP()
    ClearAllESP()
    if Config.ESPEnabled then
        ScanAllESP()
    end
end

-- Monitor Objek Baru Workspace & Pemain
workspace.DescendantAdded:Connect(function(obj)
    if not Config.ESPEnabled then return end
    if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
        task.wait(0.4)
        if obj.Parent and obj.Parent.Parent then
            if not IsPlayerCharacter(obj.Parent) then
                SetupNPCESP(obj.Parent)
            end
        end
    end
end)

workspace.DescendantRemoving:Connect(function(obj)
    if obj:IsA("Model") and ESPObjects[obj] then
        RemoveESP(obj)
    end
end)

Players.PlayerAdded:Connect(function(plr)
    if plr ~= LocalPlayer then
        SetupPlayerESP(plr)
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    if plr.Character then
        RemoveESP(plr.Character)
    end
end)

-- Main ESP Loop (0.1 detik)
task.spawn(function()
    while task.wait(0.1) do
        if Config.ESPEnabled then
            for model, espData in pairs(ESPObjects) do
                local ok, err = pcall(UpdateESP, espData)
                if not ok or not espData.Model.Parent then
                    RemoveESP(model)
                end
            end
        end
    end
end)

-- Event Listeners (Tombol UI)
ToggleButton.MouseButton1Click:Connect(function()
    pcall(ToggleAutoLock)
end)

SwitchButton.MouseButton1Click:Connect(function()
    pcall(SwitchTarget)
end)

-- Keyboard Event
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    pcall(function()
        if input.KeyCode == Config.ToggleKey then
            ToggleAutoLock()
        elseif input.KeyCode == Config.SwitchKey then
            SwitchTarget()
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
