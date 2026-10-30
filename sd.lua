if not game:IsLoaded() then
    game.Loaded:Wait()
end

local cloneref = cloneref or function(instance)
    return instance
end

-- SERVICES
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))

-- PLACES
local Places = {
    [119242658671952] = {
        Movement = "movement",
        Components = "components",
        Net = "net",
    },
}

local Place = Places[game.PlaceId]
if not Place then
    return
end

local Shared = ReplicatedStorage:FindFirstChild("shared")
local Client = ReplicatedStorage:FindFirstChild("client")
if not Shared or not Client then
    return
end

local MovementModule = Shared:FindFirstChild(Place.Movement)
local ComponentsModule = Shared:FindFirstChild(Place.Components)
local NetModule = Client:FindFirstChild(Place.Net)
if not MovementModule or not ComponentsModule or not NetModule then
    return
end

local MovementOk, Movement = pcall(require, MovementModule)
local ComponentsOk, Components = pcall(require, ComponentsModule)
local NetOk, Net = pcall(require, NetModule)
if not MovementOk or not ComponentsOk or not NetOk then
    return
end

local UtilFolder = Shared:FindFirstChild("util")
local KitFolder = Shared:FindFirstChild("kit")
local ClientUtil = Client:FindFirstChild("util")
local ClockOk, Clock = pcall(require, UtilFolder and UtilFolder:FindFirstChild("clock"))
local MatchOk, Match = pcall(require, Shared:FindFirstChild("match"))
local KeeperOk, Keeper = pcall(require, Shared:FindFirstChild("keeper"))
local ActionOk, Actions = pcall(require, Shared:FindFirstChild("action"))
local DashOk, Dash = pcall(require, KitFolder and KitFolder:FindFirstChild("dash"))
local LocalActionOk, LocalAction = pcall(require, ClientUtil and ClientUtil:FindFirstChild("local_action"))
local LocalDashOk, LocalDash = pcall(require, ClientUtil and ClientUtil:FindFirstChild("local_dash"))
local ControlOk, Control = pcall(require, ClientUtil and ClientUtil:FindFirstChild("control"))
local LookOk, Look = pcall(require, ClientUtil and ClientUtil:FindFirstChild("look"))
if not ClockOk or not MatchOk or not KeeperOk or not ActionOk or not DashOk or not LocalActionOk or not LocalDashOk or not ControlOk or not LookOk then
    return
end

local BaseDrain = Movement.DRAIN
local BaseSprint = Movement.SPRINT_SPEED
local BaseExhausted = Movement.EXHAUSTED_SPEED
local BaseAccel = Movement.MOMENTUM_ACCEL
local BaseDecay = Movement.MOMENTUM_DECAY

-- CONFIG
local Defaults = {
    ["Infinite Stamina"] = false,
    ["Honest Sprint Flag"] = false,
    ["Stamina Floor"] = 1,
    ["Sprint Speed"] = 22,
    ["Instant Accel"] = true,
    ["Speed Bypass"] = true,
    ["Ball Assist"] = true,
    ["Auto Save"] = false,
    ["Save Range"] = 12,
    ["Aim Lock"] = true,
    ["Lock Range"] = 45,
}

Config = Config or {}

for Key, Value in next, Defaults do
    if Config[Key] == nil then
        Config[Key] = Value
    end
end

_G.HK_Config = Config

-- FUNCTIONS
local Func = {}
local World, Target, Scan, Original = nil, nil, 0, nil
local LastPosition, LastStamp, Drift = nil, nil, 0
local Hooked = false
local SaveAt = 0
local SaveCooldown = 0.9
local Guarded = false
local SpotAt = 0
local SpotCache = nil
local FaceCache = nil
local Locked = false

function Func:Locate()
    if os.clock() - Scan < 1 then
        return
    end
    Scan = os.clock()
    local Found
    for _, Value in getgc(true) do
        if type(Value) == "table" then
            pcall(function()
                if type(rawget(Value, "query")) ~= "function" or type(rawget(Value, "get")) ~= "function" or type(rawget(Value, "set")) ~= "function" then
                    return
                end
                local Count = 0
                for _ in Value:query(Components.stamina) do
                    Count = Count + 1
                end
                if Count == 1 then
                    Found = Value
                end
            end)
        end
    end
    if not Found then
        return
    end
    World = Found
    for Entity in World:query(Components.stamina) do
        Target = Entity
    end
end

