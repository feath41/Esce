--[[ the only one who managed to connect them was a very great person.

ReigaMajesty]]

--// Services
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst   = game:GetService("ReplicatedFirst")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local LP = Players.LocalPlayer

-- 1 FRAME,GUI,LOGIC

local UI = {}
do
    -- Window size {0, 450}, {0, 270}
    local W, H = 450, 270
    local TOP_H = 36
    local SIDE_W = 112
    local PW = 150 

    -- Color
    local Theme = {
        Bg     = Color3.fromRGB(9, 14, 26),
        Item   = Color3.fromRGB(20, 32, 56),
        ItemHi = Color3.fromRGB(28, 44, 76),
        Cyan   = Color3.fromRGB(0, 220, 255),
        Blue   = Color3.fromRGB(40, 110, 255),
        Text   = Color3.fromRGB(230, 242, 255),
        Sub    = Color3.fromRGB(130, 155, 190),
        Off    = Color3.fromRGB(44, 60, 92),
        Line   = Color3.fromRGB(30, 48, 80),
    }
    local WHITE = Color3.new(1, 1, 1)

    local EASE = Enum.EasingStyle
    local DIR  = Enum.EasingDirection
    
    -- HELPER

    local function new(class, props, children)
        local o = Instance.new(class)
        for k, v in pairs(props or {}) do o[k] = v end
        for _, c in ipairs(children or {}) do c.Parent = o end
        return o
    end

    local function corner(r)
        return new("UICorner", { CornerRadius = UDim.new(0, r or 8) })
    end

    local function pad(l, r, t, b)
        return new("UIPadding", {
            PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
            PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
        })
    end

    local function gradient(rot)
        return new("UIGradient", {
            Color = ColorSequence.new(Theme.Cyan, Theme.Blue),
            Rotation = rot or 0,
        })
    end

    local function glowStroke(thickness, transparency)
        return new("UIStroke", {
            Thickness = thickness or 1.5, Color = WHITE, Transparency = transparency or 0.35,
        }, { gradient(45) })
    end

    -- tween 64926596285
    local function tween(o, t, p, style, dir)
        local tw = TweenService:Create(o, TweenInfo.new(t, style or EASE.Quad, dir or DIR.Out), p)
        tw:Play()
        return tw
    end

    -- Stop connection / tween 9471648
    local conns = {}
    local function track(c)
        table.insert(conns, c)
        return c
    end

    -- gradient border 7572564
    local function spin(stroke, duration)
        local g = stroke:FindFirstChildOfClass("UIGradient")
        if not g then return end
        local tw = TweenService:Create(
            g,
            TweenInfo.new(duration or 5, EASE.Linear, DIR.Out, -1),
            { Rotation = g.Rotation + 360 }
        )
        tw:Play()
        track(tw)
    end

    local function getGuiParent()
        local ok, h = pcall(function() return gethui and gethui() end)
        if ok and h then return h end
        local ok2, cg = pcall(function()
            local c = game:GetService("CoreGui")
            local t = Instance.new("Folder"); t.Parent = c; t:Destroy()
            return c
        end)
        if ok2 and cg then return cg end
        return LP:WaitForChild("PlayerGui")
    end

    -- pressure effect 777362672
    local function pressFx(btn, label)
        label = label or btn
        local base = label.TextSize
        btn.MouseButton1Down:Connect(function()
            tween(label, 0.08, { TextSize = base - 2 })
        end)
        local function release()
            tween(label, 0.28, { TextSize = base }, EASE.Back, DIR.Out)
        end
        btn.MouseButton1Up:Connect(release)
        btn.MouseLeave:Connect(release)
    end

    -- hover effect 6476
    local function scaleFx(btn, hoverScale, downScale)
        local sc = new("UIScale", { Scale = 1, Parent = btn })
        btn.MouseEnter:Connect(function() tween(sc, 0.15, { Scale = hoverScale }) end)
        btn.MouseLeave:Connect(function() tween(sc, 0.22, { Scale = 1 }) end)
        btn.MouseButton1Down:Connect(function() tween(sc, 0.08, { Scale = downScale }) end)
        btn.MouseButton1Up:Connect(function()
            tween(sc, 0.3, { Scale = hoverScale }, EASE.Back, DIR.Out)
        end)
        return sc
    end

    -- drag 7777
    local function makeDraggable(handle, target, threshold)
        threshold = threshold or 0
        local dragging, moved, startInput, startPos, goal = false, false, nil, nil, nil

        handle.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                dragging   = true
                moved      = false
                startInput = i.Position
                startPos   = target.Position
                goal       = nil
                i.Changed:Connect(function()
                    if i.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)

        track(UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - startInput
                if d.Magnitude > threshold then moved = true end
                if moved then
                    goal = UDim2.new(
                        startPos.X.Scale, startPos.X.Offset + d.X,
                        startPos.Y.Scale, startPos.Y.Offset + d.Y
                    )
                end
            end
        end))

        track(RunService.RenderStepped:Connect(function(dt)
            if not goal then return end
            local nxt = target.Position:Lerp(goal, 1 - math.exp(-22 * dt))
            if math.abs(nxt.X.Offset - goal.X.Offset) < 1.5
            and math.abs(nxt.Y.Offset - goal.Y.Offset) < 1.5 then
                nxt = goal
                if not dragging then goal = nil end
            end
            target.Position = nxt
        end))

        return function() return moved end
    end

    -- section open/close 4421
    local function animateGroup(group, layout, open)
        local token = (group:GetAttribute("Tok") or 0) + 1
        group:SetAttribute("Tok", token)
        local info = TweenInfo.new(0.32, EASE.Quint, DIR.Out)

        if open then
            local startH = group.Visible and group.AbsoluteSize.Y or 0
            group.Visible = true
            local target = layout.AbsoluteContentSize.Y
            group.AutomaticSize = Enum.AutomaticSize.None
            group.ClipsDescendants = true
            group.Size = UDim2.new(1, 0, 0, startH)
            local tw = TweenService:Create(group, info, { Size = UDim2.new(1, 0, 0, target) })
            tw.Completed:Connect(function()
                if group:GetAttribute("Tok") == token then
                    group.ClipsDescendants = false
                    group.AutomaticSize = Enum.AutomaticSize.Y
                    group.Size = UDim2.new(1, 0, 0, 0)
                end
            end)
            tw:Play()
        else
            local cur = group.AbsoluteSize.Y
            group.AutomaticSize = Enum.AutomaticSize.None
            group.ClipsDescendants = true
            group.Size = UDim2.new(1, 0, 0, cur)
            local tw = TweenService:Create(group, info, { Size = UDim2.new(1, 0, 0, 0) })
            tw.Completed:Connect(function()
                if group:GetAttribute("Tok") == token then
                    group.Visible = false
                    group.ClipsDescendants = false
                    group.AutomaticSize = Enum.AutomaticSize.Y
                    group.Size = UDim2.new(1, 0, 0, 0)
                end
            end)
            tw:Play()
        end
    end

    -- Notify 5518
    local notifHolder
    local notifCount = 0

    function UI:Notify(cfg)
        if not notifHolder then return end
        task.spawn(function()
            notifCount = notifCount + 1
            local wrap = new("Frame", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1, LayoutOrder = notifCount, Parent = notifHolder,
            })
            local card = new("CanvasGroup", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                Position = UDim2.fromOffset(60, 0), GroupTransparency = 1,
                BackgroundColor3 = Theme.Bg, BorderSizePixel = 0, Parent = wrap,
            }, {
                corner(8), glowStroke(1.2, 0.3), pad(10, 10, 7, 7),
                new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
            })
            new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, LayoutOrder = 1,
                Text = cfg.Title or "ReigaX", TextColor3 = WHITE,
                Font = Enum.Font.GothamBold, TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
            }, { gradient() })
            new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1, LayoutOrder = 2, Text = cfg.Content or "",
                TextColor3 = Theme.Text, Font = Enum.Font.Gotham, TextSize = 11,
                TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
            })

            tween(card, 0.4, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, EASE.Back, DIR.Out)
            task.wait(cfg.Duration or 3)
            tween(card, 0.25, { Position = UDim2.fromOffset(60, 0), GroupTransparency = 1 }, EASE.Quad, DIR.In)
            task.wait(0.28)
            pcall(function() wrap:Destroy() end)
        end)
    end

    -- Window 3302
    function UI:CreateWindow(cfg)
        cfg = cfg or {}
        local Window = {}

        local parent = getGuiParent()
        local old = parent:FindFirstChild("ReigaX")
        if old then old:Destroy() end

        local gui = new("ScreenGui", {
            Name = "ReigaX", ResetOnSpawn = false, IgnoreGuiInset = true,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
        })
        gui.Parent = parent

        notifHolder = new("Frame", {
            Size = UDim2.new(0, 220, 1, -20), Position = UDim2.new(1, -230, 0, 10),
            BackgroundTransparency = 1, ZIndex = 200, Parent = gui,
        }, {
            new("UIListLayout", {
                Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
                VerticalAlignment = Enum.VerticalAlignment.Bottom,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
            }),
        })

        -- Main frame
        local mainStroke = glowStroke(1.5, 0.3)
        local main = new("Frame", {
            Name = "Main", Size = UDim2.fromOffset(W, H),
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            BackgroundColor3 = Theme.Bg, BorderSizePixel = 0, Parent = gui,
        }, { corner(12), mainStroke })
        spin(mainStroke, 6)
        local mainScale = new("UIScale", { Scale = 0.8, Parent = main })

        -- Part 1 / top bar
        local top = new("Frame", {
            Name = "Top", Size = UDim2.new(1, 0, 0, TOP_H),
            BackgroundTransparency = 1, Parent = main,
        })
        new("Frame", {
            Size = UDim2.new(1, -16, 0, 1), Position = UDim2.new(0, 8, 0, TOP_H),
            BackgroundColor3 = Theme.Line, BorderSizePixel = 0, Parent = main,
        })

        -- Logo 1:1
        if cfg.Logo and cfg.Logo ~= "" then
            new("ImageLabel", {
                Size = UDim2.fromOffset(22, 22), Position = UDim2.new(0, 10, 0.5, -11),
                BackgroundTransparency = 1, Image = cfg.Logo, Parent = top,
            }, { corner(5), new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
        else
            new("Frame", {
                Size = UDim2.fromOffset(22, 22), Position = UDim2.new(0, 10, 0.5, -11),
                BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = top,
            }, {
                corner(5), gradient(45),
                new("UIAspectRatioConstraint", { AspectRatio = 1 }),
                new("TextLabel", {
                    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "R",
                    TextColor3 = WHITE, Font = Enum.Font.GothamBlack, TextSize = 14,
                }),
            })
        end

        -- Title
        new("TextLabel", {
            Size = UDim2.new(0, 160, 1, 0), Position = UDim2.new(0, 40, 0, 0),
            BackgroundTransparency = 1, Text = cfg.Name or "ReigaX",
            TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left, Parent = top,
        }, { gradient() })

        -- Top buttons
        local function topBtn(txt, xOff, color)
            local b = new("TextButton", {
                Size = UDim2.fromOffset(24, 20), AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(1, xOff + 12, 0.5, 0),
                BackgroundColor3 = color, Text = txt, TextColor3 = Theme.Text,
                Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = true, Parent = top,
            }, { corner(6) })
            scaleFx(b, 1.12, 0.86)
            return b
        end
        local btnMin   = topBtn("-", -58, Theme.Item)
        local btnClose = topBtn("X", -30, Color3.fromRGB(200, 60, 85))

        makeDraggable(top, main, 0)

        -- Body
        local body = new("Frame", {
            Name = "Body", Size = UDim2.new(1, 0, 1, -(TOP_H + 1)),
            Position = UDim2.new(0, 0, 0, TOP_H + 1), BackgroundTransparency = 1, Parent = main,
        })

        -- Tab slider
        local pill = new("Frame", {
            Name = "TabPill", Size = UDim2.fromOffset(SIDE_W - 14, 28),
            Position = UDim2.fromOffset(8, 8), BackgroundColor3 = WHITE,
            BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
            ZIndex = 1, Parent = body,
        }, { corner(8), gradient(0) })

        -- Part 2 / feature list
        local sidebar = new("Frame", {
            Name = "Sidebar", Size = UDim2.new(0, SIDE_W, 1, 0),
            BackgroundTransparency = 1, ZIndex = 2, Parent = body,
        }, {
            pad(8, 6, 8, 8),
            new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
        })
        new("Frame", {
            Size = UDim2.new(0, 1, 1, -12), Position = UDim2.new(0, SIDE_W, 0, 6),
            BackgroundColor3 = Theme.Line, BorderSizePixel = 0, Parent = body,
        })

        -- Part 3 / content
        local contentBase = UDim2.new(0, SIDE_W + 4, 0, 4)
        local contentWrap = new("CanvasGroup", {
            Name = "ContentWrap", Size = UDim2.new(1, -(SIDE_W + 8), 1, -8),
            Position = contentBase, BackgroundTransparency = 1, Parent = body,
        })
        local content = new("ScrollingFrame", {
            Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Cyan,
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = contentWrap,
        }, {
            pad(6, 6, 2, 4),
            new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
        })

        local order = 0
        local function nextOrder()
            order = order + 1
            return order
        end

        local currentParent = content   -- current parent
        local sectionOpen   = {}        -- section state
        local activeTabName = ""

        -- Side panel
        local panel

        function Window:ClosePanel()
            if panel then
                local p = panel
                panel = nil
                local out = p:GetAttribute("OnRight") and UDim2.new(1, -20, 0, 0) or UDim2.new(0, -PW + 20, 0, 0)
                tween(p, 0.2, { GroupTransparency = 1, Position = out }, EASE.Quad, DIR.In)
                task.delay(0.22, function() pcall(function() p:Destroy() end) end)
            end
        end

        function Window:OpenPanel(title, options, current, onPick, owner)
            Window:ClosePanel()
            options = options or {}

            local vp = gui.AbsoluteSize.X
            if vp == 0 then
                local cam = workspace.CurrentCamera
                vp = cam and cam.ViewportSize.X or 1000
            end
            local rightRoom = vp - (main.AbsolutePosition.X + W)
            local onRight = rightRoom >= PW + 8
            local finalPos = onRight and UDim2.new(1, 8, 0, 0) or UDim2.new(0, -(PW + 8), 0, 0)
            local startPos = onRight and UDim2.new(1, -20, 0, 0) or UDim2.new(0, -PW + 20, 0, 0)

            local myPanel = new("CanvasGroup", {
                Name = "SidePanel", Size = UDim2.fromOffset(PW, H), Position = startPos,
                GroupTransparency = 1, BackgroundColor3 = Theme.Bg, BorderSizePixel = 0, Parent = main,
            }, { corner(12), glowStroke(1.5, 0.3) })
            panel = myPanel
            myPanel:SetAttribute("Owner", owner)
            myPanel:SetAttribute("OnRight", onRight)

            new("TextLabel", {
                Size = UDim2.new(1, -16, 0, 28), Position = UDim2.new(0, 10, 0, 0),
                BackgroundTransparency = 1, Text = title, TextColor3 = WHITE,
                Font = Enum.Font.GothamBold, TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left, Parent = myPanel,
            }, { gradient() })
            new("Frame", {
                Size = UDim2.new(1, -16, 0, 1), Position = UDim2.new(0, 8, 0, 28),
                BackgroundColor3 = Theme.Line, BorderSizePixel = 0, Parent = myPanel,
            })

            local list = new("ScrollingFrame", {
                Size = UDim2.new(1, -8, 1, -36), Position = UDim2.new(0, 4, 0, 32),
                BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
                ScrollBarImageColor3 = Theme.Cyan, CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = myPanel,
            }, {
                pad(4, 6, 2, 4),
                new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
            })

            if #options == 0 then
                new("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Text = "Empty",
                    TextColor3 = Theme.Sub, Font = Enum.Font.Gotham, TextSize = 12, Parent = list,
                })
            end

            for i, opt in ipairs(options) do
                local selected = (opt == current)
                local b = new("TextButton", {
                    Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i,
                    BackgroundColor3 = selected and WHITE or Theme.Item,
                    Text = "", AutoButtonColor = false, Parent = list,
                }, { corner(7) })
                if selected then gradient().Parent = b end
                local lbl = new("TextLabel", {
                    Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 8, 0, 0),
                    BackgroundTransparency = 1, Text = tostring(opt),
                    TextColor3 = selected and WHITE or Theme.Text,
                    Font = Enum.Font.Gotham, TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd, Parent = b,
                })
                pressFx(b, lbl)
                if not selected then
                    b.MouseEnter:Connect(function()
                        tween(b, 0.12, { BackgroundColor3 = Theme.ItemHi })
                        tween(lbl, 0.15, { Position = UDim2.new(0, 12, 0, 0) })
                    end)
                    b.MouseLeave:Connect(function()
                        tween(b, 0.15, { BackgroundColor3 = Theme.Item })
                        tween(lbl, 0.2, { Position = UDim2.new(0, 8, 0, 0) })
                    end)
                end
                b.MouseButton1Click:Connect(function()
                    if panel ~= myPanel then return end
                    Window:ClosePanel()
                    if onPick then task.spawn(onPick, opt) end
                end)
            end

            tween(myPanel, 0.35, { GroupTransparency = 0, Position = finalPos }, EASE.Back, DIR.Out)
        end

        -- Page elements
        local Page = {}

        local function row(h)
            return new("Frame", {
                Size = UDim2.new(1, 0, 0, h or 30), LayoutOrder = nextOrder(),
                BackgroundColor3 = Theme.Item, BorderSizePixel = 0, Parent = currentParent,
            }, { corner(8) })
        end

        local function rowLabel(parent, text, reserve)
            return new("TextLabel", {
                Size = UDim2.new(1, -(reserve or 0) - 20, 1, 0), Position = UDim2.new(0, 10, 0, 0),
                BackgroundTransparency = 1, Text = text, TextColor3 = Theme.Text,
                Font = Enum.Font.Gotham, TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd, Parent = parent,
            })
        end

        -- Section 8830
        function Page:Section(text, defaultOpen)
            local key = activeTabName .. "/" .. text
            if sectionOpen[key] == nil then
                sectionOpen[key] = defaultOpen and true or false
            end
            local open = sectionOpen[key]

            local hStroke = new("UIStroke", { Color = Theme.Cyan, Thickness = 1, Transparency = 0.7 })
            local header = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder(),
                BackgroundColor3 = Theme.Item, Text = "", AutoButtonColor = false, Parent = content,
            }, { corner(8), hStroke })

            local title = new("TextLabel", {
                Size = UDim2.new(1, -40, 1, 0), Position = UDim2.new(0, 10, 0, 0),
                BackgroundTransparency = 1, Text = text, TextColor3 = WHITE,
                Font = Enum.Font.GothamBold, TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
            }, { gradient() })

            local arrow = new("TextLabel", {
                Size = UDim2.fromOffset(20, 28), Position = UDim2.new(1, -26, 0, 0),
                BackgroundTransparency = 1, Text = ">", Rotation = open and 180 or 0,
                TextColor3 = Theme.Cyan, Font = Enum.Font.GothamBold, TextSize = 14, Parent = header,
            })

            local glayout = new("UIListLayout", {
                Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
            })
            local group = new("Frame", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = nextOrder(), BackgroundTransparency = 1,
                Visible = open, Parent = content,
            }, { glayout })
            currentParent = group

            pressFx(header, title)
            header.MouseEnter:Connect(function()
                tween(header, 0.15, { BackgroundColor3 = Theme.ItemHi })
                tween(hStroke, 0.15, { Transparency = 0.2 })
            end)
            header.MouseLeave:Connect(function()
                tween(header, 0.2, { BackgroundColor3 = Theme.Item })
                tween(hStroke, 0.2, { Transparency = 0.7 })
            end)
            header.MouseButton1Click:Connect(function()
                open = not open
                sectionOpen[key] = open
                tween(arrow, 0.35, { Rotation = open and 180 or 0 }, EASE.Back, DIR.Out)
                animateGroup(group, glayout, open)
            end)
        end

        function Page:Toggle(o)
            local state = o.Value and true or false
            local r = row(30)
            rowLabel(r, o.Name, 50)

            local sw = new("Frame", {
                Size = UDim2.fromOffset(36, 18), Position = UDim2.new(1, -46, 0.5, -9),
                BackgroundColor3 = Theme.Off, BorderSizePixel = 0, Parent = r,
            }, { corner(9) })
            -- ON layer
            local fill = new("Frame", {
                Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE,
                BackgroundTransparency = state and 0 or 1, BorderSizePixel = 0, Parent = sw,
            }, { corner(9), gradient() })
            local knob = new("Frame", {
                Size = UDim2.fromOffset(14, 14), BackgroundColor3 = WHITE, BorderSizePixel = 0,
                Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7),
                ZIndex = 2, Parent = sw,
            }, { corner(7) })

            local function render()
                tween(fill, 0.25, { BackgroundTransparency = state and 0 or 1 })
                tween(knob, 0.32, {
                    Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7),
                }, EASE.Back, DIR.Out)
            end

            local hit = new("TextButton", {
                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = r,
            })
            hit.MouseEnter:Connect(function() tween(r, 0.15, { BackgroundColor3 = Theme.ItemHi }) end)
            hit.MouseLeave:Connect(function() tween(r, 0.2, { BackgroundColor3 = Theme.Item }) end)
            hit.MouseButton1Click:Connect(function()
                state = not state
                render()
                if o.Callback then task.spawn(o.Callback, state) end
            end)
        end

        function Page:Input(o)
            local r = row(30)
            rowLabel(r, o.Name, 100)

            local boxStroke = new("UIStroke", { Color = Theme.Cyan, Thickness = 1, Transparency = 0.6 })
            local box = new("TextBox", {
                Size = UDim2.fromOffset(90, 22), Position = UDim2.new(1, -100, 0.5, -11),
                BackgroundColor3 = Theme.Bg, Text = o.Value or "",
                PlaceholderText = o.Placeholder or "", PlaceholderColor3 = Theme.Sub,
                TextColor3 = Theme.Cyan, Font = Enum.Font.GothamMedium, TextSize = 12,
                ClearTextOnFocus = false, Parent = r,
            }, { corner(6), boxStroke })

            box.Focused:Connect(function()
                tween(boxStroke, 0.2, { Transparency = 0, Thickness = 1.8 })
            end)
            box.FocusLost:Connect(function()
                tween(boxStroke, 0.3, { Transparency = 0.6, Thickness = 1 })
                if o.Callback then task.spawn(o.Callback, box.Text) end
            end)

            local obj = {}
            function obj:Get() return box.Text end
            function obj:Set(v) box.Text = tostring(v) end
            return obj
        end

        function Page:Button(o)
            local stroke = new("UIStroke", { Color = Theme.Blue, Thickness = 1, Transparency = 0.5 })
            local b = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder(),
                BackgroundColor3 = Theme.Item, Text = o.Name, TextColor3 = Theme.Text,
                Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = false, Parent = currentParent,
            }, { corner(8), stroke })

            pressFx(b)
            b.MouseEnter:Connect(function()
                tween(b, 0.15, { BackgroundColor3 = Theme.ItemHi })
                tween(stroke, 0.15, { Transparency = 0.1 })
            end)
            b.MouseLeave:Connect(function()
                tween(b, 0.22, { BackgroundColor3 = Theme.Item })
                tween(stroke, 0.22, { Transparency = 0.5 })
            end)
            b.MouseButton1Click:Connect(function()
                tween(b, 0.08, { BackgroundColor3 = Theme.Blue })
                task.delay(0.1, function()
                    if b.Parent then tween(b, 0.3, { BackgroundColor3 = Theme.ItemHi }) end
                end)
                if o.Callback then task.spawn(o.Callback) end
            end)
        end

        -- Button row (Apply | Reset)
        function Page:Buttons(list)
            local r = new("Frame", {
                Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder(),
                BackgroundTransparency = 1, Parent = currentParent,
            }, {
                new("UIListLayout", {
                    FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5),
                    SortOrder = Enum.SortOrder.LayoutOrder,
                }),
            })

            local n = #list
            local gap = math.ceil(5 * (n - 1) / n)
            for i, o in ipairs(list) do
                local baseTr = o.Accent and 0.2 or 0.5
                local stroke = new("UIStroke", {
                    Color = o.Accent and Theme.Cyan or Theme.Blue, Thickness = 1, Transparency = baseTr,
                })
                local b = new("TextButton", {
                    Size = UDim2.new(1 / n, -gap, 1, 0), LayoutOrder = i,
                    BackgroundColor3 = Theme.Item, Text = o.Name, TextColor3 = Theme.Text,
                    Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = false, Parent = r,
                }, { corner(8), stroke })

                pressFx(b)
                b.MouseEnter:Connect(function()
                    tween(b, 0.15, { BackgroundColor3 = Theme.ItemHi })
                    tween(stroke, 0.15, { Transparency = 0 })
                end)
                b.MouseLeave:Connect(function()
                    tween(b, 0.22, { BackgroundColor3 = Theme.Item })
                    tween(stroke, 0.22, { Transparency = baseTr })
                end)
                b.MouseButton1Click:Connect(function()
                    tween(b, 0.08, { BackgroundColor3 = Theme.Blue })
                    task.delay(0.1, function()
                        if b.Parent then tween(b, 0.3, { BackgroundColor3 = Theme.ItemHi }) end
                    end)
                    if o.Callback then task.spawn(o.Callback) end
                end)
            end
        end

        -- Select (opens side panel)
        function Page:Select(o)
            local r = row(30)
            rowLabel(r, o.Name, 150)

            local sStroke = new("UIStroke", { Color = Theme.Cyan, Thickness = 1, Transparency = 0.5 })
            local btn = new("TextButton", {
                Size = UDim2.fromOffset(140, 22), Position = UDim2.new(1, -150, 0.5, -11),
                BackgroundColor3 = Theme.Bg, Text = "", AutoButtonColor = false, Parent = r,
            }, { corner(6), sStroke })

            local val = new("TextLabel", {
                Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 8, 0, 0),
                BackgroundTransparency = 1, Text = tostring(o.Get() or "-"),
                TextColor3 = Theme.Cyan, Font = Enum.Font.GothamMedium, TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn,
            })
            local arrow = new("TextLabel", {
                Size = UDim2.fromOffset(16, 22), Position = UDim2.new(1, -18, 0, 0),
                BackgroundTransparency = 1, Text = ">", TextColor3 = Theme.Sub,
                Font = Enum.Font.GothamBold, TextSize = 12, Parent = btn,
            })

            pressFx(btn, val)
            btn.MouseEnter:Connect(function() tween(sStroke, 0.15, { Transparency = 0 }) end)
            btn.MouseLeave:Connect(function() tween(sStroke, 0.2, { Transparency = 0.5 }) end)

            -- sync label / arrow
            task.spawn(function()
                local lastOpen = false
                while val.Parent do
                    val.Text = tostring(o.Get() or "-")
                    local isOpen = panel ~= nil and panel:GetAttribute("Owner") == o.Name
                    if isOpen ~= lastOpen then
                        lastOpen = isOpen
                        tween(arrow, 0.3, { Rotation = isOpen and 180 or 0 }, EASE.Back, DIR.Out)
                    end
                    task.wait(0.12)
                end
            end)

            btn.MouseButton1Click:Connect(function()
                -- click again = close
                if panel and panel:GetAttribute("Owner") == o.Name then
                    Window:ClosePanel()
                    return
                end
                Window:OpenPanel(o.Title or o.Name, o.Options(), o.Get(), function(opt)
                    o.Set(opt)
                    val.Text = tostring(opt)
                end, o.Name)
            end)
        end

        -- Tabs 2290
        local tabs, active = {}, nil
        local switchId = 0
        local pillPlaced = false

        local function clearContent()
            for _, c in ipairs(content:GetChildren()) do
                if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
                    c:Destroy()
                end
            end
            order = 0
            currentParent = content
            content.CanvasPosition = Vector2.new(0, 0)
        end

        local function setTabStyle(t, on)
            tween(t.lbl, 0.25, { TextColor3 = on and WHITE or Theme.Sub })
            if on then
                tween(t.btn, 0.15, { BackgroundTransparency = 1 })
                local target = UDim2.fromOffset(8, 8 + (t.index - 1) * 34)
                if not pillPlaced then
                    pillPlaced = true
                    pill.Position = target
                    pill.Visible = true
                    tween(pill, 0.4, { BackgroundTransparency = 0 })
                else
                    tween(pill, 0.38, { Position = target }, EASE.Back, DIR.Out)
                end
            end
        end

        local function selectTab(t)
            if active == t then return end
            switchId = switchId + 1
            local myId = switchId
            Window:ClosePanel()

            local prev = active
            active = t
            if prev then setTabStyle(prev, false) end
            setTabStyle(t, true)

            -- old content out
            if prev then
                tween(contentWrap, 0.12, {
                    GroupTransparency = 1, Position = contentBase + UDim2.fromOffset(-12, 0),
                }, EASE.Quad, DIR.In)
                task.wait(0.13)
                if myId ~= switchId then return end
            end

            -- swap content
            activeTabName = t.name
            clearContent()
            contentWrap.GroupTransparency = 1
            contentWrap.Position = contentBase + UDim2.fromOffset(16, 0)
            t.build(Page)
            tween(contentWrap, 0.32, { GroupTransparency = 0, Position = contentBase }, EASE.Quint, DIR.Out)
        end

        function Window:AddTab(name, build)
            local idx = #tabs + 1
            local btn = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 28), LayoutOrder = idx,
                BackgroundColor3 = Theme.ItemHi, BackgroundTransparency = 1,
                Text = "", AutoButtonColor = false, Parent = sidebar,
            }, { corner(8) })
            local lbl = new("TextLabel", {
                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = name,
                TextColor3 = Theme.Sub, Font = Enum.Font.GothamMedium, TextSize = 12, Parent = btn,
            })
            local t = { name = name, index = idx, btn = btn, lbl = lbl, build = build }
            table.insert(tabs, t)

            pressFx(btn, lbl)
            btn.MouseEnter:Connect(function()
                if active ~= t then tween(btn, 0.15, { BackgroundTransparency = 0.5 }) end
            end)
            btn.MouseLeave:Connect(function()
                tween(btn, 0.2, { BackgroundTransparency = 1 })
            end)
            btn.MouseButton1Click:Connect(function() selectTab(t) end)
        end

        function Window:SelectTab(name)
            for _, t in ipairs(tabs) do
                if t.name == name then selectTab(t) return end
            end
        end

        -- rebuild tab
        function Window:Refresh()
            if active then
                clearContent()
                active.build(Page)
            end
        end

        -- Open / close
        local opened, openToken = true, 0

        local function setOpen(v)
            opened = v
            openToken = openToken + 1
            local myTok = openToken
            if v then
                main.Visible = true
                tween(mainScale, 0.45, { Scale = 1 }, EASE.Back, DIR.Out)
            else
                Window:ClosePanel()
                local tw = tween(mainScale, 0.2, { Scale = 0.8 }, EASE.Quad, DIR.In)
                tw.Completed:Connect(function()
                    if myTok == openToken then main.Visible = false end
                end)
            end
        end

        -- Open button
        local openStroke = glowStroke(1.5, 0.2)
        local openBtn = new("ImageButton", {
            Name = "OpenButton", Size = UDim2.fromOffset(42, 42),
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 33, 0, 91),
            BackgroundColor3 = Theme.Bg, BorderSizePixel = 0,
            Image = cfg.Logo or "", ScaleType = Enum.ScaleType.Fit,
            AutoButtonColor = false, Parent = gui,
        }, {
            corner(10), openStroke,
            new("UIAspectRatioConstraint", { AspectRatio = 1 }),
        })
        spin(openStroke, 4)

        local openScale = scaleFx(openBtn, 1.1, 0.88)
        local openDragged = makeDraggable(openBtn, openBtn, 6)

        openBtn.MouseButton1Click:Connect(function()
            if openDragged() then return end
            setOpen(not opened)
        end)

        -- hide gui
        btnMin.MouseButton1Click:Connect(function()
            setOpen(false)
        end)

        -- Warning
        local warn_ = nil   -- warn data
        local closing = false

        -- destroy all
        function Window:Destroy()
            if warn_ then
                pcall(function() warn_.gui:Destroy() end)
                warn_ = nil
            end
            for _, c in ipairs(conns) do
                pcall(function()
                    if typeof(c) == "RBXScriptConnection" then c:Disconnect() else c:Cancel() end
                end)
            end
            table.clear(conns)
            notifHolder = nil
            gui:Destroy()
        end

        local function closeWarning(cb)
            if not warn_ then
                if cb then cb() end
                return
            end
            local w = warn_
            warn_ = nil
            tween(w.scale, 0.2, { Scale = 0.85 }, EASE.Quad, DIR.In)
            tween(w.box, 0.2, { GroupTransparency = 1 }, EASE.Quad, DIR.In)
            tween(w.gui, 0.25, { BackgroundTransparency = 1 }, EASE.Quad, DIR.In)
            task.delay(0.27, function()
                pcall(function() w.gui:Destroy() end)
                if cb then cb() end
            end)
        end

        local function showWarning()
            if warn_ or closing then return end
            Window:ClosePanel()

            local RED = Color3.fromRGB(255, 85, 105)

            -- dark backdrop
            local backdrop = new("Frame", {
                Name = "Warning", Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
                BorderSizePixel = 0, Active = true, ZIndex = 100, Parent = gui,
            })

            local box = new("CanvasGroup", {
                Size = UDim2.fromOffset(300, 150), AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5), GroupTransparency = 1,
                BackgroundColor3 = Theme.Bg, BorderSizePixel = 0, Parent = backdrop,
            }, { corner(12), glowStroke(1.5, 0.2) })
            local boxScale = new("UIScale", { Scale = 0.8, Parent = box })

            warn_ = { gui = backdrop, box = box, scale = boxScale }

            new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 10),
                BackgroundTransparency = 1, Text = "Warning!", TextColor3 = RED,
                Font = Enum.Font.GothamBlack, TextSize = 18, Parent = box,
            })
            new("TextLabel", {
                Size = UDim2.new(1, -28, 0, 32), Position = UDim2.new(0, 14, 0, 40),
                BackgroundTransparency = 1,
                Text = "Script Akan Di Nonaktifkan dan Frame Akan Di Hapus!",
                TextColor3 = Theme.Text, Font = Enum.Font.GothamMedium, TextSize = 12,
                TextWrapped = true, Parent = box,
            })
            new("TextLabel", {
                Size = UDim2.new(1, -28, 0, 18), Position = UDim2.new(0, 14, 0, 76),
                BackgroundTransparency = 1,
                Text = "Apakah anda serius ingin menghapus script?",
                TextColor3 = Theme.Sub, Font = Enum.Font.Gotham, TextSize = 11,
                TextWrapped = true, Parent = box,
            })

            -- dialog button
            local function dlgBtn(text, x, color, strokeColor)
                local b = new("TextButton", {
                    Size = UDim2.fromOffset(128, 30), AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0, x + 64, 0, 123),
                    BackgroundColor3 = color, Text = text, TextColor3 = Theme.Text,
                    Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = true, Parent = box,
                }, { corner(8), new("UIStroke", { Color = strokeColor, Thickness = 1, Transparency = 0.3 }) })
                scaleFx(b, 1.06, 0.92)
                return b
            end

            local btnNo  = dlgBtn("No", 16, Theme.Item, Theme.Blue)
            local btnYes = dlgBtn("Yes", 156, Color3.fromRGB(190, 55, 75), RED)

            btnNo.MouseButton1Click:Connect(function() closeWarning() end)
            btnYes.MouseButton1Click:Connect(function()
                if closing then return end
                closing = true
                if cfg.OnClose then pcall(cfg.OnClose) end   -- stop all features
                closeWarning(function()
                    -- close anim
                    tween(mainScale, 0.28, { Scale = 0.6 }, EASE.Back, DIR.In)
                    tween(openScale, 0.28, { Scale = 0 }, EASE.Back, DIR.In)
                    task.delay(0.3, function() Window:Destroy() end)
                end)
            end)

            -- open anim
            tween(backdrop, 0.25, { BackgroundTransparency = 0.45 })
            tween(box, 0.25, { GroupTransparency = 0 })
            tween(boxScale, 0.4, { Scale = 1 }, EASE.Back, DIR.Out)
        end

        btnClose.MouseButton1Click:Connect(showWarning)

        if cfg.ToggleKey then
            track(UserInputService.InputBegan:Connect(function(i, gp)
                if gp then return end
                if i.KeyCode == cfg.ToggleKey then setOpen(not opened) end
            end))
        end

        -- intro anim
        openScale.Scale = 0
        tween(openScale, 0.55, { Scale = 1 }, EASE.Back, DIR.Out)
        setOpen(true)

        return Window
    end
