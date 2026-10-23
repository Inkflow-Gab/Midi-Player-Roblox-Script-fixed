-- Config
-- Central configuration for the MidiPlayer.
--
-- Folders are scanned in the order they appear. Every `.mid`/`.midi` file
-- (including files inside subfolders) shows up in the sidebar.
--
-- You can override the folders without editing this file by placing this at
-- the top of your main script:
--
--     getgenv().MidiPlayerConfig = {
--         Folders = { "/storage/emulated/0/MyMidis", "midi" },
--
--         -- Window header text (nil = "MIDI - IMPROVISED BY GAB")
--         Title = "MIDI - IMPROVISED BY GAB",
--
--         Options = {
--             -- Set a number to throttle playback on weak phones, e.g. 25.
--             -- nil = unlimited notes per second.
--             MaxNotesPerSecond = nil,
--
--             -- Default mobile layout already scales the window; true skips it.
--             DisableMobileScale = false,
--         },
--     }
--

local Config = {}

-- Exact text shown on the player window header
local DEFAULT_TITLE = "MIDI - IMPROVISED BY GAB"

-- Default search locations, in priority order:
local DEFAULT_FOLDERS = {
    -- Android executor (Delta) MIDI workspace:
    "/storage/emulated/0/Delta/Workspace/MIDI",
    -- Classic relative fallback used by the original script:
    "midi",
}

-- Depth-limit for walking subfolders (0 = only the folder itself)
local MAX_SCAN_DEPTH = 3

local Extensions = {
    [".mid"] = true,
    [".midi"] = true,
}


local function getOverrides()
    local ok, overrides = pcall(function()
        return getgenv().MidiPlayerConfig
    end)
    if (ok and type(overrides) == "table") then
        return overrides
    end
    return {}
end

local function trimPath(path)
    return (path:gsub("[/\\]+$", ""))
end

local function folderExists(path)
    local ok, result = pcall(isfolder, path)
    return ok and result == true
end


--[[
    Config:GetTitle() -> string

    The branding text drawn at the top of the player window.
    Override with getgenv().MidiPlayerConfig.Title = "Your text here".
]]
function Config:GetTitle()
    local overrides = getOverrides()
    if (type(overrides.Title) == "string" and overrides.Title ~= "") then
        return overrides.Title
    end
    return DEFAULT_TITLE
end


--[[
    Config:GetMaxNotesPerSecond() -> number | nil

    Optional playback throttle. When set (via
    getgenv().MidiPlayerConfig.Options.MaxNotesPerSecond), Input will
    postpone presses that arrive beyond this many notes in a rolling
    one-second window, which protects weaker phones on very dense MIDIs.
    Nil (the default) means unlimited.
]]
function Config:GetMaxNotesPerSecond()
    local overrides = getOverrides()
    local options = overrides.Options
    if (type(options) == "table") then
        local cap = tonumber(options.MaxNotesPerSecond)
        if (cap and cap > 0) then
            return cap
        end
    end
    return nil
end


--[[
    Config:FindFile(title) -> path | nil

    Returns the full path of the first `.mid`/`.midi` file whose *name*
    (without extension) matches `title`, searched in all configured folders.
]]
function Config:FindFile(title)
    local target = tostring(title):lower()

    for _,filePath in ipairs(self:GetMidiFiles()) do
        local fullname = filePath:match("[^/\\]+$") or ""
        local name = fullname:match("^([^%.]+)") or ""
        if (name:lower() == target) then
            return filePath
        end
    end

    return nil
end

--[[
    Config:GetFolders() -> { path, ... }

    Returns the list of configured folders that actually exist on this
    device. Absolute Android paths and relative executor paths both work.
    Always returns at least one folder ("midi" as last resort).
]]
function Config:GetFolders()
    local overrides = getOverrides()

    local list = overrides.Folders
    if (type(list) == "string") then
        list = { list }
    end
    if (type(list) ~= "table" or #list == 0) then
        list = DEFAULT_FOLDERS
    end

    local folders = {}
    local seen = {}

    local function add(path)
        if (type(path) ~= "string" or path == "") then
            return
        end
        path = trimPath(path)
        if (path ~= "" and not seen[path]) then
            seen[path] = true
            table.insert(folders, path)
        end
    end

    local anyExists = false
    for _,path in ipairs(list) do
        if (type(path) == "string" and folderExists(path)) then
            add(path)
            anyExists = true
        end
    end

    -- Fall back to the classic "midi" folder when nothing else exists
    if (not anyExists) then
        add(DEFAULT_FOLDERS[#DEFAULT_FOLDERS])
    end

    return folders
end


--[[
    Config:GetMidiFiles() -> { filePath, ... }

    Lists every MIDI file in every configured folder (subfolders included),
    deduplicated and free of missing files.
]]
function Config:GetMidiFiles()
    local files = {}
    local seen = {}

    local function accept(entry)
        if (seen[entry]) then
            return
        end
        local lower = entry:lower()
        local extension = lower:match("(%.[^%.]+)$")
        if (Extensions[extension]) then
            seen[entry] = true
            table.insert(files, entry)
        end
    end

    local function walk(directory, depth)
        local ok, entries = pcall(listfiles, directory)
        if (not ok or type(entries) ~= "table") then
            return
        end
        for _,entry in ipairs(entries) do
            if (folderExists(entry) and depth < MAX_SCAN_DEPTH) then
                walk(entry, depth + 1)
            else
                accept(entry)
            end
        end
    end

    for _,folder in ipairs(self:GetFolders()) do
        if (folderExists(folder)) then
            walk(folder, 0)
        end
    end

    return files
end


--[[
    Config:EnsureFolders()

    Creates missing configured folders where possible. With default settings
    this only ensures the relative "midi" fallback folder exists (absolute
    Android paths must not be created as relative junk on other platforms).
    Overridden folders are considered intentional, so missing ones are made.
]]
function Config:EnsureFolders()
    local overrides = getOverrides()

    if (overrides.Folders ~= nil) then
        local list = overrides.Folders
        if (type(list) == "string") then
            list = { list }
        end
        if (type(list) == "table") then
            for _,path in ipairs(list) do
                if (type(path) == "string" and path ~= "" and not folderExists(path)) then
                    pcall(makefolder, trimPath(path))
                end
            end
        end
        return
    end

    if (not folderExists("midi")) then
        pcall(makefolder, "midi")
    end
end


return Config