function Func:Sprint(Honest)
    local Signal = Net.sprint_set
    if type(Signal) ~= "table" or type(Signal.fire) ~= "function" then
        return
    end
    Original = Original or Signal.fire
    Signal.fire = Honest and Original or function(_)
        return Original(false)
    end
end

function Func:Stamina(On)
    if On then
        Func:Sprint(Config["Honest Sprint Flag"])
        return
    end
    Movement.DRAIN = BaseDrain
    if Original then
        Net.sprint_set.fire = Original
    end
end

function Func:NearBall()
    if not World or not Target then
        return false
    end
    local MineOk, Mine = pcall(function()
        return World:get(Target, Components.position)
    end)
    if not MineOk or not Mine then
        return false
    end
    for Entity in World:query(Components.FOOTBALL) do
        local BallOk, Ball = pcall(function()
            return World:get(Entity, Components.position)
        end)
        if BallOk and Ball then
            local Delta = Ball - Mine
            if Vector3.new(Delta.X, 0, Delta.Z).Magnitude < 14 then
                return true
            end
        end
    end
    return false
end

function Func:Speed()
    local Value = Config["Sprint Speed"] or BaseSprint
    if Config["Ball Assist"] and Value > BaseSprint and Func:NearBall() then
        Value = BaseSprint
    end
    Movement.SPRINT_SPEED = Value
    Movement.EXHAUSTED_SPEED = math.max(Value, BaseExhausted)
    if Config["Instant Accel"] then
        Movement.MOMENTUM_ACCEL = 300
        Movement.MOMENTUM_DECAY = 300
    else
        Movement.MOMENTUM_ACCEL = BaseAccel
        Movement.MOMENTUM_DECAY = BaseDecay
    end
end

function Func:Ball()
    if not World then
        return nil
    end
    local Best, BestScore
    for Entity in World:query(Components.FOOTBALL) do
        local Ok, Position = pcall(function()
            return World:get(Entity, Components.position)
        end)
        if Ok and Position and math.abs(Position.Z) < 80 and Position.Y < 40 then
            local Score = math.abs(Position.Z)
            if not BestScore or Score < BestScore then
                Best, BestScore = Entity, Score
            end
        end
    end
    return Best
end

function Func:Side()
    if not World or not Target then
        return nil
    end
    local Ok, Side, Team, Mine = pcall(function()
        return World:get(Target, Components.side), World:get(Target, Components.TEAM), World:get(Target, Components.position)
    end)
    if not Ok then
        return nil
    end
    if Side == Match.WEST or Side == Match.EAST then
        return Side
    end
    if Team == Match.WEST or Team == Match.EAST then
        return Team
    end
    if Mine then
        return Mine.X < 0 and Match.WEST or Match.EAST
    end
    return nil
end

function Func:Spot()
    if os.clock() - SpotAt < 0.1 then
        return SpotCache
    end
    SpotAt = os.clock()
    SpotCache = nil
    if not World or not Target then
        return nil
    end
    local KeeperOk, IsKeeper = pcall(function()
        return World:has(Target, Components.GOALKEEPER)
    end)
    if not KeeperOk or not IsKeeper then
        return nil
    end
    local Ball = Func:Ball()
    if not Ball then
        return nil
    end
    if World:target(Ball, Components.HELD_BY, 0) == Target then
        return nil
    end
    local ReadOk, Mine, BallPos = pcall(function()
        return World:get(Target, Components.position), World:get(Ball, Components.position)
    end)
    if not ReadOk or not Mine or not BallPos then
        return nil
    end
    local Side = Func:Side()
    if not Side then
        return nil
    end
    local Goal = Match.goal_of(Side)
    local Delta = Vector3.new(BallPos.X - Goal.X, 0, BallPos.Z - Goal.Z)
    local Distance = Delta.Magnitude
    if Distance < 2 then
        return nil
    end
    local ToGoal = Vector3.new(Goal.X - BallPos.X, 0, Goal.Z - BallPos.Z)
    local Spot
    if Distance <= Config["Save Range"] * 3 then
        Spot = BallPos + ToGoal.Unit * math.min(5, Distance)
    else
        Spot = Goal + Delta.Unit * math.clamp(Distance * 0.1, 1.5, 9)
    end
    SpotCache = Vector3.new(Spot.X, Mine.Y, Spot.Z)
    local ToBall = Vector3.new(BallPos.X - Mine.X, 0, BallPos.Z - Mine.Z)
    FaceCache = ToBall.Magnitude > 0.1 and ToBall.Unit or nil
    return SpotCache
end

