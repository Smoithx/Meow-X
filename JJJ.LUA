if not game:IsLoaded() then
    game.Loaded:Wait()
end

local cloneref = cloneref or function(instance)
    return instance
end

-- SERVICES
local Players = cloneref(game:GetService("Players"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local HttpService = cloneref(game:GetService("HttpService"))
local TweenService = cloneref(game:GetService("TweenService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local GuiService = cloneref(game:GetService("GuiService"))
local VirtualInputManager = cloneref(game:GetService("VirtualInputManager"))

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- CONFIG
Config = Config or {
    ["Auto Dungeon"] = false,
    ["Head Height"] = 3,
    ["Head Rotation"] = -90,
    ["Attack Interval"] = 0.3,
    ["Auto Skill"] = false,
    ["World"] = "World1",
    ["Difficulty"] = 1,
    ["Auto Join"] = false,
    ["Auto Sell"] = false,
    ["Sell Interval"] = 10,
    ["Sell Items"] = {},
}

-- SAVE
local SaveFolder = "Iron Dungeon"
local SaveFile = SaveFolder .. "/Config.json"
local SaveKeys = {
    ["Auto Dungeon"] = true,
    ["Head Height"] = true,
    ["Head Rotation"] = true,
    ["Attack Interval"] = true,
    ["Auto Skill"] = true,
    ["World"] = true,
    ["Difficulty"] = true,
    ["Auto Join"] = true,
    ["Auto Sell"] = true,
    ["Sell Interval"] = true,
    ["Sell Items"] = true,
}
local Theme = {
    Background = Color3.fromRGB(18, 18, 22),
    Surface = Color3.fromRGB(27, 27, 33),
    Stroke = Color3.fromRGB(46, 46, 58),
    Accent = Color3.fromRGB(120, 170, 255),
    Text = Color3.fromRGB(236, 236, 242),
    Muted = Color3.fromRGB(138, 138, 154),
}

-- REFERENCES
local FrameworkOk, Framework = pcall(require, ReplicatedStorage:FindFirstChild("Framework"))

-- FUNCTIONS
local Func = {}
local Controller
local Choices = {}
local InteractDuplicated = {}
local NextScan = 0
local NextAttack = 0
local NextOpen = 0
local NextMove = 0
local NextPortal = 0
local NextJoin = 0
local NextSkill = 0
local NextSell = 0
local SkillAt = {}

function Func:Load()
    if type(isfile) ~= "function" or type(readfile) ~= "function" or not isfile(SaveFile) then
        return
    end
    local Ok, Data = pcall(function()
        return HttpService:JSONDecode(readfile(SaveFile))
    end)
    if not Ok or type(Data) ~= "table" then
        return
    end
    for Key, Value in next, Data do
        if SaveKeys[Key] and type(Value) == type(Config[Key]) then
            Config[Key] = Value
        end
    end
end

function Func:Save()
    if type(writefile) ~= "function" or type(makefolder) ~= "function" then
        return
    end
    if type(isfolder) ~= "function" or not isfolder(SaveFolder) then
        pcall(makefolder, SaveFolder)
    end
    local Data = {}
    for Key in next, SaveKeys do
        Data[Key] = Config[Key]
    end
    local Ok, Encoded = pcall(function()
        return HttpService:JSONEncode(Data)
    end)
    if not Ok then
        return
    end
    if type(isfile) == "function" and type(readfile) == "function" and isfile(SaveFile) then
        local ReadOk, Existing = pcall(readfile, SaveFile)
        if ReadOk and Existing == Encoded then
            return
        end
    end
    pcall(writefile, SaveFile, Encoded)
end

function Func:Refresh()
    if os.clock() < NextScan then
        return
    end
    NextScan = os.clock() + 1
    local Character = LocalPlayer.Character
    Controller = nil
    if not Character then
        return
    end
    for _, Value in filtergc("table", { Keys = { "Character", "ActionList", "LastSkillStage" } }, false) do
        if rawget(Value, "Character") == Character then
            Controller = Value
            return
        end
    end
end

function Func:Nearest(Folder, RoundNum, Position)
    local Result, Distance = nil, math.huge
    for _, Value in Folder:GetChildren() do
        local Root = Value:FindFirstChild("Root")
        local Part = Value:FindFirstChild("Door")
        if Root and Part and Root:GetAttribute("RoundNum") == RoundNum then
            local Current = (Part.Position - Position).Magnitude
            if Current < Distance then
                Result = Value
                Distance = Current
            end
        end
    end
    return Result
end

function Func:Portal(Folder, RoundNum, Position)
    local Result, Distance = nil, math.huge
    for _, Value in Folder:GetChildren() do
        local Root = Value:FindFirstChild("Root")
        local Remote = Root and Root:FindFirstChild("RF")
        if Remote and Root:GetAttribute("RoundNum") == RoundNum then
            local Current = (Root.Position - Position).Magnitude
            if Current < Distance then
                Result = Root
                Distance = Current
            end
        end
    end
    return Result
end

function Func:Beyond(Door, Position, Reference)
    local Part = Door:FindFirstChild("Door")
    if not Part then
        return false
    end
    local Forward = Part.CFrame.LookVector
    if (Reference - Part.Position):Dot(Forward) > 0 then
        Forward = -Forward
    end
    return (Position - Part.Position):Dot(Forward) > 0
end

function Func:Forward(DoorFolder, GatePart, RoundNum, Position)
    local Ahead = Func:Nearest(DoorFolder, RoundNum, Position)
    local AheadPart = Ahead and Ahead:FindFirstChild("Door")
    local Direction = AheadPart and (AheadPart.Position - GatePart.Position)
    if not Direction or Vector3.new(Direction.X, 0, Direction.Z).Magnitude < 1 then
        local Behind = Func:Nearest(DoorFolder, RoundNum - 2, Position)
        local BehindPart = Behind and Behind:FindFirstChild("Door")
        Direction = BehindPart and (GatePart.Position - BehindPart.Position)
    end
    if not Direction then
        Direction = GatePart.Position - Position
    end
    Direction = Vector3.new(Direction.X, 0, Direction.Z)
    if Direction.Magnitude < 1 then
        local Look = GatePart.CFrame.LookVector
        Direction = Vector3.new(Look.X, 0, Look.Z)
    end
    if Direction.Magnitude < 1 then
        return nil
    end
    return Direction.Unit
end

function Func:Move(Target, HumanoidRootPart)
    if os.clock() < NextMove then
        return
    end
    local Current = HumanoidRootPart.Position
    local Offset = Vector3.new(Target.X - Current.X, 0, Target.Z - Current.Z)
    local Distance = Offset.Magnitude
    if Distance < 3 then
        return
    end
    NextMove = os.clock() + 0.2
    local Position = Current + Offset.Unit * math.min(Distance, 12)
    HumanoidRootPart.CFrame = CFrame.new(Position.X, Current.Y, Position.Z)
end

function Func:Attack(Target, HumanoidRootPart)
    local TargetRoot = Target:FindFirstChild("HumanoidRootPart")
    local Humanoid = Target:FindFirstChildOfClass("Humanoid")
    if not TargetRoot or not Humanoid or Humanoid.Health <= 0 then
        return
    end
    local Head = Target:FindFirstChild("Head") or TargetRoot
    HumanoidRootPart.CFrame = CFrame.new(Head.Position + Vector3.new(0, Config["Head Height"], 0)) * CFrame.Angles(math.rad(Config["Head Rotation"]), 0, 0)
    HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
    HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero
    if Controller and Config["Auto Skill"] then
        Func:Skill()
    end
    if os.clock() < NextAttack then
        return
    end
    NextAttack = os.clock() + Config["Attack Interval"]
    if Controller then
        pcall(function()
            Controller:PerformAction("BaseAttack")
        end)
    end
end

function Func:Skill()
    if not Controller then
        return
    end
    if os.clock() < NextSkill then
        return
    end
    NextSkill = os.clock() + 0.2
    if Controller:HasSkillAction() or Controller:HasAction("BeHit") or Controller:HasAction("Dash") then
        return
    end
    for _, Slot in next, { "SkillU", "SkillAW", "Skill3", "Skill2", "Skill1" } do
        if os.clock() >= (SkillAt[Slot] or 0) and not Controller:HasAction(Slot) then
            local Ready
            pcall(function()
                Ready = Controller:CheckSkillCD(Slot)
            end)
            if Ready or Ready == nil then
                SkillAt[Slot] = os.clock() + 0.2
                pcall(function()
                    Controller:PerformAction(Slot)
                end)
            end
        end
    end
end

function Func:Run()
    local GameRoundCfg = ReplicatedStorage:FindFirstChild("GameRoundCfg")
    if not GameRoundCfg then
        return
    end
    local Round = GameRoundCfg:GetAttribute("GameRound") or 0
    local MaxRound = GameRoundCfg:GetAttribute("MaxRound") or 0
    if Round < 1 or Round > MaxRound or LocalPlayer:GetAttribute("Settlement") then
        return
    end
    local Character = LocalPlayer.Character
    local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
    local DoorFolder = workspace:FindFirstChild("RoundDoor")
    local EnemyFolder = workspace:FindFirstChild("EnemyNpc")
    if not HumanoidRootPart or not DoorFolder or not EnemyFolder then
        return
    end
    if not Controller or Controller.Character ~= Character then
        Func:Refresh()
    end
    local Position = HumanoidRootPart.Position
    local Gate = Func:Nearest(DoorFolder, Round - 1, Position)
    local Ahead = Func:Nearest(DoorFolder, Round, Position)
    local GateRoot = Gate and Gate:FindFirstChild("Root")
    local AheadRoot = Ahead and Ahead:FindFirstChild("Root")
    local Barrier = {}
    if GateRoot and GateRoot:GetAttribute("Switch") ~= 1 then
        table.insert(Barrier, Gate)
    end
    if AheadRoot and AheadRoot:GetAttribute("Switch") ~= 1 then
        table.insert(Barrier, Ahead)
    end
    local Target, Distance = nil, math.huge
    for _, Enemy in EnemyFolder:GetChildren() do
        local EnemyRoot = Enemy:FindFirstChild("HumanoidRootPart")
        local Humanoid = Enemy:FindFirstChildOfClass("Humanoid")
        if EnemyRoot and Humanoid and Humanoid.Health > 0 then
            local Blocked = false
            for _, Door in Barrier do
                if Func:Beyond(Door, EnemyRoot.Position, Position) then
                    Blocked = true
                    break
                end
            end
            local Current = (EnemyRoot.Position - Position).Magnitude
            if not Blocked and Current < Distance then
                Target = Enemy
                Distance = Current
            end
        end
    end
    if Target then
        Func:Attack(Target, HumanoidRootPart)
        return
    end
    if Controller and Controller.HoldingBaseAttack then
        pcall(function()
            Controller:StopAction("BaseAttack")
        end)
    end
    local Remote = GateRoot and GateRoot:FindFirstChild("RE")
    if GateRoot and GateRoot:GetAttribute("Switch") ~= 1 then
        if Remote and os.clock() >= NextOpen then
            NextOpen = os.clock() + 0.5
            Remote:FireServer()
        end
        return
    end
    local GatePart = Gate and Gate:FindFirstChild("Door")
    local AheadPart = Ahead and Ahead:FindFirstChild("Door")
    local PortalRoot = Func:Portal(DoorFolder, Round - 1, Position)
    if PortalRoot then
        local Safe = PortalRoot:FindFirstChild("Safe")
        local Remote = PortalRoot:FindFirstChild("RF")
        if Remote and (not Safe or (Position - Safe.Position).Magnitude > 60) and os.clock() >= NextPortal then
            NextPortal = os.clock() + 2
            pcall(function()
                Remote:InvokeServer()
            end)
        end
        return
    end
    if GatePart then
        local Deep = Func:Forward(DoorFolder, GatePart, Round, Position)
        if Deep and (Position - GatePart.Position):Dot(Deep) < 20 then
            Func:Move(GatePart.Position + Deep * 25, HumanoidRootPart)
            return
        end
    end
    if AheadPart then
        local Offset = Vector3.new(Position.X - AheadPart.Position.X, 0, Position.Z - AheadPart.Position.Z)
        if Offset.Magnitude > 14 then
            Func:Move(AheadPart.Position + Offset.Unit * 10, HumanoidRootPart)
        end
    end
end

function Func:ClickGui(Target)
    if typeof(Target) ~= "Instance" or not Target:IsA("GuiObject") then
        return
    end
    if InteractDuplicated[Target] then
        return
    end
    InteractDuplicated[Target] = true
    local Clicked = false
    for _, EventName in next, { "Activated", "MouseButton1Down", "MouseButton1Click", "MouseButton1Up" } do
        pcall(function()
            for _, Connection in next, getconnections(Target[EventName]) do
                pcall(function()
                    if type(Connection.Function) ~= "function" then
                        return
                    end
                    Connection.Function()
                    Clicked = true
                end)
            end
        end)
    end
    if not Clicked then
        xpcall(function()
            for _ = 1, 10 do
                GuiService.SelectedObject = Target
                if GuiService.SelectedObject == Target then
                    break
                end
                task.wait()
            end
            if GuiService.SelectedObject == Target then
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
            end
            GuiService.SelectedObject = nil
        end, function() end)
    end
    InteractDuplicated[Target] = false
end

function Func:Room(Position)
    local Folder = workspace:FindFirstChild("MatchRoom")
    if not Folder then
        return nil
    end
    local Result, Distance = nil, math.huge
    for _, Value in Folder:GetChildren() do
        local Part = Value:FindFirstChild("Root") or Value:FindFirstChildWhichIsA("BasePart")
        if Part and Value:GetAttribute("Mode") == "Story" then
            local Current = (Part.Position - Position).Magnitude
            if Current < Distance then
                Result = Value
                Distance = Current
            end
        end
    end
    return Result
end

function Func:Join()
    local MainGui = PlayerGui:FindFirstChild("MainGui")
    local Screen = MainGui and MainGui:FindFirstChild("ScreenMatch")
    local Character = LocalPlayer.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
    if not Screen or not Humanoid or not HumanoidRootPart then
        return false
    end
    local Blocked = false
    if FrameworkOk then
        pcall(function()
            local Info = Framework.Modules.WorldUtil:GetWorldDiffInfo(Config["World"], Config["Difficulty"])
            if Info and Info.LootType == "Ore" then
                Blocked = not Framework.Modules.ForgeUtil:CheckCanAdd(LocalPlayer, 1)
            elseif Info and Info.LootType == "Material" then
                Blocked = not Framework.Modules.MaterialUtil:CheckCanAdd(LocalPlayer, 1)
            end
        end)
    end
    if Blocked then
        return true
    end
    if not Screen.Visible then
        local Room = Func:Room(HumanoidRootPart.Position)
        local Part = Room and (Room:FindFirstChild("Root") or Room:FindFirstChildWhichIsA("BasePart"))
        if not Part then
            return false
        end
        local Offset = HumanoidRootPart.Position - Part.Position
        Offset = Vector3.new(Offset.X, 0, Offset.Z)
        if Offset.Magnitude < 1 then
            Offset = Vector3.new(0, 0, 1)
        else
            Offset = Offset.Unit
        end
        HumanoidRootPart.CFrame = CFrame.new(Part.Position + Offset * 16 + Vector3.new(0, 3, 0))
        task.wait(0.2)
        Humanoid:MoveTo(Part.Position)
        local Deadline = os.clock() + 4
        while os.clock() < Deadline and not Screen.Visible do
            task.wait(0.1)
        end
        if not Screen.Visible then
            return false
        end
    end
    local Scroll = Screen.WorldFrame.ChapterFrame.Tab:FindFirstChild("ScrollingFrame")
    local WorldItem = Scroll and Scroll:FindFirstChild(Config["World"])
    local WorldButton = WorldItem and WorldItem:FindFirstChild("Btn")
    if WorldButton then
        Func:ClickGui(WorldButton)
        task.wait(0.25)
    end
    local DiffTab = Screen.WorldFrame.DiffTabs:FindFirstChild(tostring(Config["Difficulty"]))
    if DiffTab then
        Func:ClickGui(DiffTab)
        task.wait(0.25)
    end
    local Control = Screen.Control
    local MatchCount = Control.Match:FindFirstChild("MatchCount")
    local MinusButton = Control.Match:FindFirstChild("MinusButton")
    if MatchCount and MinusButton then
        for _ = 1, 4 do
            if MatchCount.Text == "1" then
                break
            end
            Func:ClickGui(MinusButton)
            task.wait(0.15)
        end
    end
    local CreateButton = Control:FindFirstChild("CreatBtn")
    if CreateButton then
        Func:ClickGui(CreateButton)
    end
    task.wait(0.3)
    return false
end

function Func:AutoJoin()
    if os.clock() < NextJoin then
        return
    end
    if LocalPlayer:GetAttribute("EnterRoomId") or ReplicatedStorage:FindFirstChild("GameRoundCfg") then
        NextJoin = os.clock() + 10
        return
    end
    NextJoin = os.clock() + 15
    if Func:Join() then
        NextJoin = os.clock() + 30
    end
end

function Func:Sell()
    if not FrameworkOk then
        return
    end
    local Ores, Crystals = {}, {}
    for Key in next, Config["Sell Items"] do
        if Framework.Modules.ForgeUtil:IsValidId(Key) then
            Ores[Key] = 0
        elseif Framework.Modules.MaterialUtil:IsValidId(Key) then
            Crystals[Key] = 0
        end
    end
    if next(Ores) then
        pcall(function()
            Framework.Modules.ForgeUtil:Sell(LocalPlayer, Ores)
        end)
    end
    if next(Crystals) then
        pcall(function()
            Framework.Modules.MaterialUtil:Sell(LocalPlayer, Crystals, {})
        end)
    end
end

function Func:SellList(Scroll)
    for _, Row in next, Scroll:GetChildren() do
        if Row:IsA("GuiObject") then
            Row:Destroy()
        end
    end
    if not FrameworkOk then
        return
    end
    local Items = {}
    local OreOk, Ores = pcall(function()
        return Framework.Modules.ForgeUtil:GetOres(LocalPlayer)
    end)
    if OreOk and type(Ores) == "table" then
        for Key, Count in next, Ores do
            if Count > 0 then
                Items[Key] = Count
            end
        end
    end
    local CrystalOk, Crystals = pcall(function()
        return Framework.Modules.DataUtil:GetValue(LocalPlayer, { "Crystals" })
    end)
    if CrystalOk and type(Crystals) == "table" then
        for Key, Count in next, Crystals do
            if Count > 0 and not Items[Key] then
                Items[Key] = Count
            end
        end
    end
    local Keys = {}
    for Key in next, Items do
        table.insert(Keys, Key)
    end
    table.sort(Keys)
    for Index, Key in next, Keys do
        local Selected = Config["Sell Items"][Key] == true
        local Button = Func:Create("TextButton", {
            Name = Key,
            LayoutOrder = Index,
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = Selected and Theme.Accent or Theme.Surface,
            AutoButtonColor = false,
            Font = Enum.Font.Gotham,
            Text = string.format("%s  x%d", Key, Items[Key]),
            TextColor3 = Selected and Theme.Background or Theme.Muted,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = Scroll,
        })
        Func:Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = Button })
        Func:Create("UIPadding", {
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
            Parent = Button,
        })
        Button.MouseButton1Click:Connect(function()
            if Config["Sell Items"][Key] then
                Config["Sell Items"][Key] = nil
            else
                Config["Sell Items"][Key] = true
            end
            local Active = Config["Sell Items"][Key] == true
            Button.BackgroundColor3 = Active and Theme.Accent or Theme.Surface
            Button.TextColor3 = Active and Theme.Background or Theme.Muted
            Func:Save()
        end)
    end
end

function Func:Create(ClassName, Properties)
    local Object = Instance.new(ClassName)
    for Key, Value in next, Properties do
        Object[Key] = Value
    end
    return Object
end

function Func:Choice(Parent, Key, Value, Title)
    local Button = Func:Create("TextButton", {
        Name = Key .. "_" .. tostring(Value),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Surface,
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = Title,
        TextColor3 = Theme.Muted,
        TextSize = 11,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = Parent,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = Button })
    local Entry = {}
    Entry.Apply = function()
        local Selected = Config[Key] == Value
        Button.BackgroundColor3 = Selected and Theme.Accent or Theme.Surface
        Button.TextColor3 = Selected and Theme.Background or Theme.Muted
    end
    Entry.Apply()
    Choices[Key] = Choices[Key] or {}
    table.insert(Choices[Key], Entry)
    Button.MouseButton1Click:Connect(function()
        Config[Key] = Value
        for _, Other in next, Choices[Key] do
            Other.Apply()
        end
        Func:Save()
    end)
end

function Func:Toggle(Parent, Key, Title, Desc)
    local Row = Func:Create("Frame", {
        Name = Key,
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        Parent = Parent,
    })
    Func:Create("TextLabel", {
        Position = UDim2.fromOffset(0, 2),
        Size = UDim2.new(1, -60, 0, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = Title,
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Row,
    })
    Func:Create("TextLabel", {
        Position = UDim2.fromOffset(0, 20),
        Size = UDim2.new(1, -60, 0, 16),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = Desc,
        TextColor3 = Theme.Muted,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = Row,
    })
    local Switch = Func:Create("Frame", {
        Name = "Switch",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 8),
        Size = UDim2.fromOffset(42, 22),
        BackgroundColor3 = Theme.Surface,
        Parent = Row,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = Switch })
    local Knob = Func:Create("Frame", {
        Position = UDim2.fromOffset(3, 3),
        Size = UDim2.fromOffset(16, 16),
        BackgroundColor3 = Theme.Muted,
        Parent = Switch,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = Knob })
    local Active
    local function Apply(State)
        Switch.BackgroundColor3 = State and Theme.Accent or Theme.Surface
        Knob.BackgroundColor3 = State and Theme.Text or Theme.Muted
        if Active then
            Active:Cancel()
        end
        Active = TweenService:Create(Knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = State and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
        })
        Active:Play()
    end
    Apply(Config[Key])
    Func:Create("TextButton", {
        Name = "Click",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        Parent = Switch,
    }).MouseButton1Click:Connect(function()
        Config[Key] = not Config[Key]
        Apply(Config[Key])
        Func:Save()
    end)
end

function Func:Slider(Parent, Key, Title, Min, Max, Step)
    local Row = Func:Create("Frame", {
        Name = "Row",
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
        Parent = Parent,
    })
    Func:Create("TextLabel", {
        Size = UDim2.new(1, -60, 0, 16),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = Title,
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Row,
    })
    local Label = Func:Create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(60, 16),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = "",
        TextColor3 = Theme.Accent,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = Row,
    })
    local Track = Func:Create("Frame", {
        Name = "Track",
        Position = UDim2.fromOffset(0, 26),
        Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = Theme.Surface,
        Parent = Row,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = Track })
    local Fill = Func:Create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.Accent,
        Parent = Track,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = Fill })
    local Button = Func:Create("TextButton", {
        Name = "Click",
        Position = UDim2.fromOffset(0, -7),
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = "",
        Parent = Track,
    })
    local Dragging = false
    local Decimals = 0
    local Probe = Step
    while Probe < 1 and Decimals < 4 do
        Probe = Probe * 10
        Decimals = Decimals + 1
    end
    local function Apply(Value)
        Value = math.clamp(Value, Min, Max)
        Value = math.floor((Value - Min) / Step + 0.5) * Step + Min
        Value = tonumber(string.format("%." .. Decimals .. "f", Value))
        Config[Key] = Value
        Fill.Size = UDim2.fromScale((Value - Min) / (Max - Min), 1)
        Label.Text = string.format("%." .. Decimals .. "f", Value)
    end
    local function FromInput(Input)
        Apply(Min + (Input.Position.X - Track.AbsolutePosition.X) / math.max(Track.AbsoluteSize.X, 1) * (Max - Min))
    end
    Apply(Config[Key])
    Button.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 and Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        Dragging = true
        FromInput(Input)
        Func:Save()
    end)
    UserInputService.InputChanged:Connect(function(Input)
        if not Dragging then
            return
        end
        if Input.UserInputType ~= Enum.UserInputType.MouseMovement and Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        FromInput(Input)
        Func:Save()
    end)
    UserInputService.InputEnded:Connect(function(Input)
        if not Dragging then
            return
        end
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 and Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        Dragging = false
        Func:Save()
    end)
