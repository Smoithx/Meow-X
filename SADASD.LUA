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
local GuiService = cloneref(game:GetService("GuiService"))

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- MODULES
local CameraOk, CameraResult = pcall(require, ReplicatedStorage.Modules.Client.Controllers.CameraController)
local CameraController = CameraOk and CameraResult or nil
local GunOk, GunResult = pcall(require, ReplicatedStorage.Modules.Client.Controllers.GunController)
local GunController = GunOk and GunResult or nil
local HostilityOk, HostilityResult = pcall(require, ReplicatedStorage.Modules.Shared.Combat.Hostility)
local Hostility = HostilityOk and HostilityResult or nil

-- CONFIG
Config = Config or {
    ["ESP"] = true,
    ["Boxes"] = true,
    ["Health"] = true,
    ["Distance"] = true,
    ["Team Check"] = true,
    ["Max Distance"] = 1000,
    ["Aimbot"] = false,
    ["Aim Part"] = "Head",
    ["FOV Radius"] = 220,
    ["Aim Smooth"] = 40,
    ["Aim Assist Angle"] = 55,
    ["Aim Muzzle Comp"] = true,
    ["Menu"] = true,
    ["Menu Key"] = Enum.KeyCode.RightShift,
}

if Config["Config Version"] ~= 2 then
    Config["Config Version"] = 2
    Config["FOV Radius"] = 220
    Config["Aim Smooth"] = 40
    Config["Aim Assist Angle"] = 55
end

-- Teammates are filtered out of the ESP and the aimbot unconditionally, so the stored flag
-- always reads true even if an older config saved it as false.
Config["Team Check"] = true

local Func = {}
local Ranges = { 250, 500, 1000, 2500 }
local FOVOptions = { 220, 160, 120, 90, 60, 40, 30, 20 }
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
local PanelWidth = 300
local HeaderHeight = 60
local DesignHeight = 700
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
Func.LocalTeamTime = nil
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

function Func:CreateCard(Parent, Name, Height, Order)
    local Card = Instance.new("Frame")
    Card.Name = Name
    Card.Size = UDim2.new(1, 0, 0, Height)
    Card.LayoutOrder = Order or 1
    Card.BackgroundColor3 = Palette.Surface
    Card.BackgroundTransparency = 0.04
    Card.BorderSizePixel = 0
    Card.ZIndex = 103
    Card.Parent = Parent
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Card
    local Stroke = Instance.new("UIStroke")
    Stroke.Color = Palette.Stroke
    Stroke.Transparency = 0.54
    Stroke.Thickness = 1
    Stroke.Parent = Card
    local Padding = Instance.new("UIPadding")
    Padding.PaddingTop = UDim.new(0, 6)
    Padding.PaddingBottom = UDim.new(0, 6)
    Padding.PaddingLeft = UDim.new(0, 6)
    Padding.PaddingRight = UDim.new(0, 6)
    Padding.Parent = Card
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
    local Goal = UDim2.fromOffset(Enabled and 22 or 2, 2)
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
    local Radius = Func:GetAimRadius()
    if Func.UI.FOVValue then
        Func.UI.FOVValue.Text = string.format("%d px", math.floor(Radius + 0.5))
    end
    if Func.UI.FOVCircle then
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

function Func:CreatePartButton(Parent, PartName, Order)
    local Button = Instance.new("TextButton")
    Button.Name = PartName
    Button.LayoutOrder = Order or 1
    Button.Size = UDim2.new(1 / 3, -4, 1, 0)
    Button.BackgroundColor3 = Palette.SurfaceLight
    Button.BackgroundTransparency = 0.02
    Button.AutoButtonColor = false
    Button.Text = string.upper(PartName)
    Button.TextColor3 = Palette.Muted
    Button.Font = Enum.Font.Code
    Button.TextSize = 11
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
    local Viewport = Func:GetViewportSize()
    Func.UI.ViewportValue.Text = string.format("%d x %d", Viewport.X, Viewport.Y)
    if Func.UI.LastViewport ~= Viewport then
        Func.UI.LastViewport = Viewport
        Func:Layout()
    end
end

