-- ============================================================
--  GALAXY HUB | Main Script
--  Brand  : MrGalaxyDeveloper
--  Version: 1.0.0
--  Toggle : Right Shift key  |  or click the 🌌 button
-- ============================================================

-- ──────────────────────────────────────────
-- SERVICES
-- ──────────────────────────────────────────
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ──────────────────────────────────────────
-- CONFIGURATION  (edit here if needed)
-- ──────────────────────────────────────────
local CONFIG = {
    Version   = "1.0.0",
    Brand     = "MrGalaxyDeveloper",
    ToggleKey = Enum.KeyCode.RightShift,

    Colors = {
        BG          = Color3.fromRGB(10,  10,  25),
        Panel       = Color3.fromRGB(18,  18,  42),
        PanelLight  = Color3.fromRGB(28,  22,  58),
        Accent      = Color3.fromRGB(118, 38,  198),
        AccentLight = Color3.fromRGB(160, 90,  240),
        Border      = Color3.fromRGB(65,  35,  110),
        Text        = Color3.fromRGB(232, 222, 255),
        TextDim     = Color3.fromRGB(130, 110, 170),
        ToggleOff   = Color3.fromRGB(38,  33,  62),
        Green       = Color3.fromRGB(72,  200, 120),
        Yellow      = Color3.fromRGB(210, 170, 50),
        Red         = Color3.fromRGB(220, 75,  75),
    },
}

-- ──────────────────────────────────────────
-- STATE  (runtime flags & caches)
-- ──────────────────────────────────────────
local State = {
    MenuOpen         = false,
    BoosterEnabled   = false,
    CurrentMode      = "Balanced",   -- "Balanced" | "UltraLow"
    OriginalSettings = {},
    FPS              = 0,
    -- Particle original rates stored here so we can restore accurately
    ParticleCache    = {},
}

-- ──────────────────────────────────────────
-- UTILITY FUNCTIONS
-- ──────────────────────────────────────────

-- Shorthand tween helper
local function Tween(obj, props, t, style, dir)
    local info = TweenInfo.new(
        t     or 0.25,
        style or Enum.EasingStyle.Quart,
        dir   or Enum.EasingDirection.Out
    )
    TweenService:Create(obj, info, props):Play()
end

