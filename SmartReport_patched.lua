-- ReportHelper v3.1 | StarterPlayerScripts
-- Patch notes: safer clipboard handling, cleaner state management, read-only preview,
-- duplicate GUI cleanup, validation feedback, and more resilient responsive behavior.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Remove any older copy of the GUI so re-running the script stays clean.
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("ReportHelper")
if oldGui then
	oldGui:Destroy()
end

-- ╔══════════════════════════════════════╗
-- ║          ORDERED TEMPLATES           ║
-- ╚══════════════════════════════════════╝

local Categories = {
	{
		name = "🎮 Cheating / Exploiting",
		fn = function(n)
			return ("Player '%s' is using an exploit or cheat client. They were flying, clipping through walls, or dealing impossible damage. Consistent and deliberate — not lag. Please review session logs."):format(n)
		end,
	},
	{
		name = "👗 Inappropriate Avatar",
		fn = function(n)
			return ("Player '%s' has an avatar designed to appear sexualized or offensive. Uses layered clothing or body morphs to bypass avatar moderation. The combination is clearly intentional."):format(n)
		end,
	},
	{
		name = "💬 Chat Filter Bypass",
		fn = function(n)
			return ("Player '%s' is bypassing the chat filter using spaced letters, lookalike characters, or coded language to say inappropriate things. Repeated multiple times — not accidental."):format(n)
		end,
	},
	{
		name = "🔞 Inappropriate Roleplay",
		fn = function(n)
			return ("Player '%s' was engaging in inappropriate romantic or sexual roleplay using coded phrases or game mechanics. Other players may have been present."):format(n)
		end,
	},
	{
		name = "😡 Harassment / Bullying",
		fn = function(n)
			return ("Player '%s' targeted me or another user repeatedly and deliberately — followed across servers, sent hostile messages, or coordinated griefing. Sustained, not playful."):format(n)
		end,
	},
	{
		name = "🎣 Scamming",
		fn = function(n)
			return ("Player '%s' attempted to scam via fake Robux offers, developer impersonation, or a rigged trade. Appeared coordinated across multiple targets — not a misunderstanding."):format(n)
		end,
	},
	{
		name = "💣 NSFW Game / Place",
		fn = function(n)
			return ("Player '%s' is hosting or promoting a game with explicit content, hidden NSFW areas, or bypassed assets. Front page may look clean but gameplay is not. Requires human review."):format(n)
		end,
	},
	{
		name = "🤖 Bot / Account Farming",
		fn = function(n)
			return ("Player '%s' appears to be a bot or part of a farming network. Behaviour is repetitive, non-human, and scripted. No meaningful player interaction observed."):format(n)
		end,
	},
	{
		name = "🔗 Phishing / Malicious Links",
		fn = function(n)
			return ("Player '%s' is distributing suspicious or malicious links in chat, likely phishing for account credentials or Robux. Multiple players were targeted."):format(n)
		end,
	},
}

-- ╔══════════════════════════════════════╗
-- ║            THEME / COLORS            ║
-- ╚══════════════════════════════════════╝

local C = {
	BG = Color3.fromRGB(28, 28, 40),
	PANEL = Color3.fromRGB(18, 18, 28),
	ITEM = Color3.fromRGB(40, 40, 58),
	SEL_P = Color3.fromRGB(200, 50, 50),
	SEL_C = Color3.fromRGB(90, 55, 200),
	CONFIRM = Color3.fromRGB(45, 175, 95),
	CONFIRM_D = Color3.fromRGB(28, 120, 60),
	WARN = Color3.fromRGB(210, 140, 30),
	TEXT_PRI = Color3.fromRGB(230, 230, 245),
	TEXT_SEC = Color3.fromRGB(160, 160, 185),
	TEXT_GEN = Color3.fromRGB(180, 255, 190),
	WHITE = Color3.fromRGB(255, 255, 255),
}

