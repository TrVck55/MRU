-- Remote Suite v1.1
-- Executor APIs required:
-- gethui, hookmetamethod, newcclosure, checkcaller, getnamecallmethod

local CoreGui = (gethui and gethui()) or game:GetService("CoreGui")

local EXPERIMENTAL_BLOCK_BINDABLES = false
local MAX_LOGS = 100

local Supported = {
    RemoteEvent = {Color = Color3.fromRGB(70,120,255)},
    RemoteFunction = {Color = Color3.fromRGB(255,170,70)},
    UnreliableRemoteEvent = {Color = Color3.fromRGB(170,70,255)},
    BindableEvent = {Color = Color3.fromRGB(70,255,120)},
    BindableFunction = {Color = Color3.fromRGB(255,70,120)}
}

local Blocked, Buttons, Logs = {}, {}, {}
local CallCount, CPS, CurrentSecond = {}, {}, {}

local Gui = Instance.new("ScreenGui")
Gui.Name = "RemoteSuite"
Gui.ResetOnSpawn = false
Gui.Parent = CoreGui

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(750, 500)
Frame.Position = UDim2.new(.5, -375, .5, -250)
Frame.BackgroundColor3 = Color3.fromRGB(30,30,30)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true
Frame.Parent = Gui

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1,0,0,30)
Title.BackgroundTransparency = 1
Title.Text = "Remote Suite v1.1"
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 24
Title.TextColor3 = Color3.new(1,1,1)
Title.Parent = Frame

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.fromOffset(30,30)
MinBtn.Position = UDim2.new(1,-35,0,0)
MinBtn.Text = "-"
MinBtn.Parent = Frame

local Search = Instance.new("TextBox")
Search.Size = UDim2.new(1,-10,0,30)
Search.Position = UDim2.new(0,5,0,35)
Search.PlaceholderText = "Search..."
Search.Parent = Frame

local Refresh = Instance.new("TextButton")
Refresh.Size = UDim2.new(.5,-7,0,30)
Refresh.Position = UDim2.new(0,5,0,70)
Refresh.Text = "Refresh"
Refresh.Parent = Frame

local ClearLogs = Instance.new("TextButton")
ClearLogs.Size = UDim2.new(.5,-7,0,30)
ClearLogs.Position = UDim2.new(.5 + .005,0,0,70)
ClearLogs.Text = "Clear Logs"
ClearLogs.Parent = Frame

local RemoteScroll = Instance.new("ScrollingFrame")
RemoteScroll.Position = UDim2.new(0,5,0,105)
RemoteScroll.Size = UDim2.new(.45,-5,1,-110)
RemoteScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
RemoteScroll.ScrollBarThickness = 6
RemoteScroll.Parent = Frame
Instance.new("UIListLayout", RemoteScroll)

local SpyScroll = Instance.new("ScrollingFrame")
SpyScroll.Position = UDim2.new(.45,5,0,105)
SpyScroll.Size = UDim2.new(.55,-10,1,-110)
SpyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
SpyScroll.ScrollBarThickness = 6
SpyScroll.Parent = Frame
Instance.new("UIListLayout", SpyScroll)

local function Format(v, depth)
    depth = depth or 0
    if depth > 2 then return "..." end

    local t = typeof(v)
    if t == "string" then
        return '"' .. v .. '"'
    elseif t == "Instance" then
        return v:GetFullName()
    elseif t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            table.insert(parts, tostring(k) .. "=" .. Format(val, depth + 1))
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end

    return tostring(v)
end

local function AddLog(remote, method, args)
    local lines = {
        "[" .. os.date("%X") .. "]",
        remote:GetFullName(),
        method
    }

    for i, v in ipairs(args) do
        table.insert(lines, i .. " = " .. Format(v))
    end

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1,-5,0,0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.BackgroundColor3 = Color3.fromRGB(45,45,45)
    label.TextColor3 = Color3.new(1,1,1)
    label.Text = table.concat(lines, "\n")
    label.Parent = SpyScroll

    table.insert(Logs, label)

    if #Logs > MAX_LOGS then
        Logs[1]:Destroy()
        table.remove(Logs, 1)
    end
