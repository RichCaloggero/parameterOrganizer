-- Smoke test: runs ParameterOrganizer.lua against a fake REAPER, presses a
-- scripted sequence of keys, and prints everything that would be spoken.
-- Then runs it a second time, as a new session with a second instance of
-- the same plugin, to check that the saved layout comes back for both.
-- Layouts are saved under %TEMP%\po_smoke, cleared first.
-- Usage, from the project folder:  lua55.exe tests\smoke_main.lua

local K = {
  UP = 30064, DOWN = 1685026670, LEFT = 1818584692, RIGHT = 1919379572,
  HOME = 6647396, END = 1752132965, PAGE_UP = 1885828464, PAGE_DOWN = 1885824110,
  F2 = 26162, F5 = 26165, F12 = 6697266, ESCAPE = 27, DELETE = 6579564,
  -- As Control+letter arrives:
  CTRL_N = 14, A = 1, F = 6, G = 7, R = 18, V = 22, X = 24,
  SPACE = 32,
}
local CTRL, SHIFT = 4, 8

-- Home and End are swapped by default: End goes up, Home goes down.
local keys = {
  { K.RIGHT }, { K.RIGHT },                -- into Track 1, into Phaser: Rate
  { K.DOWN },                              -- Depth
  { K.PAGE_UP }, { K.PAGE_UP, SHIFT },     -- small, then large step
  { K.PAGE_DOWN, CTRL }, { K.PAGE_UP },    -- minimum, then a small step
  { K.CTRL_N, CTRL }, { K.CTRL_N, CTRL },  -- frequency, then Q, ahead of the parameters
  { K.F2 },                                -- rename Q
  { K.G, CTRL },                           -- sort: Depth before Rate
  { K.F, CTRL },                           -- filter "dep": Depth only
  { K.X, CTRL },                           -- cut Depth
  { K.END }, { K.DOWN },                   -- up a stop to frequency, then Q factor
  { K.RIGHT }, { K.V, CTRL },              -- paste into Q factor: filter clears
  { K.F2 }, { K.F2 },                      -- own name, then back to autolabel
  { K.LEFT },                              -- Q factor
  { K.DELETE }, { K.DELETE },              -- ask, then delete: Depth unplaced again, focus on Rate
  { K.END }, { K.END },                    -- up a stop to the first parameter, then the first item
  { K.HOME }, { K.HOME },                  -- down to the first parameter, then the last
  { K.R, CTRL },                           -- original order: Rate first
  { K.X, CTRL },                           -- cut Rate
  { K.END, CTRL }, { K.RIGHT },            -- first item, frequency; into it
  { K.V, CTRL },                           -- Rate placed in frequency
  { K.LEFT }, { K.V, CTRL },               -- at the effect's level: unplaced again
  { K.X, CTRL }, { K.END }, { K.RIGHT },   -- cut it once more, up to frequency, into it
  { K.V, CTRL },                           -- placed, for session 2
  -- Selection: move Rate and Depth together into a new branch, and on.
  { K.LEFT }, { K.V, CTRL },               -- unplace Rate again: two unplaced now
  { K.A, CTRL }, { K.X, CTRL },            -- select both parameters, cut them
  { K.CTRL_N, CTRL }, { K.RIGHT },         -- new branch "both", into it
  { K.V, CTRL },                           -- 2 pasted into both
  { K.LEFT }, { K.UP, SHIFT },             -- both, then extend up to frequency
  { K.X, CTRL },                           -- refused: branches are selected
  { K.ESCAPE },                            -- clears the selection, doesn't quit
  { K.DOWN }, { K.RIGHT },                 -- both, into it
  { K.SPACE, SHIFT },                      -- select Rate
  { K.DOWN, CTRL }, { K.SPACE, SHIFT },    -- Depth, keeping Rate selected; select Depth
  { K.X, CTRL },                           -- 2 cut
  { K.LEFT }, { K.END, CTRL }, { K.RIGHT }, -- frequency, into it
  { K.V, CTRL },                           -- 2 pasted into frequency, for session 2
  { K.LEFT },
  { K.F12 }, { K.PAGE_DOWN }, { K.ESCAPE }, -- change a setting
  { K.F5 },                                -- refresh keeps the place
  { K.ESCAPE },                            -- quit
}
local answers = { "frequency", "Q", "Q factor", "dep", "Mix depth", "", "both" }

-- Session 2: the second track's Phaser is a new instance of the same plugin.
local keys_session2 = {
  { K.RIGHT }, { K.RIGHT },                -- Phaser, then its saved branch
  { K.RIGHT }, { K.LEFT }, { K.LEFT }, { K.LEFT },
  { K.DOWN },                              -- Track 2
  { K.RIGHT }, { K.RIGHT }, { K.RIGHT },   -- its Phaser has the same branch
  { K.ESCAPE },
}