end

-- 2 SCRIPT,CODE

--// Vars
local Remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local Event   = Remotes:WaitForChild("Fishing")

--// Bypass
local mt       = getrawmetatable(game)
local oldIndex = mt.__index
setreadonly(mt, false)

local FireServer = newcclosure(function(self, ...)
    return oldIndex(self, "FireServer")(self, ...)
end)

setreadonly(mt, true)

--// Teleport CFrame
local TeleportCFrames = {
    ["Gem Forest"]              = CFrame.new(-1198.71, 5.88, 347.01),
    ["Lost Desert"]             = CFrame.new(1283.47, 6.67, -84.57),
    ["Lovelight Island"]        = CFrame.new(-44.90, 8.30, -1125.96),
    ["Sky Island"]              = CFrame.new(-923.05, 180.14, 1273.08),
    ["Starter Island"]          = CFrame.new(343.59, 5.87, 1378.23),
    ["Absolute Spiral"]         = CFrame.new(604.28, 4.97, -541.68),
    ["Bigmon Skeleton Event"]   = CFrame.new(591.15, 4.08, 498.32),
    ["Tournament Area"]         = CFrame.new(-172.70, 4.89, -127.29),
}

--// Config
local Config = {
    InstantCompletedDelay = 3,   -- own delays
    InstantRepeatDelay    = 5,
    CompletedDelay      = 3,
    RepeatDelay         = 5,
    Luck                = 1,
    PerfectCast         = false,
    BaitName            = "Salt Bait",
    BaitEnchant         = "",
    RodName             = "",
    RodEnchant          = "",
    DeleteFishingAnim   = false,
    WalkOnWater         = false,
    Speed               = 16,
    JumpPower           = 50
}