function Func:CreateSwitch(Parent, Key, Text, Order)
    local Row = Instance.new("TextButton")
    Row.Name = Key
    Row.LayoutOrder = Order or 1
    Row.Size = UDim2.new(1, 0, 0, 40)
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
        UDim2.new(1, -70, 1, 0),
        Enum.Font.GothamBold,
        12,
        Palette.Text
    )
    local Track = Instance.new("Frame")
    Track.Name = "Track"
    Track.AnchorPoint = Vector2.new(1, 0.5)
    Track.Position = UDim2.new(1, -8, 0.5, 0)
    Track.Size = UDim2.fromOffset(40, 20)
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
    Knob.Size = UDim2.fromOffset(16, 16)
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
        Func:RefreshStatus()
    end)
    return Row
end

function Func:GetViewportSize()
    local Camera = workspace.CurrentCamera
    if Camera then
        return Camera.ViewportSize
    end
    return Vector2.new(1280, 720)
end

function Func:GetSafeInset()
    local Ok, Inset = pcall(function()
        return GuiService:GetGuiInset()
    end)
    if Ok and typeof(Inset) == "Vector2" then
        return Inset
    end
    return Vector2.new(0, 0)
end

-- The FOV ring is drawn in viewport pixels, so a radius that is fine on a monitor would
-- spill off a phone screen. The ring and the aim test both use this clamped value, so the
-- circle always shows exactly where the assist can reach.
function Func:GetAimRadius()
    local Viewport = Func:GetViewportSize()
    local Limit = math.min(Viewport.X, Viewport.Y) * 0.42
    local Configured = tonumber(Config["FOV Radius"]) or 220
    return math.max(24, math.min(Configured, Limit))
end

function Func:SetMenuVisible(Visible)
    Config["Menu"] = Visible == true
    if Func.UI.Panel then
        Func.UI.Panel.Visible = Config["Menu"]
    end
end

-- Keeps the panel on screen after a drag or a rotation.
function Func:ClampPanel()
    local Panel = Func.UI.Panel
    if not Panel then
        return
    end
    local Viewport = Func:GetViewportSize()
    local Inset = Func:GetSafeInset()
    local Scale = Func.UI.Scale and Func.UI.Scale.Scale or 1
    local Margin = 8
    local MinX = Margin + math.max(Inset.X, 0)
    local MinY = Margin + math.max(Inset.Y, 0)
    local MaxX = math.max(MinX, Viewport.X - Margin - Panel.Size.X.Offset * Scale)
    local MaxY = math.max(MinY, Viewport.Y - Margin - Panel.Size.Y.Offset * Scale)
    local X = math.clamp(Panel.Position.X.Offset, MinX, MaxX)
    local Y = math.clamp(Panel.Position.Y.Offset, MinY, MaxY)
    Panel.Position = UDim2.fromOffset(X, Y)
end

-- The panel is authored at a fixed size, then scaled and clipped to the safe area of the
-- current device. A phone in landscape only reports about 390 px of height, so the body
-- scrolls instead of running off the bottom of the screen.
function Func:Layout()
    local Viewport = Func:GetViewportSize()
    local Inset = Func:GetSafeInset()
    local Margin = 8
    local Top = math.max(Inset.Y, 0) + Margin
    local Left = math.max(Inset.X, 0) + Margin
    local MaxWidth = math.max(200, Viewport.X - Left - Margin)
    local MaxHeight = math.max(180, Viewport.Y - Top - Margin - 10)
    local Scale = math.clamp(math.min(1, MaxWidth / PanelWidth), 0.55, 1)
    if Func.UI.Scale then
        Func.UI.Scale.Scale = Scale
    end
    local Panel = Func.UI.Panel
    local Height = math.min(DesignHeight, MaxHeight / Scale)
    Func.UI.PanelHeight = Height
    if not Func.UI.Minimized then
        Panel.Size = UDim2.fromOffset(PanelWidth, Height)
    end
    if Func.UI.Content then
        Func.UI.Content.Size = UDim2.fromOffset(PanelWidth, math.max(80, Height - HeaderHeight))
    end
    Func:ClampPanel()
    local Toggle = Func.UI.Toggle
    if Toggle then
        local ToggleSize = Toggle.Size
        local X = math.clamp(Toggle.Position.X.Offset, 0, math.max(0, Viewport.X - ToggleSize.X.Offset))
        local Y = math.clamp(Toggle.Position.Y.Offset, 0, math.max(0, Viewport.Y - ToggleSize.Y.Offset))
        Toggle.Position = UDim2.fromOffset(X, Y)
    end
    Func:RefreshFOV()
end