local resource = (os.getenv("TEMP") or ".") .. "/po_smoke"
os.execute('rmdir /s /q "' .. resource:gsub("/", "\\") .. '" 2>nul')

local tracks = {
  { name = "Vocals", number = 1, guid = "{T1}", fx = {
    { name = "JS: Phaser", guid = "{F1}", params = { "Rate", "Depth" }, values = { 0.2, 0.5 } },
  } },
}
local master = { name = "", number = -1, guid = "{M}", fx = {} }

local clock, key_index, answer_index, next_key_at
local spoken, deferred, extstate = {}, {}, {}

local function param(t, fx, p) return t.fx[fx + 1], p + 1 end

reaper = {
  osara_outputMessage = function(msg) spoken[#spoken + 1] = msg end,
  time_precise = function() clock = clock + 0.1 return clock end,
  defer = function(fn) deferred[#deferred + 1] = fn end,
  atexit = function() end,
  set_action_options = function() end,
  HasExtState = function(_, k) return extstate[k] ~= nil end,
  GetExtState = function(_, k) return extstate[k] or "" end,
  SetExtState = function(_, k, v) extstate[k] = v end,
  GetUserInputs = function()
    answer_index = answer_index + 1
    return true, answers[answer_index] or ""
  end,
  GetMasterTrack = function() return master end,
  CountTracks = function() return #tracks end,
  GetTrack = function(_, i) return tracks[i + 1] end,
  GetTrackGUID = function(t) return t.guid end,
  GetMediaTrackInfo_Value = function(t) return t.number end,
  GetSetMediaTrackInfo_String = function(t) return true, t.name end,
  TrackFX_GetCount = function(t) return #t.fx end,
  TrackFX_GetFXName = function(t, fx) return true, t.fx[fx + 1].name end,
  TrackFX_GetFXGUID = function(t, fx) return t.fx[fx + 1].guid end,
  TrackFX_GetNumParams = function(t, fx) return #t.fx[fx + 1].params end,
  TrackFX_GetParamName = function(t, fx, p) local f, i = param(t, fx, p) return true, f.params[i] end,
  TrackFX_GetNamedConfigParm = function(t, fx, name)
    if name == "fx_ident" then return true, "JS: Phaser plugin file" end
    return false, ""
  end,
  GetResourcePath = function() return resource end,
  RecursiveCreateDirectory = function(path)
    os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
  end,
  GetProjExtState = function() return 0, "" end,
  SetProjExtState = function() end,
  TrackFX_GetParameterStepSizes = function() return false, 0, 0, 0, false end,
  TrackFX_GetParamNormalized = function(t, fx, p) local f, i = param(t, fx, p) return f.values[i] end,
  TrackFX_SetParamNormalized = function(t, fx, p, x) local f, i = param(t, fx, p) f.values[i] = x end,
  TrackFX_FormatParamValueNormalized = function(_, _, _, x) return true, string.format("%d%%", math.floor(x * 100 + 0.5)) end,
  TrackFX_GetFormattedParamValue = function(t, fx, p)
    local f, i = param(t, fx, p)
    return true, string.format("%d%%", math.floor(f.values[i] * 100 + 0.5))
  end,
}

gfx = {
  mouse_cap = 0,
  init = function() end,
  quit = function() end,
  getchar = function(flag)
    if flag == 65536 then return 2 end   -- window state: focused
    -- Each frame takes a little time; let the greeting go first.
    -- Like a person, pause about a second between key presses.
    clock = clock + 0.1
    if clock < next_key_at then return 0 end
    next_key_at = clock + 1
    key_index = key_index + 1
    local key = keys[key_index]
    if not key then return -1 end
    gfx.mouse_cap = key[2] or 0
    return key[1]
  end,
}

local function session(session_keys)
  keys, clock, key_index, answer_index, next_key_at = session_keys, 0, 0, 0, 1
  spoken = {}
  package.loaded.storage, package.loaded.layout = nil, nil
  dofile("ParameterOrganizer.lua")
  while #deferred > 0 do
    table.remove(deferred, 1)()
  end
  for i, msg in ipairs(spoken) do print(i, msg) end
end

print("Session 1")
session(keys)

print("Saved layout:")
local f = io.open(resource .. "/ParameterOrganizer/layouts/" ..
  require("storage").file_name("JS: Phaser plugin file"))
io.write(f and f:read("a") or "(none)\n")
if f then f:close() end

print("Session 2")
tracks[2] = { name = "Bass", number = 2, guid = "{T2}", fx = {
  { name = "JS: Phaser", guid = "{F2}", params = { "Rate", "Depth" }, values = { 0.7, 0.1 } },
} }
session(keys_session2)