function Func:Guard()
    local Original = Control.move
    if Guarded or type(hookfunction) ~= "function" or type(Original) ~= "function" then
        return
    end
    Guarded = true
    local Move
    Move = hookfunction(Original, function(...)
        if Config["Auto Save"] then
            local Ok, Spot = pcall(Func.Spot, Func)
            if Ok and Spot then
                if FaceCache and type(Look.claim) == "function" then
                    Look.claim("hksave", 999, FaceCache, 1)
                end
                local Mine = World:get(Target, Components.position)
                if Mine then
                    local Delta = Vector3.new(Spot.X - Mine.X, 0, Spot.Z - Mine.Z)
                    if Delta.Magnitude > 0.8 then
                        return Delta.Unit
                    end
                    return Vector3.new(0, 0, 0)
                end
            end
        end
        if type(Look.release) == "function" then
            Look.release("hksave")
        end
        return Move(...)
    end)
end

function Func:Save()
    local Contest = Net.contest
    if not World or not Target or os.clock() < SaveAt or type(Contest) ~= "table" then
        return
    end
    local KeeperOk, IsKeeper = pcall(function()
        return World:has(Target, Components.GOALKEEPER)
    end)
    if not KeeperOk or not IsKeeper then
        return
    end
    local Ball = Func:Ball()
    if not Ball then
        return
    end
    if World:target(Ball, Components.HELD_BY, 0) == Target then
        return
    end
    local ReadOk, Mine, BallPos, BallVel = pcall(function()
        return World:get(Target, Components.position), World:get(Ball, Components.position), World:get(Ball, Components.velocity)
    end)
    if not ReadOk or not Mine or not BallPos or not BallVel then
        return
    end
    local Side = Func:Side()
    if not Side then
        return
    end
    local Goal = Match.goal_of(Side)
    local Toward = Goal.X - BallPos.X
    if Toward * BallVel.X <= 0 then
        return
    end
    local Arrive = (Mine.X - BallPos.X) / BallVel.X
    if Arrive <= 0 or Arrive > 0.8 then
        return
    end
    local Crossing = BallPos.Z + BallVel.Z * Arrive
    if math.abs(Crossing) > Match.GOAL_HALF_WIDTH + 6 then
        return
    end
    if Match.depth(Mine, Side) > 20 then
        return
    end
    local Lateral = Crossing - Mine.Z
    if math.abs(Lateral) > Config["Save Range"] then
        return
    end
    local Away = Side == 1 and 1 or -1
    local Direction
    if math.abs(Lateral) > 1.2 then
        Direction = Vector3.new(0, 0, Lateral > 0 and 1 or -1)
    else
        Direction = Vector3.new(Away, 0, 0)
    end
    _G.HK_SAVE = "mine=" .. tostring(Mine) .. " ball=" .. tostring(BallPos) .. " vel=" .. tostring(BallVel) .. " arrive=" .. string.format("%.2f", Arrive) .. " cross=" .. string.format("%.1f", Crossing) .. " lateral=" .. string.format("%.1f", Lateral) .. " dir=" .. tostring(Direction)
    local LookOk, Look = pcall(function()
        return World:get(Target, Components.look)
    end)
    local Forward = LookOk and typeof(Look) == "Vector3" and Look or Direction
    LocalAction.set(Target, Keeper.dive_action(Forward, Direction), Clock.server())
    LocalDash.start(Dash.DIVE, Direction, nil, 0, nil, Forward)
    Contest.fire(Direction, false, true, false, Clock.now())
    SaveAt = os.clock() + SaveCooldown
end

function Func:Clearance(From, To, Team)
    local Delta = Vector3.new(To.X - From.X, 0, To.Z - From.Z)
    local Length = Delta.Magnitude
    if Length < 0.1 then
        return 99
    end
    local Dir = Delta.Unit
    local Worst = 99
    for Entity in World:query(Components.CHARACTER) do
        if Entity ~= Target then
            local Ok, Pos, Other, Keeper = pcall(function()
                return World:get(Entity, Components.position), World:get(Entity, Components.TEAM), World:has(Entity, Components.GOALKEEPER)
            end)
            if Ok and Pos and Other ~= nil then
                local Offset = Vector3.new(Pos.X - From.X, 0, Pos.Z - From.Z)
                local Along = Offset:Dot(Dir)
                if Along > 1 and Along < Length - 1 then
                    local Radius = 1.5
                    if Other ~= Team then
                        Radius = Keeper and 4.0 or 2.2
                    end
                    local Gap = (Offset - Dir * Along).Magnitude - Radius
                    if Gap < Worst then
                        Worst = Gap
                    end
                end
            end
        end
    end
    return Worst
