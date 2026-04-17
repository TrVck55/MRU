-- SmartReport v4.1 | LocalScript → StarterPlayerScripts
-- Additions: auto-submit via Players:ReportAbuse(), submit guard,
--            char-limit trimming, live player re-resolution,
--            layout order fix, polish pass.

local Players        = game:GetService("Players")
local LocalPlayer    = Players.LocalPlayer
local TweenService   = game:GetService("TweenService") -- retained for future use

math.randomseed(math.floor(os.clock() * 1e6) % 2147483647)

-- Remove older copies so re-running the script stays clean.
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local oldGui    = playerGui:FindFirstChild("ReportHelper")
if oldGui then oldGui:Destroy() end

-- ╔══════════════════════════════════════╗
-- ║               THEME                 ║
-- ╚══════════════════════════════════════╝

local C = {
	BG       = Color3.fromRGB(25,  26,  36),
	PANEL    = Color3.fromRGB(18,  19,  28),
	PANEL_2  = Color3.fromRGB(31,  32,  46),
	ITEM     = Color3.fromRGB(41,  42,  60),
	ITEM_H   = Color3.fromRGB(55,  56,  78),
	GOOD     = Color3.fromRGB(45,  165, 95),
	GOOD_D   = Color3.fromRGB(32,  122, 70),
	BAD      = Color3.fromRGB(212, 70,  74),
	ACCENT   = Color3.fromRGB(95,  72,  220),
	ACCENT_2 = Color3.fromRGB(123, 97,  245),
	WARN     = Color3.fromRGB(220, 150, 45),
	TEXT     = Color3.fromRGB(236, 236, 246),
	SUB      = Color3.fromRGB(170, 173, 195),
	MUTED    = Color3.fromRGB(145, 148, 168),
}

-- ╔══════════════════════════════════════╗
-- ║       ORDERED CATEGORY TEMPLATES    ║
-- ╚══════════════════════════════════════╝

local ToneModes = { "Formal", "Neutral", "Urgent" }

local Templates = {
	{
		name = "🎮 Cheating / Exploiting",
		variants = {
			Formal  = { "%s appears to be using an exploit. I observed abnormal movement / combat behavior and recommend review of the session.",
			            "%s displayed behavior consistent with cheating. The actions observed were not normal gameplay and should be reviewed." },
			Neutral = { "%s seems to be exploiting. I noticed behavior that does not match normal gameplay.",
			            "%s showed suspicious movement/combat behavior that looks like an exploit." },
			Urgent  = { "%s is behaving like an exploiter right now. The actions I saw were clearly beyond normal gameplay.",
			            "%s appears to be cheating. I saw repeated abnormal actions that strongly suggest exploit use." },
		},
	},
	{
		name = "💬 Chat Filter Bypass",
		variants = {
			Formal  = { "%s appears to be bypassing chat moderation by using spaced letters, symbols, or coded wording.",
			            "%s is using repeated chat filter bypass methods. The message pattern looks intentional." },
			Neutral = { "%s is bypassing the chat filter using disguised wording or spacing.",
			            "%s sent messages that look like deliberate moderation bypass attempts." },
			Urgent  = { "%s is actively bypassing the chat filter right now. The pattern looks intentional and repeated.",
			            "%s keeps evading moderation with coded / spaced text and should be reviewed." },
		},
	},
	{
		name = "😡 Harassment / Bullying",
		variants = {
			Formal  = { "%s has been repeatedly harassing or targeting another player. The behavior appears deliberate and sustained.",
			            "%s is engaging in bullying-style behavior, including repeated hostile targeting and disruption." },
			Neutral = { "%s is repeatedly targeting and harassing others.",
			            "%s has been acting hostile toward another player in a repeated way." },
			Urgent  = { "%s is actively harassing players and it has become persistent. Please review this quickly.",
			            "%s is escalating hostile behavior and repeatedly targeting others." },
		},
	},
	{
		name = "🎣 Scamming",
		variants = {
			Formal  = { "%s appears to be attempting a scam or deceptive trade. The wording / setup suggests intentional deception.",
			            "%s is using misleading offers or impersonation-like behavior that may be intended to scam others." },
			Neutral = { "%s is trying to scam players using misleading offers or false claims.",
			            "%s appears to be running a deceptive trade / offer setup." },
			Urgent  = { "%s looks like they are actively scamming right now. The setup is misleading and may be harming other players.",
			            "%s is using a deceptive offer pattern that strongly suggests a scam attempt." },
		},
	},
	{
		name = "🔞 Inappropriate Roleplay",
		variants = {
			Formal  = { "%s was engaging in inappropriate roleplay content that may violate community standards.",
			            "%s appears to be participating in sexually suggestive or otherwise inappropriate roleplay." },
			Neutral = { "%s was doing inappropriate roleplay that crossed a line.",
			            "%s seems to be involved in sexualized or otherwise inappropriate roleplay." },
			Urgent  = { "%s is currently doing inappropriate roleplay content and should be reviewed.",
			            "%s is actively participating in inappropriate roleplay right now." },
		},
	},
	{
		name = "🤖 Bot / AFK Farming",
		variants = {
			Formal  = { "%s appears to be automated or bot-like. The behavior is repetitive and non-human in pattern.",
			            "%s shows signs of scripted / AFK farming behavior rather than normal player activity." },
			Neutral = { "%s seems bot-like or farmed. The movement and actions are repetitive.",
			            "%s is acting like a bot or AFK farm account." },
			Urgent  = { "%s looks automated right now. The repeated pattern strongly suggests botting or farming.",
			            "%s is behaving like an active bot / farm account and should be reviewed." },
		},
	},
	{
		name = "🔗 Phishing / Malicious Links",
		variants = {
			Formal  = { "%s is sharing suspicious links or messages that may be phishing or malicious.",
			            "%s appears to be distributing unsafe links or deceptive messages in chat." },
			Neutral = { "%s is posting suspicious links that look unsafe.",
			            "%s appears to be sharing links that may be phishing or malicious." },
			Urgent  = { "%s is actively sharing suspicious links right now. This may be a phishing attempt.",
			            "%s looks like they are distributing malicious or phishing-style links." },
		},
	},
	{
		name = "👗 Inappropriate Avatar",
		variants = {
			Formal  = { "%s is using an avatar that appears inappropriate or intentionally provocative.",
			            "%s has an avatar setup that may violate appearance guidelines or community standards." },
			Neutral = { "%s has an inappropriate-looking avatar setup.",
			            "%s appears to be using an avatar that crosses a moderation line." },
			Urgent  = { "%s is using an avatar that looks inappropriate and should be reviewed.",
			            "%s appears to have an intentionally provocative avatar setup." },
		},
	},
	{
		name = "💣 NSFW Game / Place",
		variants = {
			Formal  = { "%s is promoting or hosting content that appears to contain NSFW material.",
			            "%s appears to be associated with a place or game that includes explicit content." },
			Neutral = { "%s seems to be pushing NSFW content or a place with explicit material.",
			            "%s appears linked to an inappropriate game / place." },
			Urgent  = { "%s is promoting explicit content or an NSFW place right now.",
			            "%s appears to be connected to a place with explicit content and should be reviewed." },
		},
	},
}

