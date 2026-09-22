-- CombatSystem.lua
-- Modern Hub Interface (Based on Pithers Hub Design) + Full Combat Auto-Lock Features
-- 100% PURE ROBLOX ENGINE INSTANCES (NO EXECUTOR DRAWING LIBRARY NEEDED)
-- Fully compatible with Delta Mobile (Android), Arceus X, Codex, Wave, & PC

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    pcall(function()
        LocalPlayer = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    end)
    LocalPlayer = Players.LocalPlayer or LocalPlayer
end

local Camera = workspace.CurrentCamera
if not Camera then
    pcall(function()
        Camera = workspace:WaitForChild("Camera", 3) or workspace.CurrentCamera
    end)
    Camera = workspace.CurrentCamera or Camera
end

-- ============================================================================
-- KONFIGURASI SISTEM
-- ============================================================================
local Config = {
    MaxLockDistance = 80,          -- Jarak maksimal cari musuh (studs)
    BreakDistance = 100,           -- Jarak batas lepas target (otomatis MaxLockDistance + 20)
    LockAggressiveness = 50,       -- Keganasan Lock (1 - 100): 1=Smooth, 50=Seimbang, 100=Ganas
    CameraSmoothing = 0.52,        -- Kehalusan gerakan kamera (0.05 halus s/d 1.0 instan)
    AutoFaceCharacter = true,      -- Karakter otomatis menghadap musuh
    CharacterFaceSpeed = 0.54,     -- Kecepatan putar badan karakter (0.1 s/d 1.0)
    
    TargetPartChoice = "Head",     -- "Head" atau "Torso"
    LockMode = "FOV",              -- "FOV" (Hanya dalam Lingkaran FOV), "Distance" (Jarak 3D), "Cursor" (2D)
    TargetType = "All",            -- "All" (Player + Bot), "NPC" (Hanya Bot), "Player" (Hanya Player)
    TeamCheck = false,             -- false = semua pemain (aman di game FFA/PVP), true = hanya beda tim
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
    AutoShootKey = Enum.KeyCode.G,

    -- Konfigurasi External Mobile Controls (Joystick & Tombol Loncat di Layar Pemain)
    ExternalControlsEnabled = true, -- Selalu tampil di layar pemain (HUD) untuk mobile
    ExternalControlsSize = 120,     -- Ukuran diameter joystick (pixel)
    ExternalJumpSize = 72          -- Ukuran diameter tombol jump (pixel)
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
-- PENGATURAN PARENT GUI AMAN (KOMPATIBILITAS DELTA, ARCEUS X, CODEX, & PC)
-- ============================================================================
local function GetSafeGuiParent(guiInstance)
    local targetParent = nil
    -- 1. Prioritas Utama untuk Delta Mobile, Arceus X, & Codex: gethui()
    pcall(function()
        if typeof(gethui) == "function" then
            targetParent = gethui()
        end
    end)
    -- 2. Proteksi syn.protect_gui jika ada
    if guiInstance then
        pcall(function()
            if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
                syn.protect_gui(guiInstance)
            end
        end)
    end
    -- 3. Fallback ke CoreGui
    if not targetParent then
        pcall(function()
            if CoreGui then
                targetParent = CoreGui
            end
        end)
    end
    -- 4. Fallback aman ke PlayerGui jika CoreGui dibatasi
    if not targetParent then
        pcall(function()
            targetParent = LocalPlayer:WaitForChild("PlayerGui", 3) or (LocalPlayer and LocalPlayer.PlayerGui)
        end)
    end
    return targetParent or CoreGui
end

local SafeParent = GetSafeGuiParent()

-- Bersihkan instance lama jika re-execute
pcall(function()
    if _G.CombatFlyHeartbeat then _G.CombatFlyHeartbeat:Disconnect() _G.CombatFlyHeartbeat = nil end
    if _G.CombatFlyNoclip then _G.CombatFlyNoclip:Disconnect() _G.CombatFlyNoclip = nil end
    if _G.CombatBulletProjectileConn then _G.CombatBulletProjectileConn:Disconnect() _G.CombatBulletProjectileConn = nil end
    if _G.CombatExternalControlsConn then _G.CombatExternalControlsConn:Disconnect() _G.CombatExternalControlsConn = nil end
    local oldGui = SafeParent:FindFirstChild("CombatTargetGui")
    if oldGui then oldGui:Destroy() end
    local oldControlsGui = SafeParent:FindFirstChild("CombatExternalControlsGui")
    if oldControlsGui then oldControlsGui:Destroy() end
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
-- PEMBUATAN UI MODERN (PITHERS HUB DESIGN) - SCOPED REGISTERS
-- ============================================================================
local ScreenGui
local FOVCircle, FOVStroke
local CollapsedBar, MiniKotak, MainFrame, Sidebar
local DotIndicator, StatusVal
local activeDropdownList, activeDropdownArrow
local TPScanBtn, TPDropdownBtn, TPArrow, TPListFrame
local TPButton, FlyButton, TPStatusLabel
local TrackingStatusLabel, TrackingTargetLabel, TrackingToggleButton
local AutoShootToggleBtn, AutoShootToggleStroke
local ExternalControlsToggleBtn, ExternalControlsToggleStroke
local TargetNameLabel, DistanceLabel, HealthBarFill
local ToggleButton, SwitchButton
local MaxDistance = 150
local MainTab, PlayerTab, TrackingTab, VisualTab, SettingsTab
local CloseAllDropdowns

-- ============================================================================
-- EXTERNAL MOBILE CONTROLS (JOYSTICK & TOMBOL LONCAT MANDIRI)
-- Dibuat langsung di layar pemain (HUD), BUKAN di dalam frame UI menu script.
-- Selalu ada di layar pemain agar saat Auto Shoot aktif atau tombol bawaan Roblox
-- terhapus/tersembunyi karena simulasi input mouse, pemain tetap leluasa bergerak & loncat.
-- Seluruh proses & event dibungkus pcall.
-- ============================================================================
local ExternalControlsGui, ExternalControlsFrame
local JoystickBase, JoystickKnob, JumpButton, JumpStroke
local thumbstickVector = Vector2.zero
local activeJoystickTouch = nil
local isJumping = false

pcall(function()
    ExternalControlsGui = Instance.new("ScreenGui")
    ExternalControlsGui.Name = "CombatExternalControlsGui"
    ExternalControlsGui.ResetOnSpawn = false
    ExternalControlsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ExternalControlsGui.IgnoreGuiInset = true
    ExternalControlsGui.DisplayOrder = 999999
    pcall(function() ExternalControlsGui.Parent = SafeParent end)

    ExternalControlsFrame = Instance.new("Frame")
    ExternalControlsFrame.Name = "ExternalControlsFrame"
    ExternalControlsFrame.Size = UDim2.new(1, 0, 1, 0)
    ExternalControlsFrame.Position = UDim2.new(0, 0, 0, 0)
    ExternalControlsFrame.BackgroundTransparency = 1
    ExternalControlsFrame.BorderSizePixel = 0
    ExternalControlsFrame.Parent = ExternalControlsGui

    -- 1. JOYSTICK ANALOG EXTERNAL (Bawah-Kiri Layar Pemain)
    local joySize = Config.ExternalControlsSize or 120
    JoystickBase = Instance.new("Frame")
    JoystickBase.Name = "ExternalJoystickBase"
    JoystickBase.Size = UDim2.new(0, joySize, 0, joySize)
    JoystickBase.Position = UDim2.new(0, 40, 1, -joySize - 40)
    JoystickBase.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
    JoystickBase.BackgroundTransparency = 0.45
    JoystickBase.BorderSizePixel = 0
    JoystickBase.Active = true
    JoystickBase.Parent = ExternalControlsFrame

    local baseCorner = Instance.new("UICorner")
    baseCorner.CornerRadius = UDim.new(1, 0)
    baseCorner.Parent = JoystickBase

    local baseStroke = Instance.new("UIStroke")
    baseStroke.Thickness = 2
    baseStroke.Color = Color3.fromRGB(0, 180, 255)
    baseStroke.Transparency = 0.35
    baseStroke.Parent = JoystickBase

    local dirCenter = Instance.new("Frame")
    dirCenter.Size = UDim2.new(0, 8, 0, 8)
    dirCenter.AnchorPoint = Vector2.new(0.5, 0.5)
    dirCenter.Position = UDim2.new(0.5, 0, 0.5, 0)
    dirCenter.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
    dirCenter.BackgroundTransparency = 0.5
    dirCenter.BorderSizePixel = 0
    dirCenter.Parent = JoystickBase

    local dirCorner = Instance.new("UICorner")
    dirCorner.CornerRadius = UDim.new(1, 0)
    dirCorner.Parent = dirCenter

    local knobSize = math.floor(joySize * 0.44)
    JoystickKnob = Instance.new("Frame")
    JoystickKnob.Name = "ExternalJoystickKnob"
    JoystickKnob.Size = UDim2.new(0, knobSize, 0, knobSize)
    JoystickKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    JoystickKnob.Position = UDim2.new(0.5, 0, 0.5, 0)
    JoystickKnob.BackgroundColor3 = Color3.fromRGB(0, 160, 255)
    JoystickKnob.BackgroundTransparency = 0.2
    JoystickKnob.BorderSizePixel = 0
    JoystickKnob.Parent = JoystickBase

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = JoystickKnob

    local knobStroke = Instance.new("UIStroke")
    knobStroke.Thickness = 2
    knobStroke.Color = Color3.fromRGB(255, 255, 255)
    knobStroke.Transparency = 0.2
    knobStroke.Parent = JoystickKnob

    -- 2. TOMBOL LONCAT EXTERNAL (Bawah-Kanan Layar Pemain)
    local jumpSize = Config.ExternalJumpSize or 72
    JumpButton = Instance.new("ImageButton")
    JumpButton.Name = "ExternalJumpButton"
    JumpButton.Size = UDim2.new(0, jumpSize, 0, jumpSize)
    JumpButton.Position = UDim2.new(1, -jumpSize - 40, 1, -jumpSize - 55)
    JumpButton.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
    JumpButton.BackgroundTransparency = 0.35
    JumpButton.BorderSizePixel = 0
    JumpButton.AutoButtonColor = false
    JumpButton.Active = true
    JumpButton.Parent = ExternalControlsFrame

    local jumpCorner = Instance.new("UICorner")
    jumpCorner.CornerRadius = UDim.new(1, 0)
    jumpCorner.Parent = JumpButton

    JumpStroke = Instance.new("UIStroke")
    JumpStroke.Thickness = 2
    JumpStroke.Color = Color3.fromRGB(0, 180, 255)
    JumpStroke.Transparency = 0.3
    JumpStroke.Parent = JumpButton

    local jumpText = Instance.new("TextLabel")
    jumpText.Size = UDim2.new(1, 0, 1, 0)
    jumpText.BackgroundTransparency = 1
    jumpText.Text = "JUMP\n▲"
    jumpText.TextColor3 = Color3.fromRGB(255, 255, 255)
    jumpText.Font = Enum.Font.GothamBold
    jumpText.TextSize = 13
    jumpText.Parent = JumpButton

    ExternalControlsGui.Enabled = (Config.ExternalControlsEnabled ~= false)

    -- Event & Input Handling Touch Joystick (Multi-Touch Compatible)
    local function UpdateKnobPosition(inputPos)
        pcall(function()
            if not JoystickBase or not JoystickKnob then return end
            local basePos = JoystickBase.AbsolutePosition
            local baseSize = JoystickBase.AbsoluteSize
            local center = basePos + (baseSize / 2)
            local maxRadius = math.max((baseSize.X / 2) - 4, 1)

            local delta = inputPos - center
            local dist = delta.Magnitude
            if dist > maxRadius then
                delta = delta.Unit * maxRadius
                dist = maxRadius
            end

            JoystickKnob.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)

            if maxRadius > 0 then
                thumbstickVector = Vector2.new(delta.X / maxRadius, delta.Y / maxRadius)
            else
                thumbstickVector = Vector2.zero
            end
        end)
    end

    local function ResetKnobPosition()
        pcall(function()
            activeJoystickTouch = nil
            thumbstickVector = Vector2.zero
            if JoystickKnob then
                local resetTween = TweenService:Create(
                    JoystickKnob,
                    TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { Position = UDim2.new(0.5, 0, 0.5, 0) }
                )
                resetTween:Play()
            end

            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:Move(Vector3.zero, false)
            end
        end)
    end

    if JoystickBase then
        JoystickBase.InputBegan:Connect(function(input)
            pcall(function()
                if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                    if not activeJoystickTouch then
                        activeJoystickTouch = input
                        UpdateKnobPosition(Vector2.new(input.Position.X, input.Position.Y))
                    end
                end
            end)
        end)
    end

    UserInputService.InputChanged:Connect(function(input)
        pcall(function()
            if activeJoystickTouch and input == activeJoystickTouch then
                UpdateKnobPosition(Vector2.new(input.Position.X, input.Position.Y))
            end
        end)
    end)

    UserInputService.InputEnded:Connect(function(input)
        pcall(function()
            if activeJoystickTouch and input == activeJoystickTouch then
                ResetKnobPosition()
            end
        end)
    end)

    if UserInputService.TouchEnded then
        UserInputService.TouchEnded:Connect(function(touch)
            pcall(function()
                if activeJoystickTouch and touch == activeJoystickTouch then
                    ResetKnobPosition()
                end
            end)
        end)
    end

    -- Event & Input Handling Tombol Loncat (Jump Button)
    if JumpButton then
        local function PerformJump()
            pcall(function()
                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    hum.Jump = true
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
        end

        JumpButton.InputBegan:Connect(function(input)
            pcall(function()
                if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                    isJumping = true
                    JumpButton.BackgroundColor3 = Color3.fromRGB(0, 160, 240)
                    if JumpStroke then
                        JumpStroke.Color = Color3.fromRGB(255, 255, 255)
                        JumpStroke.Transparency = 0.1
                    end
                    PerformJump()
                end
            end)
        end)

        JumpButton.InputEnded:Connect(function(input)
            pcall(function()
                if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                    isJumping = false
                    JumpButton.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
                    if JumpStroke then
                        JumpStroke.Color = Color3.fromRGB(0, 180, 255)
                        JumpStroke.Transparency = 0.3
                    end
                end
            end)
        end)
    end
end)

-- Loop Pergerakan Karakter dari Joystick & Jump External (RenderStepped)
pcall(function()
    _G.CombatExternalControlsConn = RunService.RenderStepped:Connect(function()
        pcall(function()
            if not Config.ExternalControlsEnabled then return end

            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then return end

            -- 1. Gerakan dari External Joystick (Kamera-Relatif di bidang XZ)
            if thumbstickVector and thumbstickVector.Magnitude > 0.05 then
                local cam = workspace.CurrentCamera
                if cam then
                    local look = cam.CFrame.LookVector
                    local right = cam.CFrame.RightVector
                    local flatLook = Vector3.new(look.X, 0, look.Z)
                    local flatRight = Vector3.new(right.X, 0, right.Z)
                    if flatLook.Magnitude > 0.001 then flatLook = flatLook.Unit else flatLook = Vector3.new(0, 0, -1) end
                    if flatRight.Magnitude > 0.001 then flatRight = flatRight.Unit else flatRight = Vector3.new(1, 0, 0) end

                    local moveDir = (flatRight * thumbstickVector.X) + (flatLook * (-thumbstickVector.Y))
                    hum:Move(moveDir, false)
                end
            end

            -- 2. Tahan tombol loncat jika pemain masih menekan Jump
            if isJumping then
                hum.Jump = true
            end
        end)
    end)
end)

ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CombatTargetGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
pcall(function() ScreenGui.Parent = SafeParent end)

-- Lingkaran FOV (Field of View) untuk Bullet Tracking (Terkunci di Tengah Layar / Crosshair)
FOVCircle = Instance.new("Frame")
FOVCircle.Name = "CombatBulletFOVCircle"
FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
FOVCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
FOVCircle.BackgroundTransparency = 1
FOVCircle.Visible = false
FOVCircle.ZIndex = 40
FOVCircle.Parent = ScreenGui

local FOVCorner = Instance.new("UICorner")
FOVCorner.CornerRadius = UDim.new(1, 0)
FOVCorner.Parent = FOVCircle

FOVStroke = Instance.new("UIStroke")
FOVStroke.Thickness = 1.5
FOVStroke.Color = Config.BulletFOVCircleColor
FOVStroke.Transparency = 0.35
FOVStroke.Parent = FOVCircle

-- ============================================================================
-- THEME CONFIGURATION (PITHERS / MODERN HUB PALETTE)
-- ============================================================================
local THEME = {
    Background    = Color3.fromRGB(15, 17, 21),   -- #0F1115
    Panel         = Color3.fromRGB(24, 27, 33),   -- #181B21
    PanelHover    = Color3.fromRGB(30, 34, 42),
    Sidebar       = Color3.fromRGB(19, 21, 27),
    Accent        = Color3.fromRGB(124, 92, 255), -- #7C5CFF
    AccentMuted   = Color3.fromRGB(80, 60, 160),
    Stroke        = Color3.fromRGB(40, 45, 55),
    StrokeAccent  = Color3.fromRGB(124, 92, 255),
    TextPrimary   = Color3.fromRGB(245, 245, 250),
    TextSecondary = Color3.fromRGB(148, 163, 184),
    Success       = Color3.fromRGB(34, 197, 94),
    CornerRadius  = UDim.new(0, 8),
    TweenInfoFast = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    TweenInfoNorm = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
}

local function createCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = radius or THEME.CornerRadius
    corner.Parent = parent
    return corner
end

local function createStroke(parent, color, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or THEME.Stroke
    stroke.Thickness = thickness or 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = parent
    return stroke
end

-- ============================================================================
-- TOAST NOTIFICATION CONTAINER (BOTTOM RIGHT)
-- ============================================================================
local ToastContainer = Instance.new("Frame")
ToastContainer.Name = "ToastContainer"
ToastContainer.Size = UDim2.new(0, 260, 1, -40)
ToastContainer.Position = UDim2.new(1, -280, 0, 20)
ToastContainer.BackgroundTransparency = 1
ToastContainer.ZIndex = 100
ToastContainer.Parent = ScreenGui

local ToastListLayout = Instance.new("UIListLayout")
ToastListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ToastListLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
ToastListLayout.Padding = UDim.new(0, 8)
ToastListLayout.Parent = ToastContainer

local function ShowToast(message, duration)
    duration = duration or 2.5
    local toast = Instance.new("Frame")
    toast.Name = "Toast"
    toast.Size = UDim2.new(1, 0, 0, 42)
    toast.BackgroundColor3 = THEME.Panel
    toast.BackgroundTransparency = 1
    toast.Parent = ToastContainer
    createCorner(toast, UDim.new(0, 6))

    local stroke = createStroke(toast, THEME.Accent, 1)
    stroke.Transparency = 1

    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 24, 1, 0)
    icon.Position = UDim2.new(0, 8, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Font = Enum.Font.GothamBold
    icon.Text = "✓"
    icon.TextColor3 = THEME.Success
    icon.TextSize = 14
    icon.TextTransparency = 1
    icon.Parent = toast

    local msgLabel = Instance.new("TextLabel")
    msgLabel.Size = UDim2.new(1, -38, 1, 0)
    msgLabel.Position = UDim2.new(0, 32, 0, 0)
    msgLabel.BackgroundTransparency = 1
    msgLabel.Font = Enum.Font.Gotham
    msgLabel.Text = message
    msgLabel.TextColor3 = THEME.TextPrimary
    msgLabel.TextSize = 11
    msgLabel.TextXAlignment = Enum.TextXAlignment.Left
    msgLabel.TextTruncate = Enum.TextTruncate.AtEnd
    msgLabel.TextTransparency = 1
    msgLabel.Parent = toast

    TweenService:Create(toast, THEME.TweenInfoFast, {BackgroundTransparency = 0}):Play()
    TweenService:Create(stroke, THEME.TweenInfoFast, {Transparency = 0}):Play()
    TweenService:Create(icon, THEME.TweenInfoFast, {TextTransparency = 0}):Play()
    TweenService:Create(msgLabel, THEME.TweenInfoFast, {TextTransparency = 0}):Play()

    task.delay(duration, function()
        pcall(function()
            TweenService:Create(toast, THEME.TweenInfoFast, {BackgroundTransparency = 1}):Play()
            TweenService:Create(stroke, THEME.TweenInfoFast, {Transparency = 1}):Play()
            TweenService:Create(icon, THEME.TweenInfoFast, {TextTransparency = 1}):Play()
            local fadeMsg = TweenService:Create(msgLabel, THEME.TweenInfoFast, {TextTransparency = 1})
            fadeMsg:Play()
            fadeMsg.Completed:Connect(function()
                toast:Destroy()
            end)
        end)
    end)
end

-- ============================================================================
-- COLLAPSED BAR & MINI KOTAK WIDGET
-- ============================================================================
local isCollapsed = false

CollapsedBar = Instance.new("Frame")
CollapsedBar.Name = "CollapsedBar"
CollapsedBar.Size = UDim2.new(0, 420, 0, 36)
CollapsedBar.Position = UDim2.new(0.5, -210, 0.05, 0)
CollapsedBar.BackgroundColor3 = THEME.Background
CollapsedBar.BorderSizePixel = 0
CollapsedBar.Visible = false
CollapsedBar.ZIndex = 50
CollapsedBar.Parent = ScreenGui
createCorner(CollapsedBar, THEME.CornerRadius)
createStroke(CollapsedBar, THEME.Stroke, 1)

local ColIcon = Instance.new("TextLabel")
ColIcon.Size = UDim2.new(0, 24, 0, 24)
ColIcon.Position = UDim2.new(0, 8, 0.5, -12)
ColIcon.BackgroundColor3 = THEME.Accent
ColIcon.Text = "⚡"
ColIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
ColIcon.Font = Enum.Font.GothamBold
ColIcon.TextSize = 13
ColIcon.ZIndex = 51
ColIcon.Parent = CollapsedBar
createCorner(ColIcon, UDim.new(0, 6))

local ColTitle = Instance.new("TextLabel")
ColTitle.Size = UDim2.new(0, 85, 1, 0)
ColTitle.Position = UDim2.new(0, 38, 0, 0)
ColTitle.BackgroundTransparency = 1
ColTitle.Text = "FEATH HUB"
ColTitle.TextColor3 = THEME.TextPrimary
ColTitle.Font = Enum.Font.GothamBold
ColTitle.TextSize = 11
ColTitle.TextXAlignment = Enum.TextXAlignment.Left
ColTitle.ZIndex = 51
ColTitle.Parent = CollapsedBar

local ColBadge = Instance.new("TextLabel")
ColBadge.Size = UDim2.new(0, 58, 0, 18)
ColBadge.Position = UDim2.new(0, 126, 0.5, -9)
ColBadge.BackgroundColor3 = THEME.Panel
ColBadge.Text = "Collapsed"
ColBadge.TextColor3 = THEME.Accent
ColBadge.Font = Enum.Font.GothamMedium
ColBadge.TextSize = 9
ColBadge.ZIndex = 51
ColBadge.Parent = CollapsedBar
createCorner(ColBadge, UDim.new(0, 4))

local ExpandBtn = Instance.new("TextButton")
ExpandBtn.Size = UDim2.new(0, 140, 0, 24)
ExpandBtn.Position = UDim2.new(0, 190, 0.5, -12)
ExpandBtn.BackgroundColor3 = THEME.Panel
ExpandBtn.Text = "📖 Click to Expand"
ExpandBtn.TextColor3 = THEME.TextSecondary
ExpandBtn.Font = Enum.Font.GothamMedium
ExpandBtn.TextSize = 9
ExpandBtn.ZIndex = 51
ExpandBtn.Parent = CollapsedBar
createCorner(ExpandBtn, UDim.new(0, 6))

local ToKotakBtn = Instance.new("TextButton")
ToKotakBtn.Size = UDim2.new(0, 50, 0, 24)
ToKotakBtn.Position = UDim2.new(0, 335, 0.5, -12)
ToKotakBtn.BackgroundColor3 = THEME.Panel
ToKotakBtn.Text = "⛶ Kotak"
ToKotakBtn.TextColor3 = THEME.Accent
ToKotakBtn.Font = Enum.Font.GothamBold
ToKotakBtn.TextSize = 9
ToKotakBtn.ZIndex = 51
ToKotakBtn.Parent = CollapsedBar
createCorner(ToKotakBtn, UDim.new(0, 6))

local CloseColBtn = Instance.new("TextButton")
CloseColBtn.Size = UDim2.new(0, 24, 0, 24)
CloseColBtn.Position = UDim2.new(1, -28, 0.5, -12)
CloseColBtn.BackgroundTransparency = 1
CloseColBtn.Text = "✕"
CloseColBtn.TextColor3 = THEME.TextSecondary
CloseColBtn.Font = Enum.Font.GothamBold
CloseColBtn.TextSize = 12
CloseColBtn.ZIndex = 51
CloseColBtn.Parent = CollapsedBar

-- Mini Kotak Widget
MiniKotak = Instance.new("Frame")
MiniKotak.Name = "MiniKotak"
MiniKotak.Size = UDim2.new(0, 44, 0, 44)
MiniKotak.Position = UDim2.new(0, 20, 0.5, -22)
MiniKotak.BackgroundColor3 = THEME.Background
MiniKotak.BorderSizePixel = 0
MiniKotak.Visible = false
MiniKotak.Active = true
MiniKotak.ZIndex = 60
MiniKotak.Parent = ScreenGui
createCorner(MiniKotak, UDim.new(0, 10))
createStroke(MiniKotak, THEME.Accent, 1.5)

local MiniKotakBtn = Instance.new("TextButton")
MiniKotakBtn.Size = UDim2.new(1, 0, 1, 0)
MiniKotakBtn.BackgroundTransparency = 1
MiniKotakBtn.Text = "⚡"
MiniKotakBtn.TextColor3 = THEME.Accent
MiniKotakBtn.Font = Enum.Font.GothamBold
MiniKotakBtn.TextSize = 20
MiniKotakBtn.ZIndex = 61
MiniKotakBtn.Parent = MiniKotak

local isKotakDragging = false
local isKotakMoved = false
local kotakDragStart = nil
local kotakStartPos = nil

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
    MiniKotak.Visible = true
end)

MiniKotakBtn.MouseButton1Click:Connect(function()
    if not isKotakMoved then
        MiniKotak.Visible = false
        MainFrame.Visible = true
    end
end)

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

-- ============================================================================
-- MAIN WINDOW FRAME (520x360) & TITLEBAR
-- ============================================================================
MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 360)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -180)
MainFrame.BackgroundColor3 = THEME.Background
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
createCorner(MainFrame, THEME.CornerRadius)
createStroke(MainFrame, THEME.Stroke, 1)

