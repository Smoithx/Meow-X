-- Iron Soul | Auto Dungeon (Tween) + Auto Attack + Auto Skill
-- Game: Iron Soul (Starless Forest / World1..5) + Auto Join (Dungeon Select)

if not game:IsLoaded() then
    game.Loaded:Wait()
end

if not LPH_OBFUSCATED then
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Luraph/macrosdk/main/luraphsdk.lua"))()
end

local cloneref = cloneref or function(instance)
    return instance
end

-- SERVICES

local Players = cloneref(game:GetService("Players"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local CollectionService = cloneref(game:GetService("CollectionService"))
local TweenService = cloneref(game:GetService("TweenService"))
local RunService = cloneref(game:GetService("RunService"))
local TeleportService = cloneref(game:GetService("TeleportService"))
local GuiService = cloneref(game:GetService("GuiService"))
local VirtualInputManager = cloneref(game:GetService("VirtualInputManager"))
local HttpService = cloneref(game:GetService("HttpService"))

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- REMOTES

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameRoundRE = Remotes:FindFirstChild("GameRoundRE")

-- GameRoundCfg only replicates inside a dungeon instance. Lobby has none, so it is
-- resolved on the fly and every read is guarded.
local GameRoundCfg

-- MODULES

local Framework = require(ReplicatedStorage:WaitForChild("Framework"))

local FinderOk, FinderUtility = pcall(require, ReplicatedStorage:WaitForChild("GameUtil"):WaitForChild("FinderUtility"))

local WorldUtil
local ModuleOk, Modules = pcall(function()
    return Framework.Modules
end)
if ModuleOk and type(Modules) == "table" then
    WorldUtil = Modules.WorldUtil
end

-- GamePlaceUtil is optional: it is the only thing that knows the place names, and
-- the Script still runs without it by reading the WorldId attribute instead.
local GamePlaceUtil
pcall(function()
    GamePlaceUtil = require(ReplicatedStorage:WaitForChild("Utility"):WaitForChild("GamePlaceUtil"))
end)

-- CONFIG

local DefaultConfig = {
    ["Auto Dungeon"] = true,
    ["Auto Attack"] = true,
    ["Auto Skill"] = true,
    ["Auto Replay"] = false,
    ["Attack Distance"] = 4.5,
    ["Tween Speed"] = 60,
    ["Kill Radius"] = 14,
    ["Skill Delay"] = 0.35,
    ["Auto Join"] = false,
    ["Join World"] = "World1",
    ["Join Stage"] = 1,
    ["Join Hell"] = false,
    ["Join Players"] = 1,
    ["Join Retry"] = 3,
    ["Auto Sell Ores"] = false,
    ["Sell Ore Rarities"] = { "Common" },
    ["Keep Ores"] = 0,
    ["Auto Sell Armor"] = false,
    ["Sell Armor Rarities"] = { "Common" },
}

Config = Config or {}
for Key, Value in pairs(DefaultConfig) do
    if Config[Key] == nil then
        Config[Key] = Value
    end
end

-- SAVE

local SaveFolder = "Iron Soul"
local SaveFile = SaveFolder .. "/Config.json"
local SaveSupported = readfile and writefile and isfile and isfolder and makefolder

local function EncodeCFrame(CF)
    local RX, RY, RZ = CF:ToOrientation()
    return { X = CF.Position.X, Y = CF.Position.Y, Z = CF.Position.Z, RX = RX, RY = RY, RZ = RZ }
end

local function DecodeCFrame(Value)
    if typeof(Value) == "table" and Value.__cframe then
        Value = Value.__cframe
    end
    if typeof(Value) ~= "table" then
        return nil
    end
    for _, Key in ipairs({ "X", "Y", "Z", "RX", "RY", "RZ" }) do
        if type(Value[Key]) ~= "number" then
            return nil
        end
    end
    return CFrame.new(Value.X, Value.Y, Value.Z) * CFrame.Angles(Value.RX, Value.RY, Value.RZ)
end

local function SaveSettings()
    if not SaveSupported then
        return false, "Executor Not Support Save System"
    end

    local Success, Error = pcall(function()
        if not isfolder(SaveFolder) then
            makefolder(SaveFolder)
        end
        local SaveData = {}
        for Key, Value in pairs(Config) do
            if typeof(Value) == "CFrame" then
                SaveData[Key] = { __cframe = EncodeCFrame(Value) }
            else
                SaveData[Key] = Value
            end
        end
        local Encoded = HttpService:JSONEncode(SaveData)
        if not isfile(SaveFile) or readfile(SaveFile) ~= Encoded then
            writefile(SaveFile, Encoded)
        end
    end)
    if not Success then
        warn("[Iron Soul] SaveSettings failed: " .. tostring(Error))
    end
    return Success, Error
end

local function LoadSettings()
    if not SaveSupported then
        warn("Executor Not Support Save System")
        return false
    end

    local Success, Data = pcall(function()
        if not isfolder(SaveFolder) then
            makefolder(SaveFolder)
        end
        if not isfile(SaveFile) then
            return nil
        end
        return HttpService:JSONDecode(readfile(SaveFile))
    end)
    if not Success then
        warn("[Iron Soul] LoadSettings failed: " .. tostring(Data))
        return false
    end
    if Data == nil then
        return SaveSettings()
    end
    if type(Data) ~= "table" then
        warn("[Iron Soul] Invalid settings: expected a JSON object")
        return false
    end
    for Key, Value in pairs(Data) do
        if Key == "Save Position" or (typeof(Value) == "table" and Value.__cframe) then
            Config[Key] = DecodeCFrame(Value) or Value
        else
            Config[Key] = Value
        end
    end
    return true
end

LoadSettings()

-- INVENTORY MODULES

local EquipmentUtil = Framework.Modules.EquipmentUtil
local EquipmentData = Framework.Modules.EquipmentData
local ForgeUtil = Framework.Modules.ForgeUtil
local CodesRF = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Systems")
    :WaitForChild("CodesSystem"):WaitForChild("CodesRF", 10)
local RarityNames = {}
for Index, Tier in ipairs(Framework.Modules.RarityTiers.Tiers) do
    RarityNames[Index] = Tier.Name
end
local InventoryState = {
    RedeemBusy = false,
    OresBusy = false,
    ArmorBusy = false,
    OresNote = "พร้อม",
    ArmorNote = "พร้อม",
}

-- CONSTANTS

-- Public code lists checked 2026-10-17; redemption availability is decided by the game.
-- https://robloxden.com/game-codes/iron-soul-dungeon
-- https://beebom.com/iron-soul-dungeon-codes/
-- https://www.destructoid.com/iron-soul-dungeon-codes/
local REDEEM_CODES = {
    "IRONSOULWEEKEND28",
    "BOWANDSKILLTREE",
    "IRONSOULWEEKEND27",
    "TRADEISLANDUPDATE",
    "RAGNAROK",
    "IRONWEEKENDGIFT26",
    "IRONTRADETYCOON",
    "SEASON4COMING",
    "IRONSOULBIGUPDATE",
    "BOSSODINARRIVED",
    "IRONSOULWEEKEND25",
    "SEASON3ENDEVENT",
    "IRONSMALLUPDATE",
    "IRONNEWUPDATE",
    "IRONSOULWEEKEND24",
    "MAP5HELL",
    "IRONSOULWEEKEND23",
    "MAP5COMING",
    "IRONSOULWEEKEND22",
    "SEASON3EXPANSION",
    "250KMEMBERGIFT",
    "LALAGANG",
    "IRONSOULWEEKEND21",
    "Ahjughh",
    "SEASONVOUCHER",
    "IRONSOULWEEKEND17",
    "SCYTHEWEAPON",
    "NEWMAP",
    "CELEBRATEFOR150KMEMBER",
    "NEWMAPEXPAND",
    "IRONSOULWEEKEND16",
    "IRONSOULWEEKEND15",
    "SEASON2EXPAND",
    "DMGHOTFIX",
    "SEASONSPINSSS",
    "IRONSOULWEEKEND14",
    "TGIFSEASON2",
    "SEASON2GIFTA",
    "SEASON2LIVE",
    "SEASON2OPEN",
    "IRONSOULWEEKEND13",
}

local SKILL_ORDER = { "SkillU", "Skill2", "Skill1" }
local ENEMY_TAG = "EnemyNpc"
local ROOT_NAME = "Root"

-- Room centres are read from the instance itself, so the Script works on every
-- world and difficulty instead of relying on one hardcoded map.
local WaypointCache = {}

-- AUTO JOIN DATA

-- Names are the exact UI title from Dungeon Select. PlaceId and mode come from the
-- game itself, so the config only carries what the UI cannot show.
local JOIN_WORLDS = {
    { Key = "World1", Title = "Starless Forest", PlaceId = 116456628154258, Mode = "Story", Hell = true },
    { Key = "World2", Title = "Crimson Ravine", PlaceId = 136216144170036, Mode = "Story", Hell = true },
    { Key = "World3", Title = "Sundered Highlands", PlaceId = 112316840155266, Mode = "Story", Hell = true },
    { Key = "World4", Title = "Abyssal Realm", PlaceId = 80693195250724, Mode = "Story", Hell = true },
    { Key = "World5", Title = "Timeless Dunes", PlaceId = 132785415090516, Mode = "Story", Hell = true },
    { Key = "Cave1", Title = "Frozen Valley", PlaceId = 91584731222940, Mode = "Resource", Hell = false },
    { Key = "Cave2", Title = "Oathlost Castle", PlaceId = 119524374829397, Mode = "Resource", Hell = false },
    { Key = "Cave3", Title = "Tartarus", PlaceId = 132445869992129, Mode = "Resource", Hell = false },
    { Key = "Endless1", Title = "Endless", PlaceId = 88838868041067, Mode = "Endless", Hell = false },
    { Key = "ValhallaCombatArena", Title = "Valhalla Arena", PlaceId = 96723078832427, Mode = "Valhalla", Hell = true },
    { Key = "SeasonResource1", Title = "Season Resource", PlaceId = 130098968673165, Mode = "SeasonResource", Hell = false },
    { Key = "Lobby", Title = "Lobby", PlaceId = 117533937949084, Mode = "Lobby", Hell = false },
}

-- Stage names map to Difficulty 1..5 and to the closest tab name in Dungeon Select,
-- so the UI shows the same label the game uses for that stage.
local JOIN_STAGES = { "Trial", "Challenge", "Pertent", "Torment", "Inferno" }

-- Stages that are actually playable per mode; everything else is a locked tab.

local function GetRoomWaypoint(Round)
    if not Round or Round <= 0 then
        return nil
    end

    if WaypointCache[Round] then
        return WaypointCache[Round]
    end

    local Folder = workspace:FindFirstChild("WorldEnemys")
    if not Folder then
        return nil
    end

    -- 1) RoundWakeTouch is the room trigger that starts the round.
    local WakeFolder = Folder:FindFirstChild("RoundWakeTouch")
    if WakeFolder then
        local Wake = WakeFolder:FindFirstChild("Round" .. Round)
        if Wake and Wake:IsA("BasePart") then
            local Position = Vector3.new(Wake.Position.X, Wake.Position.Y, Wake.Position.Z)
            WaypointCache[Round] = Position
            return Position
        end
    end

    -- 2) Fall back to the average spawn point of that round.
    local SpawnFolder = Folder:FindFirstChild("RoundSpawnGroup")
    if SpawnFolder then
        local Group = SpawnFolder:FindFirstChild("Round" .. Round)
        if Group then
            local Total, Count = Vector3.new(0, 0, 0), 0
            for _, Point in ipairs(Group:GetChildren()) do
                if Point:IsA("BasePart") then
                    Total = Total + Point.Position
                    Count = Count + 1
                end
            end
            if Count > 0 then
                local Position = Total / Count
                WaypointCache[Round] = Position
                return Position
            end
        end
    end

    -- 3) Last resort: the round trigger of the highest round that exists.
    if WakeFolder then
        local Best, BestRound = nil, -1
        for _, Wake in ipairs(WakeFolder:GetChildren()) do
            local Number = tonumber(string.match(Wake.Name, "Round(%d+)"))
            if Number and Number <= Round and Number > BestRound and Wake:IsA("BasePart") then
                Best, BestRound = Wake, Number
            end
        end
        if Best then
            local Position = Best.Position
            WaypointCache[Round] = Position
            return Position
        end
    end

    return nil