-- ╔══════════════════════════════════════╗
-- ║           CLIPBOARD HELPERS         ║
-- ╚══════════════════════════════════════╝

local function SafeCopy(text)
	if type(setclipboard) ~= "function" then
		return false
	end

	local ok = pcall(function()
		setclipboard(text)
	end)

	return ok
end

-- ╔══════════════════════════════════════╗
-- ║          GUI CONSTRUCTION            ║
-- ╚══════════════════════════════════════╝

local Gui = Instance.new("ScreenGui")
Gui.Name = "ReportHelper"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.IgnoreGuiInset = true
Gui.Parent = playerGui

local function Corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function Padding(parent, px)
	local p = Instance.new("UIPadding")
	local u = UDim.new(0, px)
	p.PaddingTop = u
	p.PaddingBottom = u
	p.PaddingLeft = u
	p.PaddingRight = u
	p.Parent = parent
	return p
end

local function Label(parent, text, size, color, xAlign)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size or 13
	l.Font = Enum.Font.GothamSemibold
	l.TextColor3 = color or C.TEXT_SEC
	l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1, 0, 0, 0)
	l.Parent = parent
	return l
end

local function MakeButton(parent, text, height)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -8, 0, height or 30)
	btn.BackgroundColor3 = C.ITEM
	btn.Text = text
	btn.TextColor3 = C.TEXT_PRI
	btn.TextSize = 12
	btn.Font = Enum.Font.Gotham
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.TextTruncate = Enum.TextTruncate.AtEnd
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	Corner(btn, 6)
	btn.Parent = parent
	return btn
end

-- Main frame
local Main = Instance.new("Frame")
Main.Name = "Main"
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Main.Size = UDim2.new(0.92, 0, 0, 540)
Main.BackgroundColor3 = C.BG
Main.BorderSizePixel = 0
Main.Active = true
Main.Visible = false
Main.ClipsDescendants = true
Main.Parent = Gui
Corner(Main, 12)

local SizeConstraint = Instance.new("UISizeConstraint")
SizeConstraint.MaxSize = Vector2.new(460, math.huge)
SizeConstraint.Parent = Main

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 44)
TitleBar.BackgroundColor3 = C.PANEL
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Main
Corner(TitleBar, 12)

local TitleMask = Instance.new("Frame")
TitleMask.Size = UDim2.new(1, 0, 0.5, 0)
TitleMask.Position = UDim2.new(0, 0, 0.5, 0)
TitleMask.BackgroundColor3 = C.PANEL
TitleMask.BorderSizePixel = 0
TitleMask.Parent = TitleBar

local TitleTxt = Instance.new("TextLabel")
TitleTxt.Size = UDim2.new(1, -90, 1, 0)
TitleTxt.Position = UDim2.new(0, 14, 0, 0)
TitleTxt.BackgroundTransparency = 1
TitleTxt.Text = "🚨  Report Helper  v3"
TitleTxt.TextColor3 = C.SEL_P
TitleTxt.TextSize = 16
TitleTxt.Font = Enum.Font.GothamBold
TitleTxt.TextXAlignment = Enum.TextXAlignment.Left
TitleTxt.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -36, 0.5, -14)
CloseBtn.BackgroundColor3 = C.SEL_P
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = C.WHITE
CloseBtn.TextSize = 13
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BorderSizePixel = 0
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = TitleBar
Corner(CloseBtn, 6)

CloseBtn.MouseButton1Click:Connect(function()
	Main.Visible = false
end)

-- Body
local Body = Instance.new("ScrollingFrame")
Body.Size = UDim2.new(1, 0, 1, -44)
Body.Position = UDim2.new(0, 0, 0, 44)
Body.BackgroundTransparency = 1
Body.BorderSizePixel = 0
Body.ScrollBarThickness = 4
Body.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 130)
Body.AutomaticCanvasSize = Enum.AutomaticSize.Y
Body.CanvasSize = UDim2.new(0, 0, 0, 0)
Body.Parent = Main