local CHAR_ID = LP.Name

--// Animation
local FISHING_ANIM_ID = "rbxassetid://95332204205980"
local currentTrack    = nil

--// State
local running        = false
local loopThread     = nil
local waterPart      = nil
local waterConn      = nil
local isChanging     = false
local forceUIEnabled = false
local alive          = true   -- false = script off
local speedConn      = nil
local completedConn  = nil

--// ---------- ANIMATION ----------

local function getAnimator()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hum  = char:WaitForChild("Humanoid", 5)
    if not hum then return end
    return hum:WaitForChild("Animator", 5)
end

local function playFishingAnim()
    if Config.DeleteFishingAnim then return end
    local animator = getAnimator()
    if not animator then return end

    if currentTrack then
        pcall(function() currentTrack:Stop() end)
        currentTrack = nil
    end

    local anim = Instance.new("Animation")
    anim.AnimationId = FISHING_ANIM_ID

    local ok, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)

    if ok and track then
        track.Priority = Enum.AnimationPriority.Action
        track.Looped   = false
        track:Play()
        currentTrack = track
    end
end

local function stopFishingAnim()
    if currentTrack then
        pcall(function() currentTrack:Stop() end)
        currentTrack = nil
    end
end

--// ---------- DETECTOR ----------

local function parseSelection(raw)
    if type(raw) == "table" then return raw
    elseif type(raw) == "string" and raw ~= "" then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(raw)
        end)
        if ok and type(decoded) == "table" then return decoded end
    end
    return nil