local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = THEME.Sidebar
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame
createCorner(TitleBar, THEME.CornerRadius)

local TitleBarSeam = Instance.new("Frame")
TitleBarSeam.Name = "Seam"
TitleBarSeam.Size = UDim2.new(1, 0, 0, 6)
TitleBarSeam.Position = UDim2.new(0, 0, 1, -6)
TitleBarSeam.BackgroundColor3 = THEME.Sidebar
TitleBarSeam.BorderSizePixel = 0
TitleBarSeam.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "TitleLabel"
TitleLabel.Size = UDim2.new(0, 240, 1, 0)
TitleLabel.Position = UDim2.new(0, 12, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "⚡ FEATH HUB  <font color=\"#7C5CFF\">v2.6</font>"
TitleLabel.RichText = true
TitleLabel.TextColor3 = THEME.TextPrimary
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TitleBar

local TagBadge = Instance.new("TextLabel")
TagBadge.Size = UDim2.new(0, 62, 0, 18)
TagBadge.Position = UDim2.new(0, 175, 0.5, -9)
TagBadge.BackgroundColor3 = THEME.Panel
TagBadge.Text = "Universal"
TagBadge.TextColor3 = THEME.Accent
TagBadge.Font = Enum.Font.GothamMedium
TagBadge.TextSize = 9
TagBadge.Parent = TitleBar
createCorner(TagBadge, UDim.new(0, 4))

local ControlsContainer = Instance.new("Frame")
ControlsContainer.Name = "Controls"
ControlsContainer.Size = UDim2.new(0, 70, 1, 0)
ControlsContainer.Position = UDim2.new(1, -75, 0, 0)
ControlsContainer.BackgroundTransparency = 1
ControlsContainer.Parent = TitleBar

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Name = "MinimizeBtn"
MinimizeBtn.Size = UDim2.new(0, 26, 0, 26)
MinimizeBtn.Position = UDim2.new(0, 5, 0.5, -13)
MinimizeBtn.BackgroundColor3 = THEME.Panel
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.Text = "—"
MinimizeBtn.TextColor3 = THEME.TextSecondary
MinimizeBtn.TextSize = 12
MinimizeBtn.AutoButtonColor = false
MinimizeBtn.Parent = ControlsContainer
createCorner(MinimizeBtn, UDim.new(0, 6))

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(0, 38, 0.5, -13)
CloseBtn.BackgroundColor3 = THEME.Panel
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = THEME.TextSecondary
CloseBtn.TextSize = 12
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = ControlsContainer
createCorner(CloseBtn, UDim.new(0, 6))

for _, btn in ipairs({MinimizeBtn, CloseBtn}) do
    btn.MouseEnter:Connect(function()
        local targetColor = (btn == CloseBtn) and Color3.fromRGB(239, 68, 68) or THEME.PanelHover
        local textColor = (btn == CloseBtn) and Color3.fromRGB(255, 255, 255) or THEME.TextPrimary
        TweenService:Create(btn, THEME.TweenInfoFast, {BackgroundColor3 = targetColor, TextColor3 = textColor}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, THEME.TweenInfoFast, {BackgroundColor3 = THEME.Panel, TextColor3 = THEME.TextSecondary}):Play()
    end)
end

local isDragging = false
local dragInput, dragStart, startPos

TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = true
        dragStart = input.Position
        startPos = MainFrame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                isDragging = false
            end
        end)
    end