local BodyLayout = Instance.new("UIListLayout")
BodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
BodyLayout.Padding = UDim.new(0, 10)
BodyLayout.Parent = Body
Padding(Body, 12)

local function Section(title, layoutOrder)
	local wrapper = Instance.new("Frame")
	wrapper.Name = title
	wrapper.LayoutOrder = layoutOrder
	wrapper.BackgroundTransparency = 1
	wrapper.AutomaticSize = Enum.AutomaticSize.Y
	wrapper.Size = UDim2.new(1, 0, 0, 0)
	wrapper.Parent = Body

	local inner = Instance.new("UIListLayout")
	inner.SortOrder = Enum.SortOrder.LayoutOrder
	inner.Padding = UDim.new(0, 6)
	inner.Parent = wrapper

	local lbl = Label(wrapper, title, 11, C.TEXT_SEC)
	lbl.LayoutOrder = 0
	lbl.TextSize = 11

	return wrapper
end

-- Step 1
local Step1 = Section("① SELECT PLAYER", 1)

local PlayerPanel = Instance.new("ScrollingFrame")
PlayerPanel.LayoutOrder = 1
PlayerPanel.Size = UDim2.new(1, 0, 0, 120)
PlayerPanel.BackgroundColor3 = C.PANEL
PlayerPanel.BorderSizePixel = 0
PlayerPanel.ScrollBarThickness = 4
PlayerPanel.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 130)
PlayerPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
PlayerPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
PlayerPanel.Parent = Step1
Corner(PlayerPanel, 8)
Padding(PlayerPanel, 4)

local PlayerLayout = Instance.new("UIListLayout")
PlayerLayout.SortOrder = Enum.SortOrder.LayoutOrder
PlayerLayout.Padding = UDim.new(0, 4)
PlayerLayout.Parent = PlayerPanel

-- Step 2
local Step2 = Section("② SELECT VIOLATION CATEGORY", 2)

local CatPanel = Instance.new("ScrollingFrame")
CatPanel.LayoutOrder = 1
CatPanel.Size = UDim2.new(1, 0, 0, 155)
CatPanel.BackgroundColor3 = C.PANEL
CatPanel.BorderSizePixel = 0
CatPanel.ScrollBarThickness = 4
CatPanel.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 130)
CatPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
CatPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
CatPanel.Parent = Step2
Corner(CatPanel, 8)
Padding(CatPanel, 4)

local CatLayout = Instance.new("UIListLayout")
CatLayout.SortOrder = Enum.SortOrder.LayoutOrder
CatLayout.Padding = UDim.new(0, 4)
CatLayout.Parent = CatPanel

-- Step 3
local Step3 = Section("③ GENERATED REPORT TEMPLATE", 3)

local PreviewBox = Instance.new("TextBox")
PreviewBox.LayoutOrder = 1
PreviewBox.Size = UDim2.new(1, 0, 0, 90)
PreviewBox.BackgroundColor3 = C.PANEL
PreviewBox.TextColor3 = C.TEXT_GEN
PreviewBox.Text = "Select a player and add one or more violation instances to generate your report."
PreviewBox.TextSize = 11
PreviewBox.Font = Enum.Font.Gotham
PreviewBox.TextWrapped = true
PreviewBox.MultiLine = true
PreviewBox.ClearTextOnFocus = false
PreviewBox.TextEditable = false
PreviewBox.Selectable = true
PreviewBox.TextXAlignment = Enum.TextXAlignment.Left
PreviewBox.TextYAlignment = Enum.TextYAlignment.Top
PreviewBox.BorderSizePixel = 0
PreviewBox.Parent = Step3
Corner(PreviewBox, 8)
Padding(PreviewBox, 8)