-- A keyboard is not available on a phone, so a touch device gets a floating button that
-- shows and hides the panel. It can be dragged out of the way of the game's own buttons.
function Func:BuildToggle()
    local ToggleGui = Instance.new("ScreenGui")
    ToggleGui.Name = "PrismPlayerIntelToggle"
    ToggleGui.ResetOnSpawn = false
    ToggleGui.IgnoreGuiInset = true
    ToggleGui.DisplayOrder = 1001
    ToggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ToggleGui.Parent = PlayerGui
    Func.UI.ToggleGui = ToggleGui
    local Viewport = Func:GetViewportSize()
    local Inset = Func:GetSafeInset()
    local Toggle = Instance.new("TextButton")
    Toggle.Name = "MenuToggle"
    Toggle.Size = UDim2.fromOffset(48, 48)
    Toggle.Position = UDim2.fromOffset(math.max(8, Viewport.X - 58), math.max(Inset.Y, 0) + 10)
    Toggle.BackgroundColor3 = Palette.Background
    Toggle.BackgroundTransparency = 0.12
    Toggle.AutoButtonColor = false
    Toggle.Text = "≡"
    Toggle.TextColor3 = Palette.Accent
    Toggle.Font = Enum.Font.GothamBlack
    Toggle.TextSize = 24
    Toggle.Visible = UserInputService.TouchEnabled
    Toggle.ZIndex = 5
    Toggle.Parent = ToggleGui
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 10)
    Corner.Parent = Toggle
    local Stroke = Instance.new("UIStroke")
    Stroke.Color = Palette.Accent
    Stroke.Transparency = 0.45
    Stroke.Thickness = 1
    Stroke.Parent = Toggle
    Func.UI.Toggle = Toggle
    local Drag = {
        Active = false,
        Moved = false,
        Start = Vector2.zero,
        Origin = Vector2.zero,
    }
    Func:Connect(Toggle.InputBegan, function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 and Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        Drag.Active = true
        Drag.Moved = false
        Drag.Start = Vector2.new(Input.Position.X, Input.Position.Y)
        Drag.Origin = Vector2.new(Toggle.Position.X.Offset, Toggle.Position.Y.Offset)
    end)
    Func:Connect(Toggle.InputChanged, function(Input)
        if not Drag.Active then
            return
        end
        if Input.UserInputType ~= Enum.UserInputType.MouseMovement and Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local Delta = Vector2.new(Input.Position.X, Input.Position.Y) - Drag.Start
        if Delta.Magnitude > 6 then
            Drag.Moved = true
        end
        local Size = Func:GetViewportSize()
        local X = math.clamp(Drag.Origin.X + Delta.X, 0, math.max(0, Size.X - Toggle.Size.X.Offset))
        local Y = math.clamp(Drag.Origin.Y + Delta.Y, 0, math.max(0, Size.Y - Toggle.Size.Y.Offset))
        Toggle.Position = UDim2.fromOffset(X, Y)
    end)
    Func:Connect(Toggle.InputEnded, function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 and Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        Drag.Active = false
    end)
    Func:Connect(Toggle.Activated, function()
        if Drag.Moved then
            return
        end
        Func:SetMenuVisible(not Config["Menu"])
    end)
end