end

function Func:Aim()
    if not World or not Target then
        return nil
    end
    local Ball = Func:Ball()
    if not Ball then
        return nil
    end
    local ReadOk, Mine, BallPos, Team = pcall(function()
        return World:get(Target, Components.position), World:get(Ball, Components.position), World:get(Target, Components.TEAM)
    end)
    if not ReadOk or not Mine or not BallPos then
        return nil
    end
    local Side = Func:Side()
    if not Side then
        _G.HK_AIM = "no-side"
        return nil
    end
    local Goal = Match.goal_of(Match.other(Side))
    local Distance = Vector3.new(Goal.X - Mine.X, 0, Goal.Z - Mine.Z).Magnitude
    if Distance > Config["Lock Range"] then
        _G.HK_AIM = "too-far:" .. math.floor(Distance)
        return nil
    end
    local Half = Match.GOAL_HALF_WIDTH - 1.5
    local Best, BestScore, BestGap
    for Step = -4, 4 do
        local Point = Vector3.new(Goal.X, 0, Half * (Step / 4))
        local Gap = Func:Clearance(BallPos, Point, Team)
        if Gap > 0.5 then
            local Score = math.min(Gap, 8) + math.abs(Point.Z) * 0.3
            if not BestScore or Score > BestScore then
                Best, BestScore, BestGap = Point, Score, Gap
            end
        end
    end
    if not Best then
        _G.HK_AIM = "no-lane"
        return nil
    end
    local Aim = Vector3.new(Best.X - BallPos.X, 0, Best.Z - BallPos.Z)
    if Aim.Magnitude < 0.1 then
        return nil
    end
    _G.HK_AIM = string.format("z%.1f/gap%.1f/dist%d", Best.Z, BestGap, math.floor(Distance))
    return Aim.Unit
end

function Func:Lock()
    local Fire = Net.contest and Net.contest.fire
    if Locked or type(hookfunction) ~= "function" or type(Fire) ~= "function" then
        return
    end
    Locked = true
    local Original
    Original = hookfunction(Fire, function(Direction, Shot, Dive, Curve, Stamp)
        if Shot and Config["Aim Lock"] then
            local Ok, Aim = pcall(Func.Aim, Func)
            if Ok and Aim then
                Direction = Aim
            end
        end
        return Original(Direction, Shot, Dive, Curve, Stamp)
    end)
end

function Func:Watch()
    local State = Net.character_state
    if Hooked or type(hookfunction) ~= "function" or type(State) ~= "table" or type(State.fire) ~= "function" then
        return
    end
    Hooked = true
    local Fire
    Fire = hookfunction(State.fire, function(Position, Yaw, A, B, C, Velocity, Look, Curve, Stamp, Charge)
        if not Config["Speed Bypass"] or not LastPosition or type(Stamp) ~= "number" then
            LastPosition, LastStamp, Drift = Position, Stamp, 0
            return Fire(Position, Yaw, A, B, C, Velocity, Look, Curve, Stamp, Charge)
        end
        local Delta = Position - LastPosition
        local Planar = Vector3.new(Delta.X, 0, Delta.Z).Magnitude
        local Elapsed = Stamp - LastStamp
        if Elapsed > 0 and Elapsed < 1 then
            local Budget = BaseSprint * 1.15 * Elapsed
            if Planar > Budget and Planar < Budget * 6 then
                Drift = Drift + math.min((Planar - Budget) / (BaseSprint * 1.15), 0.05)
            end
        end
        LastPosition, LastStamp = Position, Stamp
        return Fire(Position, Yaw, A, B, C, Velocity, Look, Curve, Stamp + Drift, Charge)
    end)
end

Func:Watch()
Func:Guard()
Func:Lock()

-- UI
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Window = WindUI:CreateWindow({
    Title = "HK",
    Icon = "zap",
    Author = "Kanha",
    Folder = "HK",
    Size = UDim2.fromOffset(520, 420),
    ToggleKey = Enum.KeyCode.RightShift,
    Theme = "Dark",
    Transparent = false,
    Resizable = true,
})

local Tab = Window:Tab({
    Title = "Street Soccer Pro",
    Icon = "goal",
})

Tab:Toggle({
    Title = "Infinite Stamina",
    Desc = "Stops the local drain and locks stamina at the floor value",
    Icon = "battery-charging",
    Value = Config["Infinite Stamina"],
    Callback = function(State)
        Config["Infinite Stamina"] = State
        Func:Stamina(State)
    end,
})