end

-- STATE

local State = {
    Round = 0,
    RoundComplete = 0,
    MaxRound = 0,
    LastSkill = 0,
    LastRequeue = 0,
    LastProgress = 0,
    LastSignature = "",
    LastPortal = 0,
    LastJoin = 0,
    LastJoinAttempt = 0,
    JoinTries = 0,
    JoinNote = "พร้อม",
}

-- FUNCTIONS

local function GetCharacter()
    return LocalPlayer.Character
end

local function GetRootPart()
    local Character = GetCharacter()
    return Character and Character:FindFirstChild("HumanoidRootPart")
end

local function GetHumanoid()
    local Character = GetCharacter()
    return Character and Character:FindFirstChildOfClass("Humanoid")
end

local function GetController()
    for _, RenderStep in ipairs(getrendersteppedlist()) do
        if RenderStep.Name == "PlayerControl" then
            local Upvalues = debug.getupvalues(RenderStep.Function)
            return Upvalues and Upvalues[1]
        end
    end
    return nil
end

local function GetEnemyRoot(Model)
    if not Model or not Model.Parent then
        return nil
    end

    local Humanoid = Model:FindFirstChildOfClass("Humanoid")
    if not Humanoid or Humanoid.Health <= 0 then
        return nil
    end

    local Root = Humanoid.RootPart or Model:FindFirstChild(ROOT_NAME) or Model.PrimaryPart
    if not Root or not Root.Parent then
        return nil
    end

    return Root, Humanoid
end

-- Enemy body parts are streamed in separately from the model. These helpers push
-- the streaming system toward the room the round is supposed to happen in.
local function RequestStream(Position)
    local Ok = pcall(function()
        workspace:RequestStreamAroundAsync(Position, 2)
    end)
    return Ok
end

-- RoomDoor portals teleport through their own RemoteFunction; invoking it is the
-- only way to land in the boss arena so its enemies replicate with bodies.
local function FindPortalParts(Model)
    local Remote
    local Destination

    local Root = Model:FindFirstChild("Root")
    if Root then
        Remote = Root:FindFirstChild("RF")
        local To = Root:FindFirstChild("To")
        if To and To:IsA("Attachment") then
            Destination = To.WorldPosition
        end
    end

    if not Destination then
        local FX = Model:FindFirstChild("FX")
        local To = FX and FX:FindFirstChild("To")
        if To and To:IsA("Attachment") then
            Destination = To.WorldPosition
        end
    end

    return Remote, Destination
end