end

local function UpdateButton(remote)
    local btn = Buttons[remote]
    if not btn then return end

    btn.Text = string.format(
        "[%s] [%s]\nCalls: %d | %d/s\n%s",
        Blocked[remote] and "X" or " ",
        remote.ClassName,
        CallCount[remote] or 0,
        CPS[remote] or 0,
        remote:GetFullName()
    )
end

local function AddRemote(remote)
    if Buttons[remote] or not Supported[remote.ClassName] then return end

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,-5,0,60)
    btn.TextWrapped = true
    btn.TextColor3 = Color3.new(1,1,1)
    btn.BackgroundColor3 = Supported[remote.ClassName].Color
    btn.Parent = RemoteScroll

    Buttons[remote] = btn
    UpdateButton(remote)

    btn.MouseButton1Click:Connect(function()
        Blocked[remote] = not Blocked[remote]
        btn.BackgroundTransparency = Blocked[remote] and .4 or 0
        UpdateButton(remote)
    end)
end

local function RemoveRemote(remote)
    if Buttons[remote] then
        Buttons[remote]:Destroy()
        Buttons[remote] = nil
    end
    Blocked[remote] = nil
end

local function Scan()
    for _, btn in pairs(Buttons) do
        btn:Destroy()
    end
    table.clear(Buttons)

    local descendants = game:GetDescendants()
    for i, obj in ipairs(descendants) do
        if Supported[obj.ClassName] then
            AddRemote(obj)
        end
        if i % 300 == 0 then
            task.wait()
        end
    end
end

Refresh.MouseButton1Click:Connect(Scan)

ClearLogs.MouseButton1Click:Connect(function()
    for _, v in ipairs(Logs) do
        v:Destroy()
    end
    table.clear(Logs)
end)

Search:GetPropertyChangedSignal("Text"):Connect(function()
    local txt = Search.Text:lower()
    for remote, btn in pairs(Buttons) do
        btn.Visible = txt == "" or remote:GetFullName():lower():find(txt)
    end
end)

game.DescendantAdded:Connect(function(obj)
    if Supported[obj.ClassName] then
        AddRemote(obj)
    end
end)

game.DescendantRemoving:Connect(RemoveRemote)

local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized

    RemoteScroll.Visible = not minimized
    SpyScroll.Visible = not minimized
    Search.Visible = not minimized
    Refresh.Visible = not minimized
    ClearLogs.Visible = not minimized

    Frame.Size = minimized and UDim2.fromOffset(750,30)
        or UDim2.fromOffset(750,500)
end)

task.spawn(function()
    while true do
        task.wait(1)
        for remote, count in pairs(CurrentSecond) do
            CPS[remote] = count
            CurrentSecond[remote] = 0
            UpdateButton(remote)
        end
    end
end)

Scan()

local Old
Old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = {...}

    if not checkcaller() and typeof(self) == "Instance" then
        local allowed =
            (self:IsA("RemoteEvent") and method == "FireServer") or
            (self:IsA("UnreliableRemoteEvent") and method == "FireServer") or
            (self:IsA("RemoteFunction") and method == "InvokeServer") or
            (self:IsA("BindableEvent") and method == "Fire") or
            (self:IsA("BindableFunction") and method == "Invoke")

        if allowed then
            CallCount[self] = (CallCount[self] or 0) + 1
            CurrentSecond[self] = (CurrentSecond[self] or 0) + 1

            if Buttons[self] then
                UpdateButton(self)
            end

            AddLog(self, method, args)

            local isBindable = self:IsA("BindableEvent") or self:IsA("BindableFunction")

            if Blocked[self] and (not isBindable or EXPERIMENTAL_BLOCK_BINDABLES) then
                warn("Blocked:", self:GetFullName())
                return nil
            end
        end
    end

    return Old(self, ...)
end))