function Func:BuildUI()
    local Existing = PlayerGui:FindFirstChild("PrismPlayerIntel")
    if Existing then
        Existing:Destroy()
    end
    local ExistingToggle = PlayerGui:FindFirstChild("PrismPlayerIntelToggle")
    if ExistingToggle then
        ExistingToggle:Destroy()
    end
    local Gui = Instance.new("ScreenGui")
    Gui.Name = "PrismPlayerIntel"
    Gui.ResetOnSpawn = false
    Gui.IgnoreGuiInset = true
    Gui.DisplayOrder = 999
    Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Gui.Enabled = true
    Gui.Parent = PlayerGui
    Func.UI.Gui = Gui
    Func.UI.Minimized = false
    Func.UI.LastViewport = nil
    local Overlay = Instance.new("Frame")
    Overlay.Name = "Overlay"
    Overlay.Size = UDim2.fromScale(1, 1)
    Overlay.BackgroundTransparency = 1
    Overlay.ZIndex = 10
    Overlay.Parent = Gui
    Func.UI.Overlay = Overlay
    local InitialRadius = Func:GetAimRadius()
    local FOVCircle = Instance.new("Frame")
    FOVCircle.Name = "FOVCircle"
    FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    FOVCircle.Position = UDim2.fromScale(0.5, 0.5)
    FOVCircle.Size = UDim2.fromOffset(InitialRadius * 2, InitialRadius * 2)
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
    AimHint.Position = UDim2.new(0.5, 0, 0.5, InitialRadius + 10)
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
    Panel.Position = UDim2.fromOffset(16, 16)
    Panel.Size = UDim2.fromOffset(PanelWidth, DesignHeight)
    Panel.BackgroundColor3 = Palette.Background
    Panel.BackgroundTransparency = 0.03
    Panel.BorderSizePixel = 0
    Panel.ClipsDescendants = true
    Panel.Visible = Config["Menu"] == true
    Panel.ZIndex = 100
    Panel.Parent = Gui
    Func.UI.Panel = Panel
    local PanelScale = Instance.new("UIScale")
    PanelScale.Name = "Scale"
    PanelScale.Scale = 1
    PanelScale.Parent = Panel
    Func.UI.Scale = PanelScale
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
    Header.Size = UDim2.fromOffset(PanelWidth, HeaderHeight)
    Header.BackgroundTransparency = 1
    Header.ZIndex = 101
    Header.Parent = Panel
    local DragArea = Instance.new("TextButton")
    DragArea.Name = "DragArea"
    DragArea.Size = UDim2.fromScale(1, 1)
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
        UDim2.fromOffset(18, 8),
        UDim2.fromOffset(140, 24),
        Enum.Font.GothamBlack,
        18,
        Palette.Text
    )
    Logo.TextXAlignment = Enum.TextXAlignment.Left
    local Subtitle = Func:CreateLabel(
        Header,
        "Subtitle",
        "PLAYER INTELLIGENCE",
        UDim2.fromOffset(19, 32),
        UDim2.fromOffset(160, 14),
        Enum.Font.Code,
        9,
        Palette.Cyan
    )
    Subtitle.TextXAlignment = Enum.TextXAlignment.Left
    local StatusDot = Instance.new("Frame")
    StatusDot.Name = "StatusDot"
    StatusDot.AnchorPoint = Vector2.new(1, 0.5)
    StatusDot.Position = UDim2.new(1, -114, 0, 30)
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
        UDim2.new(1, -106, 0, 22),
        UDim2.fromOffset(52, 16),
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
    Minimize.Position = UDim2.new(1, -10, 0, 10)
    Minimize.Size = UDim2.fromOffset(40, 40)
    Minimize.BackgroundColor3 = Palette.SurfaceLight
    Minimize.BackgroundTransparency = 0.05
    Minimize.AutoButtonColor = false
    Minimize.Text = "-"
    Minimize.TextColor3 = Palette.Text
    Minimize.Font = Enum.Font.Code
    Minimize.TextSize = 20
    Minimize.ZIndex = 106
    Minimize.Parent = Header
    local MinimizeCorner = Instance.new("UICorner")
    MinimizeCorner.CornerRadius = UDim.new(0, 6)
    MinimizeCorner.Parent = Minimize
    Func.UI.Minimize = Minimize
    local HeaderLine = Instance.new("Frame")
    HeaderLine.Name = "HeaderLine"
    HeaderLine.Position = UDim2.fromOffset(12, HeaderHeight - 1)
    HeaderLine.Size = UDim2.new(1, -24, 0, 1)
    HeaderLine.BackgroundColor3 = Palette.Stroke
    HeaderLine.BackgroundTransparency = 0.36
    HeaderLine.BorderSizePixel = 0
    HeaderLine.ZIndex = 102
    HeaderLine.Parent = Panel
    local Content = Instance.new("ScrollingFrame")
    Content.Name = "Content"
    Content.Position = UDim2.fromOffset(0, HeaderHeight)
    Content.Size = UDim2.fromOffset(PanelWidth, DesignHeight - HeaderHeight)
    Content.BackgroundTransparency = 1
    Content.BorderSizePixel = 0
    Content.ScrollBarThickness = 3
    Content.ScrollBarImageColor3 = Palette.Stroke
    Content.ScrollBarImageTransparency = 0.25
    Content.ScrollingDirection = Enum.ScrollingDirection.Y
    Content.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
    Content.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
    Content.CanvasSize = UDim2.fromOffset(0, 0)
    Content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Content.ZIndex = 101
    Content.Parent = Panel
    Func.UI.Content = Content
    local ContentPadding = Instance.new("UIPadding")
    ContentPadding.PaddingTop = UDim.new(0, 10)
    ContentPadding.PaddingBottom = UDim.new(0, 12)
    ContentPadding.PaddingLeft = UDim.new(0, 12)
    ContentPadding.PaddingRight = UDim.new(0, 12)
    ContentPadding.Parent = Content
    local ContentList = Instance.new("UIListLayout")
    ContentList.FillDirection = Enum.FillDirection.Vertical
    ContentList.SortOrder = Enum.SortOrder.LayoutOrder
    ContentList.Padding = UDim.new(0, 8)
    ContentList.Parent = Content
    local Order = 0
    local function NextOrder()
        Order = Order + 1
        return Order
    end
    local function AddSection(Text)
        local Label = Func:CreateLabel(
            Content,
            "Section",
            Text,
            UDim2.fromOffset(0, 0),
            UDim2.new(1, 0, 0, 14),
            Enum.Font.Code,
            9,
            Palette.Muted
        )
        Label.LayoutOrder = NextOrder()
        return Label
    end
    local function AddList(Parent, Padding)
        local List = Instance.new("UIListLayout")
        List.FillDirection = Enum.FillDirection.Vertical
        List.SortOrder = Enum.SortOrder.LayoutOrder
        List.Padding = UDim.new(0, Padding or 4)
        List.Parent = Parent
        return List
    end
    AddSection("VISUAL LAYERS")
    local SwitchCard = Func:CreateCard(Content, "SwitchCard", 184, NextOrder())
    AddList(SwitchCard, 4)
    Func:CreateSwitch(SwitchCard, "ESP", "PLAYER ESP", 1)
    Func:CreateSwitch(SwitchCard, "Boxes", "BOUNDING BOX", 2)
    Func:CreateSwitch(SwitchCard, "Health", "HEALTH READOUT", 3)
    Func:CreateSwitch(SwitchCard, "Distance", "DISTANCE READOUT", 4)
    AddSection("SCAN LIMIT")
    local RangeCard = Func:CreateCard(Content, "RangeCard", 64, NextOrder())
    local RangeRow = Instance.new("Frame")
    RangeRow.Name = "RangeRow"
    RangeRow.Size = UDim2.new(1, 0, 0, 52)
    RangeRow.BackgroundTransparency = 1
    RangeRow.ZIndex = RangeCard.ZIndex + 1
    RangeRow.Parent = RangeCard
    local RangeLabel = Func:CreateLabel(
        RangeRow,
        "RangeLabel",
        "DISTANCE CULL",
        UDim2.fromOffset(6, 4),
        UDim2.new(1, -124, 0, 16),
        Enum.Font.GothamBold,
        12,
        Palette.Text
    )
    RangeLabel.TextXAlignment = Enum.TextXAlignment.Left
    local RangeHint = Func:CreateLabel(
        RangeRow,
        "RangeHint",
        "TAP TO CYCLE",
        UDim2.fromOffset(6, 24),
        UDim2.new(1, -124, 0, 14),
        Enum.Font.Code,
        8,
        Palette.Muted
    )
    RangeHint.TextXAlignment = Enum.TextXAlignment.Left
    local RangeButton = Instance.new("TextButton")
    RangeButton.Name = "RangeButton"
    RangeButton.AnchorPoint = Vector2.new(1, 0.5)
    RangeButton.Position = UDim2.new(1, -4, 0.5, 0)
    RangeButton.Size = UDim2.fromOffset(110, 42)
    RangeButton.BackgroundColor3 = Palette.SurfaceLight
    RangeButton.BackgroundTransparency = 0.02
    RangeButton.AutoButtonColor = false
    RangeButton.Text = ""
    RangeButton.ZIndex = RangeRow.ZIndex + 1
    RangeButton.Parent = RangeRow
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
    AddSection("COMBAT MODULE")
    local AimCard = Func:CreateCard(Content, "AimCard", 182, NextOrder())
    AddList(AimCard, 4)
    Func:CreateSwitch(AimCard, "Aimbot", "AIM BOT", 1)
    local LockLabel = Func:CreateLabel(
        AimCard,
        "LockLabel",
        "LOCK PART",
        UDim2.fromOffset(6, 0),
        UDim2.new(1, 0, 0, 14),
        Enum.Font.Code,
        8,
        Palette.Muted
    )
    LockLabel.LayoutOrder = 2
    local PartRow = Instance.new("Frame")
    PartRow.Name = "PartRow"
    PartRow.Size = UDim2.new(1, 0, 0, 36)
    PartRow.BackgroundTransparency = 1
    PartRow.LayoutOrder = 3
    PartRow.ZIndex = AimCard.ZIndex + 1
    PartRow.Parent = AimCard
    local PartList = Instance.new("UIListLayout")
    PartList.FillDirection = Enum.FillDirection.Horizontal
    PartList.SortOrder = Enum.SortOrder.LayoutOrder
    PartList.Padding = UDim.new(0, 4)
    PartList.Parent = PartRow
    Func:CreatePartButton(PartRow, "Head", 1)
    Func:CreatePartButton(PartRow, "Neck", 2)
    Func:CreatePartButton(PartRow, "Body", 3)
    local FOVRow = Instance.new("Frame")
    FOVRow.Name = "FOVRow"
    FOVRow.Size = UDim2.new(1, 0, 0, 34)
    FOVRow.BackgroundTransparency = 1
    FOVRow.LayoutOrder = 4
    FOVRow.ZIndex = AimCard.ZIndex + 1
    FOVRow.Parent = AimCard
    local FOVLabel = Func:CreateLabel(
        FOVRow,
        "FOVLabel",
        "FOV RADIUS",
        UDim2.fromOffset(6, 0),
        UDim2.new(1, -124, 1, 0),
        Enum.Font.GothamBold,
        11,
        Palette.Text
    )
    local FOVButton = Instance.new("TextButton")
    FOVButton.Name = "FOVButton"
    FOVButton.AnchorPoint = Vector2.new(1, 0.5)
    FOVButton.Position = UDim2.new(1, -4, 0.5, 0)
    FOVButton.Size = UDim2.fromOffset(110, 32)
    FOVButton.BackgroundColor3 = Palette.SurfaceLight
    FOVButton.BackgroundTransparency = 0.02
    FOVButton.AutoButtonColor = false
    FOVButton.Text = ""
    FOVButton.ZIndex = FOVRow.ZIndex + 1
    FOVButton.Parent = FOVRow
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
        "220 px",
        UDim2.fromScale(0, 0),
        UDim2.fromScale(1, 1),
        Enum.Font.Code,
        12,
        Palette.Accent,
        Enum.TextXAlignment.Center
    )
    Func.UI.FOVValue = FOVValue
    local SmoothRow = Instance.new("Frame")
    SmoothRow.Name = "SmoothRow"
    SmoothRow.Size = UDim2.new(1, 0, 0, 30)
    SmoothRow.BackgroundTransparency = 1
    SmoothRow.LayoutOrder = 5
    SmoothRow.ZIndex = AimCard.ZIndex + 1
    SmoothRow.Parent = AimCard
    local SmoothButton = Instance.new("TextButton")
    SmoothButton.Name = "SmoothButton"
    SmoothButton.Position = UDim2.fromOffset(4, 1)
    SmoothButton.Size = UDim2.fromOffset(150, 28)
    SmoothButton.BackgroundColor3 = Palette.SurfaceLight
    SmoothButton.BackgroundTransparency = 0.02
    SmoothButton.AutoButtonColor = false
    SmoothButton.Text = ""
    SmoothButton.ZIndex = SmoothRow.ZIndex + 1
    SmoothButton.Parent = SmoothRow
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
        10,
        Palette.Accent,
        Enum.TextXAlignment.Center
    )
    Func.UI.SmoothValue = SmoothValue
    local AimState = Func:CreateLabel(
        SmoothRow,
        "AimState",
        "STANDBY",
        UDim2.new(1, -96, 0, 0),
        UDim2.fromOffset(90, 30),
        Enum.Font.Code,
        9,
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
    AddSection("TELEMETRY")
    local TelemetryCard = Func:CreateCard(Content, "TelemetryCard", 68, NextOrder())
    local CountLabel = Func:CreateLabel(
        TelemetryCard,
        "CountLabel",
        "TRACKED",
        UDim2.fromOffset(0, 2),
        UDim2.fromOffset(80, 12),
        Enum.Font.Code,
        8,
        Palette.Muted
    )
    local CountValue = Func:CreateLabel(
        TelemetryCard,
        "CountValue",
        "00",
        UDim2.fromOffset(0, 14),
        UDim2.fromOffset(80, 28),
        Enum.Font.GothamBlack,
        18,
        Palette.Accent
    )
    Func.UI.CountValue = CountValue
    local ViewportLabel = Func:CreateLabel(
        TelemetryCard,
        "ViewportLabel",
        "VIEWPORT",
        UDim2.fromOffset(92, 2),
        UDim2.fromOffset(100, 12),
        Enum.Font.Code,
        8,
        Palette.Muted
    )
    local ViewportValue = Func:CreateLabel(
        TelemetryCard,
        "ViewportValue",
        "0 x 0",
        UDim2.fromOffset(92, 14),
        UDim2.new(1, -92, 0, 28),
        Enum.Font.Code,
        12,
        Palette.Cyan
    )
    Func.UI.ViewportValue = ViewportValue
    local KeyHint = Func:CreateLabel(
        TelemetryCard,
        "KeyHint",
        UserInputService.TouchEnabled and "MENU  TOP RIGHT BUTTON" or "MENU  RIGHT SHIFT",
        UDim2.fromOffset(0, 44),
        UDim2.new(1, 0, 0, 12),
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
        local TargetHeight = Func.UI.Minimized and HeaderHeight or (Func.UI.PanelHeight or DesignHeight)
        Func.UI.PanelTween = TweenService:Create(
            Panel,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = UDim2.fromOffset(PanelWidth, TargetHeight) }
        )
        Func.UI.PanelTween:Play()
    end)
    Func:Layout()
    Func:BuildToggle()
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
    local Now = os.clock()
    if Func.LocalTeamTime and Now - Func.LocalTeamTime < 0.5 then
        return Func.LocalTeam
    end
    Func.LocalTeamTime = Now
    local Team = nil
    local Character = LocalPlayer.Character
    if Character then
        local Attr = Character:GetAttribute("Team")
        if typeof(Attr) == "string" and Attr ~= "" then
            Team = Attr
        end
    end
    if not Team and Hostility then
        local Ok, Result = pcall(Hostility.TeamOfPlayer, LocalPlayer)
        if Ok and typeof(Result) == "string" and Result ~= "" then
            Team = Result
        end
    end
    if not Team then
        local Attr = LocalPlayer:GetAttribute("Team")
        if typeof(Attr) == "string" and Attr ~= "" then
            Team = Attr
        end
    end
    Func.LocalTeam = Team
    return Team