end

local function detectSelection()
    local bobber = parseSelection(LP:GetAttribute("SelectedBobber"))
    local rod    = parseSelection(LP:GetAttribute("SelectedRod"))

    if bobber then
        Config.BaitName    = bobber.Name    or Config.BaitName
        Config.BaitEnchant = bobber.Enchant or ""
    end
    if rod then
        Config.RodName    = rod.Name    or Config.RodName
        Config.RodEnchant = rod.Enchant or ""
    end

    return bobber, rod
end

detectSelection()

--// ---------- HELPER ----------

local function getRodParts()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local rod = char:WaitForChild("Rod", 5)
    if not rod then return end
    local beam = rod:WaitForChild("Beam", 5)
    local rope = rod:WaitForChild("Rope", 5)
    if not beam or not rope then return end
    return beam, rope
end

--// ---------- FORCE FISHING UI ----------

local function enableFishingUI()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end

    local frontGui = pg:FindFirstChild("FrontGUI")
    if frontGui then
        local fp = frontGui:FindFirstChild("FrameParent")
        if fp then
            local ff = fp:FindFirstChild("FrameFishing")
            if ff then
                local btn = ff:FindFirstChild("BtnFishing")
                if btn then btn.Visible = true end
            end
        end
    end

    local fishingGui = pg:FindFirstChild("FishingGUI")
    if fishingGui then
        fishingGui.Enabled = true

        local fp2 = fishingGui:FindFirstChild("FrameParent")
        if fp2 then
            local frameCatch = fp2:FindFirstChild("FrameCatch")
            if frameCatch then
                local bar = frameCatch:FindFirstChild("Bar")
                if bar then bar.Size = UDim2.new(1, 0, 1, 0) end
            end

            local frameLuck = fp2:FindFirstChild("FrameLuck")
            if frameLuck then
                local bar = frameLuck:FindFirstChild("Bar")
                if bar then
                    bar.Size = Config.PerfectCast and UDim2.new(1, 0, 1, 0) or UDim2.new(0.33, 0, 1, 0)
                end

                local textLabel = frameLuck:FindFirstChild("TextLabel")
                if textLabel then
                    local luckStr = "Luck: x" .. tostring(Config.Luck)
                    if textLabel.Text ~= luckStr then
                        textLabel.Text = luckStr
                    end
                end
            end
        end
    end
