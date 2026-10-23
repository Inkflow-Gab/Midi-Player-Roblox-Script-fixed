-- Main
-- 0866
-- October 31, 2020

local App = require(script.Components.App)
local Config = require(script.Config)

-- Make sure at least one MIDI folder exists (Delta workspace folder first)
Config:EnsureFolders()

App:Init()