end)

TitleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and isDragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

MinimizeBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    MiniKotak.Visible = false
    CollapsedBar.Visible = true
end)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    CollapsedBar.Visible = false
    MiniKotak.Visible = true
    ShowToast("Menu diminimalkan ke mode kotak ⚡", 2)
end)

-- ============================================================================
-- SIDEBAR & CONTENT LAYOUT
-- ============================================================================
local BodyContainer = Instance.new("Frame")
BodyContainer.Name = "Body"
BodyContainer.Size = UDim2.new(1, 0, 1, -36)
BodyContainer.Position = UDim2.new(0, 0, 0, 36)
BodyContainer.BackgroundTransparency = 1
BodyContainer.Parent = MainFrame

Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 74, 1, 0)
Sidebar.BackgroundColor3 = THEME.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = BodyContainer
createStroke(Sidebar, THEME.Stroke, 1)

local SidebarLayout = Instance.new("UIListLayout")
SidebarLayout.Padding = UDim.new(0, 6)
SidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
SidebarLayout.VerticalAlignment = Enum.VerticalAlignment.Top
SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
SidebarLayout.Parent = Sidebar

local SidebarPadding = Instance.new("UIPadding")
SidebarPadding.PaddingTop = UDim.new(0, 8)
SidebarPadding.PaddingBottom = UDim.new(0, 8)
SidebarPadding.Parent = Sidebar

local StatusCard = Instance.new("Frame")
StatusCard.Name = "StatusCard"
StatusCard.Size = UDim2.new(0, 64, 0, 34)
StatusCard.Position = UDim2.new(0.5, -32, 1, -64)
StatusCard.BackgroundColor3 = THEME.Panel
StatusCard.Parent = Sidebar
createCorner(StatusCard, UDim.new(0, 6))
createStroke(StatusCard, THEME.Stroke, 1)

DotIndicator = Instance.new("Frame")
DotIndicator.Size = UDim2.new(0, 6, 0, 6)
DotIndicator.Position = UDim2.new(0, 8, 0.5, -3)
DotIndicator.BackgroundColor3 = THEME.Success
DotIndicator.BorderSizePixel = 0
DotIndicator.Parent = StatusCard
createCorner(DotIndicator, UDim.new(1, 0))

local StatusTitle = Instance.new("TextLabel")
StatusTitle.Size = UDim2.new(1, -20, 0, 12)
StatusTitle.Position = UDim2.new(0, 18, 0, 4)
StatusTitle.BackgroundTransparency = 1
StatusTitle.Text = "STATUS"
StatusTitle.TextColor3 = THEME.TextSecondary
StatusTitle.Font = Enum.Font.GothamMedium
StatusTitle.TextSize = 8
StatusTitle.TextXAlignment = Enum.TextXAlignment.Left
StatusTitle.Parent = StatusCard

StatusVal = Instance.new("TextLabel")
StatusVal.Size = UDim2.new(1, -20, 0, 12)
StatusVal.Position = UDim2.new(0, 18, 0, 16)
StatusVal.BackgroundTransparency = 1
StatusVal.Text = "Injected"
StatusVal.TextColor3 = THEME.Success
StatusVal.Font = Enum.Font.GothamBold
StatusVal.TextSize = 9
StatusVal.TextXAlignment = Enum.TextXAlignment.Left
StatusVal.Parent = StatusCard

local FpsPingLabel = Instance.new("TextLabel")
FpsPingLabel.Name = "FpsPing"
FpsPingLabel.Size = UDim2.new(1, 0, 0, 16)
FpsPingLabel.Position = UDim2.new(0, 0, 1, -22)
FpsPingLabel.BackgroundTransparency = 1
FpsPingLabel.Text = "60 FPS • 25ms"
FpsPingLabel.TextColor3 = THEME.TextSecondary
FpsPingLabel.Font = Enum.Font.Gotham
FpsPingLabel.TextSize = 8
FpsPingLabel.Parent = Sidebar