end

local function disableFishingUI()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end

    local frontGui = pg:FindFirstChild("FrontGUI")
    if frontGui then
        local fp = frontGui:FindFirstChild("FrameParent")
        if fp then
            local ff = fp:FindFirstChild("FrameFishing")
            if ff then
                local btn = ff:FindFirstChild("BtnFishing")
                if btn then btn.Visible = false end
            end
        end
    end

    local fishingGui = pg:FindFirstChild("FishingGUI")
    if fishingGui then
        fishingGui.Enabled = false
    end
end

local function setForceUI(state)
    forceUIEnabled = state
    if state then
        enableFishingUI()
    else
        disableFishingUI()
    end
end

task.spawn(function()
    while alive and task.wait(0.1) do
        if forceUIEnabled then
            pcall(enableFishingUI)
        end
    end
end)

task.spawn(function()
    local completed = Remotes:WaitForChild("Completed", 5)
    if not completed or not completed:IsA("RemoteEvent") then
        return
    end
    completedConn = completed.OnClientEvent:Connect(function()
        if forceUIEnabled then
            setForceUI(false)
        end
    end)
end)

--// ---------- FISHING CYCLE ----------

local function fishingCycle()
    local beam, rope = getRodParts()
    if not beam or not rope then return end

    detectSelection()

    setForceUI(true)

    playFishingAnim()

    FireServer(Event, "Throw", {
        character   = CHAR_ID,
        beam        = beam,
        rope        = rope,
        currentLuck = Config.Luck,
        bobberName  = { Name = Config.BaitName, Enchant = Config.BaitEnchant },
        isWater     = true
    })

    task.wait(Config.CompletedDelay)

    FireServer(Event, "Catch", {
        getFish   = true,
        character = CHAR_ID
    })

    stopFishingAnim()

    local t0 = tick()
    while forceUIEnabled and (tick() - t0) < 2 do
        task.wait(0.1)
    end
    if forceUIEnabled then
        setForceUI(false)
    end