local FallbackNote = Instance.new("TextLabel")
FallbackNote.LayoutOrder = 2
FallbackNote.Size = UDim2.new(1, 0, 0, 0)
FallbackNote.AutomaticSize = Enum.AutomaticSize.Y
FallbackNote.BackgroundTransparency = 1
FallbackNote.Text = "⚠️ Clipboard API unavailable — manually select the text above and copy it."
FallbackNote.TextColor3 = C.WARN
FallbackNote.TextSize = 10
FallbackNote.Font = Enum.Font.Gotham
FallbackNote.TextWrapped = true
FallbackNote.TextXAlignment = Enum.TextXAlignment.Left
FallbackNote.Visible = false
FallbackNote.Parent = Step3

local InstanceBtn = Instance.new("TextButton")
InstanceBtn.LayoutOrder = 3
InstanceBtn.Size = UDim2.new(1, 0, 0, 36)
InstanceBtn.BackgroundColor3 = C.SEL_C
InstanceBtn.Text = "➕  Add Violation Instance"
InstanceBtn.TextColor3 = C.WHITE
InstanceBtn.TextSize = 13
InstanceBtn.Font = Enum.Font.GothamBold
InstanceBtn.BorderSizePixel = 0
InstanceBtn.AutoButtonColor = false
InstanceBtn.Parent = Step3
Corner(InstanceBtn, 8)

local CopyBtn = Instance.new("TextButton")
CopyBtn.LayoutOrder = 4
CopyBtn.Size = UDim2.new(1, 0, 0, 36)
CopyBtn.BackgroundColor3 = C.CONFIRM
CopyBtn.Text = "📋  Copy Combined Report"
CopyBtn.TextColor3 = C.WHITE
CopyBtn.TextSize = 13
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.BorderSizePixel = 0
CopyBtn.AutoButtonColor = false
CopyBtn.Parent = Step3
Corner(CopyBtn, 8)

local ResetBtn = Instance.new("TextButton")
ResetBtn.LayoutOrder = 5
ResetBtn.Size = UDim2.new(1, 0, 0, 28)
ResetBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
ResetBtn.Text = "↺  Clear Selections"
ResetBtn.TextColor3 = C.TEXT_SEC
ResetBtn.TextSize = 12
ResetBtn.Font = Enum.Font.Gotham
ResetBtn.BorderSizePixel = 0
ResetBtn.AutoButtonColor = false
ResetBtn.Parent = Step3
Corner(ResetBtn, 8)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.LayoutOrder = 6
StatusLabel.Size = UDim2.new(1, 0, 0, 0)
StatusLabel.AutomaticSize = Enum.AutomaticSize.Y
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Ready."
StatusLabel.TextColor3 = C.TEXT_SEC
StatusLabel.TextSize = 10
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextWrapped = true
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = Step3

-- ╔══════════════════════════════════════╗
-- ║        STATE + PREVIEW ENGINE        ║
-- ╚══════════════════════════════════════╝

local State = {
	Player = nil,
	Category = nil,
	Entries = {},
}

local playerButtons = {} -- [playerName] = button
local catButtons = {} -- [index] = button

local function SetStatus(text, color)
	StatusLabel.Text = text
	StatusLabel.TextColor3 = color or C.TEXT_SEC
end

local function GetEntryCount()
	return #State.Entries
end

local function BuildReportText()
	if not State.Player then
		return nil
	end

	if GetEntryCount() == 0 and not State.Category then
		return nil
	end

	local lines = {}
	table.insert(lines, ("Report target: %s (@%s)"):format(State.Player.DisplayName, State.Player.Name))
	table.insert(lines, ("Total violation instance%s: %d"):format(GetEntryCount() == 1 and "" or "s", math.max(GetEntryCount(), 1)))
	table.insert(lines, "")

	if GetEntryCount() > 0 then
		for i, entry in ipairs(State.Entries) do
			local cat = Categories[entry.Category]
			table.insert(lines, ("%d) %s"):format(i, cat and cat.name or "Unknown Category"))
			table.insert(lines, entry.Text or "")
			if i < GetEntryCount() then
				table.insert(lines, "")
			end
		end
		return table.concat(lines, "\n")
	end

	table.insert(lines, Categories[State.Category].fn(State.Player.Name))
	return table.concat(lines, "\n")