end

-- The merc rig is the authoritative source for an enemy's team: the game tags the rig (or one
-- of its ancestors) with the Team attribute and Hostility.TeamOfInstance walks up to find it.
-- TeamOfPlayer only sees the player object and its character, which is empty in this rig-based
-- game, so it is kept as a fallback instead of being the first choice.
function Func:GetTeamOfRig(Model, Player)
    if Hostility then
        if Model then
            local Ok, Result = pcall(Hostility.TeamOfInstance, Model)
            if Ok and typeof(Result) == "string" and Result ~= "" then
                return Result
            end
        end
        local Ok, Result = pcall(Hostility.TeamOfPlayer, Player)
        if Ok and typeof(Result) == "string" and Result ~= "" then
            return Result
        end
    end
    if Model then
        local Attr = Model:GetAttribute("Team")
        if typeof(Attr) == "string" and Attr ~= "" then
            return Attr
        end
    end
    local Attr = Player and Player:GetAttribute("Team")
    if typeof(Attr) == "string" and Attr ~= "" then
        return Attr
    end
    return nil
end

-- Team separation is always enforced: a teammate is never drawn and never locked. The
-- comparison uses the game's own hostility rule, where a missing or "Neutral" team counts as
-- hostile, so free-for-all rounds still treat everybody as an enemy. Results are cached for
-- half a second and re-checked whenever the rig model changes, which is what happens between
-- rounds when teams are reassigned.
function Func:IsTeammate(Player, Model)
    if Player == LocalPlayer then
        return true
    end
    local Now = os.clock()
    local Cached = Func.TeamCache[Player]
    if Cached and Cached.Model == Model and Now - Cached.Time < 0.5 then
        return Cached.Value
    end
    local MyTeam = Func:GetLocalTeam()
    local TheirTeam = Func:GetTeamOfRig(Model, Player)
    local Result = nil
    if Hostility then
        local Ok, Hostile = pcall(Hostility.AreTeamsHostile, MyTeam, TheirTeam)
        if Ok and typeof(Hostile) == "boolean" then
            Result = not Hostile
        end
    end
    if Result == nil then
        if not MyTeam or not TheirTeam then
            Result = false
        elseif MyTeam == "Neutral" or TheirTeam == "Neutral" then
            Result = false
        else
            Result = MyTeam == TheirTeam
        end
    end
    Func.TeamCache[Player] = { Model = Model, Team = TheirTeam, Time = Now, Value = Result }
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
    if Func:IsTeammate(Player, Model) then
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