end

local function setFishing(Value)
    if Value then
        if running then return end
        running = true
        loopThread = task.spawn(function()
            while running do
                local ok, err = pcall(fishingCycle)
                if not ok then warn("[Fishing] Error: " .. tostring(err)) end
                task.wait(Config.RepeatDelay)
            end
        end)
    else
        running = false
        if loopThread then
            pcall(task.cancel, loopThread)
            loopThread = nil
        end
        stopFishingAnim()
        setForceUI(false)
    end
end

--// ---------- INSTANT FISHING ----------
-- Throw > wait > Catch, loop

local instantRunning = false
local instantThread  = nil

-- find nil instance
local function GetNil(Name, DebugId)
    if not getnilinstances then return nil end
    for _, Object in ipairs(getnilinstances()) do
        if Object.Name == Name and (not DebugId or Object:GetDebugId() == DebugId) then
            return Object
        end
    end
end

-- beam / rope, fallback nil
local function getInstantParts()
    local char = LP.Character
    local rod  = char and char:FindFirstChild("Rod")
    local beam = rod and rod:FindFirstChild("Beam")
    local rope = rod and rod:FindFirstChild("Rope")
    if beam and rope then return beam, rope end
    return GetNil("Beam"), GetNil("Rope")
end

local function instantCycle()
    local beam, rope = getInstantParts()
    if not beam or not rope then
        return false
    end

    detectSelection()

    FireServer(Event, "Throw", {
        character   = CHAR_ID,
        beam        = beam,
        rope        = rope,
        currentLuck = Config.Luck,
        bobberName  = { Name = Config.BaitName, Enchant = Config.BaitEnchant },
        isWater     = true
    })

    task.wait(Config.InstantCompletedDelay)

    FireServer(Event, "Catch", {
        getFish   = true,
        character = CHAR_ID
    })

    return true
