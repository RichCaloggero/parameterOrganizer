-- Smoke test: runs ParameterOrganizer.lua against a fake REAPER, presses a
-- scripted sequence of keys, and prints everything that would be spoken.
-- Then runs it a second time, as a new session with a second instance of
-- the same plugin, to check that the saved layout comes back for both.
-- Layouts are saved under %TEMP%\po_smoke, cleared first.
-- Usage, from the project folder:  lua55.exe tests\smoke_main.lua

local K = {
  UP = 30064, DOWN = 1685026670, LEFT = 1818584692, RIGHT = 1919379572,
  HOME = 6647396, END = 1752132965, TAB = 9, F2 = 26162, F5 = 26165,
  F12 = 6697266, ESCAPE = 27, CTRL_N = 14, DELETE = 6579564,
  C = 3, V = 22,   -- as Control+C and Control+V arrive
}
local CTRL, SHIFT = 4, 8

local keys = {
  { K.RIGHT }, { K.RIGHT },                -- into Track 1, into Phaser
  { K.DOWN }, { K.UP, SHIFT },             -- move, nudge a value
  { K.TAB, CTRL },                         -- to the organized tree
  { K.CTRL_N, CTRL },                      -- not available at track level
  { K.RIGHT }, { K.CTRL_N, CTRL },         -- effect level: not available
  { K.RIGHT },                             -- into the empty Phaser
  { K.CTRL_N, CTRL }, { K.CTRL_N, CTRL },  -- frequency, then Q
  { K.F2 },                                -- rename Q
  { K.UP }, { K.RIGHT },                   -- into empty frequency
  { K.F5 },                                -- refresh keeps the place
  { K.LEFT }, { K.LEFT },
  { K.TAB, CTRL },                         -- back to the source tree
  { K.F12 }, { K.DOWN, SHIFT }, { K.ESCAPE },
  -- Step 6: copy Depth, paste it into a branch, rename, delete.
  { K.RIGHT }, { K.DOWN },                 -- source: Phaser, then Depth
  { K.C, CTRL },                           -- copy Depth
  { K.TAB, CTRL },                         -- organized: back in Phaser
  { K.RIGHT }, { K.DOWN },                 -- frequency, then Q factor
  { K.RIGHT },                             -- into empty Q factor
  { K.V, CTRL },                           -- paste: Depth
  { K.F2 }, { K.F2 },                      -- own name, then back to autolabel
  { K.TAB, CTRL }, { K.TAB, CTRL },        -- source says where Depth is placed
  { K.LEFT },                              -- Q factor
  { K.DELETE }, { K.DELETE },              -- ask, then delete
  { K.TAB, CTRL },                         -- source: Depth unplaced again
  { K.V, CTRL },                           -- not in the source tree
  { K.ESCAPE },                            -- quit
}
local answers = { "frequency", "Q", "Q factor", "Mix depth", "" }

-- Session 2: the second track's Phaser is a new instance of the same plugin.
local keys_session2 = {
  { K.TAB, CTRL },                         -- organized tree: Track 1
  { K.RIGHT }, { K.RIGHT },                -- Phaser, then its saved branch
  { K.LEFT }, { K.LEFT }, { K.DOWN },      -- Track 2
  { K.RIGHT }, { K.RIGHT },                -- its Phaser has the same branch
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