function Func:UpdateAimbot(DeltaTime)
    local Camera = workspace.CurrentCamera
    if not Camera or not Func.UI.FOVCircle then
        return
    end
    local Viewport = Camera.ViewportSize
    local Center = Vector2.new(Viewport.X * 0.5, Viewport.Y * 0.5)
    local Radius = Func:GetAimRadius()
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
        and Func.UI.Gui.Enabled
        and MousePosition.X >= PanelPosition.X
        and MousePosition.X <= PanelPosition.X + PanelSize.X
        and MousePosition.Y >= PanelPosition.Y
        and MousePosition.Y <= PanelPosition.Y + PanelSize.Y
    -- The lock engages only while the fire button is actually held down. Aiming/ADS alone
    -- never pulls the crosshair, so the assist cannot drift onto a player until a shot is
    -- being taken.
    local FireHeld = Func.MouseFiring
        or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    local TouchHeld = UserInputService.TouchEnabled and next(Func.Touches) ~= nil
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
        if not Func:IsTeammate(Player, Model) then
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
    if BestPlayer and PreviousTarget and BestPlayer ~= PreviousTarget and not Func:IsTeammate(PreviousTarget, Rigs[PreviousTarget]) then
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
    if Func.UI.ToggleGui then
        Func.UI.ToggleGui:Destroy()
        Func.UI.ToggleGui = nil
        Func.UI.Toggle = nil
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
    Func.UI.Panel.Position = UDim2.fromOffset(
        Func.UI.PanelStart.X.Offset + Delta.X,
        Func.UI.PanelStart.Y.Offset + Delta.Y
    )
    Func:ClampPanel()
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
        and Func.UI.Gui.Enabled
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
    local FireHit = false
    for _, Object in ipairs(UserInputService:GetGuiObjectsAtPosition(Input.Position.X, Input.Position.Y)) do
        if Object:IsA("GuiButton") then
            local LowerName = string.lower(Object.Name)
            if string.find(LowerName, "fire", 1, true)
                or string.find(LowerName, "shoot", 1, true)
                or string.find(LowerName, "attack", 1, true)
                or string.find(LowerName, "trigger", 1, true) then
                FireHit = true
                break
            end
        end
    end
    local Viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
    local LowerRight = Viewport
        and Input.Position.X >= Viewport.X * 0.72
        and Input.Position.Y >= Viewport.Y * 0.55
    if FireHit or LowerRight then
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
    Func:SetMenuVisible(not Config["Menu"])