end

local function setInstantFishing(Value)
    if Value then
        if instantRunning then return end
        instantRunning = true
        instantThread = task.spawn(function()
            while instantRunning do
                local ok, res = pcall(instantCycle)
                if not ok then
                    warn("[Instant Fishing] Error: " .. tostring(res))
                elseif res == false then
                    warn("[Instant Fishing] Beam/Rope not found (rod not equipped?)")
                    task.wait(1)
                end
                task.wait(Config.InstantRepeatDelay)
            end
        end)
    else
        instantRunning = false
        if instantThread then
            pcall(task.cancel, instantThread)
            instantThread = nil
        end
    end
end

--// ---------- WALK ON WATER ----------

local function enableWalkOnWater()
    if waterPart then return end

    waterPart = Instance.new("Part")
    waterPart.Name = "WaterWalkPart"
    waterPart.Anchored = true
    waterPart.CanCollide = false
    waterPart.CanQuery = false
    waterPart.CanTouch = false
    waterPart.Size = Vector3.new(8, 1, 8)
    waterPart.Transparency = 1
    waterPart.Material = Enum.Material.SmoothPlastic
    waterPart.Parent = workspace

    waterConn = RunService.RenderStepped:Connect(function()
        if not Config.WalkOnWater then
            if waterPart then waterPart.CanCollide = false end
            return
        end

        local char = LP.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {char, waterPart}
        params.IgnoreWater = false

        local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -200, 0), params)

        if not hit or hit.Material ~= Enum.Material.Water then
            waterPart.CanCollide = false
            return
        end

        waterPart.CFrame = CFrame.new(hrp.Position.X, hit.Position.Y + 1, hrp.Position.Z)

        local distToWater = hrp.Position.Y - hit.Position.Y
        local inRange = distToWater >= -3 and distToWater <= 8
        waterPart.CanCollide = inRange
    end)
end

local function disableWalkOnWater()
    if waterConn then
        waterConn:Disconnect()
        waterConn = nil
    end
    if waterPart then
        waterPart:Destroy()
        waterPart = nil
    end
end

--// ---------- SPEED & JUMP ----------

local function applySpeedJump()
    local char = LP.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    hum.WalkSpeed    = Config.Speed
    hum.UseJumpPower = true
    hum.JumpPower    = Config.JumpPower
end

speedConn = RunService.Heartbeat:Connect(function()
    applySpeedJump()
end)

--// ---------- ROD MODELS CHANGER (PLAYER ONLY) ----------

