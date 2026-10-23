-- Extras
-- Runtime additions layered on top of the base MIDI player GUI:
--   * "MIDI - IMPROVISED BY GAB" branding on the window header
--   * minimize button + floating restore bubble
--   * previous / next song buttons
--   * AUTO / SHUFFLE / REPEAT playlist row above the search box
--   * automatic chaining to the next song via Song.Ended
--
-- Time formatting lives in Controller (elapsed / total), the optional
-- notes-per-second throttle lives in Input (configured through Config).
--
-- Everything is built programmatically positioned relative to existing
-- siblings, so it stays glued to the binary GUI at any window size.


local midiPlayer = script:FindFirstAncestor("MidiPlayer")
local Click = require(midiPlayer.Util.Click)
local Config = require(midiPlayer.Config)

local Controller = require(midiPlayer.Components.Controller)
local Sidebar = require(midiPlayer.Components.Sidebar)
local Song = require(midiPlayer.Song)

local Extras = {}

-- Theme sampled from the binary ScreenGui
local PANEL = Color3.fromRGB(42, 42, 42)      -- window / controller cards
local DARKER = Color3.fromRGB(16, 16, 16)     -- sidebar / search background
local ACCENT = Color3.fromRGB(37, 171, 254)   -- selection blue
local DIM = Color3.fromRGB(163, 162, 165)     -- inactive icon gray
local WHITE = Color3.fromRGB(255, 255, 255)

-- Layout constants (design units: the window is 430x354, and mobile mode
-- scales everything uniformly, so offsets stay correct under any UIScale)
local PLAYLIST_ROW_HEIGHT = 30

local gui, frame, main
local restoreButton = nil
local bubbleConnections = nil
local playlistButtons = {}
local Playlist = nil


-- Fonts are copied from an existing label so new UI blends in perfectly
local function matchFont(source)
	local font = Enum.Font.GothamMedium
	local ok = pcall(function()
		if (source and source.Parent) then
			font = source.Font
		end
	end)
	if (not ok) then
		return Enum.Font.GothamMedium
	end
	return font
end


--------------------------------------------------------------------------------
-- Playlist state (shared through getgenv so it survives script re-runs)
--------------------------------------------------------------------------------

local function getPlaylist()
	if (Playlist) then
		return Playlist
	end

	Playlist = {}
	local ok, stored = pcall(function()
		return getgenv().MidiPlayerPlaylist
	end)

	if (ok and type(stored) == "table") then
		Playlist.Auto = (stored.Auto ~= false)      -- on by default
		Playlist.Shuffle = (stored.Shuffle == true)
		Playlist.Repeat = (stored.Repeat == true)
		Playlist.Index = stored.Index
	else
		Playlist.Auto = true
		Playlist.Shuffle = false
		Playlist.Repeat = false
	end

	return Playlist
end

local function savePlaylist()
	pcall(function()
		getgenv().MidiPlayerPlaylist = {
			Auto = Playlist.Auto;
			Shuffle = Playlist.Shuffle;
			Repeat = Playlist.Repeat;
			Index = Playlist.Index;
		}
	end)
end


--------------------------------------------------------------------------------
-- Playlist navigation
--------------------------------------------------------------------------------

local function findCurrentIndex(list)
	local current = Controller.CurrentFile
	if (not current) then
		return nil
	end
	for index,path in ipairs(list) do
		if (path == current) then
			return index
		end
	end
	return nil
end


local function playIndex(index)
	getPlaylist()

	local list = Sidebar:GetOrder()
	local filePath = list[index]
	if (not filePath) then
		return
	end

	Playlist.Index = index
	savePlaylist()

	Controller:Select(filePath)
	if (Controller.CurrentSong) then
		Controller.CurrentSong:Play()
	end
	Controller:Update()
end


-- Next song in the virtual playback order. `step` is -1 or +1; shuffle
-- picks any other song uniformly instead of stepping.
local function nextIndex(step)
	getPlaylist()

	local list = Sidebar:GetOrder()
	local count = #list
	if (count == 0) then
		return nil
	end

	local current = findCurrentIndex(list) or Playlist.Index or 0

	if (Playlist.Shuffle and count > 1) then
		if (current >= 1 and current <= count) then
			local offset = math.random(1, count - 1)
			local index = current + offset
			if (index > count) then
				index -= count
			end
			return index
		end
		return math.random(1, count)
	end

	return ((current - 1 + step) % count) + 1