end

local function RefreshPlayerButtons()
	for name, button in pairs(playerButtons) do
		local isSelected = State.Player and State.Player.Name == name
		button.BackgroundColor3 = isSelected and C.SEL_P or C.ITEM
		button.TextColor3 = isSelected and C.WHITE or C.TEXT_PRI
	end
end

local function RefreshCategoryButtons()
	for i, button in ipairs(catButtons) do
		local isSelected = State.Category == i
		button.BackgroundColor3 = isSelected and C.SEL_C or C.ITEM
		button.TextColor3 = isSelected and C.WHITE or C.TEXT_PRI
	end
end

local function UpdatePreview()
	local reportText = BuildReportText()
	if reportText then
		PreviewBox.Text = reportText
	else
		PreviewBox.Text = "Select a player and add one or more violation instances to generate your report."
	end

	if not State.Player then
		SetStatus("Choose a player to begin.", C.TEXT_SEC)
		return
	end

	if GetEntryCount() > 0 then
		SetStatus(("Collected %d violation instance%s for %s."):format(GetEntryCount(), GetEntryCount() == 1 and "" or "s", State.Player.DisplayName), C.CONFIRM)
		return
	end

	if State.Category then
		SetStatus(("Ready to add an instance for %s."):format(State.Player.DisplayName), C.TEXT_SEC)
	else
		SetStatus(("Choose a category for %s."):format(State.Player.DisplayName), C.TEXT_SEC)
	end
end

local function SelectPlayer(player)
	if State.Player ~= player then
		State.Entries = {}
	end

	State.Player = player
	RefreshPlayerButtons()
	UpdatePreview()
end

local function SelectCategory(index)
	State.Category = index
	RefreshCategoryButtons()
	UpdatePreview()
end

local function AddCurrentViolation()
	if not State.Player then
		SetStatus("Pick a player first.", C.WARN)
		return
	end

	if not State.Category then
		SetStatus("Pick a category first.", C.WARN)
		return
	end

	table.insert(State.Entries, {
		Category = State.Category,
		Text = Categories[State.Category].fn(State.Player.Name),
	})

	FallbackNote.Visible = false
	RefreshCategoryButtons()
	UpdatePreview()
	SetStatus(("Added violation instance #%d for %s."):format(GetEntryCount(), State.Player.DisplayName), C.CONFIRM)
end

local function ClearSelection()
	State.Player = nil
	State.Category = nil
	State.Entries = {}
	RefreshPlayerButtons()
	RefreshCategoryButtons()
	FallbackNote.Visible = false
	UpdatePreview()
end

-- Player button factory
local function AddPlayerButton(player)
	if player == LocalPlayer then
		return
	end

	if playerButtons[player.Name] then
		return
	end

	local btn = MakeButton(PlayerPanel, "  " .. player.DisplayName .. "  (@" .. player.Name .. ")", 30)
	playerButtons[player.Name] = btn

	btn.MouseButton1Click:Connect(function()
		SelectPlayer(player)
	end)

	btn.MouseEnter:Connect(function()
		if not (State.Player and State.Player.Name == player.Name) then
			btn.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
		end
	end)

	btn.MouseLeave:Connect(function()
		if not (State.Player and State.Player.Name == player.Name) then
			btn.BackgroundColor3 = C.ITEM
		end
	end)
end