-- ╔══════════════════════════════════════╗
-- ║             UTILITIES               ║
-- ╚══════════════════════════════════════╝

local function Pick(list)
	return list[math.random(1, #list)]
end

local function Trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Tries native setclipboard; returns true on success.
local function SafeCopy(text)
	if type(setclipboard) ~= "function" then return false end
	local ok = pcall(setclipboard, text)
	return ok
end

-- Roblox's report message field limit (characters).
local REPORT_CHAR_LIMIT = 900

-- Submits via the native Roblox report API.
-- Returns: ok (bool), errMsg (string | nil)
local function SafeSubmit(playerObj, categoryName, reportText)
	if type(playerObj) ~= "userdata" or not playerObj:IsA("Player") then
		return false, "Player object is invalid or has left the server."
	end

	local msg = reportText or ""
	if #msg > REPORT_CHAR_LIMIT then
		msg = msg:sub(1, REPORT_CHAR_LIMIT - 3) .. "..."
	end

	local ok, err = pcall(function()
		Players:ReportAbuse(playerObj, categoryName, msg)
	end)

	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

local function FormatNote(note)
	note = Trim(note)
	return (note ~= "") and note or nil
end

-- ╔══════════════════════════════════════╗
-- ║              GUI SETUP              ║
-- ╚══════════════════════════════════════╝

local Gui = Instance.new("ScreenGui")
Gui.Name           = "ReportHelper"
Gui.IgnoreGuiInset = true
Gui.ResetOnSpawn   = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent         = playerGui

local function Corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function Pad(parent, px)
	local p  = Instance.new("UIPadding")
	local u  = UDim.new(0, px or 8)
	p.PaddingTop    = u
	p.PaddingBottom = u
	p.PaddingLeft   = u
	p.PaddingRight  = u
	p.Parent = parent
	return p
end

local function MakeLabel(parent, text, size, color, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text           = text or ""
	l.Font           = Enum.Font.Gotham
	l.TextSize       = size or 12
	l.TextColor3     = color or C.SUB
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped    = true
	l.AutomaticSize  = Enum.AutomaticSize.Y
	l.Size           = UDim2.new(1, 0, 0, 0)
	l.Parent         = parent
	return l
end

local function MakeButton(parent, text, height, baseColor)
	local btn = Instance.new("TextButton")
	btn.Size             = UDim2.new(1, -6, 0, height or 32)
	btn.BackgroundColor3 = baseColor or C.ITEM
	btn.Text             = text or ""
	btn.TextColor3       = C.TEXT
	btn.TextSize         = 12
	btn.Font             = Enum.Font.Gotham
	btn.TextXAlignment   = Enum.TextXAlignment.Left
	btn.TextTruncate     = Enum.TextTruncate.AtEnd
	btn.BorderSizePixel  = 0
	btn.AutoButtonColor  = false
	Corner(btn, 8)
	btn.Parent = parent
	return btn
end

-- ── Main frame ───────────────────────────────────────────────────────────────

local Main = Instance.new("Frame")
Main.Name            = "Main"
Main.AnchorPoint     = Vector2.new(0.5, 0.5)
Main.Position        = UDim2.new(0.5, 0, 0.5, 0)
Main.Size            = UDim2.new(0.92, 0, 0, 640)  -- extra height for new button
Main.BackgroundColor3 = C.BG
Main.BorderSizePixel = 0
Main.Visible         = false
Main.Active          = true
Main.Parent          = Gui
Corner(Main, 14)

local MainSize = Instance.new("UISizeConstraint")
MainSize.MaxSize = Vector2.new(500, 10000)
MainSize.Parent  = Main

-- ── Title bar ────────────────────────────────────────────────────────────────

local TitleBar = Instance.new("Frame")
TitleBar.Size             = UDim2.new(1, 0, 0, 46)
TitleBar.BackgroundColor3 = C.PANEL
TitleBar.BorderSizePixel  = 0
TitleBar.Parent           = Main
Corner(TitleBar, 14)

-- Mask the bottom rounding of the title bar
local TitleMask = Instance.new("Frame")
TitleMask.Size             = UDim2.new(1, 0, 0.45, 0)
TitleMask.Position         = UDim2.new(0, 0, 0.55, 0)
TitleMask.BackgroundColor3 = C.PANEL
TitleMask.BorderSizePixel  = 0
TitleMask.Parent           = TitleBar

local Title = Instance.new("TextLabel")
Title.Size               = UDim2.new(1, -140, 1, 0)
Title.Position           = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Text               = "🚨  Report Composer v4.1"
Title.TextColor3         = C.BAD
Title.TextSize           = 16
Title.Font               = Enum.Font.GothamBold
Title.TextXAlignment     = Enum.TextXAlignment.Left
Title.Parent             = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size             = UDim2.new(0, 30, 0, 30)
CloseBtn.Position         = UDim2.new(1, -38, 0.5, -15)
CloseBtn.BackgroundColor3 = C.BAD
CloseBtn.Text             = "✕"
CloseBtn.TextColor3       = C.TEXT
CloseBtn.TextSize         = 13
CloseBtn.Font             = Enum.Font.GothamBold
CloseBtn.BorderSizePixel  = 0
CloseBtn.AutoButtonColor  = false
CloseBtn.Parent           = TitleBar
Corner(CloseBtn, 8)

-- ── Scrollable body ───────────────────────────────────────────────────────────

local Body = Instance.new("ScrollingFrame")
Body.Size                 = UDim2.new(1, 0, 1, -46)
Body.Position             = UDim2.new(0, 0, 0, 46)
Body.BackgroundTransparency = 1
Body.BorderSizePixel      = 0
Body.ScrollBarThickness   = 4
Body.ScrollBarImageColor3 = Color3.fromRGB(90, 92, 115)
Body.AutomaticCanvasSize  = Enum.AutomaticSize.Y
Body.CanvasSize           = UDim2.new(0, 0, 0, 0)
Body.Parent               = Main
Pad(Body, 12)

local BodyLayout = Instance.new("UIListLayout")
BodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
BodyLayout.Padding   = UDim.new(0, 10)
BodyLayout.Parent    = Body

-- Section wrapper factory
local function Section(title, order)
	local wrapper = Instance.new("Frame")
	wrapper.Name                 = title
	wrapper.LayoutOrder          = order
	wrapper.BackgroundTransparency = 1
	wrapper.AutomaticSize        = Enum.AutomaticSize.Y
	wrapper.Size                 = UDim2.new(1, 0, 0, 0)
	wrapper.Parent               = Body

	local inner = Instance.new("UIListLayout")
	inner.SortOrder = Enum.SortOrder.LayoutOrder
	inner.Padding   = UDim.new(0, 6)
	inner.Parent    = wrapper

	local lbl = MakeLabel(wrapper, title, 11, C.MUTED)
	lbl.LayoutOrder = 0
	return wrapper
end

-- ╔══════════════════════════════════════╗
-- ║        STEP 1 — PLAYER SELECT       ║
-- ╚══════════════════════════════════════╝

local Step1 = Section("① SELECT PLAYER", 1)

local PlayerPanel = Instance.new("ScrollingFrame")
PlayerPanel.LayoutOrder          = 1
PlayerPanel.Size                 = UDim2.new(1, 0, 0, 130)
PlayerPanel.BackgroundColor3     = C.PANEL
PlayerPanel.BorderSizePixel      = 0
PlayerPanel.ScrollBarThickness   = 4
PlayerPanel.ScrollBarImageColor3 = Color3.fromRGB(90, 92, 115)
PlayerPanel.AutomaticCanvasSize  = Enum.AutomaticSize.Y
PlayerPanel.CanvasSize           = UDim2.new(0, 0, 0, 0)
PlayerPanel.Parent               = Step1
Corner(PlayerPanel, 10)
Pad(PlayerPanel, 6)

local PlayerLayout = Instance.new("UIListLayout")
PlayerLayout.SortOrder = Enum.SortOrder.LayoutOrder
PlayerLayout.Padding   = UDim.new(0, 5)
PlayerLayout.Parent    = PlayerPanel

-- ╔══════════════════════════════════════╗
-- ║    STEP 2 — TONE + CATEGORY         ║
-- ╚══════════════════════════════════════╝

local Step2 = Section("② SELECT TONE + CATEGORY", 2)

local ControlRow = Instance.new("Frame")
ControlRow.LayoutOrder          = 1
ControlRow.BackgroundTransparency = 1
ControlRow.Size                 = UDim2.new(1, 0, 0, 72)
ControlRow.Parent               = Step2

local ControlLayout = Instance.new("UIListLayout")
ControlLayout.FillDirection = Enum.FillDirection.Horizontal
ControlLayout.SortOrder     = Enum.SortOrder.LayoutOrder
ControlLayout.Padding       = UDim.new(0, 6)
ControlLayout.Parent        = ControlRow

local TonePanel = Instance.new("Frame")
TonePanel.LayoutOrder          = 1
TonePanel.Size                 = UDim2.new(0.5, -3, 1, 0)
TonePanel.BackgroundColor3     = C.PANEL
TonePanel.BorderSizePixel      = 0
TonePanel.Parent               = ControlRow
Corner(TonePanel, 10)
Pad(TonePanel, 6)

local ToneLayout = Instance.new("UIListLayout")
ToneLayout.SortOrder = Enum.SortOrder.LayoutOrder
ToneLayout.Padding   = UDim.new(0, 4)
ToneLayout.Parent    = TonePanel

local CategorySummary = Instance.new("Frame")
CategorySummary.LayoutOrder      = 2
CategorySummary.Size             = UDim2.new(0.5, -3, 1, 0)
CategorySummary.BackgroundColor3 = C.PANEL
CategorySummary.BorderSizePixel  = 0
CategorySummary.Parent           = ControlRow
Corner(CategorySummary, 10)
Pad(CategorySummary, 6)

local CategorySummaryLayout = Instance.new("UIListLayout")
CategorySummaryLayout.SortOrder = Enum.SortOrder.LayoutOrder
CategorySummaryLayout.Padding   = UDim.new(0, 4)
CategorySummaryLayout.Parent    = CategorySummary

local ToneLabel     = MakeLabel(TonePanel,        "Tone preset",   11, C.MUTED)
ToneLabel.LayoutOrder = 1

local CategoryLabel = MakeLabel(CategorySummary,  "Template mode", 11, C.MUTED)
CategoryLabel.LayoutOrder = 1

local ToneBtn = MakeButton(TonePanel, "  Tone: Formal", 30, C.ITEM)
ToneBtn.LayoutOrder = 2

local RandomBtn = MakeButton(TonePanel, "  Randomize wording: Off", 30, C.ITEM)
RandomBtn.LayoutOrder = 3

local ForceRefreshBtn = MakeButton(CategorySummary, "  ⟳ Force Refresh", 30, C.ACCENT)
ForceRefreshBtn.LayoutOrder = 2

local ClearBtn = MakeButton(CategorySummary, "  ↺ Clear Draft", 30, C.ITEM)
ClearBtn.LayoutOrder = 3

local CategoryPanel = Instance.new("ScrollingFrame")
CategoryPanel.LayoutOrder          = 2
CategoryPanel.Size                 = UDim2.new(1, 0, 0, 170)
CategoryPanel.BackgroundColor3     = C.PANEL
CategoryPanel.BorderSizePixel      = 0
CategoryPanel.ScrollBarThickness   = 4
CategoryPanel.ScrollBarImageColor3 = Color3.fromRGB(90, 92, 115)
CategoryPanel.AutomaticCanvasSize  = Enum.AutomaticSize.Y
CategoryPanel.CanvasSize           = UDim2.new(0, 0, 0, 0)
CategoryPanel.Parent               = Step2
Corner(CategoryPanel, 10)
Pad(CategoryPanel, 6)

local CategoryLayout = Instance.new("UIListLayout")
CategoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
CategoryLayout.Padding   = UDim.new(0, 5)
CategoryLayout.Parent    = CategoryPanel

-- ╔══════════════════════════════════════╗
-- ║    STEP 3 — NOTES + PREVIEW         ║
-- ╚══════════════════════════════════════╝

local Step3 = Section("③ ADD NOTES + PREVIEW", 3)

local NotesBox = Instance.new("TextBox")
NotesBox.LayoutOrder      = 1
NotesBox.Size             = UDim2.new(1, 0, 0, 70)
NotesBox.BackgroundColor3 = C.PANEL
NotesBox.BorderSizePixel  = 0
NotesBox.TextColor3       = C.TEXT
NotesBox.TextSize         = 12
NotesBox.Font             = Enum.Font.Gotham
NotesBox.TextWrapped      = true
NotesBox.MultiLine        = true
NotesBox.ClearTextOnFocus = false
NotesBox.PlaceholderText  = "Optional note / evidence / context for the next instance..."
NotesBox.PlaceholderColor3 = C.MUTED
NotesBox.TextXAlignment   = Enum.TextXAlignment.Left
NotesBox.TextYAlignment   = Enum.TextYAlignment.Top
NotesBox.Parent           = Step3
Corner(NotesBox, 10)
Pad(NotesBox, 8)

local PreviewBox = Instance.new("TextBox")
PreviewBox.LayoutOrder      = 2
PreviewBox.Size             = UDim2.new(1, 0, 0, 120)
PreviewBox.BackgroundColor3 = C.PANEL
PreviewBox.BorderSizePixel  = 0
PreviewBox.TextColor3       = Color3.fromRGB(201, 255, 210)
PreviewBox.TextSize         = 11
PreviewBox.Font             = Enum.Font.Gotham
PreviewBox.TextWrapped      = true
PreviewBox.MultiLine        = true
PreviewBox.ClearTextOnFocus = false
PreviewBox.TextEditable     = false
PreviewBox.Selectable       = true
PreviewBox.TextXAlignment   = Enum.TextXAlignment.Left
PreviewBox.TextYAlignment   = Enum.TextYAlignment.Top
PreviewBox.Text             = "Select a player, choose a tone, pick a category, then add one or more violation instances."
PreviewBox.Parent           = Step3
Corner(PreviewBox, 10)
Pad(PreviewBox, 8)

-- LayoutOrder 3 → Copy
local CopyBtn = Instance.new("TextButton")
CopyBtn.LayoutOrder       = 3
CopyBtn.Size              = UDim2.new(1, 0, 0, 38)
CopyBtn.BackgroundColor3  = C.GOOD
CopyBtn.Text              = "📋  Copy Combined Report"
CopyBtn.TextColor3        = C.TEXT
CopyBtn.TextSize          = 13
CopyBtn.Font              = Enum.Font.GothamBold
CopyBtn.BorderSizePixel   = 0
CopyBtn.AutoButtonColor   = false
CopyBtn.Parent            = Step3
Corner(CopyBtn, 10)

-- LayoutOrder 4 → Submit  (NEW)
local SubmitBtn = Instance.new("TextButton")
SubmitBtn.LayoutOrder      = 4
SubmitBtn.Size             = UDim2.new(1, 0, 0, 38)
SubmitBtn.BackgroundColor3 = C.BAD
SubmitBtn.Text             = "🚨  Submit Report to Roblox"
SubmitBtn.TextColor3       = C.TEXT
SubmitBtn.TextSize         = 13
SubmitBtn.Font             = Enum.Font.GothamBold
SubmitBtn.BorderSizePixel  = 0
SubmitBtn.AutoButtonColor  = false
SubmitBtn.Parent           = Step3
Corner(SubmitBtn, 10)

-- LayoutOrder 5 → Add instance
local AddBtn = Instance.new("TextButton")
AddBtn.LayoutOrder       = 5
AddBtn.Size              = UDim2.new(1, 0, 0, 38)
AddBtn.BackgroundColor3  = C.ACCENT
AddBtn.Text              = "➕  Add Violation Instance"
AddBtn.TextColor3        = C.TEXT
AddBtn.TextSize          = 13
AddBtn.Font              = Enum.Font.GothamBold
AddBtn.BorderSizePixel   = 0
AddBtn.AutoButtonColor   = false
AddBtn.Parent            = Step3
Corner(AddBtn, 10)

-- LayoutOrder 6 → Status
local StatusLabel = Instance.new("TextLabel")
StatusLabel.LayoutOrder          = 6
StatusLabel.Size                 = UDim2.new(1, 0, 0, 0)
StatusLabel.AutomaticSize        = Enum.AutomaticSize.Y
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text                 = "Ready."
StatusLabel.TextColor3           = C.SUB
StatusLabel.TextSize             = 10
StatusLabel.Font                 = Enum.Font.Gotham
StatusLabel.TextWrapped          = true
StatusLabel.TextXAlignment       = Enum.TextXAlignment.Left
StatusLabel.Parent               = Step3

-- LayoutOrder 7 → Clipboard fallback hint
local ClipboardHint = Instance.new("TextLabel")
ClipboardHint.LayoutOrder          = 7
ClipboardHint.Size                 = UDim2.new(1, 0, 0, 0)
ClipboardHint.AutomaticSize        = Enum.AutomaticSize.Y
ClipboardHint.BackgroundTransparency = 1
ClipboardHint.Text                 = "⚠️  Clipboard unavailable here — select the preview text and copy it manually."
ClipboardHint.TextColor3           = C.WARN
ClipboardHint.TextSize             = 10
ClipboardHint.Font                 = Enum.Font.Gotham
ClipboardHint.TextWrapped          = true
ClipboardHint.TextXAlignment       = Enum.TextXAlignment.Left
ClipboardHint.Visible              = false
ClipboardHint.Parent               = Step3

-- ╔══════════════════════════════════════╗
-- ║              STATE                  ║
-- ╚══════════════════════════════════════╝

local State = {
	Player    = nil,
	Category  = nil,
	ToneIndex = 1,
	Randomize = false,
	Entries   = {},
}

local playerButtons  = {}
local categoryButtons = {}

-- ╔══════════════════════════════════════╗
-- ║              LOGIC                  ║
-- ╚══════════════════════════════════════╝

local function SetStatus(text, color)
	StatusLabel.Text       = text
	StatusLabel.TextColor3 = color or C.SUB
end

local function CurrentTone()
	return ToneModes[State.ToneIndex]
end

local function RefreshToneControls()
	ToneBtn.Text   = ("  Tone: %s"):format(CurrentTone())
	RandomBtn.Text = ("  Randomize wording: %s"):format(State.Randomize and "On" or "Off")
end

local function RefreshPlayerButtons()
	for name, button in pairs(playerButtons) do
		local selected           = State.Player and State.Player.Name == name
		button.BackgroundColor3  = selected and C.BAD or C.ITEM
	end
end

local function RefreshCategoryButtons()
	for idx, button in ipairs(categoryButtons) do
		local selected           = State.Category == idx
		button.BackgroundColor3  = selected and C.ACCENT_2 or C.ITEM
	end
end

local function BuildEntryText(categoryIndex, playerName, note, toneName)
	local category = Templates[categoryIndex]
	if not category then return nil end

	local tonePool = category.variants[toneName] or category.variants.Neutral
	local draft    = Pick(tonePool):format(playerName)
	local cleaned  = FormatNote(note)
	if cleaned then
		draft = draft .. "\nNote: " .. cleaned
	end
	return draft
end

local function BuildReportText()
	if not State.Player or #State.Entries == 0 then return nil end

	local lines = {}
	table.insert(lines, ("Report target: %s (@%s)"):format(
		State.Player.DisplayName, State.Player.Name))
	table.insert(lines, ("Prepared: %s"):format(os.date("%Y-%m-%d %H:%M:%S")))
	table.insert(lines, ("Instances: %d"):format(#State.Entries))
	table.insert(lines, ("Tone mode: %s%s"):format(
		CurrentTone(), State.Randomize and " (randomized per instance)" or ""))
	table.insert(lines, "")

	for i, entry in ipairs(State.Entries) do
		local cat = Templates[entry.Category]
		table.insert(lines, ("%d) %s"):format(i, cat and cat.name or "Unknown category"))
		table.insert(lines, ("Tone used: %s"):format(entry.Tone))
		table.insert(lines, entry.Text or "")
		if entry.Note and entry.Note ~= "" then
			table.insert(lines, ("Note: %s"):format(entry.Note))
		end
		if i < #State.Entries then
			table.insert(lines, "")
		end
	end

	return table.concat(lines, "\n")
end

local UpdatePreview  -- forward declaration

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

local function AddEntry()
	if not State.Player then
		SetStatus("Pick a player first.", C.WARN)
		return
	end
	if not State.Category then
		SetStatus("Pick a category first.", C.WARN)
		return
	end

	local chosenTone = State.Randomize and Pick(ToneModes) or CurrentTone()
	local note       = FormatNote(NotesBox.Text)
	local text       = BuildEntryText(State.Category, State.Player.Name, note, chosenTone)
	if not text then
		SetStatus("Unable to build draft text.", C.WARN)
		return
	end

	table.insert(State.Entries, {
		Category = State.Category,
		Tone     = chosenTone,
		Text     = text,
		Note     = note,
		Time     = os.time(),
	})

	NotesBox.Text        = ""
	ClipboardHint.Visible = false
	UpdatePreview()
	SetStatus(("Added instance #%d for %s."):format(
		#State.Entries, State.Player.DisplayName), C.GOOD)
end

local function ClearDraft(keepPlayer)
	if not keepPlayer then State.Player = nil end
	State.Category = nil
	State.Entries  = {}
	NotesBox.Text  = ""
	ClipboardHint.Visible = false
	RefreshPlayerButtons()
	RefreshCategoryButtons()
	UpdatePreview()
	SetStatus("Draft cleared.", C.SUB)
end

-- Defined after forward declaration
UpdatePreview = function()
	local text = BuildReportText()
	if text then
		PreviewBox.Text = text
	elseif not State.Player then
		PreviewBox.Text = "Select a player, choose a tone, pick a category, then add one or more violation instances."
		SetStatus("Choose a player to begin.", C.SUB)
	elseif not State.Category then
		PreviewBox.Text = "Choose a category, then add an instance. You can stack multiple instances for the same player."
		SetStatus(("Choose a category for %s."):format(State.Player.DisplayName), C.SUB)
	else
		PreviewBox.Text = "Player and category selected — press ➕ Add Violation Instance to build your report."
		SetStatus(("Ready to add an instance for %s."):format(State.Player.DisplayName), C.SUB)
	end

	if State.Player and #State.Entries > 0 then
		SetStatus(("Collected %d instance%s for %s."):format(
			#State.Entries,
			#State.Entries == 1 and "" or "s",
			State.Player.DisplayName), C.GOOD)
	end

	RefreshToneControls()
end

-- ── Player button builder ─────────────────────────────────────────────────────

local function BuildPlayerButton(player)
	if player == LocalPlayer then return end
	if playerButtons[player.Name] then return end  -- dedup guard

	local btn = MakeButton(
		PlayerPanel,
		"  " .. player.DisplayName .. "  (@" .. player.Name .. ")",
		30,
		C.ITEM
	)
	playerButtons[player.Name] = btn

	btn.MouseButton1Click:Connect(function() SelectPlayer(player) end)
	btn.MouseEnter:Connect(function()
		if not (State.Player and State.Player.Name == player.Name) then
			btn.BackgroundColor3 = C.ITEM_H
		end
	end)
	btn.MouseLeave:Connect(function()
		if not (State.Player and State.Player.Name == player.Name) then
			btn.BackgroundColor3 = C.ITEM
		end
	end)
end

local function RebuildPlayerButtons()
	for _, child in ipairs(PlayerPanel:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	table.clear(playerButtons)
	for _, p in ipairs(Players:GetPlayers()) do
		BuildPlayerButton(p)
	end
	RefreshPlayerButtons()
end

-- ── Category button builder ───────────────────────────────────────────────────

local function RebuildCategoryButtons()
	for _, child in ipairs(CategoryPanel:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	table.clear(categoryButtons)

	for i, category in ipairs(Templates) do
		local btn = MakeButton(CategoryPanel, "  " .. category.name, 30, C.ITEM)
		btn.LayoutOrder = i
		categoryButtons[i] = btn

		btn.MouseButton1Click:Connect(function() SelectCategory(i) end)
		btn.MouseEnter:Connect(function()
			if State.Category ~= i then btn.BackgroundColor3 = C.ITEM_H end
		end)
		btn.MouseLeave:Connect(function()
			if State.Category ~= i then btn.BackgroundColor3 = C.ITEM end
		end)
	end
	RefreshCategoryButtons()
end

-- ── Force refresh ─────────────────────────────────────────────────────────────

local function ForceRefresh()
	SetStatus("Force refreshing UI...", C.WARN)
	RebuildPlayerButtons()
	RebuildCategoryButtons()

	if State.Player then
		local stillValid = false
		for _, p in ipairs(Players:GetPlayers()) do
			if p == State.Player then stillValid = true break end
		end
		if not stillValid then
			State.Player   = nil
			State.Category = nil
			State.Entries  = {}
		end
	end

	UpdatePreview()
	SetStatus("Force refresh complete.", C.GOOD)
end

-- ╔══════════════════════════════════════╗
-- ║              WIRING                 ║
-- ╚══════════════════════════════════════╝

CloseBtn.MouseButton1Click:Connect(function()
	Main.Visible = false
end)

ToneBtn.MouseButton1Click:Connect(function()
	State.ToneIndex = (State.ToneIndex % #ToneModes) + 1
	RefreshToneControls()
	UpdatePreview()
end)

RandomBtn.MouseButton1Click:Connect(function()
	State.Randomize = not State.Randomize
	RefreshToneControls()
	UpdatePreview()
end)

ForceRefreshBtn.MouseButton1Click:Connect(ForceRefresh)

ClearBtn.MouseButton1Click:Connect(function()
	ClearDraft(false)
end)

AddBtn.MouseButton1Click:Connect(AddEntry)

-- ── Copy button ───────────────────────────────────────────────────────────────

CopyBtn.MouseButton1Click:Connect(function()
	local report = BuildReportText()
	if not report then
		SetStatus("Add at least one violation instance first.", C.WARN)
		return
	end

	local ok = SafeCopy(report)
	if ok then
		ClipboardHint.Visible    = false
		CopyBtn.Text             = "✅  Copied!"
		CopyBtn.BackgroundColor3 = C.GOOD_D
		SetStatus("Copied the combined report to clipboard.", C.GOOD)
		task.delay(1.8, function()
			if CopyBtn.Parent then
				CopyBtn.Text             = "📋  Copy Combined Report"
				CopyBtn.BackgroundColor3 = C.GOOD
			end
		end)
	else
		ClipboardHint.Visible = true
		SetStatus("Clipboard unavailable — select the preview text and copy it manually.", C.WARN)
		PreviewBox:CaptureFocus()
		PreviewBox.SelectionStart = 1
		PreviewBox.CursorPosition = #PreviewBox.Text + 1
	end
end)

-- ── Submit button (NEW) ───────────────────────────────────────────────────────

SubmitBtn.MouseButton1Click:Connect(function()
	-- Guard: player selected?
	if not State.Player then
		SetStatus("No player selected.", C.WARN)
		return
	end

	-- Guard: at least one entry?
	if #State.Entries == 0 then
		SetStatus("Add at least one violation instance before submitting.", C.WARN)
		return
	end

	-- Re-resolve the live Player object in case the ref has gone stale.
	local livePlayer = Players:FindFirstChild(State.Player.Name)
	if not livePlayer then
		SetStatus("⚠️  That player is no longer in this server.", C.WARN)
		return
	end

	local report       = BuildReportText() or ""
	local categoryName = (Templates[State.Category] and Templates[State.Category].name)
	                     or "Policy Violation"

	-- Warn the user if the report will be trimmed before we send it.
	if #report > REPORT_CHAR_LIMIT then
		SetStatus(("Report trimmed %d → %d chars to fit Roblox's limit."):format(
			#report, REPORT_CHAR_LIMIT), C.WARN)
		task.wait(1.2)
	end

	local ok, err = SafeSubmit(livePlayer, categoryName, report)

	if ok then
		SubmitBtn.Text             = "✅  Submitted!"
		SubmitBtn.BackgroundColor3 = C.GOOD_D
		SetStatus(("Report submitted for %s. You can now clear the draft."):format(
			livePlayer.DisplayName), C.GOOD)

		task.delay(3, function()
			if SubmitBtn and SubmitBtn.Parent then
				SubmitBtn.Text             = "🚨  Submit Report to Roblox"
				SubmitBtn.BackgroundColor3 = C.BAD
			end
		end)
	else
		-- Graceful fallback: surface the report for manual copy.
		SubmitBtn.BackgroundColor3 = C.WARN
		ClipboardHint.Visible      = true
		SetStatus(("Submit failed (%s). Use 📋 Copy instead."):format(
			err or "unknown error"), C.WARN)

		task.delay(3, function()
			if SubmitBtn and SubmitBtn.Parent then
				SubmitBtn.BackgroundColor3 = C.BAD
			end
		end)
	end
end)

-- ╔══════════════════════════════════════╗
-- ║       PLAYER JOIN / LEAVE           ║
-- ╚══════════════════════════════════════╝

for _, p in ipairs(Players:GetPlayers()) do
	BuildPlayerButton(p)
end
RebuildCategoryButtons()

Players.PlayerAdded:Connect(BuildPlayerButton)

Players.PlayerRemoving:Connect(function(player)
	local btn = playerButtons[player.Name]
	if btn then
		btn:Destroy()
		playerButtons[player.Name] = nil
	end
	-- If the reported player leaves, clear the draft so state stays consistent.
	if State.Player == player then
		ClearDraft(false)
		SetStatus("⚠️  The selected player left the server. Draft cleared.", C.WARN)
	end
end)

-- ╔══════════════════════════════════════╗
-- ║        TOGGLE BUTTON                ║
-- ╚══════════════════════════════════════╝

local Toggle = Instance.new("TextButton")
Toggle.Name             = "Toggle"
Toggle.Size             = UDim2.new(0, 160, 0, 38)
Toggle.Position         = UDim2.new(0, 12, 1, -50)
Toggle.BackgroundColor3 = C.BAD
Toggle.Text             = "🚨  Report Composer"
Toggle.TextColor3       = C.TEXT
Toggle.TextSize         = 12
Toggle.Font             = Enum.Font.GothamBold
Toggle.BorderSizePixel  = 0
Toggle.AutoButtonColor  = false
Toggle.Parent           = Gui
Corner(Toggle, 10)

Toggle.MouseEnter:Connect(function()  Toggle.BackgroundColor3 = C.ITEM_H end)
Toggle.MouseLeave:Connect(function()  Toggle.BackgroundColor3 = C.BAD    end)

Toggle.MouseButton1Click:Connect(function()
	Main.Visible = not Main.Visible
	if Main.Visible then UpdatePreview() end
end)

-- ╔══════════════════════════════════════╗
-- ║     RESPONSIVE RESIZE HANDLER       ║
-- ╚══════════════════════════════════════╝

local function Resize()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local vp = camera.ViewportSize
	-- Small screens (< 520 px wide) get a slightly wider, taller frame.
	Main.Size = (vp.X < 520)
		and UDim2.new(0.96, 0, 0, 660)
		or  UDim2.new(0.92, 0, 0, 640)
end

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(Resize)
end

-- ── Initialise ────────────────────────────────────────────────────────────────
Resize()
RefreshToneControls()
UpdatePreview()