local function GetPortals()
    local Portals = {}
    local Folder = workspace:FindFirstChild("RoundDoor")

    if not Folder then
        return Portals
    end

    for _, Model in ipairs(Folder:GetChildren()) do
        if Model.Name == "Portal" then
            local Remote, Destination = FindPortalParts(Model)
            if Remote and Destination then
                table.insert(Portals, { Model = Model, Remote = Remote, Destination = Destination })
            end
        end
    end

    return Portals
end

local function EnterNearestPortal()
    local MyRoot = GetRootPart()
    if not MyRoot then
        return false
    end

    local Portals = GetPortals()
    if #Portals == 0 then
        return false
    end

    -- Portals that lead away from every round trigger are the boss/next-zone
    -- portals. Pick whichever destination is furthest from the room we are in,
    -- which works on any world without hardcoding coordinates.
    local Target, TargetDistance

    local Waypoint = GetRoomWaypoint(State.Round)
    local Origin = Waypoint or MyRoot.Position

    for _, Portal in ipairs(Portals) do
        local Distance = (Portal.Destination - Origin).Magnitude
        if not TargetDistance or Distance > TargetDistance then
            Target, TargetDistance = Portal, Distance
        end
    end

    if not Target then
        return false
    end

    local Ok = pcall(function()
        Target.Remote:InvokeServer()
    end)

    return Ok
end

local function GetEnemyList()
    local Enemies = {}
    local Seen = {}

    for _, Model in ipairs(CollectionService:GetTagged(ENEMY_TAG)) do
        local Root, Humanoid = GetEnemyRoot(Model)
        if Root and not Seen[Model] then
            Seen[Model] = true
            table.insert(Enemies, { Model = Model, Root = Root, Humanoid = Humanoid })
        end
    end

    if FinderOk and FinderUtility then
        local MyRoot = GetRootPart()
        if MyRoot then
            local Ok, List = pcall(FinderUtility.GetEnemyList, FinderUtility, MyRoot.Position)
            if Ok and type(List) == "table" then
                for _, Part in ipairs(List) do
                    local Model = Part.Parent and Part.Parent.Parent
                    if Model and not Seen[Model] then
                        local Root, Humanoid = GetEnemyRoot(Model)
                        if Root then
                            Seen[Model] = true
                            table.insert(Enemies, { Model = Model, Root = Root, Humanoid = Humanoid })
                        end
                    end
                end
            end
        end
    end

    return Enemies
end

-- Tagged enemies that are still alive but have no body part yet.
local function GetPendingEnemies()
    local Pending = {}

    for _, Model in ipairs(CollectionService:GetTagged(ENEMY_TAG)) do
        local Humanoid = Model:FindFirstChildOfClass("Humanoid")
        if Humanoid and Humanoid.Health > 0 then
            local HasPart = false
            for _, Child in ipairs(Model:GetChildren()) do
                if Child:IsA("BasePart") then
                    HasPart = true
                    break
                end
            end
            if not HasPart then
                table.insert(Pending, Model)
            end
        end
    end

    return Pending
end

local function GetNearestEnemy()
    local MyRoot = GetRootPart()
    if not MyRoot then
        return nil
    end

    local Nearest, NearestDistance = nil, math.huge

    for _, Enemy in ipairs(GetEnemyList()) do
        local Distance = (Enemy.Root.Position - MyRoot.Position).Magnitude
        if Distance < NearestDistance then
            Nearest, NearestDistance = Enemy, Distance
        end
    end

    return Nearest, NearestDistance
end

local function FacePosition(Position)
    local MyRoot = GetRootPart()
    if not MyRoot then
        return
    end

    MyRoot.CFrame = CFrame.lookAt(MyRoot.Position, Vector3.new(Position.X, MyRoot.Position.Y, Position.Z))
end