-- Category buttons
for i, cat in ipairs(Categories) do
	local btn = MakeButton(CatPanel, "  " .. cat.name, 30)
	btn.LayoutOrder = i
	catButtons[i] = btn

	btn.MouseButton1Click:Connect(function()
		SelectCategory(i)
	end)

	btn.MouseEnter:Connect(function()
		if State.Category ~= i then
			btn.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
		end
	end)

	btn.MouseLeave:Connect(function()
		if State.Category ~= i then
			btn.BackgroundColor3 = C.ITEM
		end
	end)
end

-- Add / Copy button logic
InstanceBtn.MouseButton1Click:Connect(function()
	AddCurrentViolation()
end)

CopyBtn.MouseButton1Click:Connect(function()
	if not State.Player then
		SetStatus("Pick a player first.", C.WARN)
		return
	end

	local reportText = BuildReportText()
	if not reportText then
		SetStatus("Pick a category and add at least one violation instance first.", C.WARN)
		return
	end

	local ok = SafeCopy(reportText)

	if ok then
		FallbackNote.Visible = false
		CopyBtn.Text = "✅  Copied!"
		CopyBtn.BackgroundColor3 = C.CONFIRM_D
		SetStatus("Copied combined report to clipboard.", C.CONFIRM)

		task.delay(2.5, function()
			if CopyBtn.Parent then
				CopyBtn.Text = "📋  Copy Combined Report"
				CopyBtn.BackgroundColor3 = C.CONFIRM
			end
		end)
	else
		FallbackNote.Visible = true
		SetStatus("Clipboard access is unavailable in this environment.", C.WARN)
		PreviewBox:CaptureFocus()
		PreviewBox.SelectionStart = 1
		PreviewBox.CursorPosition = #PreviewBox.Text + 1
	end
end)

-- Reset logic
ResetBtn.MouseButton1Click:Connect(ClearSelection)

-- ╔══════════════════════════════════════╗
-- ║      PLAYER JOIN / LEAVE HANDLING    ║
-- ╚══════════════════════════════════════╝

for _, p in ipairs(Players:GetPlayers()) do
	AddPlayerButton(p)
end

Players.PlayerAdded:Connect(AddPlayerButton)

Players.PlayerRemoving:Connect(function(player)
	local btn = playerButtons[player.Name]
	if btn then
		btn:Destroy()
		playerButtons[player.Name] = nil
	end

	if State.Player == player then
		State.Player = nil
		RefreshPlayerButtons()
		UpdatePreview()
	end
end)

-- ╔══════════════════════════════════════╗
-- ║            TOGGLE BUTTON            ║
-- ╚══════════════════════════════════════╝

local Toggle = Instance.new("TextButton")
Toggle.Size = UDim2.new(0, 140, 0, 38)
Toggle.Position = UDim2.new(0, 12, 1, -50)
Toggle.BackgroundColor3 = C.SEL_P
Toggle.Text = "🚨  Report Helper"
Toggle.TextColor3 = C.WHITE
Toggle.TextSize = 12
Toggle.Font = Enum.Font.GothamBold
Toggle.BorderSizePixel = 0
Toggle.AutoButtonColor = false
Toggle.Parent = Gui
Corner(Toggle, 10)

Toggle.MouseEnter:Connect(function()
	Toggle.BackgroundColor3 = Color3.fromRGB(230, 70, 70)
end)

Toggle.MouseLeave:Connect(function()
	Toggle.BackgroundColor3 = C.SEL_P
end)

Toggle.MouseButton1Click:Connect(function()
	Main.Visible = not Main.Visible
end)

-- ╔══════════════════════════════════════╗
-- ║   RESPONSIVE SIZE RE-CALCULATION     ║
-- ╚══════════════════════════════════════╝

local function OnResize()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local vp = camera.ViewportSize
	if vp.X < 500 then
		Main.Size = UDim2.new(0.96, 0, 0, 520)
	else
		Main.Size = UDim2.new(0.92, 0, 0, 540)
	end
end

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(OnResize)
end

OnResize()
ClearSelection()
