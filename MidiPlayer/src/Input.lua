-- Input
-- 0866
-- November 03, 2020
-- (robust key sending + cleanup updates)



local Input = {}

local VirtualInputManager = game:GetService("VirtualInputManager")
local keypress = getfenv(0).keypress
local keyrelease = getfenv(0).keyrelease

local NOTE_MAP = "1!2@34$5%6^78*9(0qQwWeErtTyYuiIoOpPasSdDfgGhHjJklLzZxcCvVbBnm"
local UPPER_MAP = "!@ $%^ *( QWE TY IOP SD GHJ LZ CVB"
local LOWER_MAP = "1234567890qwertyuiopasdfghjklzxcvbnm"

local Thread = require(script.Parent.Util.Thread)
local Maid = require(script.Parent.Util.Maid)
local Config = require(script.Parent.Config)

local inputMaid = Maid.new()

local Words = {
    ["Zero"]="0",
    ["One"]="1",
    ["Two"]="2",
    ["Three"]="3",
    ["Four"]="4",
    ["Five"]="5",
    ["Six"]="6",
    ["Seven"]="7",
    ["Eight"]="8",
    ["Nine"]="9",
}

-- Executor key-function names for keys `SendKeyEvent` can't express
local FALLBACK_NAMES = {
    Shift = "lshift",
    LShift = "lshift",
    LeftShift = "lshift",
    Space = "space",
}

local function CharacterToWord(char)
    local wordfound
    for word, v in pairs(Words) do
        if v == char then
            wordfound = word
        end
    end
    return wordfound or char:upper()
end


--[[
    Sends a keyboard event through VirtualInputManager. If the executor
    doesn't support it, the classic keypress/keyrelease globals (usually
    `keypress`, `keyrelease`) are used as a fallback so playback still
    works on stripped-down mobile executors.
]]
local function SendKeyEvent(isDown, keyCode, fallbackName)
    local sent = false
    pcall(function()
        VirtualInputManager:SendKeyEvent(isDown, keyCode, false, game)
        sent = true
    end)

    if (sent) then
        return
    end

    -- VirtualInputManager unavailable; try executor key functions instead
    local hasFallback = (isDown and keypress ~= nil) or (not isDown and keyrelease ~= nil)
    if (not hasFallback) then
        return
    end

    local name = fallbackName or keyCode.Name
    local raw = FALLBACK_NAMES[name] or name:lower()
    if (isDown) then
        pcall(keypress, raw)
    else
        pcall(keyrelease, raw)
    end
end

local function GetKey(pitch)
    local idx = (pitch + 1 - 36)
    if (idx > #NOTE_MAP or idx < 1) then
        return
    else
        local key = NOTE_MAP:sub(idx, idx)
        return key, UPPER_MAP:find(key, 1, true)
    end
end


function Input.IsUpper(pitch)
    local key, upperMapIdx = GetKey(pitch)
    if (not key) then return end
    return upperMapIdx
end


function Input.Press(pitch)
    local key, upperMapIdx = GetKey(pitch)
    if (not key) then return end
    if (upperMapIdx) then
        local keyToPress = LOWER_MAP:sub(upperMapIdx, upperMapIdx)
        SendKeyEvent(true, Enum.KeyCode.LeftShift, "lshift")
        SendKeyEvent(true, CharacterToWord(keyToPress))
    else
        SendKeyEvent(true, CharacterToWord(key))
    end
end


function Input.Release(pitch)
    local key, upperMapIdx = GetKey(pitch)
    if (not key) then return end
    if (upperMapIdx) then
        local keyToPress = LOWER_MAP:sub(upperMapIdx, upperMapIdx)
        SendKeyEvent(false, Enum.KeyCode.LeftShift, "lshift")
        SendKeyEvent(false, CharacterToWord(keyToPress))
    else
        SendKeyEvent(false, CharacterToWord(key))
    end
end


-- Optional notes-per-second throttle (Config:GetMaxNotesPerSecond, default off).
-- Presses beyond the cap inside a rolling one-second window are postponed by
-- small increments so dense MIDIs don't overload weaker phones.
local RATE_WINDOW = 1
local RATE_STEP = 0.05
local RATE_MAX_DELAY = 0.5
local pressTimestamps = {}

local function bumpRateLimit()
    local cap = Config:GetMaxNotesPerSecond()
    if (not cap) then
        return 0
    end

    local now = os.clock()
    while (#pressTimestamps > 0 and now - pressTimestamps[1] >= RATE_WINDOW) do
        table.remove(pressTimestamps, 1)
    end

    local overflow = #pressTimestamps - cap + 1
    table.insert(pressTimestamps, now)

    if (overflow <= 0) then
        return 0
    end

    return math.min(overflow * RATE_STEP, RATE_MAX_DELAY)
end


function Input.Hold(pitch, duration)
    if getgenv().leftNotePitches[pitch] and not getgenv().LeftHand then return end
    if getgenv().rightNotePitches[pitch] and not getgenv().RightHand then return end
    if (inputMaid[pitch]) then
        inputMaid[pitch] = nil
    end

    local press = function()
        Input.Release(pitch)
        Input.Press(pitch)
        inputMaid[pitch] = Thread.Delay(duration, Input.Release, pitch)
    end

    local delay = bumpRateLimit()
    if (delay > 0) then
        -- Postpone only the press; the pending release timers stay in maid
        Thread.Delay(delay, press)
    else
        press()
    end
end


return Input