task.spawn(function()
    local lastTime = tick()
    local frameCount = 0
    RunService.RenderStepped:Connect(function()
        frameCount = frameCount + 1
        local now = tick()
        if now - lastTime >= 1 then
            local fps = math.floor(frameCount / (now - lastTime))
            frameCount = 0
            lastTime = now
            local ping = 25
            pcall(function()
                local stats = game:GetService("Stats")
                ping = math.floor(stats.Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            FpsPingLabel.Text = string.format("%d FPS • %dms", fps, ping)
        end
    end)
end)

local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, -74, 1, 0)
ContentArea.Position = UDim2.new(0, 74, 0, 0)
ContentArea.BackgroundTransparency = 1
ContentArea.ClipsDescendants = true
ContentArea.Parent = BodyContainer

local ContentPadding = Instance.new("UIPadding")
ContentPadding.PaddingTop = UDim.new(0, 10)
ContentPadding.PaddingBottom = UDim.new(0, 10)
ContentPadding.PaddingLeft = UDim.new(0, 10)
ContentPadding.PaddingRight = UDim.new(0, 10)
ContentPadding.Parent = ContentArea

local Tabs = {}
local TabButtons = {}

local function CreateTabFrame(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "Tab"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = THEME.Accent
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = ContentArea

    local pageLayout = Instance.new("UIListLayout")
    pageLayout.Padding = UDim.new(0, 8)
    pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pageLayout.Parent = page

    Tabs[name] = page
    return page
end

MainTab = CreateTabFrame("Main")
PlayerTab = CreateTabFrame("Player")
TrackingTab = CreateTabFrame("Tracking")
VisualTab = CreateTabFrame("Visual")
SettingsTab = CreateTabFrame("Settings")

local TabList = {
    { Name = "Main", Icon = "🏠" },
    { Name = "Player", Icon = "👤" },
    { Name = "Tracking", Icon = "🎯" },
    { Name = "Visual", Icon = "👁" },
    { Name = "Settings", Icon = "⚙" }
}

local function SwitchTab(tabName)
    if CloseAllDropdowns then CloseAllDropdowns() end
    for name, page in pairs(Tabs) do
        page.Visible = (name == tabName)
    end
    for name, btn in pairs(TabButtons) do
        local isActive = (name == tabName)
        local targetColor = isActive and THEME.Accent or THEME.Panel
        local targetText = isActive and THEME.TextPrimary or THEME.TextSecondary
        TweenService:Create(btn, THEME.TweenInfoFast, {
            BackgroundColor3 = targetColor,
            TextColor3 = targetText
        }):Play()
    end
end

for order, item in ipairs(TabList) do
    local btn = Instance.new("TextButton")
    btn.Name = item.Name .. "Btn"
    btn.Size = UDim2.new(0, 60, 0, 42)
    btn.LayoutOrder = order
    btn.BackgroundColor3 = THEME.Panel
    btn.Font = Enum.Font.GothamMedium
    btn.Text = item.Icon .. "\n" .. item.Name
    btn.TextColor3 = THEME.TextSecondary
    btn.TextSize = 10
    btn.AutoButtonColor = false
    btn.Parent = Sidebar
    createCorner(btn, UDim.new(0, 6))

    btn.MouseButton1Click:Connect(function()
        SwitchTab(item.Name)
    end)
    TabButtons[item.Name] = btn
end

-- ============================================================================
-- REUSABLE COMPONENT BUILDERS (ACCORDION DRAWER, TOGGLE, SLIDER, DROPDOWN, ETC.)
-- ============================================================================
CloseAllDropdowns = function()
    if activeDropdownList then
        activeDropdownList.Visible = false
        if activeDropdownArrow then activeDropdownArrow.Text = "▼" end
        activeDropdownList = nil
        activeDropdownArrow = nil
    end
end

local function CreateDrawer(parent, icon, title, badgeText, optionsCountText, defaultOpen)
    local isOpen = defaultOpen or false

    local container = Instance.new("Frame")
    container.Name = "Drawer_" .. title
    container.Size = UDim2.new(1, 0, 0, 38)
    container.BackgroundColor3 = THEME.Panel
    container.BorderSizePixel = 0
    container.ClipsDescendants = true
    container.Parent = parent
    createCorner(container, UDim.new(0, 8))
    local stroke = createStroke(container, THEME.Stroke, 1)

    local header = Instance.new("TextButton")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 38)
    header.BackgroundTransparency = 1
    header.Text = ""
    header.AutoButtonColor = false
    header.Parent = container

    local iconBadge = Instance.new("TextLabel")
    iconBadge.Size = UDim2.new(0, 24, 0, 24)
    iconBadge.Position = UDim2.new(0, 8, 0.5, -12)
    iconBadge.BackgroundColor3 = THEME.Sidebar
    iconBadge.Text = icon or "⚡"
    iconBadge.TextColor3 = THEME.Accent
    iconBadge.Font = Enum.Font.GothamBold
    iconBadge.TextSize = 12
    iconBadge.Parent = header
    createCorner(iconBadge, UDim.new(0, 5))

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(0.5, 0, 1, 0)
    titleLabel.Position = UDim2.new(0, 38, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = THEME.TextPrimary
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 11
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = header

    local tagBadge = Instance.new("TextLabel")
    tagBadge.Size = UDim2.new(0, 52, 0, 18)
    tagBadge.Position = UDim2.new(0.55, 0, 0.5, -9)
    tagBadge.BackgroundColor3 = THEME.Sidebar
    tagBadge.Text = badgeText or "v2.6"
    tagBadge.TextColor3 = THEME.Accent
    tagBadge.Font = Enum.Font.GothamMedium
    tagBadge.TextSize = 9
    tagBadge.Parent = header
    createCorner(tagBadge, UDim.new(0, 4))

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(0, 75, 0, 18)
    statusLabel.Position = UDim2.new(1, -100, 0.5, -9)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = optionsCountText or "• Ready"
    statusLabel.TextColor3 = THEME.TextSecondary
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 9
    statusLabel.TextXAlignment = Enum.TextXAlignment.Right
    statusLabel.Parent = header

    local chevron = Instance.new("TextLabel")
    chevron.Size = UDim2.new(0, 20, 1, 0)
    chevron.Position = UDim2.new(1, -22, 0, 0)
    chevron.BackgroundTransparency = 1
    chevron.Text = isOpen and "▲" or "▼"
    chevron.TextColor3 = THEME.TextSecondary
    chevron.Font = Enum.Font.GothamBold
    chevron.TextSize = 10
    chevron.Parent = header

    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Size = UDim2.new(1, -12, 0, 0)
    body.Position = UDim2.new(0, 6, 0, 40)
    body.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
    body.BorderSizePixel = 0
    body.Visible = isOpen
    body.Parent = container
    createCorner(body, UDim.new(0, 6))
    createStroke(body, THEME.Stroke, 1)

    local bodyLayout = Instance.new("UIListLayout")
    bodyLayout.Padding = UDim.new(0, 6)
    bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
    bodyLayout.Parent = body

    local bodyPadding = Instance.new("UIPadding")
    bodyPadding.PaddingTop = UDim.new(0, 6)
    bodyPadding.PaddingBottom = UDim.new(0, 8)
    bodyPadding.PaddingLeft = UDim.new(0, 8)
    bodyPadding.PaddingRight = UDim.new(0, 8)
    bodyPadding.Parent = body

    local subBanner = Instance.new("Frame")
    subBanner.Size = UDim2.new(1, 0, 0, 18)
    subBanner.BackgroundTransparency = 1
    subBanner.Parent = body

    local subLeft = Instance.new("TextLabel")
    subLeft.Size = UDim2.new(0.6, 0, 1, 0)
    subLeft.BackgroundTransparency = 1
    subLeft.Text = "⚙ UI KONTROL FITUR TAMBAHAN"
    subLeft.TextColor3 = THEME.TextSecondary
    subLeft.Font = Enum.Font.GothamBold
    subLeft.TextSize = 8
    subLeft.TextXAlignment = Enum.TextXAlignment.Left
    subLeft.Parent = subBanner

    local subRight = Instance.new("TextLabel")
    subRight.Size = UDim2.new(0.4, 0, 1, 0)
    subRight.Position = UDim2.new(0.6, 0, 0, 0)
    subRight.BackgroundTransparency = 1
    subRight.Text = "INTERACTIVE DRAWER"
    subRight.TextColor3 = THEME.Accent
    subRight.Font = Enum.Font.GothamBold
    subRight.TextSize = 8
    subRight.TextXAlignment = Enum.TextXAlignment.Right
    subRight.Parent = subBanner

    local function updateHeight()
        if isOpen then
            body.Visible = true
            local h = bodyLayout.AbsoluteContentSize.Y + 16
            body.Size = UDim2.new(1, -12, 0, h)
            container.Size = UDim2.new(1, 0, 0, 46 + h)
            chevron.Text = "▲"
            stroke.Color = THEME.Accent
        else
            body.Visible = false
            container.Size = UDim2.new(1, 0, 0, 38)
            chevron.Text = "▼"
            stroke.Color = THEME.Stroke
        end
    end

    bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        if isOpen then
            updateHeight()
        end
    end)

    header.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        updateHeight()
    end)

    if isOpen then
        task.defer(updateHeight)
    end

    return body, updateHeight, statusLabel
end

local function CreateToggle(parent, labelText, descText, defaultState, callback)
    local state = defaultState or false

    local frame = Instance.new("Frame")
    frame.Name = "Toggle_" .. labelText
    frame.Size = UDim2.new(1, 0, 0, 40)
    frame.BackgroundColor3 = THEME.Panel
    frame.Parent = parent
    createCorner(frame, UDim.new(0, 6))
    createStroke(frame, THEME.Stroke, 1)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -55, 0, 18)
    label.Position = UDim2.new(0, 10, 0, 4)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.Text = labelText
    label.TextColor3 = THEME.TextPrimary
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local desc = Instance.new("TextLabel")
    desc.Size = UDim2.new(1, -55, 0, 14)
    desc.Position = UDim2.new(0, 10, 0, 22)
    desc.BackgroundTransparency = 1
    desc.Font = Enum.Font.Gotham
    desc.Text = descText or ""
    desc.TextColor3 = THEME.TextSecondary
    desc.TextSize = 9
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.Parent = frame

    local switchTrack = Instance.new("TextButton")
    switchTrack.Name = "SwitchTrack"
    switchTrack.Size = UDim2.new(0, 38, 0, 20)
    switchTrack.Position = UDim2.new(1, -46, 0.5, -10)
    switchTrack.BackgroundColor3 = state and THEME.Accent or THEME.Background
    switchTrack.Text = ""
    switchTrack.AutoButtonColor = false
    switchTrack.Parent = frame
    createCorner(switchTrack, UDim.new(1, 0))

    local switchThumb = Instance.new("Frame")
    switchThumb.Name = "Thumb"
    switchThumb.Size = UDim2.new(0, 14, 0, 14)
    switchThumb.Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    switchThumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    switchThumb.Parent = switchTrack
    createCorner(switchThumb, UDim.new(1, 0))

    local function updateVisual(animate)
        local targetColor = state and THEME.Accent or THEME.Background
        local targetThumbPos = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        if animate then
            TweenService:Create(switchTrack, THEME.TweenInfoFast, {BackgroundColor3 = targetColor}):Play()
            TweenService:Create(switchThumb, THEME.TweenInfoFast, {Position = targetThumbPos}):Play()
        else
            switchTrack.BackgroundColor3 = targetColor
            switchThumb.Position = targetThumbPos
        end
    end

    switchTrack.MouseButton1Click:Connect(function()
        state = not state
        updateVisual(true)
        if callback then
            callback(state)
        end
    end)

    return frame
end

local function CreateSlider(parent, labelText, minVal, maxVal, defaultVal, unit, callback)
    minVal = minVal or 0
    maxVal = maxVal or 100
    unit = unit or ""
    local currentVal = math.clamp(defaultVal or minVal, minVal, maxVal)

    local frame = Instance.new("Frame")
    frame.Name = "Slider_" .. labelText
    frame.Size = UDim2.new(1, 0, 0, 46)
    frame.BackgroundColor3 = THEME.Panel
    frame.Parent = parent
    createCorner(frame, UDim.new(0, 6))
    createStroke(frame, THEME.Stroke, 1)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, 0, 0, 18)
    label.Position = UDim2.new(0, 10, 0, 5)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.Text = labelText
    label.TextColor3 = THEME.TextPrimary
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(0.35, 0, 0, 18)
    valueLabel.Position = UDim2.new(0.65, -10, 0, 5)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.Text = tostring(currentVal) .. unit
    valueLabel.TextColor3 = THEME.Accent
    valueLabel.TextSize = 11
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = frame

    local track = Instance.new("TextButton")
    track.Name = "Track"
    track.Size = UDim2.new(1, -20, 0, 6)
    track.Position = UDim2.new(0, 10, 0, 28)
    track.BackgroundColor3 = THEME.Background
    track.Text = ""
    track.AutoButtonColor = false
    track.Parent = frame
    createCorner(track, UDim.new(1, 0))

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    local initialRatio = (currentVal - minVal) / math.max(maxVal - minVal, 1)
    fill.Size = UDim2.new(initialRatio, 0, 1, 0)
    fill.BackgroundColor3 = THEME.Accent
    fill.BorderSizePixel = 0
    fill.Parent = track
    createCorner(fill, UDim.new(1, 0))

    local thumb = Instance.new("Frame")
    thumb.Name = "Thumb"
    thumb.Size = UDim2.new(0, 14, 0, 14)
    thumb.Position = UDim2.new(initialRatio, -7, 0.5, -7)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    thumb.Parent = track
    createCorner(thumb, UDim.new(1, 0))

    local isDraggingSlider = false

    local function updateValue(inputX)
        local trackAbsPos = track.AbsolutePosition.X
        local trackAbsSize = track.AbsoluteSize.X
        if trackAbsSize <= 0 then return end
        local ratio = math.clamp((inputX - trackAbsPos) / trackAbsSize, 0, 1)
        currentVal = math.floor(minVal + (maxVal - minVal) * ratio)
        valueLabel.Text = tostring(currentVal) .. unit
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        thumb.Position = UDim2.new(ratio, -7, 0.5, -7)
        if callback then
            callback(currentVal)
        end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDraggingSlider = true
            updateValue(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDraggingSlider = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if isDraggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateValue(input.Position.X)
        end
    end)

    return frame
