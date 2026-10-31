-- INIT
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local cloneref = cloneref or function(instance)
    return instance
end

-- SERVICES
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local TweenService = cloneref(game:GetService("TweenService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- MODULES
local CameraOk, CameraResult = pcall(require, ReplicatedStorage.Modules.Client.Controllers.CameraController)
local CameraController = CameraOk and CameraResult or nil
local GunOk, GunResult = pcall(require, ReplicatedStorage.Modules.Client.Controllers.GunController)
local GunController = GunOk and GunResult or nil
local HostilityOk, HostilityResult = pcall(require, ReplicatedStorage.Modules.Shared.Combat.Hostility)
local Hostility = HostilityOk and HostilityResult or nil
-- The game's own touch controller knows exactly when the on-screen FIRE button is held, which
-- is the only reliable "we are shooting" signal on a phone.
local MobileOk, MobileResult = pcall(require, ReplicatedStorage.Modules.Client.Controllers.MobileInputController)
local MobileInputController = MobileOk and MobileResult or nil

-- CONFIG
Config = Config or {
    ["ESP"] = true,
    ["Boxes"] = true,
    ["Health"] = true,
    ["Distance"] = true,
    ["Team Check"] = false,
    ["Max Distance"] = 1000,
    ["Aimbot"] = false,
    ["Aim Part"] = "Head",
    ["FOV Radius"] = 40,
    ["Aim Smooth"] = 40,
    ["Aim Assist Angle"] = 55,
    ["Aim Muzzle Comp"] = true,
    ["Menu"] = true,
    ["Menu Key"] = Enum.KeyCode.RightShift,
}

-- 40 px is the default because the UI targets phones, where a 220 px circle covers most of
-- the screen. Existing configs are migrated once so the smaller default actually applies.
if Config["Config Version"] ~= 3 then
    Config["Config Version"] = 3
    Config["FOV Radius"] = 40
    Config["Aim Smooth"] = 40
    Config["Aim Assist Angle"] = 55
end

local Func = {}
local Ranges = { 250, 500, 1000, 2500 }
local FOVOptions = { 20, 30, 40, 60, 90, 120, 160, 220 }
local SmoothOptions = { 0, 20, 40, 55, 60, 70, 80, 90, 95 }
local PartNames = {
    Head = true,
    UpperTorso = true,
    LowerTorso = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
}
local RigPrefix = "MercHitboxes_"
local PanelWidth = 292
local PanelHeight = 592
-- Smallest the panel is allowed to shrink to on a phone. Below this the labels stop being
-- legible, so the panel keeps this scale and the content scrolls instead.
local MinUIScale = 0.75
local ViewportMargin = 24
local Palette = {
    Background = Color3.fromRGB(8, 13, 15),
    Surface = Color3.fromRGB(13, 21, 24),
    SurfaceLight = Color3.fromRGB(20, 31, 35),
    Stroke = Color3.fromRGB(42, 63, 66),
    Text = Color3.fromRGB(232, 244, 236),
    Muted = Color3.fromRGB(119, 146, 142),
    Accent = Color3.fromRGB(190, 255, 64),
    Cyan = Color3.fromRGB(75, 224, 208),
    Danger = Color3.fromRGB(255, 77, 94),
}

Func.UI = {
    Switches = {},
    Parts = {},
}
Func.Entries = {}
Func.Connections = {}
Func.Touches = {}
Func.TeamCache = {}
Func.LocalTeam = nil
Func.VisibleCount = 0
Func.AimTarget = nil
Func.AimLook = nil
Func.MouseFiring = false
Func.FireAimPoint = nil
Func.RenderBound = false
Func.Running = true

if GunController then
    if type(_G.PrismFireDirectionHook) == "function" then
        GunController.GetFireDirectionUnspread = _G.PrismFireDirectionHook
        _G.PrismFireDirectionHook = nil
    end
    local OriginalFireDirection = GunController.GetFireDirectionUnspread
    if type(OriginalFireDirection) == "function" then
        _G.PrismFireDirectionHook = OriginalFireDirection
        GunController.GetFireDirectionUnspread = function(self, ...)
            local Point = Func.FireAimPoint
            if Point and Config["Aim Muzzle Comp"] ~= false then
                local Muzzle = Func:GetMuzzleCFrame()
                if Muzzle then
                    local Direction = Point - Muzzle.Position
                    if Direction.Magnitude > 0.5 then
                        return Direction.Unit
                    end
                end
            end
            return OriginalFireDirection(self, ...)
        end
    end
end

if type(_G.PrismESPStop) == "function" then
    pcall(_G.PrismESPStop)
end

-- FUNCTIONS
function Func:Connect(Signal, Callback)
    local Connection = Signal:Connect(Callback)
    table.insert(Func.Connections, Connection)
    return Connection
end

function Func:CreateLabel(Parent, Name, Text, Position, Size, Font, TextSize, Color, XAlignment)
    local Label = Instance.new("TextLabel")
    Label.Name = Name
    Label.Text = Text
    Label.Position = Position
    Label.Size = Size
    Label.BackgroundTransparency = 1
    Label.Font = Font
    Label.TextSize = TextSize
    Label.TextColor3 = Color
    Label.TextXAlignment = XAlignment or Enum.TextXAlignment.Left
    Label.TextYAlignment = Enum.TextYAlignment.Center
    Label.TextStrokeTransparency = 0.82
    Label.TextStrokeColor3 = Color3.new(0, 0, 0)
    Label.ZIndex = Parent.ZIndex + 1
    Label.Parent = Parent
    return Label
end

function Func:CreateCard(Parent, Name, Position, Size, ZIndex)
    local Card = Instance.new("Frame")
    Card.Name = Name
    Card.Position = Position
    Card.Size = Size
    Card.BackgroundColor3 = Palette.Surface
    Card.BackgroundTransparency = 0.04
    Card.BorderSizePixel = 0
    Card.ZIndex = ZIndex
    Card.Parent = Parent
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Card
    local Stroke = Instance.new("UIStroke")
    Stroke.Color = Palette.Stroke
    Stroke.Transparency = 0.54
    Stroke.Thickness = 1
    Stroke.Parent = Card
    return Card
end

function Func:IsRigDead(Model)
    if not Model then
        return true
    end
    if Model:GetAttribute("Dead") == true then
        return true
    end
    local Humanoid = Model:FindFirstChildOfClass("Humanoid")
    return Humanoid ~= nil and Humanoid.Health <= 0
end

function Func:CollectRigs()
    local Folder = workspace:FindFirstChild("MercPlayers")
    local Rigs = {}
    if not Folder then
        return Rigs
    end
    for _, Model in ipairs(Folder:GetChildren()) do
        if Model:IsA("Model") and string.sub(Model.Name, 1, #RigPrefix) == RigPrefix then
            local UserId = Model:GetAttribute("OwnerUserId")
            if typeof(UserId) == "number" then
                local Player = Players:GetPlayerByUserId(UserId)
                if Player and Player ~= LocalPlayer then
                    local Existing = Rigs[Player]
                    if not Existing or (Func:IsRigDead(Existing) and not Func:IsRigDead(Model)) then
                        Rigs[Player] = Model
                    end
                end
            end
        end
    end
    return Rigs
end

function Func:GetBounds(Model)
    local Min = Vector3.new(math.huge, math.huge, math.huge)
    local Max = Vector3.new(-math.huge, -math.huge, -math.huge)
    for _, Part in ipairs(Model:GetChildren()) do
        if Part:IsA("BasePart") and PartNames[Part.Name] then
            local Half = Part.Size * 0.5
            local Orientation = Part.CFrame
            local Position = Part.Position
            local Extent = Vector3.new(
                math.abs(Orientation.RightVector.X) * Half.X + math.abs(Orientation.UpVector.X) * Half.Y + math.abs(Orientation.LookVector.X) * Half.Z,
                math.abs(Orientation.RightVector.Y) * Half.X + math.abs(Orientation.UpVector.Y) * Half.Y + math.abs(Orientation.LookVector.Y) * Half.Z,
                math.abs(Orientation.RightVector.Z) * Half.X + math.abs(Orientation.UpVector.Z) * Half.Y + math.abs(Orientation.LookVector.Z) * Half.Z
            )
            Min = Vector3.new(math.min(Min.X, Position.X - Extent.X), math.min(Min.Y, Position.Y - Extent.Y), math.min(Min.Z, Position.Z - Extent.Z))
            Max = Vector3.new(math.max(Max.X, Position.X + Extent.X), math.max(Max.Y, Position.Y + Extent.Y), math.max(Max.Z, Position.Z + Extent.Z))
        end
    end
    if Min.X == math.huge then
        return nil
    end
    return Min, Max
end

function Func:GetAimPoint(Model)
    if not Model or Func:IsRigDead(Model) then
        return nil
    end
    local Head = Model:FindFirstChild("Head")
    local UpperTorso = Model:FindFirstChild("UpperTorso")
    if not UpperTorso then
        return nil
    end
    if Config["Aim Part"] == "Head" then
        return Head and Head.Position or nil
    end
    if Config["Aim Part"] == "Neck" then
        return UpperTorso.Position + Vector3.new(0, UpperTorso.Size.Y * 0.4, 0)
    end
    return UpperTorso.Position
end

function Func:GetMuzzleCFrame()
    if not GunController then
        return nil
    end
    local MuzzleOk, Muzzle = pcall(function()
        return GunController:GetActiveProjectileMuzzleWorldCFrame()
    end)
    if MuzzleOk and typeof(Muzzle) == "CFrame" then
        return Muzzle
    end
    return nil
end

-- The camera the player sees is the yaw/pitch base plus bodycam, lean and recoil offsets.
-- Only the base can be written, so aim maths works from the base direction, never from the
-- final camera look (feeding that back would add the offsets again every frame).
function Func:GetBaseLook()
    local Active = CameraController and CameraController._active
    if typeof(Active) == "table" then
        local Pitch = Active._pitchCurrent or 0
        local Yaw = Active._yawCurrent or 0
        return CFrame.fromOrientation(Pitch, Yaw, 0).LookVector
    end
    local Camera = workspace.CurrentCamera
    if Camera then
        return Camera.CFrame.LookVector
    end
    return nil
end

-- Bullets leave along the barrel (the muzzle attachment's own LookVector), not along the
-- camera, so the camera is aimed straight at the target and the shot itself is redirected in
-- the fire-direction hook installed above. This keeps the crosshair on the target while the
-- impact still lands there.
function Func:ApplyLook(Look)
    if typeof(Look) ~= "Vector3" then
        return
    end
    local Magnitude = Look.Magnitude
    if Magnitude < 0.0001 then
        return
    end
    Look = Look / Magnitude
    local Yaw = math.atan2(-Look.X, -Look.Z)
    local Pitch = math.asin(math.clamp(Look.Y, -1, 1))
    local Active = CameraController and CameraController._active
    if typeof(Active) == "table" then
        -- The controller overwrites _yawTarget with _yawCurrent whenever mouse look is
        -- suppressed (cursor-free, freelook, menus), so writing the target alone is
        -- silently discarded. Both are written so the aim always lands.
        Active._yawTarget = Yaw
        Active._yawCurrent = Yaw
        Active._yawVel = 0
        Active._pitchTarget = Pitch
        Active._pitchCurrent = Pitch
        Active._pitchVel = 0
        Active._freelookYawTarget = 0
        Active._freelookPitchTarget = 0
        Active._freelookYawCurrent = 0
        Active._freelookPitchCurrent = 0
        return
    end
    local Camera = workspace.CurrentCamera
    if Camera then
        local Position = Camera.CFrame.Position
        Camera.CFrame = CFrame.lookAt(Position, Position + Look)
    end
end

function Func:RefreshSwitch(Key)
    local Switch = Func.UI.Switches[Key]
    if not Switch then
        return
    end
    local Enabled = Config[Key] == true
    local Goal = UDim2.fromOffset(Enabled and 18 or 2, 2)
    Switch.Track.BackgroundColor3 = Enabled and Color3.fromRGB(55, 80, 35) or Palette.SurfaceLight
    Switch.Knob.BackgroundColor3 = Enabled and Palette.Accent or Palette.Muted
    Switch.Label.TextColor3 = Enabled and Palette.Text or Palette.Muted
    if Switch.Tween then
        Switch.Tween:Cancel()
    end
    Switch.Tween = TweenService:Create(
        Switch.Knob,
        TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = Goal }
    )
    Switch.Tween:Play()
end

function Func:RefreshRange()
    if Func.UI.RangeValue then
        Func.UI.RangeValue.Text = string.format("%d m", Config["Max Distance"])
    end
end

function Func:RefreshFOV()
    if Func.UI.FOVValue then
        Func.UI.FOVValue.Text = string.format("%d px", Config["FOV Radius"])
    end
    if Func.UI.FOVCircle then
        local Radius = Config["FOV Radius"]
        Func.UI.FOVCircle.Size = UDim2.fromOffset(Radius * 2, Radius * 2)
    end
end

function Func:RefreshSmooth()
    if Func.UI.SmoothValue then
        Func.UI.SmoothValue.Text = string.format("SMOOTH %d%%", Config["Aim Smooth"])
    end
end

function Func:RefreshAimPart()
    for PartName, PartButton in pairs(Func.UI.Parts) do
        local Selected = Config["Aim Part"] == PartName
        PartButton.Button.BackgroundColor3 = Selected and Color3.fromRGB(55, 80, 35) or Palette.SurfaceLight
        PartButton.Button.TextColor3 = Selected and Palette.Accent or Palette.Muted
        PartButton.Stroke.Color = Selected and Palette.Accent or Palette.Stroke
        PartButton.Stroke.Transparency = Selected and 0.18 or 0.62
    end
end

function Func:CreatePartButton(Parent, PartName, Position)
    local Button = Instance.new("TextButton")
    Button.Name = PartName
    Button.Position = Position
    Button.Size = UDim2.fromOffset(76, 28)
    Button.BackgroundColor3 = Palette.SurfaceLight
    Button.BackgroundTransparency = 0.02
    Button.AutoButtonColor = false
    Button.Text = string.upper(PartName)
    Button.TextColor3 = Palette.Muted
    Button.Font = Enum.Font.Code
    Button.TextSize = 10
    Button.ZIndex = Parent.ZIndex + 2
    Button.Parent = Parent
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 5)
    Corner.Parent = Button
    local Stroke = Instance.new("UIStroke")
    Stroke.Color = Palette.Stroke
    Stroke.Transparency = 0.62
    Stroke.Thickness = 1
    Stroke.Parent = Button
    Func.UI.Parts[PartName] = {
        Button = Button,
        Stroke = Stroke,
    }
    Func:Connect(Button.Activated, function()
        Config["Aim Part"] = PartName
        Func:RefreshAimPart()
    end)
    return Button
end

function Func:RefreshStatus()
    if not Func.UI.Status then
        return
    end
    local Active = Config["ESP"] == true
    Func.UI.Status.Text = Active and "LIVE" or "IDLE"
    Func.UI.Status.TextColor3 = Active and Palette.Accent or Palette.Muted
    Func.UI.StatusDot.BackgroundColor3 = Active and Palette.Accent or Palette.Muted
    Func.UI.CountValue.Text = string.format("%02d", Func.VisibleCount)
    if workspace.CurrentCamera then
        local Viewport = workspace.CurrentCamera.ViewportSize
        Func.UI.ViewportValue.Text = string.format("%d x %d", Viewport.X, Viewport.Y)
    end
end

function Func:CreateSwitch(Parent, Key, Text, Order)
    local Row = Instance.new("TextButton")
    Row.Name = Key
    Row.Position = UDim2.fromOffset(4, 4 + (Order - 1) * 38)
    Row.Size = UDim2.fromOffset(256, 34)
    Row.BackgroundColor3 = Palette.SurfaceLight
    Row.BackgroundTransparency = 1
    Row.AutoButtonColor = false
    Row.Text = ""
    Row.ZIndex = Parent.ZIndex + 1
    Row.Parent = Parent
    local Label = Func:CreateLabel(
        Row,
        "Label",
        Text,
        UDim2.fromOffset(10, 0),
        UDim2.fromOffset(178, 34),
        Enum.Font.GothamBold,
        11,
        Palette.Text
    )
    local Track = Instance.new("Frame")
    Track.Name = "Track"
    Track.AnchorPoint = Vector2.new(1, 0.5)
    Track.Position = UDim2.new(1, -10, 0.5, 0)
    Track.Size = UDim2.fromOffset(32, 16)
    Track.BackgroundColor3 = Palette.SurfaceLight
    Track.BorderSizePixel = 0
    Track.ZIndex = Row.ZIndex + 1
    Track.Parent = Row
    local TrackCorner = Instance.new("UICorner")
    TrackCorner.CornerRadius = UDim.new(1, 0)
    TrackCorner.Parent = Track
    local Knob = Instance.new("Frame")
    Knob.Name = "Knob"
    Knob.Position = UDim2.fromOffset(2, 2)
    Knob.Size = UDim2.fromOffset(12, 12)
    Knob.BackgroundColor3 = Palette.Muted
    Knob.BorderSizePixel = 0
    Knob.ZIndex = Track.ZIndex + 1
    Knob.Parent = Track
    local KnobCorner = Instance.new("UICorner")
    KnobCorner.CornerRadius = UDim.new(1, 0)
    KnobCorner.Parent = Knob
    Func.UI.Switches[Key] = {
        Label = Label,
        Track = Track,
        Knob = Knob,
    }
    Func:Connect(Row.Activated, function()
        Config[Key] = not Config[Key]
        Func:RefreshSwitch(Key)
        if Key == "ESP" and not Config[Key] then
            Func:ClearEntries()
        end
        if Key == "Team Check" then
            table.clear(Func.TeamCache)
            Func.LocalTeam = LocalPlayer:GetAttribute("Team")
        end
        Func:RefreshStatus()
    end)
    return Row
end

function Func:BuildUI()
    local Existing = PlayerGui:FindFirstChild("PrismPlayerIntel")
    if Existing then
        Existing:Destroy()
    end
    local Gui = Instance.new("ScreenGui")
    Gui.Name = "PrismPlayerIntel"
    Gui.ResetOnSpawn = false
    -- The overlay is positioned in viewport pixels (WorldToViewportPoint), so the GUI must
    -- start at the viewport origin. Ignoring the inset would push everything 58 px up on a
    -- windowed client and knock the ESP boxes and the FOV circle off the crosshair.
    Gui.IgnoreGuiInset = false
    Gui.DisplayOrder = 999
    Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    -- The ScreenGui stays enabled so the ESP boxes and the FOV circle keep drawing while the
    -- menu itself is closed; only the panel is hidden.
    Gui.Enabled = true
    Gui.Parent = PlayerGui
    Func.UI.Gui = Gui
    local Overlay = Instance.new("Frame")
    Overlay.Name = "Overlay"
    Overlay.Size = UDim2.fromScale(1, 1)
    Overlay.BackgroundTransparency = 1
    Overlay.ZIndex = 10
    Overlay.Parent = Gui
    Func.UI.Overlay = Overlay
    local FOVCircle = Instance.new("Frame")
    FOVCircle.Name = "FOVCircle"
    FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    FOVCircle.Position = UDim2.fromScale(0.5, 0.5)
    FOVCircle.Size = UDim2.fromOffset(Config["FOV Radius"] * 2, Config["FOV Radius"] * 2)
    FOVCircle.BackgroundTransparency = 1
    FOVCircle.BorderSizePixel = 0
    FOVCircle.Visible = false
    FOVCircle.ZIndex = 15
    FOVCircle.Parent = Overlay
    local FOVCorner = Instance.new("UICorner")
    FOVCorner.CornerRadius = UDim.new(1, 0)
    FOVCorner.Parent = FOVCircle
    local FOVStroke = Instance.new("UIStroke")
    FOVStroke.Color = Palette.Cyan
    FOVStroke.Transparency = 0.42
    FOVStroke.Thickness = 1
    FOVStroke.Parent = FOVCircle
    local FOVDot = Instance.new("Frame")
    FOVDot.Name = "CenterDot"
    FOVDot.AnchorPoint = Vector2.new(0.5, 0.5)
    FOVDot.Position = UDim2.fromScale(0.5, 0.5)
    FOVDot.Size = UDim2.fromOffset(4, 4)
    FOVDot.BackgroundColor3 = Palette.Cyan
    FOVDot.BorderSizePixel = 0
    FOVDot.ZIndex = 16
    FOVDot.Parent = FOVCircle
    local FOVDotCorner = Instance.new("UICorner")
    FOVDotCorner.CornerRadius = UDim.new(1, 0)
    FOVDotCorner.Parent = FOVDot
    Func.UI.FOVCircle = FOVCircle
    Func.UI.FOVStroke = FOVStroke
    Func.UI.FOVDot = FOVDot
    local AimHint = Instance.new("TextLabel")
    AimHint.Name = "AimHint"
    AimHint.AnchorPoint = Vector2.new(0.5, 0)
    AimHint.Position = UDim2.new(0.5, 0, 0.5, Config["FOV Radius"] + 10)
    AimHint.Size = UDim2.fromOffset(240, 16)
    AimHint.BackgroundTransparency = 1
    AimHint.BorderSizePixel = 0
    AimHint.Font = Enum.Font.Code
    AimHint.TextSize = 12
    AimHint.TextColor3 = Palette.Cyan
    AimHint.TextStrokeTransparency = 0.45
    AimHint.Text = ""
    AimHint.Visible = false
    AimHint.ZIndex = 16
    AimHint.Parent = Overlay
    Func.UI.AimHint = AimHint
    local Panel = Instance.new("Frame")
    Panel.Name = "Panel"
    Panel.Position = UDim2.fromOffset(24, 16)
    Panel.Size = UDim2.fromOffset(PanelWidth, PanelHeight)
    Panel.BackgroundColor3 = Palette.Background
    Panel.BackgroundTransparency = 0.03
    Panel.BorderSizePixel = 0
    Panel.ClipsDescendants = false
    Panel.ZIndex = 100
    Panel.Visible = Config["Menu"] == true
    Panel.Parent = Gui
    Func.UI.Panel = Panel
    -- The panel is authored at a fixed 292x592 and scaled as a whole, so the layout never has
    -- to be rewritten per device. The ESP boxes and the FOV circle stay outside this scale
    -- because they are positioned in real viewport pixels.
    local PanelScale = Instance.new("UIScale")
    PanelScale.Scale = 1
    PanelScale.Parent = Panel
    Func.UI.PanelScale = PanelScale
    -- A phone has no RightShift, so touch devices get a small floating button for the menu.
    if UserInputService.TouchEnabled then
        local Toggle = Instance.new("TextButton")
        Toggle.Name = "MenuToggle"
        Toggle.AnchorPoint = Vector2.new(1, 0)
        Toggle.Position = UDim2.new(1, -10, 0, 10)
        Toggle.Size = UDim2.fromOffset(46, 30)
        Toggle.BackgroundColor3 = Palette.Surface
        Toggle.BackgroundTransparency = 0.2
        Toggle.AutoButtonColor = false
        Toggle.Text = "MENU"
        Toggle.TextColor3 = Palette.Accent
        Toggle.Font = Enum.Font.GothamBold
        Toggle.TextSize = 9
        Toggle.ZIndex = 300
        Toggle.Parent = Gui
        local ToggleCorner = Instance.new("UICorner")
        ToggleCorner.CornerRadius = UDim.new(0, 9)
        ToggleCorner.Parent = Toggle
        local ToggleStroke = Instance.new("UIStroke")
        ToggleStroke.Color = Palette.Stroke
        ToggleStroke.Thickness = 1
        ToggleStroke.Parent = Toggle
        Func:Connect(Toggle.Activated, function()
            Func:SetMenuVisible(not Config["Menu"])
        end)
        Func.UI.MenuToggle = Toggle
    end
    local PanelCorner = Instance.new("UICorner")
    PanelCorner.CornerRadius = UDim.new(0, 9)
    PanelCorner.Parent = Panel
    local PanelStroke = Instance.new("UIStroke")
    PanelStroke.Color = Palette.Stroke
    PanelStroke.Transparency = 0.18
    PanelStroke.Thickness = 1
    PanelStroke.Parent = Panel
    local PanelGradient = Instance.new("UIGradient")
    PanelGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 22, 25)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 11, 13)),
    })
    PanelGradient.Rotation = 90
    PanelGradient.Parent = Panel
    local AccentLine = Instance.new("Frame")
    AccentLine.Name = "AccentLine"
    AccentLine.Position = UDim2.fromOffset(0, 0)
    AccentLine.Size = UDim2.new(1, 0, 0, 2)
    AccentLine.BackgroundColor3 = Palette.Accent
    AccentLine.BorderSizePixel = 0
    AccentLine.ZIndex = 102
    AccentLine.Parent = Panel
    local AccentCorner = Instance.new("UICorner")
    AccentCorner.CornerRadius = UDim.new(0, 2)
    AccentCorner.Parent = AccentLine
    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.fromOffset(PanelWidth, 62)
    Header.BackgroundTransparency = 1
    Header.ZIndex = 101
    Header.Parent = Panel
    local DragArea = Instance.new("TextButton")
    DragArea.Name = "DragArea"
    DragArea.Size = UDim2.fromOffset(198, 62)
    DragArea.BackgroundTransparency = 1
    DragArea.AutoButtonColor = false
    DragArea.Text = ""
    DragArea.ZIndex = 102
    DragArea.Parent = Header
    Func.UI.DragArea = DragArea
    local Logo = Func:CreateLabel(
        Header,
        "Logo",
        "PRISM",
        UDim2.fromOffset(18, 10),
        UDim2.fromOffset(118, 24),
        Enum.Font.GothamBlack,
        18,
        Palette.Text
    )
    Logo.TextXAlignment = Enum.TextXAlignment.Left
    local Subtitle = Func:CreateLabel(
        Header,
        "Subtitle",
        "PLAYER INTELLIGENCE",
        UDim2.fromOffset(19, 34),
        UDim2.fromOffset(155, 14),
        Enum.Font.Code,
        9,
        Palette.Cyan
    )
    Subtitle.TextXAlignment = Enum.TextXAlignment.Left
    local StatusDot = Instance.new("Frame")
    StatusDot.Name = "StatusDot"
    StatusDot.AnchorPoint = Vector2.new(1, 0.5)
    StatusDot.Position = UDim2.fromOffset(213, 20)
    StatusDot.Size = UDim2.fromOffset(6, 6)
    StatusDot.BackgroundColor3 = Palette.Accent
    StatusDot.BorderSizePixel = 0
    StatusDot.ZIndex = 103
    StatusDot.Parent = Header
    local StatusDotCorner = Instance.new("UICorner")
    StatusDotCorner.CornerRadius = UDim.new(1, 0)
    StatusDotCorner.Parent = StatusDot
    local Status = Func:CreateLabel(
        Header,
        "Status",
        "LIVE",
        UDim2.fromOffset(220, 12),
        UDim2.fromOffset(46, 16),
        Enum.Font.Code,
        10,
        Palette.Accent
    )
    Status.TextXAlignment = Enum.TextXAlignment.Left
    Func.UI.Status = Status
    Func.UI.StatusDot = StatusDot
    local Minimize = Instance.new("TextButton")
    Minimize.Name = "Minimize"
    Minimize.AnchorPoint = Vector2.new(1, 0)
    Minimize.Position = UDim2.new(1, -14, 0, 15)
    Minimize.Size = UDim2.fromOffset(24, 24)
    Minimize.BackgroundColor3 = Palette.SurfaceLight
    Minimize.BackgroundTransparency = 0.05
    Minimize.AutoButtonColor = false
    Minimize.Text = "-"
    Minimize.TextColor3 = Palette.Muted
    Minimize.Font = Enum.Font.Code
    Minimize.TextSize = 16
    Minimize.ZIndex = 104
    Minimize.Parent = Header
    local MinimizeCorner = Instance.new("UICorner")
    MinimizeCorner.CornerRadius = UDim.new(0, 5)
    MinimizeCorner.Parent = Minimize
    Func.UI.Minimize = Minimize
    local HeaderLine = Instance.new("Frame")
    HeaderLine.Name = "HeaderLine"
    HeaderLine.Position = UDim2.fromOffset(14, 62)
    HeaderLine.Size = UDim2.new(1, -28, 0, 1)
    HeaderLine.BackgroundColor3 = Palette.Stroke
    HeaderLine.BackgroundTransparency = 0.36
    HeaderLine.BorderSizePixel = 0
    HeaderLine.ZIndex = 102
    HeaderLine.Parent = Panel
    local Content = Instance.new("ScrollingFrame")
    Content.Name = "Content"
    Content.Position = UDim2.fromOffset(0, 63)
    Content.Size = UDim2.fromOffset(PanelWidth, PanelHeight - 63)
    Content.CanvasSize = UDim2.fromOffset(PanelWidth, PanelHeight - 63)
    Content.ScrollingDirection = Enum.ScrollingDirection.Y
    Content.ScrollBarThickness = 3
    Content.ScrollBarImageColor3 = Palette.Stroke
    Content.ScrollBarImageTransparency = 0.2
    Content.ElasticBehavior = Enum.ElasticBehavior.Never
    Content.BackgroundTransparency = 1
    Content.BorderSizePixel = 0
    Content.ZIndex = 101
    Content.Parent = Panel
    Func.UI.Content = Content
    local SectionOne = Func:CreateLabel(
        Content,
        "SectionOne",
        "VISUAL LAYERS",
        UDim2.fromOffset(16, 12),
        UDim2.fromOffset(180, 16),
        Enum.Font.Code,
        9,
        Palette.Muted
    )
    SectionOne.TextXAlignment = Enum.TextXAlignment.Left
    local SwitchCard = Func:CreateCard(Content, "SwitchCard", UDim2.fromOffset(14, 34), UDim2.fromOffset(264, 160), 103)
    Func:CreateSwitch(SwitchCard, "ESP", "PLAYER ESP", 1)
    Func:CreateSwitch(SwitchCard, "Boxes", "BOUNDING BOX", 2)
    Func:CreateSwitch(SwitchCard, "Health", "HEALTH READOUT", 3)
    Func:CreateSwitch(SwitchCard, "Distance", "DISTANCE READOUT", 4)
    local SectionTwo = Func:CreateLabel(
        Content,
        "SectionTwo",
        "SCAN LIMIT",
        UDim2.fromOffset(16, 204),
        UDim2.fromOffset(180, 16),
        Enum.Font.Code,
        9,
        Palette.Muted
    )
    SectionTwo.TextXAlignment = Enum.TextXAlignment.Left
    local RangeCard = Func:CreateCard(Content, "RangeCard", UDim2.fromOffset(14, 226), UDim2.fromOffset(264, 58), 103)
    local RangeLabel = Func:CreateLabel(
        RangeCard,
        "RangeLabel",
        "DISTANCE CULL",
        UDim2.fromOffset(12, 8),
        UDim2.fromOffset(120, 16),
        Enum.Font.GothamBold,
        11,
        Palette.Text
    )
    RangeLabel.TextXAlignment = Enum.TextXAlignment.Left
    local RangeHint = Func:CreateLabel(
        RangeCard,
        "RangeHint",
        "CLICK TO CYCLE",
        UDim2.fromOffset(12, 31),
        UDim2.fromOffset(120, 14),
        Enum.Font.Code,
        8,
        Palette.Muted
    )
    RangeHint.TextXAlignment = Enum.TextXAlignment.Left
    local RangeButton = Instance.new("TextButton")
    RangeButton.Name = "RangeButton"
    RangeButton.AnchorPoint = Vector2.new(1, 0)
    RangeButton.Position = UDim2.new(1, -10, 0, 9)
    RangeButton.Size = UDim2.fromOffset(104, 40)
    RangeButton.BackgroundColor3 = Palette.SurfaceLight
    RangeButton.BackgroundTransparency = 0.02
    RangeButton.AutoButtonColor = false
    RangeButton.Text = ""
    RangeButton.ZIndex = 105
    RangeButton.Parent = RangeCard
    local RangeButtonCorner = Instance.new("UICorner")
    RangeButtonCorner.CornerRadius = UDim.new(0, 5)
    RangeButtonCorner.Parent = RangeButton
    local RangeButtonStroke = Instance.new("UIStroke")
    RangeButtonStroke.Color = Palette.Cyan
    RangeButtonStroke.Transparency = 0.65
    RangeButtonStroke.Thickness = 1
    RangeButtonStroke.Parent = RangeButton
    local RangeValue = Func:CreateLabel(
        RangeButton,
        "RangeValue",
        "1000 m",
        UDim2.fromScale(0, 0),
        UDim2.fromScale(1, 1),
        Enum.Font.Code,
        13,
        Palette.Accent,
        Enum.TextXAlignment.Center
    )
    Func.UI.RangeValue = RangeValue
    Func:Connect(RangeButton.Activated, function()
        local Current = Config["Max Distance"]
        local Found = false
        for Index, Value in ipairs(Ranges) do
            if Value == Current then
                Config["Max Distance"] = Ranges[(Index % #Ranges) + 1]
                Found = true
                break
            end
        end
        if not Found then
            Config["Max Distance"] = Ranges[3]
        end
        Func:RefreshRange()
    end)
    local SectionCombat = Func:CreateLabel(
        Content,
        "SectionCombat",
        "COMBAT MODULE",
        UDim2.fromOffset(16, 280),
        UDim2.fromOffset(180, 16),
        Enum.Font.Code,
        9,
        Palette.Muted
    )
    SectionCombat.TextXAlignment = Enum.TextXAlignment.Left
    local AimCard = Func:CreateCard(Content, "AimCard", UDim2.fromOffset(14, 302), UDim2.fromOffset(264, 136), 103)
    Func:CreateSwitch(AimCard, "Aimbot", "AIM BOT", 1)
    local LockLabel = Func:CreateLabel(
        AimCard,
        "LockLabel",
        "LOCK PART",
        UDim2.fromOffset(12, 42),
        UDim2.fromOffset(90, 14),
        Enum.Font.Code,
        8,
        Palette.Muted
    )
    Func:CreatePartButton(AimCard, "Head", UDim2.fromOffset(12, 58))
    Func:CreatePartButton(AimCard, "Neck", UDim2.fromOffset(94, 58))
    Func:CreatePartButton(AimCard, "Body", UDim2.fromOffset(176, 58))
    local FOVLabel = Func:CreateLabel(
        AimCard,
        "FOVLabel",
        "FOV RADIUS",
        UDim2.fromOffset(12, 92),
        UDim2.fromOffset(100, 16),
        Enum.Font.GothamBold,
        10,
        Palette.Text
    )
    local FOVButton = Instance.new("TextButton")
    FOVButton.Name = "FOVButton"
    FOVButton.AnchorPoint = Vector2.new(1, 0)
    FOVButton.Position = UDim2.new(1, -10, 0, 88)
    FOVButton.Size = UDim2.fromOffset(96, 30)
    FOVButton.BackgroundColor3 = Palette.SurfaceLight
    FOVButton.BackgroundTransparency = 0.02
    FOVButton.AutoButtonColor = false
    FOVButton.Text = ""
    FOVButton.ZIndex = AimCard.ZIndex + 2
    FOVButton.Parent = AimCard
    local FOVButtonCorner = Instance.new("UICorner")
    FOVButtonCorner.CornerRadius = UDim.new(0, 5)
    FOVButtonCorner.Parent = FOVButton
    local FOVButtonStroke = Instance.new("UIStroke")
    FOVButtonStroke.Color = Palette.Cyan
    FOVButtonStroke.Transparency = 0.65
    FOVButtonStroke.Thickness = 1
    FOVButtonStroke.Parent = FOVButton
    local FOVValue = Func:CreateLabel(
        FOVButton,
        "FOVValue",
        "40 px",
        UDim2.fromScale(0, 0),
        UDim2.fromScale(1, 1),
        Enum.Font.Code,
        11,
        Palette.Accent,
        Enum.TextXAlignment.Center
    )
    Func.UI.FOVValue = FOVValue
    local SmoothButton = Instance.new("TextButton")
    SmoothButton.Name = "SmoothButton"
    SmoothButton.Position = UDim2.fromOffset(12, 113)
    SmoothButton.Size = UDim2.fromOffset(140, 20)
    SmoothButton.BackgroundColor3 = Palette.SurfaceLight
    SmoothButton.BackgroundTransparency = 0.02
    SmoothButton.AutoButtonColor = false
    SmoothButton.Text = ""
    SmoothButton.ZIndex = AimCard.ZIndex + 2
    SmoothButton.Parent = AimCard
    local SmoothButtonCorner = Instance.new("UICorner")
    SmoothButtonCorner.CornerRadius = UDim.new(0, 5)
    SmoothButtonCorner.Parent = SmoothButton
    local SmoothButtonStroke = Instance.new("UIStroke")
    SmoothButtonStroke.Color = Palette.Cyan
    SmoothButtonStroke.Transparency = 0.65
    SmoothButtonStroke.Thickness = 1
    SmoothButtonStroke.Parent = SmoothButton
    local SmoothValue = Func:CreateLabel(
        SmoothButton,
        "SmoothValue",
        "SMOOTH 60%",
        UDim2.fromScale(0, 0),
        UDim2.fromScale(1, 1),
        Enum.Font.Code,
        9,
        Palette.Accent,
        Enum.TextXAlignment.Center
    )
    Func.UI.SmoothValue = SmoothValue
    local AimState = Func:CreateLabel(
        AimCard,
        "AimState",
        "STANDBY",
        UDim2.fromOffset(112, 113),
        UDim2.fromOffset(140, 20),
        Enum.Font.Code,
        8,
        Palette.Muted,
        Enum.TextXAlignment.Right
    )
    Func.UI.AimState = AimState
    Func:Connect(FOVButton.Activated, function()
        local Current = Config["FOV Radius"]
        local Found = false
        for Index, Value in ipairs(FOVOptions) do
            if Value == Current then
                Config["FOV Radius"] = FOVOptions[(Index % #FOVOptions) + 1]
                Found = true
                break
            end
        end
        if not Found then
            Config["FOV Radius"] = FOVOptions[3]
        end
        Func:RefreshFOV()
    end)
    Func:Connect(SmoothButton.Activated, function()
        local Current = Config["Aim Smooth"]
        local Found = false
        for Index, Value in ipairs(SmoothOptions) do
            if Value == Current then
                Config["Aim Smooth"] = SmoothOptions[(Index % #SmoothOptions) + 1]
                Found = true
                break
            end
        end
        if not Found then
            Config["Aim Smooth"] = 60
        end
        Func:RefreshSmooth()
    end)
    local SectionThree = Func:CreateLabel(
        Content,
        "SectionThree",
        "TELEMETRY",
        UDim2.fromOffset(16, 446),
        UDim2.fromOffset(180, 16),
        Enum.Font.Code,
        9,
        Palette.Muted
    )
    SectionThree.TextXAlignment = Enum.TextXAlignment.Left
    local TelemetryCard = Func:CreateCard(Content, "TelemetryCard", UDim2.fromOffset(14, 468), UDim2.fromOffset(264, 60), 103)
    local CountLabel = Func:CreateLabel(
        TelemetryCard,
        "CountLabel",
        "TRACKED",
        UDim2.fromOffset(12, 5),
        UDim2.fromOffset(70, 14),
        Enum.Font.Code,
        8,
        Palette.Muted
    )
    local CountValue = Func:CreateLabel(
        TelemetryCard,
        "CountValue",
        "00",
        UDim2.fromOffset(12, 18),
        UDim2.fromOffset(70, 26),
        Enum.Font.GothamBlack,
        17,
        Palette.Accent
    )
    Func.UI.CountValue = CountValue
    local ViewportLabel = Func:CreateLabel(
        TelemetryCard,
        "ViewportLabel",
        "VIEWPORT",
        UDim2.fromOffset(116, 5),
        UDim2.fromOffset(70, 14),
        Enum.Font.Code,
        8,
        Palette.Muted
    )
    local ViewportValue = Func:CreateLabel(
        TelemetryCard,
        "ViewportValue",
        "0 x 0",
        UDim2.fromOffset(116, 18),
        UDim2.fromOffset(136, 26),
        Enum.Font.Code,
        13,
        Palette.Cyan
    )
    Func.UI.ViewportValue = ViewportValue
    local KeyHint = Func:CreateLabel(
        TelemetryCard,
        "KeyHint",
        UserInputService.TouchEnabled and "MENU  TOP RIGHT BUTTON" or "MENU  RIGHT SHIFT",
        UDim2.fromOffset(12, 44),
        UDim2.fromOffset(240, 12),
        Enum.Font.Code,
        8,
        Palette.Muted,
        Enum.TextXAlignment.Right
    )
    Func:Connect(Minimize.Activated, function()
        Func.UI.Minimized = not Func.UI.Minimized
        Content.Visible = not Func.UI.Minimized
        Minimize.Text = Func.UI.Minimized and "+" or "-"
        if Func.UI.PanelTween then
            Func.UI.PanelTween:Cancel()
        end
        Func.UI.PanelTween = TweenService:Create(
            Panel,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = Func.UI.Minimized and UDim2.fromOffset(PanelWidth, 62) or UDim2.fromOffset(PanelWidth, Func.UI.PanelHeight or PanelHeight) }
        )
        Func.UI.PanelTween:Play()
    end)
    Func.UI.Minimized = false
    Func:LayoutUI(true)
end

-- Opening/closing the menu only hides the panel, so the ESP boxes keep rendering either way.
function Func:SetMenuVisible(Visible)
    Config["Menu"] = Visible == true
    if Func.UI.Panel then
        Func.UI.Panel.Visible = Config["Menu"]
    end
end

-- Fits the panel to the current viewport. Phones get a smaller overall scale plus a scrolling
-- body, so the whole menu stays usable without changing the authored layout.
function Func:LayoutUI(Force)
    local Camera = workspace.CurrentCamera
    local Viewport = Camera and Camera.ViewportSize or Vector2.new(1280, 720)
    if not Force and Func.LastViewport == Viewport then
        return
    end
    Func.LastViewport = Viewport
    local Fit = math.min(
        (Viewport.Y - ViewportMargin) / PanelHeight,
        (Viewport.X - ViewportMargin) / PanelWidth
    )
    local Scale = math.clamp(Fit, MinUIScale, 1)
    local Available = math.max(120, (Viewport.Y - ViewportMargin) / Scale)
    local Height = math.min(PanelHeight, Available)
    Func.UI.PanelHeight = Height
    if Func.UI.PanelScale then
        Func.UI.PanelScale.Scale = Scale
    end
    local Panel = Func.UI.Panel
    local Content = Func.UI.Content
    if Panel and not Func.UI.Minimized then
        Panel.Size = UDim2.fromOffset(PanelWidth, Height)
    end
    if Content then
        Content.Size = UDim2.fromOffset(PanelWidth, math.max(120, Height - 63))
    end
    if Panel then
        local ShownHeight = Func.UI.Minimized and 62 or Height
        local MaxX = math.max(8, Viewport.X - PanelWidth * Scale - 8)
        local MaxY = math.max(8, Viewport.Y - ShownHeight * Scale - 8)
        local X = math.clamp(Panel.Position.X.Offset, 8, MaxX)
        local Y = math.clamp(Panel.Position.Y.Offset, 8, MaxY)
        if X ~= Panel.Position.X.Offset or Y ~= Panel.Position.Y.Offset then
            Panel.Position = UDim2.fromOffset(X, Y)
        end
    end
end

function Func:CreateEntry(Player)
    local Overlay = Func.UI.Overlay
    local Box = Instance.new("Frame")
    Box.Name = "Box"
    Box.BackgroundColor3 = Palette.Cyan
    Box.BackgroundTransparency = 0.94
    Box.BorderSizePixel = 0
    Box.Visible = false
    Box.ZIndex = 20
    Box.Parent = Overlay
    local BoxStroke = Instance.new("UIStroke")
    BoxStroke.Color = Palette.Cyan
    BoxStroke.Transparency = 0.28
    BoxStroke.Thickness = 1.25
    BoxStroke.Parent = Box
    local CornerSpecs = {
        { Vector2.new(0, 0), UDim2.fromOffset(0, 0), UDim2.fromOffset(12, 2) },
        { Vector2.new(0, 0), UDim2.fromOffset(0, 0), UDim2.fromOffset(2, 12) },
        { Vector2.new(1, 0), UDim2.fromOffset(0, 0), UDim2.fromOffset(12, 2) },
        { Vector2.new(1, 0), UDim2.fromOffset(0, 0), UDim2.fromOffset(2, 12) },
        { Vector2.new(0, 1), UDim2.fromOffset(0, 0), UDim2.fromOffset(12, 2) },
        { Vector2.new(0, 1), UDim2.fromOffset(0, 0), UDim2.fromOffset(2, 12) },
        { Vector2.new(1, 1), UDim2.fromOffset(0, 0), UDim2.fromOffset(12, 2) },
        { Vector2.new(1, 1), UDim2.fromOffset(0, 0), UDim2.fromOffset(2, 12) },
    }
    for Index, Spec in ipairs(CornerSpecs) do
        local Corner = Instance.new("Frame")
        Corner.Name = "Corner" .. Index
        Corner.AnchorPoint = Spec[1]
        Corner.Position = Spec[2]
        Corner.Size = Spec[3]
        Corner.BackgroundColor3 = Palette.Accent
        Corner.BorderSizePixel = 0
        Corner.ZIndex = 21
        Corner.Parent = Box
    end
    local HealthBack = Instance.new("Frame")
    HealthBack.Name = "HealthBack"
    HealthBack.BackgroundColor3 = Color3.fromRGB(5, 8, 9)
    HealthBack.BackgroundTransparency = 0.08
    HealthBack.BorderSizePixel = 0
    HealthBack.ClipsDescendants = true
    HealthBack.Visible = false
    HealthBack.ZIndex = 22
    HealthBack.Parent = Overlay
    local HealthBackCorner = Instance.new("UICorner")
    HealthBackCorner.CornerRadius = UDim.new(1, 0)
    HealthBackCorner.Parent = HealthBack
    local HealthBackStroke = Instance.new("UIStroke")
    HealthBackStroke.Color = Color3.fromRGB(0, 0, 0)
    HealthBackStroke.Transparency = 0.2
    HealthBackStroke.Thickness = 1
    HealthBackStroke.Parent = HealthBack
    local HealthFill = Instance.new("Frame")
    HealthFill.Name = "HealthFill"
    HealthFill.AnchorPoint = Vector2.new(0, 1)
    HealthFill.Position = UDim2.new(0, 0, 1, 0)
    HealthFill.Size = UDim2.fromScale(1, 1)
    HealthFill.BackgroundColor3 = Palette.Accent
    HealthFill.BorderSizePixel = 0
    HealthFill.ZIndex = 23
    HealthFill.Parent = HealthBack
    local HealthFillCorner = Instance.new("UICorner")
    HealthFillCorner.CornerRadius = UDim.new(1, 0)
    HealthFillCorner.Parent = HealthFill
    local NameLabel = Func:CreateLabel(
        Overlay,
        "NameLabel",
        Player.DisplayName,
        UDim2.fromOffset(0, 0),
        UDim2.fromOffset(180, 18),
        Enum.Font.GothamBold,
        12,
        Palette.Text,
        Enum.TextXAlignment.Center
    )
    NameLabel.AnchorPoint = Vector2.new(0.5, 0)
    NameLabel.TextStrokeTransparency = 0.28
    NameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    NameLabel.Visible = false
    NameLabel.ZIndex = 24
    local InfoLabel = Func:CreateLabel(
        Overlay,
        "InfoLabel",
        "",
        UDim2.fromOffset(0, 0),
        UDim2.fromOffset(180, 16),
        Enum.Font.Code,
        10,
        Palette.Accent,
        Enum.TextXAlignment.Center
    )
    InfoLabel.AnchorPoint = Vector2.new(0.5, 0)
    InfoLabel.TextStrokeTransparency = 0.3
    InfoLabel.Visible = false
    InfoLabel.ZIndex = 24
    local Entry = {
        Box = Box,
        BoxStroke = BoxStroke,
        HealthBack = HealthBack,
        HealthFill = HealthFill,
        NameLabel = NameLabel,
        InfoLabel = InfoLabel,
        Objects = { Box, HealthBack, NameLabel, InfoLabel },
    }
    Func.Entries[Player] = Entry
    return Entry
end

function Func:RemoveEntry(Player)
    local Entry = Func.Entries[Player]
    if not Entry then
        return
    end
    for _, Object in ipairs(Entry.Objects) do
        Object:Destroy()
    end
    Func.Entries[Player] = nil
end

function Func:ClearEntries()
    for _, Entry in pairs(Func.Entries) do
        for _, Object in ipairs(Entry.Objects) do
            Object:Destroy()
        end
    end
    Func.Entries = {}
    Func.VisibleCount = 0
end

function Func:HideEntry(Entry)
    Entry.Box.Visible = false
    Entry.HealthBack.Visible = false
    Entry.NameLabel.Visible = false
    Entry.InfoLabel.Visible = false
end

function Func:GetLocalTeam()
    local Team = LocalPlayer:GetAttribute("Team")
    if Team ~= nil then
        Func.LocalTeam = Team
    end
    return Func.LocalTeam
end

-- Uses the game's own hostility rules so it matches who the server treats as an ally.
-- TeamOfPlayer is authoritative; the Team attribute is only a fallback. Results are cached
-- briefly because ESP and the aimbot both ask per player, every frame.
function Func:IsTeammate(Player)
    if not Config["Team Check"] then
        return false
    end
    if Player == LocalPlayer then
        return true
    end
    local Now = os.clock()
    local Cached = Func.TeamCache[Player]
    if Cached and Now - Cached.Time < 0.5 then
        return Cached.Value
    end
    local Result = false
    if Hostility then
        local Ok, Hostile = pcall(function()
            return Hostility.AreTeamsHostile(Hostility.TeamOfPlayer(LocalPlayer), Hostility.TeamOfPlayer(Player))
        end)
        if Ok and typeof(Hostile) == "boolean" then
            Result = not Hostile
        end
    else
        local MyTeam = Func:GetLocalTeam()
        local Team = Player:GetAttribute("Team")
        Result = MyTeam ~= nil and Team ~= nil and MyTeam == Team
    end
    Func.TeamCache[Player] = { Time = Now, Value = Result }
    return Result
end

function Func:UpdateEntry(Player, Model, Entry)
    local Camera = workspace.CurrentCamera
    local Humanoid = Model:FindFirstChildOfClass("Humanoid")
    if not Camera or Func:IsRigDead(Model) then
        Func:HideEntry(Entry)
        return false
    end
    local Min, Max = Func:GetBounds(Model)
    if not Min then
        Func:HideEntry(Entry)
        return false
    end
    if Func:IsTeammate(Player) then
        Func:HideEntry(Entry)
        return false
    end
    local Center = (Min + Max) * 0.5
    local Distance = (Center - Camera.CFrame.Position).Magnitude
    if Distance > Config["Max Distance"] then
        Func:HideEntry(Entry)
        return false
    end
    local ScreenMinX, ScreenMinY = math.huge, math.huge
    local ScreenMaxX, ScreenMaxY = -math.huge, -math.huge
    local Visible = true
    for XAxis = 0, 1 do
        for YAxis = 0, 1 do
            for ZAxis = 0, 1 do
                local Corner = Vector3.new(
                    XAxis == 0 and Min.X or Max.X,
                    YAxis == 0 and Min.Y or Max.Y,
                    ZAxis == 0 and Min.Z or Max.Z
                )
                local Point = Camera:WorldToViewportPoint(Corner)
                if Point.Z <= 0 then
                    Visible = false
                else
                    ScreenMinX = math.min(ScreenMinX, Point.X)
                    ScreenMinY = math.min(ScreenMinY, Point.Y)
                    ScreenMaxX = math.max(ScreenMaxX, Point.X)
                    ScreenMaxY = math.max(ScreenMaxY, Point.Y)
                end
            end
        end
    end
    local Viewport = Camera.ViewportSize
    if not Visible or ScreenMaxX < 0 or ScreenMinX > Viewport.X or ScreenMaxY < 0 or ScreenMinY > Viewport.Y then
        Func:HideEntry(Entry)
        return false
    end
    local BoxWidth = math.max(8, ScreenMaxX - ScreenMinX)
    local BoxHeight = math.max(8, ScreenMaxY - ScreenMinY)
    local Left = ScreenMinX
    local Top = ScreenMinY
    local CenterX = (ScreenMinX + ScreenMaxX) * 0.5
    Entry.Box.Position = UDim2.fromOffset(Left, Top)
    Entry.Box.Size = UDim2.fromOffset(BoxWidth, BoxHeight)
    Entry.Box.Visible = Config["Boxes"] == true
    local Health = Humanoid and Humanoid.Health or Model:GetAttribute("Health")
    local MaxHealth = Humanoid and Humanoid.MaxHealth or Model:GetAttribute("MaxHealth")
    local HealthRatio = nil
    if typeof(Health) == "number" and typeof(MaxHealth) == "number" and MaxHealth > 0 then
        HealthRatio = math.clamp(Health / MaxHealth, 0, 1)
    end
    if HealthRatio then
        Entry.HealthBack.Position = UDim2.fromOffset(Left - 7, Top)
        Entry.HealthBack.Size = UDim2.fromOffset(3, BoxHeight)
        Entry.HealthFill.Size = UDim2.fromScale(1, HealthRatio)
        Entry.HealthFill.BackgroundColor3 = Palette.Danger:Lerp(Palette.Accent, HealthRatio)
        Entry.HealthBack.Visible = Config["Health"] == true
    else
        Entry.HealthBack.Visible = false
    end
    Entry.NameLabel.Text = Player.DisplayName ~= "" and Player.DisplayName or Player.Name
    Entry.NameLabel.Size = UDim2.fromOffset(math.max(140, BoxWidth + 90), 18)
    Entry.NameLabel.Position = UDim2.fromOffset(CenterX, math.max(2, Top - 20))
    Entry.NameLabel.Visible = true
    local Parts = {}
    if Config["Health"] and HealthRatio then
        table.insert(Parts, string.format("HP %d", math.ceil(Health)))
    end
    if Config["Distance"] then
        table.insert(Parts, string.format("%d m", math.floor(Distance + 0.5)))
    end
    Entry.InfoLabel.Text = table.concat(Parts, "   /   ")
    Entry.InfoLabel.Size = UDim2.fromOffset(math.max(120, BoxWidth + 80), 16)
    Entry.InfoLabel.Position = UDim2.fromOffset(CenterX, math.min(Viewport.Y - 16, Top + BoxHeight + 4))
    Entry.InfoLabel.Visible = #Parts > 0
    return true
end

function Func:UpdateESP()
    if not Config["ESP"] then
        if next(Func.Entries) then
            Func:ClearEntries()
        end
        return
    end
    if not workspace.CurrentCamera then
        return
    end
    Func.VisibleCount = 0
    local Rigs = Func:CollectRigs()
    for Player in pairs(Func.Entries) do
        if not Rigs[Player] then
            Func:RemoveEntry(Player)
        end
    end
    for Player, Model in pairs(Rigs) do
        local Entry = Func.Entries[Player]
        if not Entry then
            Entry = Func:CreateEntry(Player)
        end
        if Func:UpdateEntry(Player, Model, Entry) then
            Func.VisibleCount += 1
        end
    end
end

-- True only while the player is actually shooting on a touch device. The game's mobile
-- controller is authoritative (its FIRE button state), so dragging the screen to look around
-- never engages the lock. The tracked-touch list is only a fallback for when that module is
-- missing or its controls are disabled.
function Func:IsTouchFiring()
    if MobileInputController then
        local Ok, Held = pcall(function()
            return MobileInputController:IsFireHeld()
        end)
        if Ok and typeof(Held) == "boolean" then
            if Held then
                return true
            end
            if MobileInputController._enabled == true then
                return false
            end
        end
    end
    return UserInputService.TouchEnabled and next(Func.Touches) ~= nil
end

function Func:UpdateAimbot(DeltaTime)
    local Camera = workspace.CurrentCamera
    if not Camera or not Func.UI.FOVCircle then
        return
    end
    -- Cheap no-op unless the viewport actually changed (rotation, window resize, device swap).
    Func:LayoutUI()
    local Viewport = Camera.ViewportSize
    local Center = Vector2.new(Viewport.X * 0.5, Viewport.Y * 0.5)
    local Radius = Config["FOV Radius"]
    Func.UI.FOVCircle.Position = UDim2.fromOffset(Center.X, Center.Y)
    Func.UI.FOVCircle.Size = UDim2.fromOffset(Radius * 2, Radius * 2)
    Func.UI.FOVCircle.Visible = Config["Aimbot"] == true
    if Func.UI.AimHint then
        Func.UI.AimHint.Position = UDim2.new(0.5, 0, 0.5, Radius + 10)
        Func.UI.AimHint.Visible = Config["Aimbot"] == true
    end
    local function SetState(Text, TextColor, RingColor, RingTransparency)
        Func.UI.AimState.Text = Text
        Func.UI.AimState.TextColor3 = TextColor
        Func.UI.FOVStroke.Color = RingColor
        Func.UI.FOVStroke.Transparency = RingTransparency
        Func.UI.FOVDot.BackgroundColor3 = RingColor
        if Func.UI.AimHint then
            Func.UI.AimHint.Text = Text
            Func.UI.AimHint.TextColor3 = TextColor
        end
    end
    local PreviousTarget = Func.AimTarget
    Func.AimTarget = nil
    Func.FireAimPoint = nil
    if not Config["Aimbot"] then
        Func.AimLook = nil
        SetState("STANDBY", Palette.Muted, Palette.Cyan, 0.42)
        return
    end
    local MousePosition = UserInputService:GetMouseLocation()
    local PanelPosition = Func.UI.Panel.AbsolutePosition
    local PanelSize = Func.UI.Panel.AbsoluteSize
    local MouseOverPanel = Func.UI.Panel.Visible
        and MousePosition.X >= PanelPosition.X
        and MousePosition.X <= PanelPosition.X + PanelSize.X
        and MousePosition.Y >= PanelPosition.Y
        and MousePosition.Y <= PanelPosition.Y + PanelSize.Y
    -- The lock engages only while the fire button is actually held down. Aiming/ADS alone
    -- never pulls the crosshair, so the assist cannot drift onto a player until a shot is
    -- being taken.
    local FireHeld = Func.MouseFiring
        or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    local TouchHeld = Func:IsTouchFiring()
    local Focused = UserInputService:GetFocusedTextBox()
    if not ((FireHeld and not MouseOverPanel) or TouchHeld) or Focused then
        Func.AimLook = nil
        SetState(Focused and "PAUSED" or "HOLD FIRE", Focused and Palette.Muted or Palette.Cyan, Palette.Cyan, 0.42)
        return
    end
    local Rigs = Func:CollectRigs()
    local CameraPosition = Camera.CFrame.Position
    local CameraLook = Camera.CFrame.LookVector
    local AssistAngle = Config["Aim Assist Angle"] or 55
    local BestDistance = math.huge
    local BestPlayer
    local BestPoint
    -- Only players whose aim point is inside the FOV circle (and inside the assist cone) are
    -- candidates, and the closest player wins - distance, not screen offset, so the lock stays
    -- on whoever is nearest instead of jumping to whatever drifts past the crosshair.
    for Player, Model in pairs(Rigs) do
        if not Func:IsTeammate(Player) then
            local AimPoint = Func:GetAimPoint(Model)
            if AimPoint then
                local Delta = AimPoint - CameraPosition
                local Distance = Delta.Magnitude
                if Distance > 0.5 and Distance <= Config["Max Distance"] then
                    local Screen = Camera:WorldToViewportPoint(AimPoint)
                    if Screen.Z > 0 then
                        local Offset = (Vector2.new(Screen.X, Screen.Y) - Center).Magnitude
                        local Angle = math.deg(math.acos(math.clamp(Delta.Unit:Dot(CameraLook), -1, 1)))
                        if Offset <= Radius and Angle <= AssistAngle and Distance < BestDistance then
                            BestDistance = Distance
                            BestPlayer = Player
                            BestPoint = AimPoint
                        end
                    end
                end
            end
        end
    end
    if BestPlayer and PreviousTarget and BestPlayer ~= PreviousTarget and not Func:IsTeammate(PreviousTarget) then
        local PreviousModel = Rigs[PreviousTarget]
        if PreviousModel and not Func:IsRigDead(PreviousModel) then
            local PreviousPoint = Func:GetAimPoint(PreviousModel)
            if PreviousPoint then
                local PreviousScreen = Camera:WorldToViewportPoint(PreviousPoint)
                if PreviousScreen.Z > 0 then
                    local PreviousOffset = (Vector2.new(PreviousScreen.X, PreviousScreen.Y) - Center).Magnitude
                    local PreviousDistance = (PreviousPoint - CameraPosition).Magnitude
                    if PreviousOffset <= Radius + 12 and PreviousDistance <= BestDistance * 1.3 then
                        BestPlayer = PreviousTarget
                        BestPoint = PreviousPoint
                        BestDistance = PreviousDistance
                    end
                end
            end
        end
    end
    if not BestPoint then
        Func.AimLook = nil
        SetState("NO TARGET", Palette.Cyan, Palette.Cyan, 0.42)
        return
    end
    local SmoothAmount = math.clamp(Config["Aim Smooth"] / 100, 0, 0.98)
    local Step = math.clamp(DeltaTime or (1 / 60), 0.001, 0.1)
    local Alpha = 1 - SmoothAmount ^ (Step * 60)
    if BestPlayer ~= PreviousTarget then
        Alpha = math.max(Alpha, 0.55)
    end
    local CurrentLook = Func.AimLook or Func:GetBaseLook()
    if not CurrentLook then
        return
    end
    local TargetLook = (BestPoint - CameraPosition).Unit
    local NextLook = CurrentLook:Lerp(TargetLook, Alpha)
    if NextLook.Magnitude > 0.0001 then
        NextLook = NextLook.Unit
    end
    Func:ApplyLook(NextLook)
    Func.AimLook = NextLook
    Func.AimTarget = BestPlayer
    Func.FireAimPoint = BestPoint
    SetState(string.format("LOCKED %dm", math.floor(BestDistance + 0.5)), Palette.Accent, Palette.Accent, 0.18)
end

function Func:Stop()
    if not Func.Running then
        return
    end
    Func.Running = false
    if Func.RenderBound then
        RunService:UnbindFromRenderStep("PrismAimbot")
        Func.RenderBound = false
    end
    for _, Connection in ipairs(Func.Connections) do
        pcall(function()
            Connection:Disconnect()
        end)
    end
    table.clear(Func.Connections)
    Func:ClearEntries()
    Func.FireAimPoint = nil
    if GunController and type(_G.PrismFireDirectionHook) == "function" then
        GunController.GetFireDirectionUnspread = _G.PrismFireDirectionHook
        _G.PrismFireDirectionHook = nil
    end
    if Func.UI.Gui then
        Func.UI.Gui:Destroy()
    end
    if _G.PrismESPStop then
        _G.PrismESPStop = nil
    end
    if _G.PrismAim == Func then
        _G.PrismAim = nil
    end
end

-- CONNECTIONS
Func:BuildUI()
Func:RefreshSwitch("ESP")
Func:RefreshSwitch("Boxes")
Func:RefreshSwitch("Health")
Func:RefreshSwitch("Distance")
Func:RefreshSwitch("Team Check")
Func:RefreshSwitch("Aimbot")
Func:RefreshRange()
Func:RefreshAimPart()
Func:RefreshFOV()
Func:RefreshSmooth()
Func:RefreshStatus()

RunService:BindToRenderStep("PrismAimbot", Enum.RenderPriority.Last.Value, function(DeltaTime)
    if Func.Running then
        Func:UpdateAimbot(DeltaTime)
    end
end)
Func.RenderBound = true

Func:Connect(Func.UI.DragArea.InputBegan, function(Input)
    if Input.UserInputType ~= Enum.UserInputType.MouseButton1 and Input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    Func.UI.Dragging = true
    Func.UI.DragStart = Input.Position
    Func.UI.PanelStart = Func.UI.Panel.Position
end)

Func:Connect(UserInputService.InputChanged, function(Input)
    if not Func.UI.Dragging then
        return
    end
    if Input.UserInputType ~= Enum.UserInputType.MouseMovement and Input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local Delta = Input.Position - Func.UI.DragStart
    local Scale = Func.UI.PanelScale and Func.UI.PanelScale.Scale or 1
    local Camera = workspace.CurrentCamera
    local Viewport = Camera and Camera.ViewportSize or Vector2.new(1280, 720)
    local ShownHeight = Func.UI.Minimized and 62 or (Func.UI.PanelHeight or PanelHeight)
    local MaxX = math.max(8, Viewport.X - PanelWidth * Scale - 8)
    local MaxY = math.max(8, Viewport.Y - ShownHeight * Scale - 8)
    Func.UI.Panel.Position = UDim2.fromOffset(
        math.clamp(Func.UI.PanelStart.X.Offset + Delta.X / Scale, 8, MaxX),
        math.clamp(Func.UI.PanelStart.Y.Offset + Delta.Y / Scale, 8, MaxY)
    )
end)

Func:Connect(UserInputService.InputEnded, function(Input)
    if Input.UserInputType == Enum.UserInputType.MouseButton1 then
        Func.MouseFiring = false
        Func.UI.Dragging = false
    elseif Input.UserInputType == Enum.UserInputType.Touch then
        Func.UI.Dragging = false
    end
end)

Func:Connect(UserInputService.InputBegan, function(Input)
    local PanelPosition = Func.UI.Panel.AbsolutePosition
    local PanelSize = Func.UI.Panel.AbsoluteSize
    local OverPanel = Func.UI.Panel.Visible
        and Input.Position.X >= PanelPosition.X
        and Input.Position.X <= PanelPosition.X + PanelSize.X
        and Input.Position.Y >= PanelPosition.Y
        and Input.Position.Y <= PanelPosition.Y + PanelSize.Y
    if Input.UserInputType == Enum.UserInputType.MouseButton1 then
        Func.MouseFiring = not OverPanel
        return
    end
    if Input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if OverPanel then
        return
    end
    -- Fallback only: a touch counts as firing when it lands on a fire-style button. A plain
    -- drag anywhere on the screen is camera look, so it must not engage the lock.
    local FireHit = false
    for _, Object in ipairs(UserInputService:GetGuiObjectsAtPosition(Input.Position.X, Input.Position.Y)) do
        local Node = Object
        for _ = 1, 3 do
            if not Node or not Node:IsA("GuiObject") then
                break
            end
            if Node:IsA("GuiButton") then
                local LowerName = string.lower(Node.Name)
                if string.find(LowerName, "fire", 1, true)
                    or string.find(LowerName, "shoot", 1, true)
                    or string.find(LowerName, "attack", 1, true)
                    or string.find(LowerName, "trigger", 1, true) then
                    FireHit = true
                    break
                end
            end
            Node = Node.Parent
        end
        if FireHit then
            break
        end
    end
    if FireHit then
        Func.Touches[Input] = true
    end
end)

Func:Connect(UserInputService.InputEnded, function(Input)
    if Input.UserInputType == Enum.UserInputType.Touch then
        Func.Touches[Input] = nil
    end
end)

Func:Connect(UserInputService.InputBegan, function(Input, GameProcessed)
    if GameProcessed or Input.KeyCode ~= Config["Menu Key"] then
        return
    end
    Config["Menu"] = not Config["Menu"]
    Func:SetMenuVisible(Config["Menu"])
end)

Func:Connect(Players.PlayerRemoving, function(Player)
    Func.TeamCache[Player] = nil
    Func:RemoveEntry(Player)
end)

-- Teams are reassigned between rounds, so the cached answer has to be dropped when they change.
local function WatchTeam(Player)
    if Player == LocalPlayer then
        return
    end
    Func:Connect(Player:GetAttributeChangedSignal("Team"), function()
        Func.TeamCache[Player] = nil
    end)
end

Func:Connect(LocalPlayer:GetAttributeChangedSignal("Team"), function()
    Func.LocalTeam = LocalPlayer:GetAttribute("Team")
    table.clear(Func.TeamCache)
end)

for _, Player in ipairs(Players:GetPlayers()) do
    WatchTeam(Player)
end

Func:Connect(Players.PlayerAdded, WatchTeam)

_G.PrismESPStop = function()
    Func:Stop()
end

_G.PrismAim = Func

-- LOOPS
task.spawn(function()
    while task.wait() do
        if not Func.Running then
            break
        end
        pcall(function()
            if Config["ESP"] then
                Func:UpdateESP()
            else
                Func:ClearEntries()
            end
            Func:RefreshStatus()
        end)
    end
end)