local function getRodModelNames()
    local rodModels = ReplicatedFirst:FindFirstChild("RodModels")
    if not rodModels then return {} end

    local list = {}
    for _, child in ipairs(rodModels:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") then
            table.insert(list, child.Name)
        end
    end
    table.sort(list)
    return list
end

local function getRodOnBack_Player()
    local char = LP.Character
    if not char then return nil end
    return char:FindFirstChild("RodOnBack")
end

local function updateSelectedRodAttribute(rodName, enchant)
    local data = { Name = rodName, Enchant = enchant or "" }
    local ok, json = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if not ok then return false end

    return pcall(function()
        LP:SetAttribute("SelectedRod", json)
    end)
end

local function changeRodModelCore(rodName, targetType)
    if isChanging then return false, "Already changing, wait a bit" end
    isChanging = true

    local rodModels = ReplicatedFirst:FindFirstChild("RodModels")
    if not rodModels then isChanging = false; return false, "RodModels not found" end

    local selectedRod = rodModels:FindFirstChild(rodName)
    if not selectedRod then isChanging = false; return false, "Rod '" .. rodName .. "' not found" end

    local handle = selectedRod:FindFirstChild("Handle")
    if not handle then isChanging = false; return false, "Handle not found" end

    local rodOnBack, targetLabel
    if targetType == "player" then
        rodOnBack = getRodOnBack_Player()
        targetLabel = "Character.RodOnBack"
    else
        isChanging = false; return false, "Target invalid"
    end

    if not rodOnBack then
        isChanging = false; return false, "RodOnBack not found in " .. targetLabel
    end

    local rodEnchant = ""
    local rd = parseSelection(LP:GetAttribute("SelectedRod"))
    if rd and rd.Enchant then rodEnchant = rd.Enchant end
    updateSelectedRodAttribute(rodName, rodEnchant)

    task.wait(0.15)

    for _, child in ipairs(rodOnBack:GetChildren()) do
        pcall(function() child:Destroy() end)
    end

    local movedCount = 0
    for _, child in ipairs(handle:GetChildren()) do
        if child.Name ~= "Handle" then
            local ok, clone = pcall(function() return child:Clone() end)
            if ok and clone then
                clone.Parent = rodOnBack
                movedCount = movedCount + 1
            end
        end
    end

    task.wait(0.5)
    isChanging = false

    return true, string.format("[%s] Rod '%s' (%d items)", targetLabel, rodName, movedCount)
end

--// State rod changer
local rodModelNames = getRodModelNames()
local userOverride  = false

local function getSelectedRodName()
    local rodData = parseSelection(LP:GetAttribute("SelectedRod"))
    if rodData and rodData.Name then
        for _, n in ipairs(rodModelNames) do
            if n == rodData.Name then return rodData.Name end
        end
    end
    return nil
end

local selectedRodModel_Player = getSelectedRodName() or rodModelNames[1] or ""

-- auto detect rod
task.spawn(function()
    while alive and task.wait(1) do
        pcall(function()
            if userOverride or isChanging then return end
            local selName = getSelectedRodName()
            if selName then
                selectedRodModel_Player = selName
                Config.RodName = selName
            end
        end)
    end
end)

--// ---------- TELEPORT ----------

local islandList = {}
for name, _ in pairs(TeleportCFrames) do
    table.insert(islandList, name)
end
table.sort(islandList)

local selectedIsland = islandList[1]

local function teleportToIsland()
    local target = TeleportCFrames[selectedIsland]
    if not target then return false end
    local char = LP.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    hrp.CFrame = target
    return true
end

-- 3 FULL GUI SELECTION

local Window = UI:CreateWindow({
    Name      = "ReigaX",
    Logo      = "rbxassetid://82294263086838",  -- title + open button logo
    ToggleKey = Enum.KeyCode.K,  -- hide/show (PC)
    OnClose   = function()
        alive = false
        setInstantFishing(false)          -- instant off
        setFishing(false)                 -- fast off
        Config.WalkOnWater = false
        disableWalkOnWater()
        Config.DeleteFishingAnim = false
        Config.PerfectCast = false
        Config.Luck = 1
        Config.Speed     = 16
        Config.JumpPower = 50
        applySpeedJump()                  -- back to default
        if speedConn then speedConn:Disconnect(); speedConn = nil end
        if completedConn then completedConn:Disconnect(); completedConn = nil end
    end,
})

--// ---------- TAB: FISHING ----------
Window:AddTab("Fishing", function(P)
    --// Cast Settings
    P:Section("Cast Settings")

    P:Toggle({
        Name = "Perfect Cast (Luck x3)",
        Value = Config.PerfectCast,
        Callback = function(Value)
            Config.PerfectCast = Value
            Config.Luck = Value and 3 or 1
            UI:Notify({
                Title = "Perfect Cast",
                Content = Value and "Perfect Cast (Luck x3) ON" or "Perfect Cast OFF (Luck x1)",
                Duration = 3,
            })
        end
    })

    --// Fast Fishing
    P:Section("Fast Fishing")

    P:Input({
        Name = "Completed Delay",
        Value = tostring(Config.CompletedDelay),
        Placeholder = "ex: 3",
        Callback = function(Text)
            local num = tonumber(Text)
            if num and num >= 0 then Config.CompletedDelay = num
            else UI:Notify({ Title = "Fast Fishing", Content = "Completed Delay must be a number!", Duration = 3 }) end
        end
    })

    P:Input({
        Name = "Repeat Delay",
        Value = tostring(Config.RepeatDelay),
        Placeholder = "ex: 5",
        Callback = function(Text)
            local num = tonumber(Text)
            if num and num >= 0 then Config.RepeatDelay = num
            else UI:Notify({ Title = "Fast Fishing", Content = "Repeat Delay must be a number!", Duration = 3 }) end
        end
    })

    P:Toggle({
        Name = "Start Fast Fishing",
        Value = running,
        Callback = function(Value)
            setFishing(Value)
            UI:Notify({ Title = "Fast Fishing", Content = Value and "Fast fishing ON" or "Fast fishing OFF", Duration = 3 })
            -- can't run together
            if Value and instantRunning then
                setInstantFishing(false)
                Window:Refresh()
                UI:Notify({ Title = "Fast Fishing", Content = "Instant Fishing turned off (can't run together)", Duration = 3 })
            end
        end
    })

    --// Instant Fishing
    P:Section("Instant Fishing")

    P:Input({
        Name = "Completed Delay",
        Value = tostring(Config.InstantCompletedDelay),
        Placeholder = "ex: 3",
        Callback = function(Text)
            local num = tonumber(Text)
            if num and num >= 0 then Config.InstantCompletedDelay = num
            else UI:Notify({ Title = "Instant Fishing", Content = "Completed Delay must be a number!", Duration = 3 }) end
        end
    })

    P:Input({
        Name = "Repeat Delay",
        Value = tostring(Config.InstantRepeatDelay),
        Placeholder = "ex: 5",
        Callback = function(Text)
            local num = tonumber(Text)
            if num and num >= 0 then Config.InstantRepeatDelay = num
            else UI:Notify({ Title = "Instant Fishing", Content = "Repeat Delay must be a number!", Duration = 3 }) end
        end
    })

    P:Toggle({
        Name = "Start Instant Fishing",
        Value = instantRunning,
        Callback = function(Value)
            setInstantFishing(Value)
            UI:Notify({ Title = "Instant Fishing", Content = Value and "Instant fishing ON" or "Instant fishing OFF", Duration = 3 })
            -- can't run together
            if Value and running then
                setFishing(false)
                Window:Refresh()
                UI:Notify({ Title = "Instant Fishing", Content = "Fast Fishing turned off (can't run together)", Duration = 3 })
            end
        end
    })
end)

--// ---------- TAB: TELEPORT ----------
Window:AddTab("Teleport", function(P)
    P:Section("Island")

    P:Select({
        Name    = "Select Island",
        Title   = "Select Island",
        Options = function() return islandList end,
        Get     = function() return selectedIsland end,
        Set     = function(v) selectedIsland = v end,
    })

    P:Button({
        Name = "Teleport",
        Callback = function()
            if teleportToIsland() then
                UI:Notify({ Title = "Teleport", Content = "Teleport to " .. tostring(selectedIsland), Duration = 3 })
            end
        end
    })
end)

--// ---------- TAB: MISC ----------
Window:AddTab("Misc", function(P)
    P:Section("Animation")

    P:Toggle({
        Name = "Delete Fishing Animation",
        Value = Config.DeleteFishingAnim,
        Callback = function(Value)
            Config.DeleteFishingAnim = Value
            if Value then stopFishingAnim() end
        end
    })

    P:Section("Movement")

    P:Toggle({
        Name = "Walk On Water",
        Value = Config.WalkOnWater,
        Callback = function(Value)
            Config.WalkOnWater = Value
            if Value then enableWalkOnWater() else disableWalkOnWater() end
        end
    })

    P:Section("Character")

    local speedBox = P:Input({
        Name = "Speed (def: 16)",
        Value = tostring(Config.Speed),
        Placeholder = "16",
    })
    P:Buttons({
        { Name = "Apply", Accent = true, Callback = function()
            local num = tonumber(speedBox:Get())
            if num and num > 0 then
                Config.Speed = num
                applySpeedJump()
                UI:Notify({ Title = "Speed", Content = "Speed set to " .. num, Duration = 2 })
            else
                UI:Notify({ Title = "Speed", Content = "Speed must be a number above 0!", Duration = 3 })
            end
        end },
        { Name = "Reset", Callback = function()
            Config.Speed = 16
            speedBox:Set("16")
            applySpeedJump()
            UI:Notify({ Title = "Speed", Content = "Speed reset to 16", Duration = 2 })
        end },
    })

    local jumpBox = P:Input({
        Name = "Jump Power (def: 50)",
        Value = tostring(Config.JumpPower),
        Placeholder = "50",
    })
    P:Buttons({
        { Name = "Apply", Accent = true, Callback = function()
            local num = tonumber(jumpBox:Get())
            if num and num > 0 then
                Config.JumpPower = num
                applySpeedJump()
                UI:Notify({ Title = "Jump Power", Content = "Jump Power set to " .. num, Duration = 2 })
            else
                UI:Notify({ Title = "Jump Power", Content = "Jump Power must be a number above 0!", Duration = 3 })
            end
        end },
        { Name = "Reset", Callback = function()
            Config.JumpPower = 50
            jumpBox:Set("50")
            applySpeedJump()
            UI:Notify({ Title = "Jump Power", Content = "Jump Power reset to 50", Duration = 2 })
        end },
    })

    P:Section("Rod Changer")

    P:Select({
        Name    = "Rod Models",
        Title   = "Rod Models",
        Options = function() return rodModelNames end,
        Get     = function() return selectedRodModel_Player end,
        Set     = function(v)
            selectedRodModel_Player = v
            Config.RodName = v
            userOverride = true
        end,
    })

    P:Button({
        Name = "Change Rod Models",
        Callback = function()
            if not selectedRodModel_Player or selectedRodModel_Player == "" then return end
            local ok, msg = changeRodModelCore(selectedRodModel_Player, "player")
            UI:Notify({ Title = "Rod Changer", Content = msg, Duration = 4 })
            task.wait(2)
            userOverride = false
        end
    })

    P:Button({
        Name = "Refresh Rod List",
        Callback = function()
            rodModelNames = getRodModelNames()
            userOverride = false

            local currentSel = getSelectedRodName()
            if currentSel then selectedRodModel_Player = currentSel end
            UI:Notify({ Title = "Rod Changer", Content = "Rod list refreshed (" .. #rodModelNames .. ")", Duration = 3 })
        end
    })
end)

Window:SelectTab("Fishing")