end

local function CreateDropdown(parent, labelText, options, defaultVal, callback)
    options = options or {}
    local selectedName = defaultVal or (options[1] and (options[1].Name or options[1])) or "Pilih..."
    local isOpen = false

    local frame = Instance.new("Frame")
    frame.Name = "Dropdown_" .. labelText
    frame.Size = UDim2.new(1, 0, 0, 36)
    frame.BackgroundColor3 = THEME.Panel
    frame.ClipsDescendants = false
    frame.Parent = parent
    createCorner(frame, UDim.new(0, 6))
    createStroke(frame, THEME.Stroke, 1)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.48, 0, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.Text = labelText
    label.TextColor3 = THEME.TextPrimary
    label.TextSize = 10
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local selectorBtn = Instance.new("TextButton")
    selectorBtn.Size = UDim2.new(0.5, -8, 0, 24)
    selectorBtn.Position = UDim2.new(0.5, 0, 0.5, -12)
    selectorBtn.BackgroundColor3 = THEME.Background
    selectorBtn.Font = Enum.Font.Gotham
    selectorBtn.Text = tostring(selectedName) .. " ▾"
    selectorBtn.TextColor3 = THEME.Accent
    selectorBtn.TextSize = 9
    selectorBtn.AutoButtonColor = false
    selectorBtn.ZIndex = 25
    selectorBtn.Parent = frame
    createCorner(selectorBtn, UDim.new(0, 4))
    createStroke(selectorBtn, THEME.Stroke, 1)

    local optionList = Instance.new("Frame")
    optionList.Name = "OptionList"
    optionList.Size = UDim2.new(1, 0, 0, #options * 24 + 4)
    optionList.Position = UDim2.new(0, 0, 1, 2)
    optionList.BackgroundColor3 = THEME.Sidebar
    optionList.Visible = false
    optionList.ZIndex = 30
    optionList.Parent = selectorBtn
    createCorner(optionList, UDim.new(0, 6))
    createStroke(optionList, THEME.StrokeAccent, 1)

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = optionList

    local listPadding = Instance.new("UIPadding")
    listPadding.PaddingTop = UDim.new(0, 2)
    listPadding.PaddingBottom = UDim.new(0, 2)
    listPadding.PaddingLeft = UDim.new(0, 4)
    listPadding.PaddingRight = UDim.new(0, 4)
    listPadding.Parent = optionList

    for _, opt in ipairs(options) do
        local optName = type(opt) == "table" and opt.Name or tostring(opt)
        local optVal = type(opt) == "table" and (opt.Value ~= nil and opt.Value or opt.Name) or opt

        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, 0, 0, 22)
        optBtn.BackgroundColor3 = THEME.Sidebar
        optBtn.Font = Enum.Font.Gotham
        optBtn.Text = optName
        optBtn.TextColor3 = THEME.TextSecondary
        optBtn.TextSize = 9
        optBtn.ZIndex = 31
        optBtn.AutoButtonColor = false
        optBtn.Parent = optionList
        createCorner(optBtn, UDim.new(0, 4))

        optBtn.MouseEnter:Connect(function()
            optBtn.BackgroundColor3 = THEME.Accent
            optBtn.TextColor3 = THEME.TextPrimary
        end)
        optBtn.MouseLeave:Connect(function()
            optBtn.BackgroundColor3 = THEME.Sidebar
            optBtn.TextColor3 = THEME.TextSecondary
        end)

        optBtn.MouseButton1Click:Connect(function()
            selectedName = optName
            selectorBtn.Text = optName .. " ▾"
            optionList.Visible = false
            isOpen = false
            if callback then
                callback(optVal)
            end
        end)
    end

    selectorBtn.MouseButton1Click:Connect(function()
        if isOpen then
            optionList.Visible = false
            isOpen = false
            if activeDropdownList == optionList then
                activeDropdownList = nil
            end
        else
            CloseAllDropdowns()
            optionList.Visible = true
            isOpen = true
            activeDropdownList = optionList
        end
    end)

    return frame
end

local function CreateKeybind(parent, labelText, defaultKey, callback)
    local currentKey = defaultKey or Enum.KeyCode.RightShift
    local listening = false

    local frame = Instance.new("Frame")
    frame.Name = "Keybind_" .. labelText
    frame.Size = UDim2.new(1, 0, 0, 36)
    frame.BackgroundColor3 = THEME.Panel
    frame.Parent = parent
    createCorner(frame, UDim.new(0, 6))
    createStroke(frame, THEME.Stroke, 1)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, 0, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.Text = labelText
    label.TextColor3 = THEME.TextPrimary
    label.TextSize = 10
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local keyButton = Instance.new("TextButton")
    keyButton.Size = UDim2.new(0, 85, 0, 24)
    keyButton.Position = UDim2.new(1, -95, 0.5, -12)
    keyButton.BackgroundColor3 = THEME.Background
    keyButton.Font = Enum.Font.Code
    keyButton.Text = "[ " .. currentKey.Name .. " ]"
    keyButton.TextColor3 = THEME.Accent
    keyButton.TextSize = 10
    keyButton.AutoButtonColor = false
    keyButton.Parent = frame
    createCorner(keyButton, UDim.new(0, 4))
    local keyStroke = createStroke(keyButton, THEME.Stroke, 1)

    keyButton.MouseButton1Click:Connect(function()
        if listening then return end
        listening = true
        keyButton.Text = "[ ... ]"
        keyStroke.Color = THEME.Accent

        local connection
        connection = UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                currentKey = input.KeyCode
                keyButton.Text = "[ " .. currentKey.Name .. " ]"
                keyStroke.Color = THEME.Stroke
                listening = false
                connection:Disconnect()
                if callback then
                    callback(currentKey)
                end
                ShowToast("Pintasan diset ke [" .. currentKey.Name .. "]", 2)
            end
        end)
    end)

    return frame
end

local function CreateActionButton(parent, text, icon, bgColor, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = bgColor or THEME.Accent
    btn.Text = (icon and (icon .. "  ") or "") .. text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.AutoButtonColor = false
    btn.Parent = parent
    createCorner(btn, UDim.new(0, 6))

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, THEME.TweenInfoFast, {BackgroundTransparency = 0.2}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, THEME.TweenInfoFast, {BackgroundTransparency = 0}):Play()
    end)

    if callback then
        btn.MouseButton1Click:Connect(callback)
    end

    return btn
end

-- ============================================================================
-- MODULAR TAB BUILDERS
-- ============================================================================
local function BuildMainTab()
    local ProfileCard = Instance.new("Frame")
    ProfileCard.Size = UDim2.new(1, 0, 0, 56)
    ProfileCard.BackgroundColor3 = THEME.Panel
    ProfileCard.Parent = MainTab
    createCorner(ProfileCard, UDim.new(0, 8))
    createStroke(ProfileCard, THEME.Stroke, 1)

    local AvatarCircle = Instance.new("ImageLabel")
    AvatarCircle.Size = UDim2.new(0, 40, 0, 40)
    AvatarCircle.Position = UDim2.new(0, 10, 0.5, -20)
    AvatarCircle.BackgroundColor3 = THEME.Sidebar
    AvatarCircle.Image = "rbxassetid://10903333338"
    AvatarCircle.Parent = ProfileCard
    createCorner(AvatarCircle, UDim.new(1, 0))

    local DevName = Instance.new("TextLabel")
    DevName.Size = UDim2.new(0, 200, 0, 16)
    DevName.Position = UDim2.new(0, 58, 0, 10)
    DevName.BackgroundTransparency = 1
    DevName.Text = "Created by feath"
    DevName.TextColor3 = THEME.TextPrimary
    DevName.Font = Enum.Font.GothamBold
    DevName.TextSize = 12
    DevName.TextXAlignment = Enum.TextXAlignment.Left
    DevName.Parent = ProfileCard

    local DevRole = Instance.new("TextLabel")
    DevRole.Size = UDim2.new(0, 200, 0, 14)
    DevRole.Position = UDim2.new(0, 58, 0, 28)
    DevRole.BackgroundTransparency = 1
    DevRole.Text = "Developer • Combat System Suite"
    DevRole.TextColor3 = THEME.Accent
    DevRole.Font = Enum.Font.GothamMedium
    DevRole.TextSize = 9
    DevRole.TextXAlignment = Enum.TextXAlignment.Left
    DevRole.Parent = ProfileCard

    local DevBadge = Instance.new("TextLabel")
    DevBadge.Size = UDim2.new(0, 75, 0, 16)
    DevBadge.Position = UDim2.new(1, -85, 0.5, -8)
    DevBadge.BackgroundColor3 = THEME.Sidebar
    DevBadge.Text = "VERIFIED DEV"
    DevBadge.TextColor3 = THEME.Accent
    DevBadge.Font = Enum.Font.GothamBold
    DevBadge.TextSize = 8
    DevBadge.Parent = ProfileCard
    createCorner(DevBadge, UDim.new(0, 4))

    local tpBody, _, _ = CreateDrawer(MainTab, "⚡", "[Teleport Instan ke Target]", "v2.6", "3 Modes", true)

    local tpTargetRow = Instance.new("Frame")
    tpTargetRow.Size = UDim2.new(1, 0, 0, 28)
    tpTargetRow.BackgroundTransparency = 1
    tpTargetRow.Parent = tpBody

    TPDropdownBtn = Instance.new("TextButton")
    TPDropdownBtn.Size = UDim2.new(0.72, 0, 1, 0)
    TPDropdownBtn.BackgroundColor3 = THEME.Background
    TPDropdownBtn.Font = Enum.Font.Gotham
    TPDropdownBtn.TextSize = 9
    TPDropdownBtn.TextColor3 = THEME.TextPrimary
    TPDropdownBtn.TextXAlignment = Enum.TextXAlignment.Left
    TPDropdownBtn.Text = "  ⭐ [Target Terdekat (Auto)]"
    TPDropdownBtn.ZIndex = 20
    TPDropdownBtn.Parent = tpTargetRow
    createCorner(TPDropdownBtn, UDim.new(0, 4))
    createStroke(TPDropdownBtn, THEME.Stroke, 1)

    TPArrow = Instance.new("TextLabel")
    TPArrow.Size = UDim2.new(0, 20, 1, 0)
    TPArrow.Position = UDim2.new(1, -22, 0, 0)
    TPArrow.BackgroundTransparency = 1
    TPArrow.Text = "▼"
    TPArrow.TextColor3 = THEME.TextSecondary
    TPArrow.Font = Enum.Font.GothamBold
    TPArrow.TextSize = 9
    TPArrow.ZIndex = 20
    TPArrow.Parent = TPDropdownBtn

    TPScanBtn = Instance.new("TextButton")
    TPScanBtn.Size = UDim2.new(0.26, 0, 1, 0)
    TPScanBtn.Position = UDim2.new(0.74, 0, 0, 0)
    TPScanBtn.BackgroundColor3 = THEME.Panel
    TPScanBtn.Text = "🔄 Scan"
    TPScanBtn.TextColor3 = THEME.Accent
    TPScanBtn.Font = Enum.Font.GothamBold
    TPScanBtn.TextSize = 9
    TPScanBtn.Parent = tpTargetRow
    createCorner(TPScanBtn, UDim.new(0, 4))
    createStroke(TPScanBtn, THEME.Stroke, 1)

    TPListFrame = Instance.new("ScrollingFrame")
    TPListFrame.Name = "TPDropdownList"
    TPListFrame.Size = UDim2.new(1, 0, 0, 100)
    TPListFrame.BackgroundColor3 = THEME.Sidebar
    TPListFrame.BorderSizePixel = 0
    TPListFrame.ScrollBarThickness = 2
    TPListFrame.ScrollBarImageColor3 = THEME.Accent
    TPListFrame.CanvasSize = UDim2.new(0, 0, 0, 120)
    TPListFrame.Visible = false
    TPListFrame.ZIndex = 35
    TPListFrame.Parent = tpBody
    createCorner(TPListFrame, UDim.new(0, 6))
    createStroke(TPListFrame, THEME.StrokeAccent, 1)

    TPButton = CreateActionButton(tpBody, "TELEPORT INSTAN KE TARGET", "⚡", Color3.fromRGB(0, 140, 255), nil)

    TPStatusLabel = Instance.new("TextLabel")
    TPStatusLabel.Size = UDim2.new(1, 0, 0, 18)
    TPStatusLabel.BackgroundTransparency = 1
    TPStatusLabel.Text = "Pilih target lalu tekan tombol aksi di atas"
    TPStatusLabel.TextColor3 = THEME.TextSecondary
    TPStatusLabel.Font = Enum.Font.Gotham
    TPStatusLabel.TextSize = 9
    TPStatusLabel.Parent = tpBody

    local flyBody, _, _ = CreateDrawer(MainTab, "🚀", "[Terbang ke Target / Free Fly]", "v2.6", "2 Options", false)

    CreateSlider(flyBody, "Kecepatan Terbang:", 20, 350, Config.FlySpeed, " studs/s", function(val)
        Config.FlySpeed = val
    end)

    FlyButton = CreateActionButton(flyBody, "AKTIFKAN TERBANG (FLY: ON / OFF)", "🚀", Color3.fromRGB(120, 60, 240), nil)

    local statsBody, _, _ = CreateDrawer(flyBody, "📊", "[Informasi Target & Jarak]", "Live", "Stats", false)
    local statsInfo = Instance.new("TextLabel")
    statsInfo.Size = UDim2.new(1, 0, 0, 24)
    statsInfo.BackgroundTransparency = 1
    statsInfo.Text = "• Mendukung target Player dan NPC Bot di seluruh Workspace."
    statsInfo.TextColor3 = THEME.TextSecondary
    statsInfo.Font = Enum.Font.Gotham
    statsInfo.TextSize = 8
    statsInfo.TextWrapped = true
    statsInfo.Parent = statsBody