end)

Func:Connect(Players.PlayerRemoving, function(Player)
    Func.TeamCache[Player] = nil
    Func:RemoveEntry(Player)
end)

-- Teams are reassigned between rounds, so the cached answer has to be dropped when they change.
-- The rig models are rebuilt each round too, and IsTeammate already re-checks when the model
-- changes, but the attribute signals catch a team edit that happens on the same rig.
local function WatchTeam(Player)
    if Player == LocalPlayer then
        return
    end
    Func:Connect(Player:GetAttributeChangedSignal("Team"), function()
        Func.TeamCache[Player] = nil
    end)
    Func:Connect(Player.CharacterAdded, function(Character)
        Func.TeamCache[Player] = nil
        Func:Connect(Character:GetAttributeChangedSignal("Team"), function()
            Func.TeamCache[Player] = nil
        end)
    end)
end

Func:Connect(LocalPlayer:GetAttributeChangedSignal("Team"), function()
    Func.LocalTeam = nil
    Func.LocalTeamTime = nil
    table.clear(Func.TeamCache)
end)

Func:Connect(LocalPlayer.CharacterAdded, function(Character)
    Func.LocalTeam = nil
    Func.LocalTeamTime = nil
    table.clear(Func.TeamCache)
    Func:Connect(Character:GetAttributeChangedSignal("Team"), function()
        Func.LocalTeam = nil
        Func.LocalTeamTime = nil
        table.clear(Func.TeamCache)
    end)
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




