local SourceUrl = "https://raw.githubusercontent.com/Smoithx/Meow-X/refs/heads/main/Load.lua"

local Ok, Source = pcall(game.HttpGet, game, SourceUrl)
if not Ok then
    error("[UI] failed to download: " .. tostring(Source) .. " @ " .. SourceUrl, 0)
end

local Chunk, LoadError = loadstring(Source)
if not Chunk then
    error("[UI] library failed to compile: " .. tostring(LoadError) .. " @ " .. SourceUrl, 0)
end

local Library = Chunk()

local Window = Library:CreateWindow({
    Title = "Gravity Hub",
    Subtitle = os.date("%d/%m/%Y"),
    LogoUrl = "https://raw.githubusercontent.com/Smoithx/Meow-X/main/image.png"
})

local ItemCount = 0
local function fillDemo(group, tag)
    ItemCount = ItemCount + 1
    local n = ItemCount

    group:AddLabel(tag .. " section - label #" .. n .. "\n11111111111111111")

    group:AddToggle(tag .. "_ToggleA", {
        Text = "Enable " .. tag,
        Desc = "Toggle with description",
        Default = (n % 2 == 0),
        Callback = function(Value)
            print(tag .. " toggle:", Value)
        end
    })

    group:AddToggle(tag .. "_ToggleB", {
        Text = tag .. " Extra Option",
        Default = false,
        Callback = function(Value)
            print(tag .. " extra:", Value)
        end
    })

    group:AddSlider(tag .. "_Slider", {
        Text = tag .. " Speed",
        Min = 0,
        Max = 200,
        Default = 50 + n,
        Rounding = 0,
        Callback = function(Value)
            print(tag .. " slider:", Value)
        end
    })

    group:AddDropdown(tag .. "_Dropdown", {
        Text = tag .. " Mode",
        SubText = "Pick one mode",
        Default = "Mode 1",
        Values = { "Mode 1", "Mode 2", "Mode 3", "Mode 4" },
        Callback = function(Value)
            print(tag .. " dropdown:", Value)
        end
    })

    group:AddDropdown(tag .. "_Multi", {
        Text = tag .. " Multi",
        SubText = "Pick several",
        Multi = true,
        Default = { "Alpha", "Beta" },
        Values = { "Alpha", "Beta", "Gamma", "Delta", "Omega" },
        Callback = function(Value, IsSelected)
            print(tag .. " multi:", Value, IsSelected)
        end
    })

    group:AddInput(tag .. "_Input", {
        Text = tag .. " Text Box",
        Default = "",
        Placeholder = "type something...",
        Callback = function(Value)
            print(tag .. " input:", Value)
        end
    })

    group:AddKeyBind({
        Title = tag .. " Keybind",
        Default = "F",
        Mode = "Toggle",
        Callback = function(Value)
            print(tag .. " keybind:", Value)
        end
    })

    group:AddButton({
        Text = tag .. " Button",
        Func = function()
            Library:Notify({
                Title = tag,
                Description = "Button #" .. n .. " clicked",
                Duration = 3
            })
        end
    })
end

-- Tab 1: everything
local MainTab = Window:AddTab("Main Menu")
local MainGroup = MainTab:AddLeftGroupbox("All Features")
fillDemo(MainGroup, "Main")

local MainExtra = MainTab:AddRightGroupbox("Second Group")
MainExtra:AddButton({
    Text = "Clear Main Multi",
    Func = function()
        print("clear requested")
    end
})
MainExtra:AddToggle("MainTabToggle", {
    Text = "Only in second group",
    Default = true,
    Callback = function(Value)
        print("second group toggle:", Value)
    end
})

local ExtraTabs = { "Combat", "Visuals", "Player", "Misc", "Settings", "Test One", "Test Two" }
for index, tabName in ipairs(ExtraTabs) do
    local Tab = Window:AddTab(tabName)
    local Left = Tab:AddLeftGroupbox(tabName .. " Left")
    fillDemo(Left, tabName)

    local Right = Tab:AddRightGroupbox(tabName .. " Right")
    Right:AddToggle(tabName .. "_RightToggle", {
        Text = tabName .. " Right Toggle",
        Default = false,
        Callback = function(Value)
            print(tabName .. " right toggle:", Value)
        end
    })
    Right:AddSlider(tabName .. "_RightSlider", {
        Text = tabName .. " Right Slider",
        Min = 0,
        Max = 10,
        Default = index,
        Rounding = 1,
        Callback = function(Value)
            print(tabName .. " right slider:", Value)
        end
    })
    Right:AddDropdown(tabName .. "_RightDropdown", {
        Text = tabName .. " Right Dropdown",
        SubText = "Extra dropdown",
        Default = 1,
        Values = { "One", "Two", "Three" },
        Callback = function(Value)
            print(tabName .. " right dropdown:", Value)
        end
    })
end

Library:Notify({
    Title = "Loaded",
    Description = "Stress test with 8 tabs.",
    Duration = 3
})