local function TweenTo(TargetPosition)
    local MyRoot = GetRootPart()
    local Humanoid = GetHumanoid()
    if not MyRoot or not Humanoid or Humanoid.Health <= 0 then
        return false
    end

    local Distance = (TargetPosition - MyRoot.Position).Magnitude
    if Distance <= 0.5 then
        return true
    end

    local Speed = math.max(Config["Tween Speed"], 1)
    local Duration = math.clamp(Distance / Speed, 0.08, 2)

    local Tween = TweenService:Create(
        MyRoot,
        TweenInfo.new(Duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        { CFrame = CFrame.lookAt(TargetPosition, Vector3.new(TargetPosition.X, TargetPosition.Y, TargetPosition.Z + 1)) }
    )

    local Finished = false
    local Connection
    Connection = Tween.Completed:Connect(function()
        Connection:Disconnect()
        Finished = true
    end)

    Tween:Play()

    local Timeout = os.clock() + Duration + 1
    while not Finished and os.clock() < Timeout and Config["Auto Dungeon"] do
        RunService.Heartbeat:Wait()
    end

    Connection:Disconnect()
    Tween:Cancel()
    Tween:Destroy()

    return Finished
end

local function MoveToEnemy(Enemy)
    local MyRoot = GetRootPart()
    if not MyRoot or not Enemy or not Enemy.Root or not Enemy.Root.Parent then
        return false
    end

    local TargetPosition = Enemy.Root.Position
    local Direction = MyRoot.Position - TargetPosition
    if Direction.Magnitude < 0.001 then
        Direction = Vector3.new(0, 0, 1)
    end

    local StopDistance = Config["Attack Distance"]
    local Destination = TargetPosition + Direction.Unit * StopDistance
    Destination = Vector3.new(Destination.X, MyRoot.Position.Y, Destination.Z)

    if (Destination - MyRoot.Position).Magnitude > 1 then
        TweenTo(Destination)
    end

    FacePosition(TargetPosition)
    return true
end

local function PerformAttack()
    local Controller = GetController()
    if not Controller or not Controller.WeaponDef.Ready then
        return false
    end

    Controller:PerformAction("BaseAttack")
    return true
end

local function PerformSkill()
    local Controller = GetController()
    if not Controller or not Controller.WeaponDef.Ready then
        return false
    end

    if Controller:HasSkillAction() or Controller:HasAction("Dash") or Controller:HasAction("BeHit") then
        return false
    end

    for _, SkillName in ipairs(SKILL_ORDER) do
        if Controller.WeaponDef[SkillName] and Controller:CheckSkillCD(SkillName) then
            Controller:PerformAction(SkillName)
            State.LastSkill = os.clock()
            return true
        end
    end

    return false
end

local function GetRoundCfg()
    if GameRoundCfg and GameRoundCfg.Parent then
        return GameRoundCfg
    end
    GameRoundCfg = ReplicatedStorage:FindFirstChild("GameRoundCfg")
    return GameRoundCfg
end

local function ReadRound()
    local RoundCfg = GetRoundCfg()
    if not RoundCfg then
        State.Round = 0
        State.RoundComplete = 0
        State.MaxRound = 0
        return
    end

    State.Round = RoundCfg:GetAttribute("GameRound") or 0
    State.RoundComplete = RoundCfg:GetAttribute("GameRoundComplete") or 0
    State.MaxRound = RoundCfg:GetAttribute("MaxRound") or 0
end

local function WalkToWaypoint()
    local Waypoint = GetRoomWaypoint(State.Round)
    local MyRoot = GetRootPart()
    if not Waypoint or not MyRoot then
        return false
    end

    local Destination = Vector3.new(Waypoint.X, MyRoot.Position.Y, Waypoint.Z)
    if (Destination - MyRoot.Position).Magnitude < 6 then
        return false
    end

    TweenTo(Destination)
    return true
end

local function IsRoundStuck()
    local Signature = table.concat({ tostring(State.Round), tostring(State.RoundComplete) }, ":")

    if Signature ~= State.LastSignature then
        State.LastSignature = Signature
        State.LastProgress = os.clock()
        return false
    end

    -- A round that still has killable enemies is not stuck; the fight simply is
    -- not over yet, so the replay timer must never fire in that case.
    if #GetEnemyList() > 0 then
        State.LastProgress = os.clock()
        return false
    end

    local Pending = GetPendingEnemies()
    local ReachedWaypoint = true

    local Waypoint = GetRoomWaypoint(State.Round)
    local MyRoot = GetRootPart()
    if Waypoint and MyRoot then
        ReachedWaypoint = (Vector3.new(Waypoint.X, MyRoot.Position.Y, Waypoint.Z) - MyRoot.Position).Magnitude < 12
    end

    -- Only give up when we are standing in the room and the bodies still never
    -- arrive; that is the genuine server-side spawn failure.
    local Grace = (#Pending > 0 and ReachedWaypoint) and 75 or 120

    return os.clock() - State.LastProgress > Grace
end

-- AUTO JOIN FUNCTIONS

local function GetMyDungeon()
    if GamePlaceUtil then
        local Ok, Name = pcall(GamePlaceUtil.GetPlaceName, GamePlaceUtil)
        if Ok and Name then
            return Name
        end
    end

    local RoundCfg = GetRoundCfg()
    return RoundCfg and RoundCfg:GetAttribute("WorldId")
end

local function GetJoinWorld()
    for _, Entry in ipairs(JOIN_WORLDS) do
        if Entry.Key == Config["Join World"] then
            return Entry
        end
    end
    return JOIN_WORLDS[1]
end

local function IsInDungeon()
    local Me = GetMyDungeon()
    return Me ~= nil and Me ~= "Lobby" and Me ~= "Prologue" and Me ~= "Booth"
end

-- getconnect / ClickGui give both the direct connection invoke and the
-- GuiService fallback the skill requires for the Create button.
local function ClickTarget(Target)
    if not Target then
        return false
    end

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

    return Clicked
end

local function ClickGui(Target)
    if typeof(Target) ~= "Instance" or not Target:IsA("GuiObject") then
        return false
    end

    local Done = pcall(function()
        local Timeout = os.clock() + 1
        repeat
            task.wait()
            GuiService.SelectedObject = Target
        until GuiService.SelectedObject == Target or os.clock() > Timeout

        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)

        task.wait()
        GuiService.SelectedObject = nil
    end)

    return Done
end

-- JOIN FLOW

local JoinBusy = false
local JoinTween

local function GetJoinRoom()
    local Folder = workspace:FindFirstChild("MatchRoom")
    return Folder and Folder:FindFirstChild("Room1")
end

local function GetMatchPanel()
    local MainGui = PlayerGui:FindFirstChild("MainGui")
    return MainGui and MainGui:FindFirstChild("ScreenMatch")
end

local function PressJoinButton(Button)
    if not Button or not Button:IsA("GuiButton") then
        return false
    end
    if ClickTarget(Button) then
        return true
    end
    return ClickGui(Button)
end

local function MoveJoinTo(Position)
    local Root = GetRootPart()
    if not Root then
        return false
    end
    if JoinTween then
        JoinTween:Cancel()
    end
    local Duration = math.clamp((Root.Position - Position).Magnitude / Config["Tween Speed"], 0.2, 8)
    JoinTween = TweenService:Create(Root, TweenInfo.new(Duration, Enum.EasingStyle.Linear), {
        CFrame = CFrame.new(Position),
    })
    JoinTween:Play()
    local Result = JoinTween.Completed:Wait()
    JoinTween = nil
    return Result == Enum.PlaybackState.Completed and (Root.Position - Position).Magnitude < 6
end

local function EnterJoinRoom()
    local Room = GetJoinRoom()
    local Root = Room and Room:FindFirstChild("Root")
    local MyRoot = GetRootPart()
    if not Root or not MyRoot then
        State.JoinNote = "ไม่พบ workspace.MatchRoom.Room1"
        return false
    end
    local Owner = Room:GetAttribute("HomeownerId")
    if Owner and Owner ~= 0 and Owner ~= LocalPlayer.UserId then
        State.JoinNote = "Room1 มีเจ้าของแล้ว รอห้องว่าง"
        return false
    end
    local Panel = GetMatchPanel()
    if Panel and Panel.Visible and (MyRoot.Position - Root.Position).Magnitude < 12 then
        return true
    end
    local Outside = Root:FindFirstChild("RoomOut")
    local Inside = Root:FindFirstChild("RoomIn")
    if not Outside or not Inside then
        State.JoinNote = "ไม่พบจุดเข้า Room1"
        return false
    end
    State.JoinNote = "กำลังเข้า Room1"
    if not MoveJoinTo(Outside.WorldPosition) then
        State.JoinNote = "เดินไปหน้า Room1 ไม่สำเร็จ"
        return false
    end
    task.wait(0.4)
    if not MoveJoinTo(Inside.WorldPosition) then
        State.JoinNote = "เข้า Room1 ไม่สำเร็จ"
        return false
    end
    local Deadline = os.clock() + 5
    repeat
        Panel = GetMatchPanel()
        if Panel and Panel.Visible then
            return true
        end
        task.wait(0.1)
    until os.clock() >= Deadline
    State.JoinNote = "เข้า Room1 แล้ว แต่หน้าเลือกดันเจี้ยนยังไม่เปิด"
    return false
end

local function ClickCreateButton()
    if not EnterJoinRoom() then
        return false
    end
    local Entry = GetJoinWorld()
    local Panel = GetMatchPanel()
    local WorldFrame = Panel and Panel:FindFirstChild("WorldFrame")
    local Chapters = WorldFrame and WorldFrame:FindFirstChild("ChapterFrame")
    local Tab = Chapters and Chapters:FindFirstChild("Tab")
    local Scrolling = Tab and Tab:FindFirstChild("ScrollingFrame")
    local Item = Scrolling and Scrolling:FindFirstChild(Entry.Key)
    if not Item or not PressJoinButton(Item:FindFirstChild("Btn")) then
        State.JoinNote = "Room1 ไม่มีตัวเลือก " .. Entry.Title
        return false
    end
    task.wait(0.25)

    local Details = WorldFrame:FindFirstChild("Details")
    local HellMode = Details and Details:FindFirstChild("HellMode")
    local HellButton = HellMode and HellMode:FindFirstChild("BTN")
    local WantHell = Config["Join Hell"] == true
    if WantHell and (not HellButton or not HellMode.Visible) then
        State.JoinNote = "ด่านที่เลือกไม่มี Hell Mode"
        return false
    end
    if HellButton and (HellButton:GetAttribute("Open") == true) ~= WantHell then
        PressJoinButton(HellButton)
        task.wait(0.2)
        if (HellButton:GetAttribute("Open") == true) ~= WantHell then
            State.JoinNote = "ยังไม่ปลดล็อก Hell Mode"
            return false
        end
    end

    local Stage = Config["Join Stage"]
    local DiffLevel = Stage
    if WorldUtil then
        local List = WorldUtil:GetWorldStyleList(Entry.Key, WantHell and "Hell" or "Normal")
        local Found = false
        for _, Info in ipairs(List or {}) do
            if Info.Difficulty == Stage then
                DiffLevel = Info.DiffLevel
                Found = true
                break
            end
        end
        if not Found or not WorldUtil:IsUnlockWorldDiff(LocalPlayer, Entry.Key, DiffLevel) then
            State.JoinNote = "ด่านหรือระดับที่เลือกยังไม่ปลดล็อก"
            return false
        end
    end
    local DiffTabs = WorldFrame:FindFirstChild("DiffTabs")
    local DiffButton = DiffTabs and DiffTabs:FindFirstChild(tostring(Stage))
    if not PressJoinButton(DiffButton) then
        State.JoinNote = "ไม่พบปุ่มระดับที่เลือก"
        return false
    end
    task.wait(0.2)

    local Control = Panel:FindFirstChild("Control")
    local Match = Control and Control:FindFirstChild("Match")
    local Count = Match and Match:FindFirstChild("MatchCount")
    local Wanted = math.clamp(Config["Join Players"], 1, 4)
    for _ = 1, 4 do
        local Current = Count and tonumber(Count.Text)
        if not Current then
            State.JoinNote = "อ่านจำนวนผู้เล่นไม่ได้"
            return false
        end
        if Current == Wanted then
            break
        end
        PressJoinButton(Match:FindFirstChild(Current > Wanted and "MinusButton" or "AddButton"))
        task.wait(0.15)
    end
    if not Count or tonumber(Count.Text) ~= Wanted then
        State.JoinNote = "ตั้งจำนวนผู้เล่นไม่สำเร็จ"
        return false
    end
    if not Panel.Visible or not PressJoinButton(Control:FindFirstChild("CreatBtn")) then
        State.JoinNote = "หน้าเลือกดันเจี้ยนปิดก่อนกด Create"
        return false
    end

    State.JoinNote = "กด Create แล้ว รอเซิร์ฟเวอร์ยืนยัน Room1"
    local Deadline = os.clock() + 8
    repeat
        local Room = GetJoinRoom()
        local RoomState = Room and Room:GetAttribute("RoomState")
        if Room and Room:GetAttribute("HomeownerId") == LocalPlayer.UserId
            and Room:GetAttribute("WorldId") == Entry.Key
            and Room:GetAttribute("DiffLevel") == DiffLevel
            and (RoomState == 2 or RoomState == 3) then
            State.JoinNote = "Room1 ยืนยันแล้ว รอเทเลพอร์ตเข้า " .. Entry.Title
            return true
        end
        task.wait(0.2)
    until os.clock() >= Deadline
    State.JoinNote = "กด Create แล้ว แต่ยังไม่ได้รับการยืนยัน Room1"
    return false
end

local function StartAutoJoin()
    if JoinBusy then
        return
    end
    if IsInDungeon() then
        State.JoinNote = "อยู่ในดันเจี้ยนแล้ว"
        return
    end
    local Room = GetJoinRoom()
    local RoomState = Room and Room:GetAttribute("RoomState")
    if Room and Room:GetAttribute("HomeownerId") == LocalPlayer.UserId
        and (RoomState == 2 or RoomState == 3) then
        State.JoinNote = "Room1 ยืนยันแล้ว รอเทเลพอร์ต"
        return
    end
    JoinBusy = true
    State.LastJoin = os.clock()
    State.JoinTries += 1
    local Ok, Error = pcall(ClickCreateButton)
    if not Ok then
        State.JoinNote = "Join ผิดพลาด: " .. tostring(Error)
        warn("[Iron Soul] " .. State.JoinNote)
    end
    JoinBusy = false
end

-- INVENTORY FUNCTIONS

local function IsSellRaritySelected(Selected, Rarity)
    return type(Selected) == "table" and table.find(Selected, RarityNames[Rarity]) ~= nil
end

local function GetOreSellList()
    local Selected, Total = {}, 0
    local Keep = math.max(0, math.floor(tonumber(Config["Keep Ores"]) or 0))
    for ID, Count in pairs(ForgeUtil:GetOres(LocalPlayer)) do
        local Def = ForgeUtil:GetDef(ID)
        if Def and type(Count) == "number" and IsSellRaritySelected(Config["Sell Ore Rarities"], Def.Rarity) then
            local Amount = math.max(0, math.floor(Count) - Keep)
            if Amount > 0 then
                Selected[ID] = Amount
                Total = Total + Amount
            end
        end
    end
    return Selected, Total
end

local function GetArmorSellList()
    local Selected = {}
    local Equipped = EquipmentData:GetEquipped(LocalPlayer) or {}
    local ExtraWeapon = EquipmentUtil:GetExtraWeaponUUID(LocalPlayer)
    for UUID, Item in pairs(EquipmentData:GetOwned(LocalPlayer) or {}) do
        local Def = EquipmentUtil:GetDef(Item.ID)
        if Def and Def.Type == "Armor"
            and IsSellRaritySelected(Config["Sell Armor Rarities"], EquipmentUtil:GetOreRarity(Item.MaxOre))
            and not Equipped[UUID] and UUID ~= ExtraWeapon
            and not EquipmentUtil:IsEquipByUUID(LocalPlayer, UUID)
            and not EquipmentUtil:IsLocked(LocalPlayer, UUID) then
            table.insert(Selected, UUID)
        end
    end
    return Selected, #Selected
end

local function SellOres()
    if InventoryState.OresBusy then
        return
    end
    InventoryState.OresBusy = true
    local Success, Error = pcall(function()
        local Selected, Count = GetOreSellList()
        if Count == 0 then
            InventoryState.OresNote = "ไม่มีแร่ตรงเงื่อนไข"
            return
        end
        ForgeUtil:Sell(LocalPlayer, Selected)
        InventoryState.OresNote = "ส่งคำขอขายแร่ " .. Count .. " ชิ้นแล้ว"
    end)
    if not Success then
        InventoryState.OresNote = "ขายแร่ผิดพลาด: " .. tostring(Error)
    end
    InventoryState.OresBusy = false
end

local function SellArmor()
    if InventoryState.ArmorBusy then
        return
    end
    InventoryState.ArmorBusy = true
    local Success, Error = pcall(function()
        local Selected, Count = GetArmorSellList()
        if Count == 0 then
            InventoryState.ArmorNote = "ไม่มีเกราะตรงเงื่อนไข"
            return
        end
        EquipmentUtil:Sell(LocalPlayer, Selected)
        InventoryState.ArmorNote = "ส่งคำขอขายเกราะ " .. Count .. " ชิ้นแล้ว"
    end)
    if not Success then
        InventoryState.ArmorNote = "ขายเกราะผิดพลาด: " .. tostring(Error)
    end
    InventoryState.ArmorBusy = false
end

local function RedeemCodes()
    if InventoryState.RedeemBusy then
        return "กำลัง Redeem Code อยู่"
    end
    if not CodesRF then
        return "ไม่พบระบบ Redeem Code"
    end
    InventoryState.RedeemBusy = true
    local Seen, Results = {}, {}
    local Redeemed, Skipped, Failed = 0, 0, 0
    local Success, Error = pcall(function()
        for _, Code in ipairs(REDEEM_CODES) do
            if not Seen[Code] then
                Seen[Code] = true
                local CallOk, Accepted, Message = pcall(function()
                    return CodesRF:InvokeServer("RedeemCode", Code)
                end)
                if CallOk and (Message == "Cooldown" or Message == "Busy") then
                    task.wait(3)
                    CallOk, Accepted, Message = pcall(function()
                        return CodesRF:InvokeServer("RedeemCode", Code)
                    end)
                end
                if CallOk and Accepted == true then
                    Redeemed = Redeemed + 1
                elseif CallOk and Message == "AlreadyUsed" then
                    Skipped = Skipped + 1
                else
                    Failed = Failed + 1
                end
                local Detail = CallOk and Message or Accepted
                table.insert(Results, Code .. ": " .. tostring(Detail or Accepted))
                task.wait(1)
            end
        end
    end)
    InventoryState.RedeemBusy = false
    if not Success then
        return "Redeem ผิดพลาด: " .. tostring(Error)
    end
    return string.format("สำเร็จ %d | ใช้แล้ว %d | ไม่สำเร็จ %d", Redeemed, Skipped, Failed)
        .. "\n" .. table.concat(Results, "\n")
end

-- LOOPS

task.spawn(function()
    while task.wait(0.1) do
        pcall(function()
            if not Config["Auto Dungeon"] or not IsInDungeon() then
                return
            end

            local Humanoid = GetHumanoid()
            if not Humanoid or Humanoid.Health <= 0 then
                return
            end

            ReadRound()

            local Enemy, Distance = GetNearestEnemy()

            if not Enemy then
                -- No reachable enemy: either the room is clear (walk to the next
                -- room trigger) or enemies exist but their body has not streamed
                -- in yet. Both cases need the same thing: go to the room centre.
                local Pending = GetPendingEnemies()
                if #Pending > 0 then
                    local Waypoint = GetRoomWaypoint(State.Round)
                    if Waypoint then
                        RequestStream(Waypoint)
                    end
                end

                WalkToWaypoint()
                return
            end
            MoveToEnemy(Enemy)

            if Distance and Distance <= Config["Kill Radius"] then
                if Config["Auto Skill"] and os.clock() - State.LastSkill >= Config["Skill Delay"] then
                    if PerformSkill() then
                        return
                    end
                end

                if Config["Auto Attack"] then
                    PerformAttack()
                end
            end
        end)
    end
end)

task.spawn(function()
    while task.wait(1) do
        pcall(function()
            if not Config["Auto Dungeon"] or not IsInDungeon() then
                return
            end

            ReadRound()

            local Settlement = PlayerGui:FindFirstChild("ResultGui")
            Settlement = Settlement and Settlement:FindFirstChild("ScreenSettlement")

            -- Portal routing is part of the route, not the replay. It runs even
            -- when Auto Replay is off so the dungeon can still be finished.
            local ShouldRequeue = false

            local Pending = GetPendingEnemies()
            if #Pending > 0 and os.clock() - State.LastPortal >= 12 then
                -- Enemies exist but none has a body: the round spawned models with
                -- no geometry, which only happens when we are not in the arena the
                -- round expects. The RoomDoor portal is the way into that arena.
                State.LastPortal = os.clock()
                EnterNearestPortal()
            elseif #GetEnemyList() == 0 then
                -- No enemies and no waypoint left: this is the final round of the
                -- world, so take the far portal into the boss arena.
                local NoWaypoint = GetRoomWaypoint(State.Round) == nil
                local AtLastRound = State.MaxRound > 0 and State.Round >= State.MaxRound

                if (NoWaypoint or AtLastRound) and os.clock() - State.LastPortal >= 12 then
                    State.LastPortal = os.clock()
                    EnterNearestPortal()
                end
            end

            if not Config["Auto Replay"] then
                return
            end

            if Settlement and Settlement.Visible then
                ShouldRequeue = true
            elseif IsRoundStuck() then
                ShouldRequeue = true
            end

            if not ShouldRequeue then
                return
            end

            if os.clock() - State.LastRequeue < 8 then
                return
            end

            State.LastRequeue = os.clock()
            State.LastProgress = os.clock()
            if GameRoundRE then
                GameRoundRE:FireServer("PlayAgainAlone")
            end
        end)
    end
end)

task.spawn(function()
    while task.wait(3) do
        if Config["Auto Join"] and not JoinBusy then
            local MaxTries = math.max(Config["Join Retry"], 0)
            if IsInDungeon() then
                State.JoinNote = "อยู่ในดันเจี้ยนแล้ว"
            elseif MaxTries > 0 and State.JoinTries >= MaxTries then
                State.JoinNote = "ครบจำนวนครั้งที่ลองแล้ว กด Join เพื่อลองใหม่"
            elseif os.clock() - State.LastJoin >= 15 then
                StartAutoJoin()
            end
        end
    end
end)

local Ex_Function = {}
Ex_Function["Auto Sell"] = function()
    task.spawn(function()
        while task.wait(5) do
            pcall(function()
                if Config["Auto Sell Ores"] then
                    SellOres()
                end
                if Config["Auto Sell Armor"] then
                    SellArmor()
                end
            end)
        end
    end)
end
Ex_Function["Auto Sell"]()

-- UI

local WINDUI_URL = "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"

-- Re-running the Script must not stack a second window, so an existing one is
-- destroyed before a new one is built.
local ExistingGui = PlayerGui:FindFirstChild("WindUI")
local CoreGui = game:GetService("CoreGui")
local CoreWind = CoreGui and CoreGui:FindFirstChild("RobloxGui") and CoreGui.RobloxGui:FindFirstChild("WindUI")

if ExistingGui then
    ExistingGui:Destroy()
end

if CoreWind then
    for _, Child in ipairs(CoreWind:GetChildren()) do
        if Child.Name == "Window" then
            Child:Destroy()
        end
    end
end

-- WindUI is loaded defensively: a failed fetch must not stop the Script, and the
-- window object is checked before any Tab/Section call so a new WindUI build
-- cannot throw halfway through the UI block.
local WindOk, WindUI = pcall(function()
    return loadstring(game:HttpGet(WINDUI_URL))()
end)

if not WindOk or type(WindUI) ~= "table" then
    warn("[Iron Soul] WindUI load failed: " .. tostring(WindUI))
    return State
end

pcall(function()
    WindUI:SetNotificationLower(true)
end)

local WindowOk, Window = pcall(function()
    return WindUI:CreateWindow({
        Title = "Iron Soul",
        Icon = "swords",
        Author = "Auto Dungeon",
        Theme = "Dark",
        ToggleKey = Enum.KeyCode.RightControl,
    })
end)

if not WindowOk or not Window then
    warn("[Iron Soul] CreateWindow failed: " .. tostring(Window))
    return State
end

local MainTab = Window:Tab({
    Title = "Main",
    Icon = "swords",
})

local JoinTab = Window:Tab({
    Title = "Join",
    Icon = "door-open",
})

local SettingTab = Window:Tab({
    Title = "Settings",
    Icon = "settings",
})

local InventoryTab = Window:Tab({
    Title = "Codes / Sell",
    Icon = "package",
})

MainTab:Select()

local JoinTitles = {}
for _, Entry in ipairs(JOIN_WORLDS) do
    table.insert(JoinTitles, Entry.Title)
end

-- REDEEM AND SELL UI

local RedeemSection = InventoryTab:Section({ Title = "Redeem Code", Icon = "gift", Opened = true })
RedeemSection:Button({
    Title = "Redeem All Code",
    Icon = "gift",
    Callback = function()
        if InventoryState.RedeemBusy then
            return
        end
        task.spawn(function()
            local Result = RedeemCodes()
            WindUI:Notify({
                Title = "Redeem All Code",
                Content = Result,
                Duration = 10,
            })
        end)
    end,
})

local OreSection = InventoryTab:Section({ Title = "ขายแร่ / Ores", Icon = "gem", Opened = true })
local OreStatus = OreSection:Paragraph({ Title = "สถานะแร่", Desc = InventoryState.OresNote })
OreSection:Dropdown({
    Title = "ความหายากแร่ที่ขาย",
    Values = RarityNames,
    Value = Config["Sell Ore Rarities"],
    Multi = true,
    AllowNone = true,
    Callback = function(Value)
        Config["Sell Ore Rarities"] = Value
        SaveSettings()
    end,
})
OreSection:Slider({
    Title = "เก็บแร่ไว้ต่อชนิด",
    Desc = "ขายเฉพาะส่วนที่เกินจำนวนนี้",
    Value = { Min = 0, Max = 1000, Default = Config["Keep Ores"] },
    Step = 1,
    Callback = function(Value)
        Config["Keep Ores"] = Value
        SaveSettings()
    end,
})
OreSection:Toggle({
    Title = "Auto Sell Ores",
    Desc = "ขายแร่ตามเงื่อนไขทุก 5 วินาที",
    Value = Config["Auto Sell Ores"],
    Callback = function(Value)
        Config["Auto Sell Ores"] = Value
        SaveSettings()
    end,
})
OreSection:Button({
    Title = "ตรวจรายการแร่ก่อนขาย",
    Callback = function()
        local Success, Selected, Count = pcall(GetOreSellList)
        local Lines = {}
        if Success then
            for ID, Amount in pairs(Selected) do
                table.insert(Lines, ID .. " x" .. Amount)
            end
            table.sort(Lines)
        end
        WindUI:Notify({
            Title = "แร่ที่ตรงเงื่อนไข",
            Content = Success and ("รวม " .. Count .. " ชิ้น\n" .. table.concat(Lines, "\n")) or tostring(Selected),
            Duration = 8,
        })
    end,
})
OreSection:Button({
    Title = "ขายแร่ตามเงื่อนไขตอนนี้",
    Callback = function()
        task.spawn(SellOres)
    end,
})

local ArmorSection = InventoryTab:Section({ Title = "ขายเกราะ / Armor", Icon = "shield", Opened = true })
local ArmorStatus = ArmorSection:Paragraph({
    Title = "สถานะเกราะ",
    Desc = "ขายเฉพาะเกราะที่ไม่ได้สวมใส่และไม่ได้ล็อก",
})
ArmorSection:Dropdown({
    Title = "ความหายากเกราะที่ขาย",
    Values = RarityNames,
    Value = Config["Sell Armor Rarities"],
    Multi = true,
    AllowNone = true,
    Callback = function(Value)
        Config["Sell Armor Rarities"] = Value
        SaveSettings()
    end,
})
ArmorSection:Toggle({
    Title = "Auto Sell Armor",
    Desc = "ขายเกราะตามเงื่อนไขทุก 5 วินาที ข้ามชิ้นที่ใส่หรือล็อกไว้",
    Value = Config["Auto Sell Armor"],
    Callback = function(Value)
        Config["Auto Sell Armor"] = Value
        SaveSettings()
    end,
})
ArmorSection:Button({
    Title = "ตรวจจำนวนเกราะก่อนขาย",
    Callback = function()
        local Success, Selected, Count = pcall(GetArmorSellList)
        WindUI:Notify({
            Title = "เกราะที่ตรงเงื่อนไข",
            Content = Success and ("รวม " .. Count .. " ชิ้น (ข้ามชิ้นที่ใส่หรือล็อกไว้)") or tostring(Selected),
            Duration = 5,
        })
    end,
})
ArmorSection:Button({
    Title = "ขายเกราะตามเงื่อนไขตอนนี้",
    Callback = function()
        task.spawn(SellArmor)
    end,
})

-- Join

local JoinSection = JoinTab:Section({ Title = "Dungeon Select", Icon = "map", Opened = true })

local JoinStatus = JoinSection:Paragraph({
    Title = "สถานะ",
    Desc = "พร้อม",
})

JoinSection:Dropdown({
    Title = "Dungeon",
    Desc = "เลือกดันเจี้ยนตามชื่อใน UI",
    Icon = "map-pin",
    Values = JoinTitles,
    Value = GetJoinWorld().Title,
    Multi = false,
    Callback = function(Value)
        for _, Entry in ipairs(JOIN_WORLDS) do
            if Entry.Title == Value then
                Config["Join World"] = Entry.Key
                SaveSettings()
                return
            end
        end
    end,
})

local JoinStageDropdown = JoinSection:Dropdown({
    Title = "Stage",
    Desc = "ระดับความยากที่ UI แสดง (Trial = 1)",
    Icon = "layers",
    Values = JOIN_STAGES,
    Value = JOIN_STAGES[Config["Join Stage"]],
    Multi = false,
    Callback = function(Value)
        for Index, Name in ipairs(JOIN_STAGES) do
            if Name == Value then
                Config["Join Stage"] = Index
                SaveSettings()
                return
            end
        end
    end,
})

JoinSection:Toggle({
    Title = "Hell Mode",
    Desc = "เปิดโหมด Hell ของดันเจี้ยนที่รองรับ",
    Icon = "flame",
    Value = Config["Join Hell"],
    Callback = function(Value)
        Config["Join Hell"] = Value
        SaveSettings()
        State.JoinNote = Value and "Hell Mode เปิด" or "Hell Mode ปิด"
    end,
})

JoinSection:Toggle({
    Title = "Auto Join",
    Desc = "เข้า Room1 → เลือกด่าน → ตั้งจำนวนผู้เล่น → Create",
    Icon = "door-open",
    Value = Config["Auto Join"],
    Callback = function(Value)
        Config["Auto Join"] = Value
        SaveSettings()
        State.JoinTries = 0
        State.LastJoin = os.clock() - 60
        State.JoinNote = Value and "Auto Join ทำงาน" or "Auto Join หยุด"
    end,
})

local JoinActionSection = JoinTab:Section({ Title = "Actions", Icon = "zap", Opened = true })

JoinActionSection:Button({
    Title = "Join / สร้างห้องเลย",
    Desc = "เข้า Room1 ก่อน แล้วเลือกด่านและกด Create ผ่าน UI",
    Icon = "play",
    Callback = function()
        State.JoinTries = 0
        StartAutoJoin()
        WindUI:Notify({
            Title = "Join",
            Content = State.JoinNote,
            Duration = 4,
        })
    end,
})

JoinActionSection:Button({
    Title = "กด Create",
    Desc = "กดปุ่ม Create ในหน้า Dungeon Select",
    Icon = "check",
    Callback = function()
        State.JoinTries = 0
        StartAutoJoin()
        WindUI:Notify({ Title = "Create", Content = State.JoinNote, Duration = 3 })
    end,
})

JoinActionSection:Button({
    Title = "กลับล็อบบี้",
    Desc = "ออกจากห้องปัจจุบันกลับไป Lobby",
    Icon = "home",
    Callback = function()
        if WorldUtil and WorldUtil.RemoteEvent then
            WorldUtil.RemoteEvent:FireServer("BackLobby")
        end
        State.JoinNote = "กลับล็อบบี้แล้ว"
    end,
})

JoinActionSection:Slider({
    Title = "Players",
    Desc = "จำนวนผู้เล่นตอนสร้างห้อง",
    Value = { Min = 1, Max = 4, Default = Config["Join Players"] },
    Step = 1,
    Callback = function(Value)
        Config["Join Players"] = Value
        SaveSettings()
    end,
})

JoinActionSection:Slider({
    Title = "Retry",
    Desc = "จำนวนครั้งที่ลอง Join ซ้ำก่อนหยุด",
    Value = { Min = 0, Max = 20, Default = Config["Join Retry"] },
    Step = 1,
    Callback = function(Value)
        Config["Join Retry"] = Value
        SaveSettings()
        State.JoinTries = 0
    end,
})

-- Main

local DungeonSection = MainTab:Section({ Title = "Dungeon", Icon = "swords", Opened = true })

local RoundParagraph = DungeonSection:Paragraph({
    Title = "รอบ",
    Desc = "Round 0 / 0",
})

DungeonSection:Toggle({
    Title = "Auto Dungeon",
    Desc = "เดินและดันเจี้ยนอัตโนมัติ (Tween)",
    Icon = "footprints",
    Value = Config["Auto Dungeon"],
    Callback = function(Value)
        Config["Auto Dungeon"] = Value
        SaveSettings()
        State.LastProgress = os.clock()
    end,
})

DungeonSection:Toggle({
    Title = "Auto Attack",
    Desc = "โจมตีปกติอัตโนมัติ",
    Icon = "sword",
    Value = Config["Auto Attack"],
    Callback = function(Value)
        Config["Auto Attack"] = Value
        SaveSettings()
    end,
})

DungeonSection:Toggle({
    Title = "Auto Skill",
    Desc = "ใช้สกิลอัตโนมัติตามลำดับ",
    Icon = "sparkles",
    Value = Config["Auto Skill"],
    Callback = function(Value)
        Config["Auto Skill"] = Value
        SaveSettings()
    end,
})

DungeonSection:Toggle({
    Title = "Auto Replay",
    Desc = "เล่นซ้ำอัตโนมัติเมื่อจบหรือติดขัด",
    Icon = "repeat",
    Value = Config["Auto Replay"],
    Callback = function(Value)
        Config["Auto Replay"] = Value
        SaveSettings()
    end,
})

local ActionSection = MainTab:Section({ Title = "Actions", Icon = "zap", Opened = true })

ActionSection:Button({
    Title = "เข้า Portal ถัดไป",
    Desc = "วาร์ปไปห้องบอสทันที",
    Icon = "door-open",
    Callback = function()
        local Ok = EnterNearestPortal()
        WindUI:Notify({
            Title = Ok and "Portal" or "ไม่สำเร็จ",
            Content = Ok and "วาร์ปไปห้องถัดไปแล้ว" or "ไม่พบ Portal ในห้องนี้",
            Duration = 3,
        })
    end,
})

ActionSection:Button({
    Title = "เริ่มดันเจี้ยนใหม่",
    Desc = "PlayAgainAlone",
    Icon = "rotate-ccw",
    Callback = function()
        if GameRoundRE then
            GameRoundRE:FireServer("PlayAgainAlone")
            WindUI:Notify({ Title = "ดันเจี้ยน", Content = "กำลังเริ่มรอบใหม่", Duration = 3 })
        else
            WindUI:Notify({ Title = "ดันเจี้ยน", Content = "ไม่พบ GameRoundRE ในดันนี้", Duration = 3 })
        end
    end,
})

ActionSection:Button({
    Title = "กลับล็อบบี้",
    Icon = "log-out",
    Color = Color3.fromRGB(255, 100, 100),
    Callback = function()
        local WorldUtil = Framework.Modules.WorldUtil
        if WorldUtil and WorldUtil.RemoteEvent then
            WorldUtil.RemoteEvent:FireServer("BackLobby")
        end
    end,
})

-- Settings

local SaveSection = SettingTab:Section({ Title = "Config", Icon = "save", Opened = true })

SaveSection:Paragraph({
    Title = "บันทึกอัตโนมัติ",
    Desc = "โหลดค่าเมื่อรันสคริปต์ และบันทึกเมื่อเปลี่ยนค่าใน UI\n" .. SaveFile,
})

SaveSection:Button({
    Title = "บันทึก Config",
    Desc = "บันทึกค่าปัจจุบันลงไฟล์",
    Icon = "save",
    Callback = function()
        local Success, Error = SaveSettings()
        WindUI:Notify({
            Title = Success and "บันทึกสำเร็จ" or "บันทึกไม่สำเร็จ",
            Content = Success and SaveFile or tostring(Error),
            Duration = 4,
        })
    end,
})

local CombatSection = SettingTab:Section({ Title = "Combat", Icon = "sword", Opened = true })

CombatSection:Slider({
    Title = "Attack Distance",
    Desc = "ระยะหยุดยืนตี",
    Value = { Min = 2, Max = 15, Default = Config["Attack Distance"] },
    Step = 0.5,
    Callback = function(Value)
        Config["Attack Distance"] = Value
        SaveSettings()
    end,
})

CombatSection:Slider({
    Title = "Kill Radius",
    Desc = "ระยะเริ่มออกสกิล",
    Value = { Min = 5, Max = 40, Default = Config["Kill Radius"] },
    Step = 1,
    Callback = function(Value)
        Config["Kill Radius"] = Value
        SaveSettings()
    end,
})

CombatSection:Slider({
    Title = "Skill Delay",
    Desc = "หน่วงก่อนใช้สกิลครั้งถัดไป",
    Value = { Min = 0.1, Max = 3, Default = Config["Skill Delay"] },
    Step = 0.05,
    Callback = function(Value)
        Config["Skill Delay"] = Value
        SaveSettings()
    end,
})

local MoveSection = SettingTab:Section({ Title = "Movement", Icon = "move", Opened = true })

MoveSection:Slider({
    Title = "Tween Speed",
    Desc = "ความเร็วในการเคลื่อนที่ (studs/s)",
    Value = { Min = 15, Max = 200, Default = Config["Tween Speed"] },
    Step = 5,
    Callback = function(Value)
        Config["Tween Speed"] = Value
        SaveSettings()
    end,
})

local StatusSection = SettingTab:Section({ Title = "Status", Icon = "activity", Opened = true })

local StatusParagraph = StatusSection:Paragraph({
    Title = "สถานะ",
    Desc = "กำลังอ่านข้อมูล...",
})

task.spawn(function()
    while task.wait(1) do
        pcall(function()
            OreStatus:SetDesc(InventoryState.OresNote)
            ArmorStatus:SetDesc(InventoryState.ArmorNote)
            ReadRound()

            local Alive = #GetEnemyList()
            local Pending = #GetPendingEnemies()

            StatusParagraph:SetDesc(string.format(
                "Round %d / %d   Complete %d\nศัตรูที่ตีได้ %d   รอโหลด %d",
                State.Round,
                State.MaxRound,
                State.RoundComplete,
                Alive,
                Pending
            ))

            RoundParagraph:SetDesc(string.format("Round %d / %d   Complete %d", State.Round, State.MaxRound, State.RoundComplete))

            local JoinEntry = GetJoinWorld()
            JoinStatus:SetDesc(string.format(
                "%s\nPlace %s   Stage %d   Hell %s   Auto %s\n%s",
                JoinEntry.Title,
                tostring(JoinEntry.PlaceId),
                Config["Join Stage"],
                Config["Join Hell"] and "On" or "Off",
                Config["Auto Join"] and "On" or "Off",
                State.JoinNote
            ))
        end)
    end
end)

pcall(function()
    WindUI:Notify({
        Title = "Iron Soul",
        Content = "โหลดสำเร็จ กด RightCtrl เพื่อเปิด/ปิด UI",
        Duration = 5,
    })
end)

return State