end

local function BuildPlayerTab()
    local InfoCard = Instance.new("Frame")
    InfoCard.Size = UDim2.new(1, 0, 0, 50)
    InfoCard.BackgroundColor3 = THEME.Panel
    InfoCard.Parent = PlayerTab
    createCorner(InfoCard, UDim.new(0, 8))
    createStroke(InfoCard, THEME.Stroke, 1)

    TargetNameLabel = Instance.new("TextLabel")
    TargetNameLabel.Size = UDim2.new(1, -16, 0, 16)
    TargetNameLabel.Position = UDim2.new(0, 8, 0, 4)
    TargetNameLabel.BackgroundTransparency = 1
    TargetNameLabel.Text = "Status: Fitur Nonaktif"
    TargetNameLabel.TextColor3 = THEME.TextPrimary
    TargetNameLabel.Font = Enum.Font.GothamBold
    TargetNameLabel.TextSize = 11
    TargetNameLabel.TextXAlignment = Enum.TextXAlignment.Left
    TargetNameLabel.Parent = InfoCard

    DistanceLabel = Instance.new("TextLabel")
    DistanceLabel.Size = UDim2.new(1, -16, 0, 14)
    DistanceLabel.Position = UDim2.new(0, 8, 0, 20)
    DistanceLabel.BackgroundTransparency = 1
    DistanceLabel.Text = "Jarak: --"
    DistanceLabel.TextColor3 = THEME.TextSecondary
    DistanceLabel.Font = Enum.Font.Gotham
    DistanceLabel.TextSize = 9
    DistanceLabel.TextXAlignment = Enum.TextXAlignment.Left
    DistanceLabel.Parent = InfoCard

    local HealthBarBg = Instance.new("Frame")
    HealthBarBg.Size = UDim2.new(1, -16, 0, 5)
    HealthBarBg.Position = UDim2.new(0, 8, 0, 38)
    HealthBarBg.BackgroundColor3 = THEME.Background
    HealthBarBg.BorderSizePixel = 0
    HealthBarBg.Parent = InfoCard
    createCorner(HealthBarBg, UDim.new(1, 0))

    HealthBarFill = Instance.new("Frame")
    HealthBarFill.Size = UDim2.new(0, 0, 1, 0)
    HealthBarFill.BackgroundColor3 = THEME.Success
    HealthBarFill.BorderSizePixel = 0
    HealthBarFill.Parent = HealthBarBg
    createCorner(HealthBarFill, UDim.new(1, 0))

    local aimBody, _, _ = CreateDrawer(PlayerTab, "🎯", "[Aim Lock Controls Utama]", "v2.6", "4 Options", true)

    local btnRow = Instance.new("Frame")
    btnRow.Size = UDim2.new(1, 0, 0, 32)
    btnRow.BackgroundTransparency = 1
    btnRow.Parent = aimBody

    ToggleButton = Instance.new("TextButton")
    ToggleButton.Size = UDim2.new(0.58, -4, 1, 0)
    ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 135, 240)
    ToggleButton.Text = "NYALAKAN (Q)"
    ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    ToggleButton.Font = Enum.Font.GothamBold
    ToggleButton.TextSize = 10
    ToggleButton.Parent = btnRow
    createCorner(ToggleButton, UDim.new(0, 6))

    SwitchButton = Instance.new("TextButton")
    SwitchButton.Size = UDim2.new(0.42, 0, 1, 0)
    SwitchButton.Position = UDim2.new(0.58, 4, 0, 0)
    SwitchButton.BackgroundColor3 = THEME.Panel
    SwitchButton.Text = "🔄 Ganti (Tab)"
    SwitchButton.TextColor3 = THEME.Accent
    SwitchButton.Font = Enum.Font.GothamBold
    SwitchButton.TextSize = 9
    SwitchButton.Parent = btnRow
    createCorner(SwitchButton, UDim.new(0, 6))
    createStroke(SwitchButton, THEME.Stroke, 1)

    CreateDropdown(aimBody, "Filter Tipe Target:", {
        { Name = "Semua Target (Player + Bot)", Value = "All" },
        { Name = "Hanya Pemain (Players)", Value = "Player" },
        { Name = "Hanya Bot (NPCs)", Value = "NPC" }
    }, "Semua Target (Player + Bot)", function(val)
        Config.TargetType = val
    end)

    CreateDropdown(aimBody, "Bagian Tubuh Target:", {
        { Name = "Head (Kepala)", Value = "Head" },
        { Name = "HumanoidRootPart (Badan)", Value = "Torso" }
    }, "Head (Kepala)", function(val)
        Config.TargetPartChoice = val
    end)

    local aggroBody, _, _ = CreateDrawer(PlayerTab, "⚡", "[Keganasan & Kehalusan Lock]", "Dynamic", "3 Markers", false)

    CreateSlider(aggroBody, "Keganasan (1% Smooth - 100% Ganas):", 1, 100, Config.LockAggressiveness, "%", function(val)
        Config.LockAggressiveness = val
        if val <= 34 then
            Config.CameraSmoothing = 0.05 + (val / 34) * 0.30
        elseif val <= 65 then
            Config.CameraSmoothing = 0.35 + ((val - 34) / 31) * 0.35
        else
            Config.CameraSmoothing = 1.0
        end
    end)

    CreateDropdown(aggroBody, "Cek Tembok (Wall Check):", {
        { Name = "Aktif (Hanya Target Bebas)", Value = true },
        { Name = "Nonaktif (Tembus Tembok)", Value = false }
    }, "Aktif (Hanya Target Bebas)", function(val)
        Config.WallCheck = val
    end)

    CreateToggle(aggroBody, "Hadap Karakter ke Musuh", "Otomatis putar tubuh menghadap musuh", Config.AutoFaceCharacter, function(st)
        Config.AutoFaceCharacter = st
    end)

    local predBody, _, _ = CreateDrawer(aggroBody, "🔮", "[Prediksi Gerakan & Jarak]", "Advanced", "2 Options", false)

    CreateSlider(predBody, "Jarak Kunci Maksimal:", 30, 250, Config.MaxLockDistance, " studs", function(val)
        Config.MaxLockDistance = val
        Config.BreakDistance = val + 20
    end)

    CreateSlider(predBody, "Kecepatan Putar Karakter:", 10, 100, math.floor(Config.CharacterFaceSpeed * 100), "%", function(val)
        Config.CharacterFaceSpeed = val / 100
    end)
end

local function BuildTrackingTab()
    local trackBody, _, _ = CreateDrawer(TrackingTab, "🎯", "[Silent Aim / Bullet Tracking]", "v2.6", "4 Options", true)

    TrackingToggleButton = CreateActionButton(trackBody, "NYALAKAN TRACKING (T)", "🎯", Color3.fromRGB(0, 135, 240), nil)

    local statusBox = Instance.new("Frame")
    statusBox.Size = UDim2.new(1, 0, 0, 36)
    statusBox.BackgroundColor3 = THEME.Sidebar
    statusBox.Parent = trackBody
    createCorner(statusBox, UDim.new(0, 6))
    createStroke(statusBox, THEME.Stroke, 1)

    TrackingStatusLabel = Instance.new("TextLabel")
    TrackingStatusLabel.Size = UDim2.new(1, -16, 0, 16)
    TrackingStatusLabel.Position = UDim2.new(0, 8, 0, 2)
    TrackingStatusLabel.BackgroundTransparency = 1
    TrackingStatusLabel.Text = "Status: Fitur Nonaktif"
    TrackingStatusLabel.TextColor3 = THEME.TextSecondary
    TrackingStatusLabel.Font = Enum.Font.GothamMedium
    TrackingStatusLabel.TextSize = 9
    TrackingStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    TrackingStatusLabel.Parent = statusBox

    TrackingTargetLabel = Instance.new("TextLabel")
    TrackingTargetLabel.Size = UDim2.new(1, -16, 0, 14)
    TrackingTargetLabel.Position = UDim2.new(0, 8, 0, 18)
    TrackingTargetLabel.BackgroundTransparency = 1
    TrackingTargetLabel.Text = "Target: --"
    TrackingTargetLabel.TextColor3 = THEME.TextSecondary
    TrackingTargetLabel.Font = Enum.Font.Gotham
    TrackingTargetLabel.TextSize = 8
    TrackingTargetLabel.TextXAlignment = Enum.TextXAlignment.Left
    TrackingTargetLabel.Parent = statusBox

    CreateDropdown(trackBody, "Target Part Peluru:", {
        { Name = "Head (Kepala)", Value = "Head" },
        { Name = "Torso (Badan)", Value = "Torso" },
        { Name = "Auto (Random)", Value = "Auto" }
    }, "Head (Kepala)", function(val)
        Config.BulletTargetPart = val
    end)

    CreateDropdown(trackBody, "Hit Chance Akurasi:", {
        { Name = "100% (Pasti Kena)", Value = 100 },
        { Name = "85% (Semi-Legit)", Value = 85 },
        { Name = "65% (Legit)", Value = 65 }
    }, "100% (Pasti Kena)", function(val)
        Config.BulletHitChance = val
    end)

    CreateToggle(trackBody, "Homing Projectiles", "Belokkan peluru proyektil di Workspace", Config.BulletHomingProjectiles, function(st)
        Config.BulletHomingProjectiles = st
    end)

    CreateToggle(trackBody, "Bullet Tracer Beam", "Visual garis laser saat peluru melesat", Config.BulletTracerEnabled, function(st)
        Config.BulletTracerEnabled = st
    end)

    local shootBody, _, _ = CreateDrawer(TrackingTab, "🔫", "[Auto Shoot (TriggerBot)]", "v2.6", "3 Options", false)

    AutoShootToggleBtn = Instance.new("TextButton")
    AutoShootToggleBtn.Size = UDim2.new(1, 0, 0, 32)
    AutoShootToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
    AutoShootToggleBtn.Text = "AUTO SHOOT: OFF (G)"
    AutoShootToggleBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
    AutoShootToggleBtn.Font = Enum.Font.GothamBold
    AutoShootToggleBtn.TextSize = 10
    AutoShootToggleBtn.Parent = shootBody
    createCorner(AutoShootToggleBtn, UDim.new(0, 6))
    AutoShootToggleStroke = createStroke(AutoShootToggleBtn, Color3.fromRGB(50, 58, 76), 1)

    CreateDropdown(shootBody, "Trigger Mode Auto Shoot:", {
        { Name = "Semua (Aim Lock + FOV)", Value = "All" },
        { Name = "Hanya Lingkaran FOV", Value = "FOV" },
        { Name = "Hanya Aim Lock", Value = "AimLock" }
    }, "Semua (Aim Lock + FOV)", function(val)
        Config.AutoShootMode = val
    end)

    CreateDropdown(shootBody, "Wall Check TriggerBot:", {
        { Name = "Aktif (Hanya Tembak Bebas)", Value = true },
        { Name = "Nonaktif (Tembus Pandang)", Value = false }
    }, "Aktif (Hanya Tembak Bebas)", function(val)
        Config.AutoShootWallCheck = val
    end)

    CreateSlider(shootBody, "Delay Tembakan (Cooldown):", 50, 500, Config.AutoShootDelayMs, " ms", function(val)
        Config.AutoShootDelayMs = val
    end)

    local joyBody, _, _ = CreateDrawer(TrackingTab, "🕹️", "[External Mobile Controls]", "HUD Mobile", "2 Controls", false)

    ExternalControlsToggleBtn = Instance.new("TextButton")
    ExternalControlsToggleBtn.Size = UDim2.new(1, 0, 0, 32)
    ExternalControlsToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
    ExternalControlsToggleBtn.Text = "EXTERNAL CONTROLS: ON"
    ExternalControlsToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    ExternalControlsToggleBtn.Font = Enum.Font.GothamBold
    ExternalControlsToggleBtn.TextSize = 10
    ExternalControlsToggleBtn.Parent = joyBody
    createCorner(ExternalControlsToggleBtn, UDim.new(0, 6))
    ExternalControlsToggleStroke = createStroke(ExternalControlsToggleBtn, Color3.fromRGB(0, 220, 150), 1)

    CreateSlider(joyBody, "Ukuran Joystick Analog:", 80, 180, Config.ExternalControlsSize, " px", function(val)
        Config.ExternalControlsSize = val
        if JoystickBase then JoystickBase.Size = UDim2.new(0, val, 0, val) end
    end)

    CreateSlider(joyBody, "Ukuran Tombol Jump:", 50, 110, Config.ExternalJumpSize, " px", function(val)
        Config.ExternalJumpSize = val
        if JumpButton then JumpButton.Size = UDim2.new(0, val, 0, val) end
    end)