-- Quick instance factory
local function New(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        inst[k] = v
    end
    if parent then inst.Parent = parent end
    return inst
end

-- ──────────────────────────────────────────
-- SAVE ORIGINAL GAME SETTINGS
-- Called once at startup before any changes.
-- ──────────────────────────────────────────
local function SaveOriginals()
    State.OriginalSettings = {
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd        = Lighting.FogEnd,
        Brightness    = Lighting.Brightness,
        QualityLevel  = settings().Rendering.QualityLevel,
        Effects       = {},   -- PostEffect / Atmosphere enabled states
    }

    for _, fx in ipairs(Lighting:GetChildren()) do
        if fx:IsA("PostEffect") or fx:IsA("Atmosphere") or fx:IsA("Sky") then
            State.OriginalSettings.Effects[fx] = {
                enabled = (fx:FindFirstChild("Enabled") ~= nil)
                    and fx.Enabled or true
            }
        end
    end

    -- Cache every particle emitter's original Rate
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ParticleEmitter") then
            State.ParticleCache[obj] = obj.Rate
        end
    end
end

-- ──────────────────────────────────────────
-- FPS BOOSTER  ─  BALANCED MODE
-- Goal: noticeable FPS gain without killing
--       the game's visual identity.
-- ──────────────────────────────────────────
local function ApplyBalanced()
    -- Shadows are the biggest GPU drain, safe to remove
    Lighting.GlobalShadows = false

    -- Only kill blur & DOF — keep color grading, bloom, etc.
    for _, fx in ipairs(Lighting:GetChildren()) do
        if fx:IsA("DepthOfFieldEffect") or fx:IsA("BlurEffect") then
            fx.Enabled = false
        end
    end

    -- Reduce particle density to 35% — still visible, much cheaper
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ParticleEmitter") then
            if not State.ParticleCache[obj] then
                State.ParticleCache[obj] = obj.Rate   -- cache late spawns
            end
            obj.Rate = State.ParticleCache[obj] * 0.35
        elseif obj:IsA("Trail") then
            obj.Enabled = false
        end
    end

    -- Quality Level 5 — good middle ground
    settings().Rendering.QualityLevel = Enum.QualityLevel.Level05
end

-- ──────────────────────────────────────────
-- FPS BOOSTER  ─  ULTRA LOW (POTATO) MODE
-- Goal: squeeze every last frame.
-- ──────────────────────────────────────────
local function ApplyUltraLow()
    Lighting.GlobalShadows = false
    Lighting.FogEnd        = 100000   -- stops fog from rendering

    -- Kill every post-processing effect and atmosphere
    for _, fx in ipairs(Lighting:GetChildren()) do
        if fx:IsA("PostEffect") or fx:IsA("Atmosphere") then
            fx.Enabled = false
        end
    end

    -- Kill all visual fluff in workspace
    for _, obj in ipairs(workspace:GetDescendants()) do
        local cls = obj.ClassName
        if cls == "ParticleEmitter" or cls == "Trail"
        or cls == "Smoke"          or cls == "Fire"
        or cls == "Sparkles" then
            obj.Enabled = false
        elseif cls == "SelectionBox" or cls == "SelectionSphere" then
            obj.Visible = false
        end
    end

    -- Minimum render quality
    settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
end

-- ──────────────────────────────────────────
-- RESTORE DEFAULTS
-- Reverts every change made by the booster.
-- ──────────────────────────────────────────
local function RestoreDefaults()
    local orig = State.OriginalSettings
    if not orig.QualityLevel then return end   -- nothing was saved yet

    -- Restore lighting
    Lighting.GlobalShadows = orig.GlobalShadows
    Lighting.FogEnd        = orig.FogEnd
    Lighting.Brightness    = orig.Brightness

    -- Re-enable effects
    for fx, data in pairs(orig.Effects) do
        if fx and fx.Parent and fx:FindFirstProperty("Enabled") then
            fx.Enabled = data.enabled
        end
    end

    -- Restore particle rates & trails
    for _, obj in ipairs(workspace:GetDescendants()) do
        local cls = obj.ClassName
        if cls == "ParticleEmitter" then
            obj.Enabled = true
            local cached = State.ParticleCache[obj]
            if cached then obj.Rate = cached end
        elseif cls == "Trail" or cls == "Smoke"
            or cls == "Fire" or cls == "Sparkles" then
            obj.Enabled = true
        elseif cls == "SelectionBox" or cls == "SelectionSphere" then
            obj.Visible = true
        end
    end

    -- Restore render quality
    settings().Rendering.QualityLevel = orig.QualityLevel
end

-- ──────────────────────────────────────────
-- FPS COUNTER  (rolling 20-frame average)
-- ──────────────────────────────────────────
local fpsBuffer = {}
local lastTick  = tick()

local function UpdateFPS()
    local now   = tick()
    local delta = now - lastTick
    lastTick    = now

    if delta > 0 then
        table.insert(fpsBuffer, 1 / delta)
        if #fpsBuffer > 20 then table.remove(fpsBuffer, 1) end

        local sum = 0
        for _, v in ipairs(fpsBuffer) do sum += v end
        State.FPS = math.floor(sum / #fpsBuffer)
    end
end

-- ──────────────────────────────────────────
-- UI  CONSTRUCTION
-- ──────────────────────────────────────────
local function BuildUI()
    -- Clean up any previous instance
    local old = PlayerGui:FindFirstChild("GalaxyHub")
    if old then old:Destroy() end

    local C = CONFIG.Colors   -- shorthand

    -- Root ScreenGui
    local Root = New("ScreenGui", {
        Name            = "GalaxyHub",
        ResetOnSpawn    = false,
        ZIndexBehavior  = Enum.ZIndexBehavior.Sibling,
        DisplayOrder    = 999,
    }, PlayerGui)

    -- ── Floating toggle button ──────────────────────────────
    local FloatBtn = New("ImageButton", {
        Name                = "FloatBtn",
        Size                = UDim2.new(0, 50, 0, 50),
        Position            = UDim2.new(0, 20, 0.5, -25),
        BackgroundColor3    = C.Accent,
        BorderSizePixel     = 0,
        ZIndex              = 20,
        AutoButtonColor     = false,
    }, Root)
    New("UICorner",  { CornerRadius = UDim.new(1, 0) }, FloatBtn)
    New("UIStroke",  { Color = C.AccentLight, Thickness = 2 }, FloatBtn)
    New("UIGradient",{
        Color    = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(160, 70, 240)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(80,  20, 160)),
        }),
        Rotation = 135,
    }, FloatBtn)
    New("TextLabel", {
        Size                = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                = "🌌",
        TextSize            = 24,
        Font                = Enum.Font.GothamBold,
        ZIndex              = 21,
    }, FloatBtn)

    -- FloatBtn drag
    do
        local drag, ds, sp = false, nil, nil
        FloatBtn.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                drag = true; ds = i.Position; sp = FloatBtn.Position
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if drag and (i.UserInputType == Enum.UserInputType.MouseMovement
                      or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - ds
                FloatBtn.Position = UDim2.new(
                    sp.X.Scale, sp.X.Offset + d.X,
                    sp.Y.Scale, sp.Y.Offset + d.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                drag = false
            end
        end)
    end

    -- ── Main panel ─────────────────────────────────────────
    local Panel = New("Frame", {
        Name                = "Panel",
        Size                = UDim2.new(0, 305, 0, 400),
        Position            = UDim2.new(0, 82, 0.5, -200),
        BackgroundColor3    = C.BG,
        BorderSizePixel     = 0,
        ClipsDescendants    = true,
        Visible             = false,
        ZIndex              = 5,
    }, Root)
    New("UICorner",  { CornerRadius = UDim.new(0, 14) }, Panel)
    New("UIStroke",  { Color = C.Border, Thickness = 1.5 }, Panel)
    New("UIGradient",{
        Color    = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 10, 32)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(8,   8, 20)),
        }),
        Rotation = 130,
    }, Panel)

    -- ── Title bar ──────────────────────────────────────────
    local TitleBar = New("Frame", {
        Name             = "TitleBar",
        Size             = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = C.Panel,
        BorderSizePixel  = 0,
        ZIndex           = 6,
    }, Panel)
    New("UICorner",  { CornerRadius = UDim.new(0, 14) }, TitleBar)
    -- Patch the bottom two corners (UICorner rounds all four)
    New("Frame", {
        Size             = UDim2.new(1, 0, 0.5, 0),
        Position         = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = C.Panel,
        BorderSizePixel  = 0,
        ZIndex           = 6,
    }, TitleBar)
    New("UIGradient",{
        Color    = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   Color3.fromRGB(90,  25, 165)),
            ColorSequenceKeypoint.new(0.6, Color3.fromRGB(35,  18,  80)),
            ColorSequenceKeypoint.new(1,   Color3.fromRGB(15,  10,  40)),
        }),
        Rotation = 90,
    }, TitleBar)
    New("TextLabel", {
        Size                = UDim2.new(1, -55, 1, 0),
        Position            = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Text                = "🌌  Galaxy Hub",
        TextColor3          = C.Text,
        TextSize            = 15,
        Font                = Enum.Font.GothamBold,
        TextXAlignment      = Enum.TextXAlignment.Left,
        ZIndex              = 7,
    }, TitleBar)
    New("TextLabel", {
        Size                = UDim2.new(0, 50, 1, 0),
        Position            = UDim2.new(1, -55, 0, 0),
        BackgroundTransparency = 1,
        Text                = "v"..CONFIG.Version,
        TextColor3          = C.TextDim,
        TextSize            = 10,
        Font                = Enum.Font.Gotham,
        ZIndex              = 7,
    }, TitleBar)

    -- Title bar drag (moves the whole panel)
    do
        local drag, ds, sp = false, nil, nil
        TitleBar.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                drag = true; ds = i.Position; sp = Panel.Position
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
                local d = i.Position - ds
                Panel.Position = UDim2.new(
                    sp.X.Scale, sp.X.Offset + d.X,
                    sp.Y.Scale, sp.Y.Offset + d.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
        end)
    end

    -- ── Scrollable content area ────────────────────────────
    local Scroll = New("ScrollingFrame", {
        Name                    = "Scroll",
        Size                    = UDim2.new(1, 0, 1, -57),
        Position                = UDim2.new(0, 0, 0, 57),
        BackgroundTransparency  = 1,
        ScrollBarThickness      = 3,
        ScrollBarImageColor3    = C.Accent,
        BorderSizePixel         = 0,
        CanvasSize              = UDim2.new(0, 0, 0, 0),
        ZIndex                  = 6,
    }, Panel)
    local Layout = New("UIListLayout", {
        Padding                 = UDim.new(0, 7),
        HorizontalAlignment     = Enum.HorizontalAlignment.Center,
        SortOrder               = Enum.SortOrder.LayoutOrder,
    }, Scroll)
    New("UIPadding", {
        PaddingTop    = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft   = UDim.new(0, 12),
        PaddingRight  = UDim.new(0, 12),
    }, Scroll)
    Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        Scroll.CanvasSize = UDim2.new(0, 0, 0, Layout.AbsoluteContentSize.Y + 22)
    end)

    -- ────────────────────────────────────────────────────────
    -- WIDGET BUILDERS  (inner helpers used below)
    -- ────────────────────────────────────────────────────────

    -- Section header label
    local function SectionLabel(text, order)
        New("TextLabel", {
            Size                = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            Text                = text,
            TextColor3          = C.AccentLight,
            TextSize            = 10,
            Font                = Enum.Font.GothamBold,
            TextXAlignment      = Enum.TextXAlignment.Left,
            LayoutOrder         = order,
            ZIndex              = 7,
        }, Scroll)
    end

    -- Toggle row — returns a table with SetState(bool)
    local function ToggleRow(label, order, onChange)
        local row = New("Frame", {
            Size             = UDim2.new(1, 0, 0, 38),
            BackgroundColor3 = C.Panel,
            BorderSizePixel  = 0,
            LayoutOrder      = order,
            ZIndex           = 7,
        }, Scroll)
        New("UICorner",  { CornerRadius = UDim.new(0, 9) }, row)

        New("TextLabel", {
            Size                = UDim2.new(1, -62, 1, 0),
            Position            = UDim2.new(0, 13, 0, 0),
            BackgroundTransparency = 1,
            Text                = label,
            TextColor3          = C.Text,
            TextSize            = 13,
            Font                = Enum.Font.Gotham,
            TextXAlignment      = Enum.TextXAlignment.Left,
            ZIndex              = 8,
        }, row)

        local track = New("Frame", {
            Size             = UDim2.new(0, 42, 0, 22),
            Position         = UDim2.new(1, -50, 0.5, -11),
            BackgroundColor3 = C.ToggleOff,
            BorderSizePixel  = 0,
            ZIndex           = 8,
        }, row)
        New("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

        local knob = New("Frame", {
            Size             = UDim2.new(0, 18, 0, 18),
            Position         = UDim2.new(0, 2, 0.5, -9),
            BackgroundColor3 = Color3.fromRGB(210, 200, 230),
            BorderSizePixel  = 0,
            ZIndex           = 9,
        }, track)
        New("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

        local on = false
        local function SetState(v)
            on = v
            Tween(track, { BackgroundColor3 = on and C.Accent or C.ToggleOff }, 0.2)
            Tween(knob,  { Position = on
                and UDim2.new(0, 22, 0.5, -9)
                or  UDim2.new(0,  2, 0.5, -9) }, 0.2)
        end

        -- Invisible click button covering entire row
        local btn = New("TextButton", {
            Size                = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text                = "",
            ZIndex              = 10,
        }, row)
        btn.MouseButton1Click:Connect(function()
            SetState(not on)
            if onChange then onChange(on) end
        end)

        return { SetState = SetState, Get = function() return on end }
    end

    -- Generic button
    local function Btn(text, order, color, onClick)
        local b = New("TextButton", {
            Size             = UDim2.new(1, 0, 0, 36),
            BackgroundColor3 = color,
            BorderSizePixel  = 0,
            Text             = text,
            TextColor3       = C.Text,
            TextSize         = 13,
            Font             = Enum.Font.GothamBold,
            LayoutOrder      = order,
            ZIndex           = 7,
            AutoButtonColor  = false,
        }, Scroll)
        New("UICorner", { CornerRadius = UDim.new(0, 9) }, b)
        New("UIStroke", { Color = C.Border, Thickness = 1 }, b)
        b.MouseButton1Click:Connect(onClick)
        -- Subtle hover
        b.MouseEnter:Connect(function()
            Tween(b, { BackgroundColor3 = color:Lerp(Color3.new(1,1,1), 0.1) }, 0.15)
        end)
        b.MouseLeave:Connect(function()
            Tween(b, { BackgroundColor3 = color }, 0.2)
        end)
        return b
    end

    -- Thin divider line
    local function Divider(order)
        New("Frame", {
            Size             = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = C.Border,
            BackgroundTransparency = 0.4,
            BorderSizePixel  = 0,
            LayoutOrder      = order,
            ZIndex           = 7,
        }, Scroll)
    end

    -- ────────────────────────────────────────────────────────
    -- SECTION: PERFORMANCE  (FPS counter)
    -- ────────────────────────────────────────────────────────
    SectionLabel("📊  PERFORMANCE", 1)

    local fpsRow = New("Frame", {
        Size             = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = C.Panel,
        BorderSizePixel  = 0,
        LayoutOrder      = 2,
        ZIndex           = 7,
    }, Scroll)
    New("UICorner", { CornerRadius = UDim.new(0, 9) }, fpsRow)
    New("UIGradient",{
        Color    = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 18, 55)),
            ColorSequenceKeypoint.new(1, C.Panel),
        }),
        Rotation = 0,
    }, fpsRow)
    New("TextLabel", {
        Size                = UDim2.new(0.55, 0, 1, 0),
        Position            = UDim2.new(0, 13, 0, 0),
        BackgroundTransparency = 1,
        Text                = "Live FPS",
        TextColor3          = C.TextDim,
        TextSize            = 12,
        Font                = Enum.Font.Gotham,
        TextXAlignment      = Enum.TextXAlignment.Left,
        ZIndex              = 8,
    }, fpsRow)

    local FPSLabel = New("TextLabel", {
        Size                = UDim2.new(0.45, -10, 1, 0),
        Position            = UDim2.new(0.55, 0, 0, 0),
        BackgroundTransparency = 1,
        Text                = "-- FPS",
        TextColor3          = C.Green,
        TextSize            = 17,
        Font                = Enum.Font.GothamBold,
        TextXAlignment      = Enum.TextXAlignment.Right,
        ZIndex              = 8,
    }, fpsRow)

    -- ────────────────────────────────────────────────────────
    -- SECTION: FPS BOOSTER
    -- ────────────────────────────────────────────────────────
    Divider(3)
    SectionLabel("⚡  FPS BOOSTER", 4)

    -- Master enable toggle
    local boosterToggle = ToggleRow("Enable FPS Booster", 5, function(isOn)
        State.BoosterEnabled = isOn
        if isOn then
            if State.CurrentMode == "Balanced" then
                ApplyBalanced()
            else
                ApplyUltraLow()
            end
        else
            RestoreDefaults()
        end
    end)

    -- Mode selector row
    local modeContainer = New("Frame", {
        Size             = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        LayoutOrder      = 6,
        ZIndex           = 7,
    }, Scroll)
    New("UIListLayout", {
        FillDirection         = Enum.FillDirection.Horizontal,
        HorizontalAlignment   = Enum.HorizontalAlignment.Center,
        VerticalAlignment     = Enum.VerticalAlignment.Center,
        Padding               = UDim.new(0, 8),
    }, modeContainer)

    local BtnBalanced = New("TextButton", {
        Size             = UDim2.new(0, 132, 0, 36),
        BackgroundColor3 = C.Accent,   -- default active
        BorderSizePixel  = 0,
        Text             = "⚖  Balanced",
        TextColor3       = C.Text,
        TextSize         = 12,
        Font             = Enum.Font.GothamBold,
        ZIndex           = 8,
        AutoButtonColor  = false,
    }, modeContainer)
    New("UICorner", { CornerRadius = UDim.new(0, 9) }, BtnBalanced)
    New("UIStroke", { Color = C.AccentLight, Thickness = 1,
        Name = "ActiveStroke" }, BtnBalanced)

    local BtnPotato = New("TextButton", {
        Size             = UDim2.new(0, 132, 0, 36),
        BackgroundColor3 = C.PanelLight,
        BorderSizePixel  = 0,
        Text             = "🥔  Potato",
        TextColor3       = C.TextDim,
        TextSize         = 12,
        Font             = Enum.Font.GothamBold,
        ZIndex           = 8,
        AutoButtonColor  = false,
    }, modeContainer)
    New("UICorner", { CornerRadius = UDim.new(0, 9) }, BtnPotato)

    -- Mode description pill
    local ModeDesc = New("TextLabel", {
        Size             = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = Color3.fromRGB(18, 14, 42),
        BorderSizePixel  = 0,
        Text             = "Keeps visuals — disables shadows, blur & DOF",
        TextColor3       = C.TextDim,
        TextSize         = 10,
        Font             = Enum.Font.Gotham,
        LayoutOrder      = 7,
        ZIndex           = 7,
    }, Scroll)
    New("UICorner", { CornerRadius = UDim.new(0, 6) }, ModeDesc)
    New("UIPadding", {
        PaddingLeft  = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, ModeDesc)

    -- Mode switch logic
    local function SwitchMode(mode)
        State.CurrentMode = mode

        if mode == "Balanced" then
            Tween(BtnBalanced, { BackgroundColor3 = C.Accent }, 0.2)
            BtnBalanced.TextColor3 = C.Text
            Tween(BtnPotato,   { BackgroundColor3 = C.PanelLight }, 0.2)
            BtnPotato.TextColor3 = C.TextDim
            ModeDesc.Text = "Keeps visuals — disables shadows, blur & DOF"

            local stroke = BtnBalanced:FindFirstChild("ActiveStroke")
            if not stroke then
                New("UIStroke", { Color = C.AccentLight, Thickness = 1,
                    Name = "ActiveStroke" }, BtnBalanced)
            end
            local ps = BtnPotato:FindFirstChild("ActiveStroke")
            if ps then ps:Destroy() end
        else
            Tween(BtnPotato,   { BackgroundColor3 = C.Accent }, 0.2)
            BtnPotato.TextColor3 = C.Text
            Tween(BtnBalanced, { BackgroundColor3 = C.PanelLight }, 0.2)
            BtnBalanced.TextColor3 = C.TextDim
            ModeDesc.Text = "Maximum FPS — kills all particles, effects & fog"

            local stroke = BtnPotato:FindFirstChild("ActiveStroke")
            if not stroke then
                New("UIStroke", { Color = C.AccentLight, Thickness = 1,
                    Name = "ActiveStroke" }, BtnPotato)
            end
            local bs = BtnBalanced:FindFirstChild("ActiveStroke")
            if bs then bs:Destroy() end
        end

        -- Re-apply booster with new mode if it's currently active
        if State.BoosterEnabled then
            if mode == "Balanced" then
                ApplyBalanced()
            else
                ApplyUltraLow()
            end
        end
    end

    BtnBalanced.MouseButton1Click:Connect(function() SwitchMode("Balanced") end)
    BtnPotato.MouseButton1Click:Connect(function()   SwitchMode("UltraLow") end)

    -- ────────────────────────────────────────────────────────
    -- SECTION: SETTINGS
    -- ────────────────────────────────────────────────────────
    Divider(8)
    SectionLabel("🔧  SETTINGS", 9)

    Btn("↺   Restore All Defaults", 10, Color3.fromRGB(35, 22, 65), function()
        RestoreDefaults()
        State.BoosterEnabled = false
        boosterToggle.SetState(false)
        SwitchMode("Balanced")
    end)

    -- ── Brand footer ───────────────────────────────────────
    New("TextLabel", {
        Size                = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Text                = "by MrGalaxyDeveloper",
        TextColor3          = C.TextDim,
        TextSize            = 10,
        Font                = Enum.Font.Gotham,
        LayoutOrder         = 11,
        ZIndex              = 7,
    }, Scroll)

    -- ────────────────────────────────────────────────────────
    -- MENU TOGGLE  (FloatBtn click + hotkey)
    -- ────────────────────────────────────────────────────────
    local function ToggleMenu()
        State.MenuOpen = not State.MenuOpen

        if State.MenuOpen then
            Panel.Position = UDim2.new(
                Panel.Position.X.Scale, Panel.Position.X.Offset - 18,
                Panel.Position.Y.Scale, Panel.Position.Y.Offset)
            Panel.Visible = true
            Panel.BackgroundTransparency = 1
            Tween(Panel, {
                BackgroundTransparency = 0,
                Position = UDim2.new(
                    Panel.Position.X.Scale, Panel.Position.X.Offset + 18,
                    Panel.Position.Y.Scale, Panel.Position.Y.Offset),
            }, 0.28)
            Tween(FloatBtn, { BackgroundColor3 = C.AccentLight }, 0.2)
        else
            Tween(Panel, { BackgroundTransparency = 1 }, 0.2)
            task.delay(0.21, function() Panel.Visible = false end)
            Tween(FloatBtn, { BackgroundColor3 = C.Accent }, 0.2)
        end
    end

    FloatBtn.MouseButton1Click:Connect(ToggleMenu)

    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == CONFIG.ToggleKey then
            ToggleMenu()
        end
    end)

    -- ────────────────────────────────────────────────────────
    -- FPS COUNTER  (updates every frame)
    -- ────────────────────────────────────────────────────────
    RunService.RenderStepped:Connect(function()
        UpdateFPS()
        FPSLabel.Text = State.FPS .. " FPS"
        -- Colour-code by performance level
        if State.FPS >= 55 then
            FPSLabel.TextColor3 = C.Green
        elseif State.FPS >= 30 then
            FPSLabel.TextColor3 = C.Yellow
        else
            FPSLabel.TextColor3 = C.Red
        end
    end)
end

-- ──────────────────────────────────────────
-- BOOT
-- ──────────────────────────────────────────
SaveOriginals()  -- must run BEFORE any changes
BuildUI()

print(string.format(
    "[GalaxyHub v%s] Loaded  |  by %s  |  Press %s to toggle",
    CONFIG.Version, CONFIG.Brand, tostring(CONFIG.ToggleKey)
))