end

function Func:Window()
    local Gui = Func:Create("ScreenGui", {
        Name = "Iron",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = PlayerGui,
    })
    local Main = Func:Create("Frame", {
        Name = "Main",
        Position = UDim2.new(0, 16, 0.5, -190),
        Size = UDim2.fromOffset(320, 380),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Parent = Gui,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = Main })
    Func:Create("UIStroke", { Color = Theme.Stroke, Parent = Main })
    local Header = Func:Create("Frame", {
        Name = "Header",
        Active = true,
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = Main,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = Header })
    Func:Create("Frame", {
        Position = UDim2.fromOffset(0, 28),
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = Header,
    })
    Func:Create("TextLabel", {
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -80, 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = "IRON DUNGEON",
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Header,
    })
    local TabBar = Func:Create("Frame", {
        Name = "TabBar",
        Position = UDim2.fromOffset(0, 38),
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        Parent = Main,
    })
    Func:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
        PaddingTop = UDim.new(0, 5),
        Parent = TabBar,
    })
    Func:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = TabBar,
    })
    local FarmPage = Func:Create("Frame", {
        Name = "FarmPage",
        Position = UDim2.fromOffset(0, 70),
        Size = UDim2.new(1, 0, 1, -70),
        BackgroundTransparency = 1,
        Parent = Main,
    })
    Func:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 10),
        Parent = FarmPage,
    })
    Func:Create("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = FarmPage,
    })
    local JoinPage = Func:Create("Frame", {
        Name = "JoinPage",
        Position = UDim2.fromOffset(0, 70),
        Size = UDim2.new(1, 0, 1, -70),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = Main,
    })
    Func:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 10),
        Parent = JoinPage,
    })
    Func:Create("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = JoinPage,
    })
    local SellPage = Func:Create("Frame", {
        Name = "SellPage",
        Position = UDim2.fromOffset(0, 70),
        Size = UDim2.new(1, 0, 1, -70),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = Main,
    })
    Func:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 10),
        Parent = SellPage,
    })
    Func:Create("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = SellPage,
    })
    Func:Toggle(SellPage, "Auto Sell", "Auto Sell", "Sell every checked item on a timer")
    Func:Slider(SellPage, "Sell Interval", "Sell Interval", 5, 60, 5)
    local SellScroll = Func:Create("ScrollingFrame", {
        Name = "SellScroll",
        Size = UDim2.new(1, 0, 0, 122),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = SellPage,
    })
    Func:Create("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = SellScroll,
    })
    local SellActions = Func:Create("Frame", {
        Name = "SellActions",
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        Parent = SellPage,
    })
    Func:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = SellActions,
    })
    local RefreshButton = Func:Create("TextButton", {
        Name = "Refresh",
        Size = UDim2.new(0.5, -3, 1, 0),
        BackgroundColor3 = Theme.Surface,
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = "REFRESH",
        TextColor3 = Theme.Muted,
        TextSize = 11,
        Parent = SellActions,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = RefreshButton })
    local SellNow = Func:Create("TextButton", {
        Name = "SellNow",
        Size = UDim2.new(0.5, -3, 1, 0),
        BackgroundColor3 = Theme.Accent,
        AutoButtonColor = false,
        Font = Enum.Font.GothamBold,
        Text = "SELL NOW",
        TextColor3 = Theme.Background,
        TextSize = 11,
        Parent = SellActions,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = SellNow })
    RefreshButton.MouseButton1Click:Connect(function()
        Func:SellList(SellScroll)
    end)
    SellNow.MouseButton1Click:Connect(function()
        Func:Sell()
    end)
    local FarmTab = Func:Create("TextButton", {
        Name = "FarmTab",
        Size = UDim2.fromOffset(78, 22),
        BackgroundColor3 = Theme.Accent,
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = "Dungeon",
        TextColor3 = Theme.Background,
        TextSize = 12,
        Parent = TabBar,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = FarmTab })
    local JoinTab = Func:Create("TextButton", {
        Name = "JoinTab",
        Size = UDim2.fromOffset(78, 22),
        BackgroundColor3 = Theme.Surface,
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = "Join",
        TextColor3 = Theme.Muted,
        TextSize = 12,
        Parent = TabBar,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = JoinTab })
    local SellTab = Func:Create("TextButton", {
        Name = "SellTab",
        Size = UDim2.fromOffset(78, 22),
        BackgroundColor3 = Theme.Surface,
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = "Sell",
        TextColor3 = Theme.Muted,
        TextSize = 12,
        Parent = TabBar,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = SellTab })
    local Pages = {
        Dungeon = FarmPage,
        Join = JoinPage,
        Sell = SellPage,
    }
    local Tabs = {
        Dungeon = FarmTab,
        Join = JoinTab,
        Sell = SellTab,
    }
    local Shown = "Dungeon"
    local Expanded = true
    local function ShowPage(Name)
        Shown = Name
        for Key, Page in next, Pages do
            Page.Visible = Expanded and Key == Name
            Tabs[Key].BackgroundColor3 = Key == Name and Theme.Accent or Theme.Surface
            Tabs[Key].TextColor3 = Key == Name and Theme.Background or Theme.Muted
        end
        if Name == "Sell" then
            Func:SellList(SellScroll)
        end
    end
    FarmTab.MouseButton1Click:Connect(function()
        ShowPage("Dungeon")
    end)
    JoinTab.MouseButton1Click:Connect(function()
        ShowPage("Join")
    end)
    SellTab.MouseButton1Click:Connect(function()
        ShowPage("Sell")
    end)
    Func:Toggle(FarmPage, "Auto Dungeon", "Auto Dungeon", "Clear each round, open the door, then farm the next round")
    Func:Toggle(FarmPage, "Auto Skill", "Auto Skill", "Cast Skill1-3, SkillU and SkillAW whenever they are ready")
    Func:Slider(FarmPage, "Head Height", "Head Height", 0, 15, 0.5)
    Func:Slider(FarmPage, "Head Rotation", "Head Rotation", -180, 180, 5)
    Func:Slider(FarmPage, "Attack Interval", "Attack Interval", 0.1, 1, 0.05)
    Func:Create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = "Dungeon",
        TextColor3 = Theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = JoinPage,
    })
    local WorldGrid = Func:Create("Frame", {
        Name = "WorldGrid",
        Size = UDim2.new(1, 0, 0, 60),
        BackgroundTransparency = 1,
        Parent = JoinPage,
    })
    Func:Create("UIGridLayout", {
        CellSize = UDim2.fromOffset(138, 26),
        CellPadding = UDim2.fromOffset(6, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = WorldGrid,
    })
    Func:Choice(WorldGrid, "World", "World1", "Starless Forest")
    Func:Choice(WorldGrid, "World", "World2", "Frozen Valley")
    Func:Choice(WorldGrid, "World", "World3", "Oathlost Castle")
    Func:Choice(WorldGrid, "World", "World4", "Tartarus")
    Func:Create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = "Difficulty",
        TextColor3 = Theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = JoinPage,
    })
    local DiffGrid = Func:Create("Frame", {
        Name = "DiffGrid",
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundTransparency = 1,
        Parent = JoinPage,
    })
    Func:Create("UIGridLayout", {
        CellSize = UDim2.fromOffset(90, 24),
        CellPadding = UDim2.fromOffset(6, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = DiffGrid,
    })
    Func:Choice(DiffGrid, "Difficulty", 1, "Trial")
    Func:Choice(DiffGrid, "Difficulty", 2, "Challenge")
    Func:Choice(DiffGrid, "Difficulty", 3, "Penitent")
    Func:Choice(DiffGrid, "Difficulty", 4, "Torment")
    Func:Choice(DiffGrid, "Difficulty", 5, "Inferno")
    Func:Toggle(JoinPage, "Auto Join", "Auto Join", "Create a room for the selected dungeon on its own")
    local JoinNow = Func:Create("TextButton", {
        Name = "JoinNow",
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.Accent,
        AutoButtonColor = false,
        Font = Enum.Font.GothamBold,
        Text = "JOIN DUNGEON",
        TextColor3 = Theme.Background,
        TextSize = 13,
        Parent = JoinPage,
    })
    Func:Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = JoinNow })
    local Hint = Func:Create("TextLabel", {
        Name = "Hint",
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = "",
        TextColor3 = Color3.fromRGB(255, 122, 122),
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = JoinPage,
    })
    JoinNow.MouseButton1Click:Connect(function()
        Hint.Text = Func:Join() and "Bag full, clear it before joining" or ""
    end)
    local Hide = Func:Create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 9),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = "-",
        TextColor3 = Theme.Muted,
        TextSize = 16,
        Parent = Header,
    })
    Hide.MouseButton1Click:Connect(function()
        Expanded = not Expanded
        TabBar.Visible = Expanded
        for Key, Page in next, Pages do
            Page.Visible = Expanded and Key == Shown
        end
        Main.Size = Expanded and UDim2.fromOffset(320, 380) or UDim2.fromOffset(320, 38)
    end)
    local Dragging = false
    local StartPosition, StartInput
    Header.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 and Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        Dragging = true
        StartPosition = Main.Position
        StartInput = Input.Position
    end)
    UserInputService.InputChanged:Connect(function(Input)
        if not Dragging then
            return
        end
        if Input.UserInputType ~= Enum.UserInputType.MouseMovement and Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local Delta = Input.Position - StartInput
        Main.Position = UDim2.new(StartPosition.X.Scale, StartPosition.X.Offset + Delta.X, StartPosition.Y.Scale, StartPosition.Y.Offset + Delta.Y)
    end)
    UserInputService.InputEnded:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 and Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        Dragging = false
    end)
    UserInputService.InputBegan:Connect(function(Input, Processed)
        if Processed then
            return
        end
        if Input.KeyCode == Enum.KeyCode.RightShift then
            Main.Visible = not Main.Visible
        end
    end)
end

Func:Load()
Func:Save()

-- LOOPS
task.spawn(function()
    while task.wait() do
        pcall(function()
            if Config["Auto Dungeon"] then
                Func:Run()
            end
        end)
    end
end)

task.spawn(function()
    while task.wait() do
        pcall(function()
            if Config["Auto Join"] then
                Func:AutoJoin()
            end
        end)
    end
end)

task.spawn(function()
    while task.wait() do
        pcall(function()
            if Config["Auto Sell"] then
                if os.clock() >= NextSell then
                    NextSell = os.clock() + Config["Sell Interval"]
                    Func:Sell()
                end
            end
        end)
    end
end)

-- UI
pcall(function()
    Func:Window()
end)