Tab:Slider({
    Title = "Stamina Floor",
    Desc = "Value pinned every frame while the cheat is on",
    Step = 0.05,
    Value = {
        Min = 0.5,
        Max = 1,
        Default = Config["Stamina Floor"],
    },
    Callback = function(Value)
        Config["Stamina Floor"] = Value
    end,
})

Tab:Toggle({
    Title = "Honest Sprint Flag",
    Desc = "Let the server see you sprinting. Turn on if you get pulled back",
    Icon = "radio",
    Value = Config["Honest Sprint Flag"],
    Callback = function(State)
        Config["Honest Sprint Flag"] = State
        if Config["Infinite Stamina"] then
            Func:Sprint(State)
        end
    end,
})

Tab:Slider({
    Title = "Sprint Speed",
    Desc = "Base 22. Above 26 the server pulls back, above 36 the dribble math breaks",
    Step = 0.5,
    Value = {
        Min = 16.5,
        Max = 55,
        Default = Config["Sprint Speed"],
    },
    Callback = function(Value)
        Config["Sprint Speed"] = Value
        Func:Speed()
    end,
})

Tab:Toggle({
    Title = "Instant Accel",
    Desc = "Reach the configured speed immediately instead of ramping up",
    Icon = "gauge",
    Value = Config["Instant Accel"],
    Callback = function(State)
        Config["Instant Accel"] = State
        Func:Speed()
    end,
})

Tab:Toggle({
    Title = "Speed Bypass",
    Desc = "Feeds the server a later timestamp so its move budget grows with your speed",
    Icon = "shield-off",
    Value = Config["Speed Bypass"],
    Callback = function(State)
        Config["Speed Bypass"] = State
        Func:Speed()
    end,
})

Tab:Toggle({
    Title = "Ball Assist",
    Desc = "Drops back to base speed near the ball so you can still trap it",
    Icon = "circle-dot",
    Value = Config["Ball Assist"],
    Callback = function(State)
        Config["Ball Assist"] = State
        Func:Speed()
    end,
})

Tab:Toggle({
    Title = "Auto Save",
    Desc = "Goalkeeper only. Walks out to cover the shot angle, then dives at shots inside the goal",
    Icon = "hand",
    Value = Config["Auto Save"],
    Callback = function(State)
        Config["Auto Save"] = State
    end,
})

Tab:Slider({
    Title = "Save Range",
    Desc = "Studs the keeper is willing to dive. Position and goal line are checked",
    Step = 0.5,
    Value = {
        Min = 4,
        Max = 20,
        Default = Config["Save Range"],
    },
    Callback = function(Value)
        Config["Save Range"] = Value
    end,
})

Tab:Toggle({
    Title = "Aim Lock",
    Desc = "When you press shoot, the shot is redirected at the clearest corner of the goal",
    Icon = "crosshair",
    Value = Config["Aim Lock"],
    Callback = function(State)
        Config["Aim Lock"] = State
    end,
})

Tab:Slider({
    Title = "Lock Range",
    Desc = "Studs from the opponent goal where Aim Lock is allowed to redirect your shot",
    Step = 1,
    Value = {
        Min = 10,
        Max = 70,
        Default = Config["Lock Range"],
    },
    Callback = function(Value)
        Config["Lock Range"] = Value
    end,
})

Tab:Select()

-- LOOPS
local Generation = (_G.HK_Generation or 0) + 1
_G.HK_Generation = Generation

task.spawn(function()
    while task.wait() do
        if _G.HK_Generation ~= Generation then
            return
        end
        pcall(function()
            if not World or not Target then
                Func:Locate()
            end
            Func:Speed()
            if Config["Auto Save"] then
                local OkSave, ErrSave = pcall(Func.Save, Func)
                if not OkSave then
                    _G.HK_SAVE_ERR = tostring(ErrSave)
                end
            end
            if Config["Infinite Stamina"] then
                if Movement.DRAIN ~= 0 then
                    Movement.DRAIN = 0
                end
                if World and Target then
                    local Ok, Value = pcall(function()
                        return World:get(Target, Components.stamina)
                    end)
                    if not Ok then
                        World, Target = nil, nil
                    elseif Value < Config["Stamina Floor"] then
                        World:set(Target, Components.stamina, Config["Stamina Floor"])
                    end
                end
            end
        end)
    end
end)