end

local function BuildVisualTab()
    local espBody, _, _ = CreateDrawer(VisualTab, "👁️", "[Highlight Target & Billboard ESP]", "Chams", "3 Options", true)

    CreateToggle(espBody, "Highlight Musuh Sekitar", "Memberikan outline kuning/merah pada musuh", Config.HighlightAllEnabled, function(st)
        Config.HighlightAllEnabled = st
        if not st then
            ClearUnlockedHighlights()
        end
    end)

    CreateDropdown(espBody, "Filter Tipe Target Visual:", {
        { Name = "Semua Target (Player + Bot)", Value = "All" },
        { Name = "Hanya Pemain", Value = "Player" },
        { Name = "Hanya Bot / NPC", Value = "NPC" }
    }, "Semua Target (Player + Bot)", function(val)
        Config.HighlightTargetType = val
        ClearUnlockedHighlights()
    end)

    CreateActionButton(espBody, "SEGAR KAN HIGHLIGHT SEKARANG", "🔄", THEME.Panel, function()
        ClearUnlockedHighlights()
        ShowToast("Highlight visual diperbarui!", 2)
    end)

    local fovBody, _, _ = CreateDrawer(VisualTab, "⭕", "[Lingkaran FOV (Field of View)]", "Crosshair", "3 Options", false)

    CreateToggle(fovBody, "Tampilkan Lingkaran FOV", "Lingkaran di tengah layar untuk silent aim & lock", Config.BulletShowFOVCircle, function(st)
        Config.BulletShowFOVCircle = st
        if FOVCircle then
            FOVCircle.Visible = st
        end
    end)

    CreateSlider(fovBody, "Radius Lingkaran FOV:", 40, 350, Config.BulletFOVRadius, " px", function(val)
        Config.BulletFOVRadius = val
        if FOVCircle then
            FOVCircle.Size = UDim2.new(0, val * 2, 0, val * 2)
        end
    end)

    CreateDropdown(fovBody, "Warna Lingkaran FOV:", {
        { Name = "Electric Cyan", Value = Color3.fromRGB(0, 180, 255) },
        { Name = "Neon Green", Value = Color3.fromRGB(0, 240, 120) },
        { Name = "Cyber Purple", Value = Color3.fromRGB(124, 92, 255) },
        { Name = "Hot Crimson", Value = Color3.fromRGB(255, 45, 75) },
        { Name = "Bright Gold", Value = Color3.fromRGB(255, 215, 0) }
    }, "Electric Cyan", function(val)
        Config.BulletFOVCircleColor = val
        if FOVStroke then
            FOVStroke.Color = val
        end
    end)

    local radBody, _, _ = CreateDrawer(espBody, "📏", "[Jarak Radius Highlight (3D Box)]", "Box", "3 Axes", false)

    CreateSlider(radBody, "Radius Horizontal X:", 50, 500, Config.HighlightRadiusX, " studs", function(val)
        Config.HighlightRadiusX = val
    end)

    CreateSlider(radBody, "Radius Vertikal Y:", 50, 300, Config.HighlightRadiusY, " studs", function(val)
        Config.HighlightRadiusY = val
    end)

    CreateSlider(radBody, "Radius Kedalaman Z:", 50, 500, Config.HighlightRadiusZ, " studs", function(val)
        Config.HighlightRadiusZ = val
    end)
end

local function BuildSettingsTab()
    local keyBody, _, _ = CreateDrawer(SettingsTab, "⌨️", "[Keybinds & Shortcut Keyboard]", "PC Keys", "5 Shortcuts", true)

    CreateKeybind(keyBody, "Buka/Tutup Menu Hub", Config.ToggleUIKey, function(k)
        Config.ToggleUIKey = k
    end)

    CreateKeybind(keyBody, "Toggle Aim Lock", Config.ToggleKey, function(k)
        Config.ToggleKey = k
    end)

    CreateKeybind(keyBody, "Ganti Target (Switch Target)", Config.SwitchKey, function(k)
        Config.SwitchKey = k
    end)

    CreateKeybind(keyBody, "Toggle Auto Shoot", Config.AutoShootKey, function(k)
        Config.AutoShootKey = k
    end)

    CreateKeybind(keyBody, "Toggle Bullet Tracking", Config.BulletToggleKey, function(k)
        Config.BulletToggleKey = k
    end)

    local themeBody, _, _ = CreateDrawer(SettingsTab, "🎨", "[Tema & Warna Antarmuka]", "Palette", "5 Themes", false)

    CreateDropdown(themeBody, "Pilihan Tema Hub:", {
        { Name = "Cyber Purple", Value = Color3.fromRGB(124, 92, 255) },
        { Name = "Electric Blue", Value = Color3.fromRGB(0, 140, 255) },
        { Name = "Emerald Hacker", Value = Color3.fromRGB(34, 197, 94) },
        { Name = "Crimson Rage", Value = Color3.fromRGB(239, 68, 68) },
        { Name = "Golden Sun", Value = Color3.fromRGB(245, 158, 11) }
    }, "Cyber Purple", function(c)
        THEME.Accent = c
        THEME.StrokeAccent = c
        ShowToast("Tema antarmuka diperbarui!", 2)
    end)

    local sysBody, _, _ = CreateDrawer(SettingsTab, "🗑️", "[Manajemen & Pembersihan Script]", "System", "2 Actions", false)

    CreateActionButton(sysBody, "RESET KONFIGURASI KE DEFAULT", "🔄", THEME.Panel, function()
        Config.MaxLockDistance = 80
        Config.LockAggressiveness = 50
        Config.CameraSmoothing = 0.52
        Config.FlySpeed = 120
        Config.AutoShootDelayMs = 100
        ShowToast("Konfigurasi direset ke default!", 2)
    end)

    CreateActionButton(sysBody, "UNLOAD / HAPUS SCRIPT DARI GAME", "🗑️", Color3.fromRGB(220, 45, 65), function()
        pcall(function()
            if ScreenGui then ScreenGui:Destroy() end
            if ExternalControlsGui then ExternalControlsGui:Destroy() end
            if _G.CombatFlyHeartbeat then _G.CombatFlyHeartbeat:Disconnect() end
            if _G.CombatFlyNoclip then _G.CombatFlyNoclip:Disconnect() end
            if _G.CombatExternalControlsConn then _G.CombatExternalControlsConn:Disconnect() end
            ClearUnlockedHighlights()
        end)
    end)
end

BuildMainTab()
BuildPlayerTab()
BuildTrackingTab()
BuildVisualTab()
BuildSettingsTab()

SwitchTab("Player")
ShowToast("Feath Hub v2.6 loaded successfully", 3)

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
    if not char then return false, nil end
    local p = Players:GetPlayerFromCharacter(char)
    if p then return true, p end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == char or (char.Parent and player.Character == char.Parent) then
            return true, player
        end
    end
    return false, nil
end