end


--------------------------------------------------------------------------------
-- 1) Branding label on the window header
--------------------------------------------------------------------------------

local function addBrandLabel()
	if (main:FindFirstChild("Branding")) then
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = "Branding"
	label.BackgroundTransparency = 1
	label.RichText = false
	label.Text = Config:GetTitle()
	label.TextColor3 = DIM
	label.TextTransparency = 0.2
	label.TextSize = 12
	label.Font = matchFont(main.Title)
	label.Size = UDim2.new(0.5, 0, 0, 14)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 10)
	label.ZIndex = 2
	label.Parent = main
end


--------------------------------------------------------------------------------
-- 2) Minimize button + floating restore bubble
--------------------------------------------------------------------------------

local function removeRestoreBubble()
	if (bubbleConnections) then
		for _,connection in ipairs(bubbleConnections) do
			pcall(function() connection:Disconnect() end)
		end
		bubbleConnections = nil
	end
	if (restoreButton) then
		restoreButton:Destroy()
		restoreButton = nil
	end
end


local function showRestoreBubble()
	if (restoreButton) then
		return
	end

	local button = Instance.new("TextButton")
	button.Name = "MidiPlayerRestore"
	button.AutoButtonColor = true
	button.BackgroundColor3 = PANEL
	button.BackgroundTransparency = 0.1
	button.BorderSizePixel = 0
	button.Text = "M"
	button.TextSize = 18
	button.Font = matchFont(main.Title)
	button.TextColor3 = WHITE
	button.Size = UDim2.fromOffset(44, 44)
	button.Position = UDim2.new(0, 24, 1, -24)
	button.AnchorPoint = Vector2.new(0, 1)
	button.ZIndex = 50

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)   -- circle
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = button

	-- Drag anywhere to move the bubble; a tap under ~10px resumes the window
	local dragInput = nil
	local dragStart = nil
	local dragPosition = nil
	local dragMoved = false

	button.InputBegan:Connect(function(input)
		if (Click.isPointer(input)) then
			dragInput = input
			dragStart = input.Position
			dragPosition = button.Position
			dragMoved = false
		end
	end)

	local UserInputService = game:GetService("UserInputService")

	-- Global connections live only while the bubble exists
	local tracked = {}
	bubbleConnections = tracked

	table.insert(tracked, UserInputService.InputChanged:Connect(function(input)
		if (input ~= dragInput) then
			return
		end
		if (Click.isPointer(input) and dragStart and dragPosition) then
			local delta = input.Position - dragStart
			if (delta.Magnitude > 10) then
				dragMoved = true
			end
			button.Position = UDim2.new(
				dragPosition.X.Scale, dragPosition.X.Offset + delta.X,
				dragPosition.Y.Scale, dragPosition.Y.Offset + delta.Y
			)
		end
	end))

	local function finish(input)
		if (input ~= dragInput) then
			return
		end
		dragInput = nil
		if (not dragMoved) then
			frame.Visible = true
			removeRestoreBubble()
		end
	end

	table.insert(tracked, UserInputService.InputEnded:Connect(finish))
	table.insert(tracked, button.InputEnded:Connect(finish))

	button.Parent = gui
	restoreButton = button
end


local function addMinimizeButton()
	if (main:FindFirstChild("Minimize")) then
		return
	end

	local button = Instance.new("TextButton")
	button.Name = "Minimize"
	button.AutoButtonColor = true
	button.BackgroundTransparency = 1
	button.Text = "–"
	button.TextSize = 20
	button.Font = matchFont(main.Title)
	button.TextColor3 = DIM
	button.Size = UDim2.fromOffset(24, 18)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -12, 0, 8)
	button.ZIndex = 3
	button.Parent = main

	Click.bind(button, function()
		frame.Visible = false
		showRestoreBubble()
	end)
end


--------------------------------------------------------------------------------
-- 3) Playback metrics: room for the longer "0:12 / 3:45" time label
--------------------------------------------------------------------------------

local function adjustPlaybackMetrics()
	local controller = frame.Main.Controller

	-- Widen the elapsed/total time label (text centered by alignment)
	local timeLabel = controller.Time
	timeLabel.Size = UDim2.fromOffset(104, 24)

	-- Shift + trim the progress scrubber so it no longer overlaps the label
	local scrubber = controller.Scrubber
	scrubber.Position = UDim2.new(0.36, 0, 0.5, 0)
	scrubber.Size = UDim2.new(0.64, 0, 0, 3)
end


--------------------------------------------------------------------------------
-- 4) Playlist row above the search box
--------------------------------------------------------------------------------

local function refreshPlaylistButtons()
	local playlist = getPlaylist()
	for _,entry in pairs(playlistButtons) do
		if (not entry.Key) then
			continue
		end
		local active = (playlist[entry.Key] == true)
		entry.Button.BackgroundColor3 = active and ACCENT or PANEL
		entry.Button.BackgroundTransparency = active and 0.15 or 0.35
		entry.Button.TextColor3 = active and WHITE or DIM
	end
end


local function bindToggle(entry)
	Click.bind(entry.Button, function()
		local playlist = getPlaylist()
		playlist[entry.Key] = not playlist[entry.Key]
		savePlaylist()
		refreshPlaylistButtons()
	end)
end


local function createPlaylistButton(row, order, name, key, text, width)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundColor3 = PANEL
	button.BackgroundTransparency = 0.35
	button.BorderSizePixel = 0
	button.Text = text
	button.TextSize = 11
	button.Font = matchFont(main.Title)
	button.TextColor3 = DIM
	button.Size = UDim2.fromOffset(width, 22)
	button.LayoutOrder = order

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	local entry = { Key = key, Button = button }
	playlistButtons[name] = entry

	button.Parent = row
	return entry
end


local function bindNavigation(entry, step)
	Click.bind(entry.Button, function()
		local index = nextIndex(step)
		if (index) then
			playIndex(index)
		end
	end)
end


local function buildPlaylistRow()
	local sidebar = frame.Sidebar
	local search = sidebar.Search

	if (sidebar:FindFirstChild("PlaylistRow")) then
		return
	end

	local row = Instance.new("Frame")
	row.Name = "PlaylistRow"
	row.BackgroundColor3 = DARKER
	row.BackgroundTransparency = 0
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, -8, 0, PLAYLIST_ROW_HEIGHT)
	row.AnchorPoint = Vector2.new(0, 1)
	-- Glued to the search box from above (search uses a scale-Y position)
	row.Position = UDim2.new(0, 0, search.Position.Y.Scale, -PLAYLIST_ROW_HEIGHT - 8)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row

	-- Song navigation then playlist toggles
	local prevButton = createPlaylistButton(row, 1, "Prev", nil, "‹", 26)
	local nextButton = createPlaylistButton(row, 2, "Next", nil, "›", 26)
	local auto = createPlaylistButton(row, 3, "Auto", "Auto", "AUTO", 44)
	local shuffle = createPlaylistButton(row, 4, "Shuffle", "Shuffle", "SHFL", 44)
	local repeatToggle = createPlaylistButton(row, 5, "Repeat", "Repeat", "RPT", 40)

	bindNavigation(prevButton, -1)
	bindNavigation(nextButton, 1)
	bindToggle(auto)
	bindToggle(shuffle)
	bindToggle(repeatToggle)

	row.Parent = sidebar
	refreshPlaylistButtons()

	-- Shorten the song list so rows don't hide underneath the new row
	sidebar.Songs.Size = UDim2.new(1, -8, 1, -16 - (PLAYLIST_ROW_HEIGHT + 32))
end


--------------------------------------------------------------------------------
-- 5) Wiring: Song.Ended drives repeat/auto-advance
--------------------------------------------------------------------------------

local function connectPlaylistEvents()
	Song.Ended:Connect(function(song)
		if (Controller.CurrentSong ~= song) then
			return
		end

		local playlist = getPlaylist()

		if (playlist.Repeat) then
			-- Play() restarts automatically from 0 once the song finished
			song:Play()
			Controller:Update()
			return
		end

		if (playlist.Auto) then
			local index = nextIndex(1)
			if (index) then
				playIndex(index)
			end
		end
	end)
end


--------------------------------------------------------------------------------

function Extras:Init(newFrame)
	frame = newFrame
	gui = frame.Parent
	main = frame.Main

	addBrandLabel()
	addMinimizeButton()
	adjustPlaybackMetrics()
	buildPlaylistRow()
	connectPlaylistEvents()
end


return Extras