local function IsSameTeam(player)
    if not player or player == LocalPlayer then return true end
    
    -- Jika pemain Neutral (mode FFA / bebas), mereka bukan kawan satu tim
    if LocalPlayer.Neutral or player.Neutral then
        return false
    end
    
    -- Hanya anggap satu tim jika ada objek Team yang valid dan sama persis
    if LocalPlayer.Team ~= nil and player.Team ~= nil then
        return LocalPlayer.Team == player.Team
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
                    if string.find(lowerName, "player") or string.find(lowerName, "char")
                       or string.find(lowerName, "npc") or string.find(lowerName, "enemi") 
                       or string.find(lowerName, "mob") or string.find(lowerName, "bot") 
                       or string.find(lowerName, "monster") or string.find(lowerName, "zombie") 
                       or string.find(lowerName, "entity") or string.find(lowerName, "creature")
                       or string.find(lowerName, "living") or string.find(lowerName, "spawn") then
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

        local centerPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        local fovRadius = Config.BulletFOVRadius or 180

        -- Kumpulkan musuh yang hanya berada di dalam lingkaran FOV tengah layar
        local fovEnemies = {}
        for _, entry in ipairs(enemies) do
            local screenPos, onScreen = Camera:WorldToViewportPoint(entry.Part.Position)
            if onScreen then
                local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude
                if screenDist <= fovRadius then
                    table.insert(fovEnemies, {
                        Entry = entry,
                        ScreenDist = screenDist
                    })
                end
            end
        end

        -- Kunci target hanya jika musuh berada di dalam lingkaran FOV
        if #fovEnemies > 0 then
            if Config.TargetSwitchMode == "LowestHP" then
                local lowestHP = math.huge
                local shortestDist = math.huge
                for _, item in ipairs(fovEnemies) do
                    local entry = item.Entry
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
            elseif Config.LockMode == "Cursor" then
                local shortestScreenDist = math.huge
                for _, item in ipairs(fovEnemies) do
                    if item.ScreenDist < shortestScreenDist then
                        shortestScreenDist = item.ScreenDist
                        best = item.Entry
                    end
                end
            else
                -- LockMode == "Distance" (default): Musuh terdekat di dalam FOV
                local shortestDist = math.huge
                for _, item in ipairs(fovEnemies) do
                    if item.Entry.Distance < shortestDist then
                        shortestDist = item.Entry.Distance
                        best = item.Entry
                    end
                end
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
                    local centerPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                    local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude
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
        local centerPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
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
                        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude
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
            tracer.CanTouch = false
            tracer.CanQuery = false
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

            -- Helper: Filter agar raycast & mouse dari script kamera Roblox tidak terganggu
            local function IsCameraCaller()
                local scr = nil
                if typeof(getcallingscript) == "function" then
                    pcall(function() scr = getcallingscript() end)
                end
                if scr then
                    local sName = string.lower(scr.Name)
                    if sName:find("camera") or sName:find("popper") or sName:find("zoom") 
                       or sName:find("playermodule") or sName:find("transparency") 
                       or sName:find("shiftlock") or sName:find("control") 
                       or sName:find("basecamera") or sName:find("invisicam") then
                        return true
                    end
                    local myPlr = LocalPlayer
                    if myPlr and myPlr:FindFirstChild("PlayerScripts") then
                        local pm = myPlr.PlayerScripts:FindFirstChild("PlayerModule")
                        if pm and scr:IsDescendantOf(pm) then
                            return true
                        end
                    end
                end
                return false
            end

            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local method = getnamecallmethod()
                local cfg = _G.FeathCombatConfig
                if cfg and cfg.BulletTrackingEnabled and (not checkcaller or not checkcaller()) then
                    if (method == "Raycast" and self == workspace)
                        or method == "FindPartOnRay"
                        or method == "FindPartOnRayWithIgnoreList"
                        or method == "FindPartOnRayWithWhitelist" then

                        -- Jangan ubah raycast internal kamera (PopperCam / ZoomController)
                        if not IsCameraCaller() then
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
                            -- Jangan alihkan Mouse.Hit bila dipanggil oleh script kamera (mencegah kamera zoom in-out)
                            if not IsCameraCaller() then
                                local hitChance = cfg.BulletHitChance or 100
                                if math.random(1, 100) <= hitChance then
                                    local fn = _G.FeathGetBulletTarget
                                    local targetPart, targetPos = fn and fn()
                                    if targetPart and targetPos then
                                        if key == "Hit" then
                                            return CFrame.new(targetPos)
                                        elseif key == "Target" then
                                            return targetPart
                                        end
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
            pcall(function()
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
        local centerPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

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
                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude
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

        -- 2. Simulasi input aman (Mobile Friendly - TANPA CaptureController)
        local isTouchDevice = UserInputService.TouchEnabled
        if isTouchDevice then
            -- Khusus Mobile / Delta Android:
            -- tool:Activate() di atas sudah menembakkan senjata tool Roblox.
            -- Gunakan VirtualInputManager tanpa CaptureController
            local vim = nil
            pcall(function() vim = game:GetService("VirtualInputManager") end)
            if vim then
                local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                pcall(function()
                    vim:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 1)
                    task.delay(0.02, function()
                        pcall(function() vim:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 1) end)
                    end)
                end)
            end

            -- Pastikan joystick & jump button external selalu aktif di layar pemain
            pcall(function()
                if ExternalControlsGui and not ExternalControlsGui.Enabled and Config.ExternalControlsEnabled then
                    ExternalControlsGui.Enabled = true
                end
                local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui"))
                if pGui then
                    local touchGui = pGui:FindFirstChild("TouchGui")
                    if touchGui then
                        touchGui.Enabled = true
                        local tFrame = touchGui:FindFirstChild("TouchControlFrame")
                        if tFrame then tFrame.Visible = true end
                    end
                end
            end)
        else
            -- Di PC
            if typeof(mouse1click) == "function" then
                mouse1click()
            elseif typeof(mouse1press) == "function" and typeof(mouse1release) == "function" then
                mouse1press()
                task.delay(0.02, function() pcall(mouse1release) end)
            else
                local vim = nil
                pcall(function() vim = game:GetService("VirtualInputManager") end)
                if vim then
                    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                    pcall(function()
                        vim:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 1)
                        task.delay(0.02, function()
                            pcall(function() vim:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 1) end)
                        end)
                    end)
                end
            end
        end
    end)
end

function ToggleAutoShoot()
    pcall(function()
        Config.AutoShootEnabled = not Config.AutoShootEnabled
        _G.FeathCombatConfig = Config
        if Config.AutoShootEnabled and Config.ExternalControlsEnabled and ExternalControlsGui then
            ExternalControlsGui.Enabled = true
        end
        UpdateUI()
    end)
end

function ToggleExternalControls()
    pcall(function()
        Config.ExternalControlsEnabled = not Config.ExternalControlsEnabled
        _G.FeathCombatConfig = Config
        if ExternalControlsGui then
            ExternalControlsGui.Enabled = Config.ExternalControlsEnabled
        end
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

        -- 5. Update Tab Tracking UI (External Mobile Controls)
        if ExternalControlsToggleBtn and ExternalControlsToggleStroke then
            if not Config.ExternalControlsEnabled then
                ExternalControlsToggleBtn.Text = "EXTERNAL CONTROLS: OFF"
                ExternalControlsToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
                ExternalControlsToggleBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
                ExternalControlsToggleStroke.Color = Color3.fromRGB(50, 58, 76)
            else
                ExternalControlsToggleBtn.Text = "EXTERNAL CONTROLS: ON"
                ExternalControlsToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
                ExternalControlsToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                ExternalControlsToggleStroke.Color = Color3.fromRGB(0, 220, 150)
            end
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
                if string.find(lowerName, "player") or string.find(lowerName, "char")
                   or string.find(lowerName, "npc") or string.find(lowerName, "enemi") 
                   or string.find(lowerName, "mob") or string.find(lowerName, "bot") 
                   or string.find(lowerName, "monster") or string.find(lowerName, "zombie") 
                   or string.find(lowerName, "entity") or string.find(lowerName, "dummy")
                   or string.find(lowerName, "creature") or string.find(lowerName, "living")
                   or string.find(lowerName, "spawn") then
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
            if string.find(lowerName, "player") or string.find(lowerName, "char")
               or string.find(lowerName, "npc") or string.find(lowerName, "enemi") 
               or string.find(lowerName, "mob") or string.find(lowerName, "bot") 
               or string.find(lowerName, "monster") or string.find(lowerName, "zombie") 
               or string.find(lowerName, "entity") or string.find(lowerName, "dummy")
               or string.find(lowerName, "creature") or string.find(lowerName, "living")
               or string.find(lowerName, "spawn") then
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

    -- Option 1: Dalam FOV (Auto)
    table.insert(options, {
        Label = "🎯 [Target di Dalam FOV (Auto)]",
        Nickname = "🎯 [Target di Dalam FOV (Auto)]",
        Model = nil,
        Mode = "FOV"
    })

    -- Option 2: Terdekat (Auto)
    table.insert(options, {
        Label = "⭐ [Target Terdekat (Auto)]",
        Nickname = "⭐ [Target Terdekat (Auto)]",
        Model = nil,
        Mode = "Auto"
    })

    -- Option 3: HP Terendah (Auto)
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
        if opt.Mode == "FOV" and SelectedTPMode == "FOV" then
            isSelected = true
        elseif opt.Mode == "Auto" and SelectedTPMode == "Auto" then
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
            if opt.Mode == "FOV" then
                SelectedTPModel = nil
                SelectedTPName = "FOV"
                SelectedTPMode = "FOV"
                TPDropdownBtn.Text = "  🎯 [Target di Dalam FOV (Auto)]"
                TPStatusLabel.Text = "Mode FOV: Target di dalam lingkaran FOV akan dipilih saat aksi"
                TPStatusLabel.TextColor3 = Color3.fromRGB(0, 200, 255)
            elseif opt.Mode == "Auto" then
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

    if SelectedTPMode == "FOV" then
        local best = FindBestTarget()
        if best and best.Character and IsValidEnemy(best.Character) then
            local isPlayer, playerObj = IsPlayerCharacter(best.Character)
            local dName = isPlayer and (playerObj.DisplayName ~= "" and playerObj.DisplayName or playerObj.Name) or best.Character.Name
            local hp = best.Health or 100
            return best.Character, dName, hp
        end
        return nil, nil, nil
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
        pcall(function()
            local c = LocalPlayer.Character
            if c then
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") and p.CanCollide then
                        p.CanCollide = false
                    end
                end
            end
        end)
    end)
    _G.CombatFlyNoclip = FlyNoclipConn

    FlyHeartbeatConn = RunService.Heartbeat:Connect(function(dt)
        pcall(function()
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

            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.AssemblyAngularVelocity = Vector3.zero
            myRoot.CFrame = CFrame.lookAt(nextPos, targetPos)

            TPStatusLabel.Text = string.format("Terbang ke [%s] (%.0f studs | Speed: %d)", targetName, dist, Config.FlySpeed)
        end)
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
    pcall(function()
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

if ExternalControlsToggleBtn then
    ExternalControlsToggleBtn.MouseButton1Click:Connect(function()
        pcall(ToggleExternalControls)
    end)
end

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
        local shouldShowFOV = (Config.BulletTrackingEnabled or Config.AutoShootEnabled or AutoLockEnabled) and Config.BulletShowFOVCircle and Config.BulletUseFOV
        if shouldShowFOV then
            local diameter = Config.BulletFOVRadius * 2
            FOVCircle.Size = UDim2.new(0, diameter, 0, diameter)
            FOVCircle.Position = UDim2.new(0.5, 0, 0.5, 0)

            local shootTarget = Config.AutoShootEnabled and GetAutoShootTarget()
            local tPart, _ = GetBulletTarget()
            if AutoLockEnabled and CurrentTargetPart then
                FOVStroke.Color = Color3.fromRGB(255, 45, 75) -- Merah Terang: Target Terkunci AimLock
                FOVStroke.Transparency = 0.15
            elseif shootTarget then
                FOVStroke.Color = Color3.fromRGB(50, 225, 120) -- Hijau: Siap Tembak
                FOVStroke.Transparency = 0.15
            elseif tPart then
                if Config.AutoShootWallCheck and not IsTargetVisible(tPart) then
                    FOVStroke.Color = Color3.fromRGB(245, 155, 40) -- Oranye: Terhalang Tembok
                    FOVStroke.Transparency = 0.25
                else
                    FOVStroke.Color = Color3.fromRGB(255, 60, 80) -- Merah: Target Terkunci Silent Aim
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
                local screenPos, onScreen = Camera:WorldToViewportPoint(CurrentTargetPart.Position)
                local centerPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                local outOfFOV = not onScreen or ((Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude > (Config.BulletFOVRadius + 60))

                if curDist > Config.BreakDistance or outOfFOV then
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
                local screenPos, onScreen = Camera:WorldToViewportPoint(CurrentTargetPart.Position)
                local centerPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                local outOfFOV = not onScreen or ((Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude > (Config.BulletFOVRadius + 60))

                if curDist > Config.BreakDistance or outOfFOV then
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
                local screenPos, onScreen = Camera:WorldToViewportPoint(CurrentTargetPart.Position)
                local centerPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                local outOfFOV = not onScreen or ((Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude > (Config.BulletFOVRadius + 60))

                if curDist > Config.BreakDistance or outOfFOV then
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

            -- 2. Hadap Karakter ke Musuh/Bot (Aman & Tidak Mematikan Gerakan/Loncat)
            if Config.AutoFaceCharacter then
                local lookVector = Vector3.new(targetPos.X, myRoot.Position.Y, targetPos.Z)
                if (lookVector - myRoot.Position).Magnitude > 0.01 then
                    local targetCharCFrame = CFrame.new(myRoot.Position, lookVector)
                    local oldVel = myRoot.AssemblyLinearVelocity
                    myRoot.CFrame = myRoot.CFrame:Lerp(targetCharCFrame, Config.CharacterFaceSpeed)
                    pcall(function() myRoot.AssemblyLinearVelocity = oldVel end)
                end
            end
        end
    end)
end)

print("[FeathHub] Loaded! UI baru bergaya Pithers Hub siap digunakan.")
