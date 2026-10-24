-- @description Parameter Organizer key test
-- @version 0.1
--
-- Throwaway spike: speaks the gfx.getchar code and modifiers for every key,
-- and appends each one to KeyTest.log next to this script.
-- F2 (no modifiers) opens a GetUserInputs prompt to test focus return.
-- Escape quits.

local MOD_CTRL, MOD_SHIFT, MOD_ALT, MOD_WIN = 4, 8, 16, 32
local KEY_ESCAPE, KEY_F2 = 27, 26162

local KEY_NAMES = {
  [30064] = "Up", [1685026670] = "Down",
  [1818584692] = "Left", [1919379572] = "Right",
  [6647396] = "Home", [1752132965] = "End",
  [1885828464] = "Page Up", [1885824110] = "Page Down",
  [6909555] = "Insert", [6579564] = "Delete",
  [8] = "Backspace", [9] = "Tab", [13] = "Enter", [27] = "Escape", [32] = "Space",
  [26161] = "F1", [26162] = "F2", [26163] = "F3", [26164] = "F4",
  [26165] = "F5", [26166] = "F6", [26167] = "F7", [26168] = "F8",
  [26169] = "F9", [6697264] = "F10", [6697265] = "F11", [6697266] = "F12",
}

-- With Control held, gfx.getchar reports letters as 1 to 26, so Tab (9),
-- Enter (13) and Backspace (8) collide with Control+I, M and H.
-- js_ReaScriptAPI's key state tells them apart when it is installed.
local VK_FOR_CODE = { [8] = 0x08, [9] = 0x09, [13] = 0x0D }

local script_dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
local log_path = script_dir .. "KeyTest.log"

local function speak(msg)
  if reaper.osara_outputMessage then
    reaper.osara_outputMessage(msg)
  end
end

local function log(line)
  local f = io.open(log_path, "a")
  if f then
    f:write(line, "\n")
    f:close()
  end
end

local function vkey_down(vk)
  if not reaper.JS_VKeys_GetState then return nil end
  local state = reaper.JS_VKeys_GetState(-2) or ""
  return (state:byte(vk) or 0) ~= 0
end

local function modifier_names(cap)
  local parts = {}
  if cap & MOD_CTRL ~= 0 then parts[#parts + 1] = "Control" end
  if cap & MOD_SHIFT ~= 0 then parts[#parts + 1] = "Shift" end
  if cap & MOD_ALT ~= 0 then parts[#parts + 1] = "Alt" end
  if cap & MOD_WIN ~= 0 then parts[#parts + 1] = "Windows" end
  return parts
end

local function key_name(code, cap)
  local ctrl = cap & MOD_CTRL ~= 0
  local vk = VK_FOR_CODE[code]

  if ctrl and vk then
    local down = vkey_down(vk)
    if down == nil then
      return KEY_NAMES[code] .. " or letter " .. string.char(code + 64) .. ", ambiguous"
    elseif not down then
      return "letter " .. string.char(code + 64)
    end
  elseif ctrl and code >= 1 and code <= 26 then
    return "letter " .. string.char(code + 64)
  end

  if KEY_NAMES[code] then return KEY_NAMES[code] end
  if code > 32 and code < 127 then return "character " .. string.char(code) end
  return "unknown"
end

local function describe(code, cap)
  local parts = modifier_names(cap)
  parts[#parts + 1] = key_name(code, cap)
  return table.concat(parts, " ") .. ", code " .. code
end

-- The screen reader announces the new window when it gains focus, which can
-- cut off speech sent at the same moment, so the greeting waits a little.
local GREETING_DELAY = 0.5
local start_time = reaper.time_precise()
local greeted = false

local function greet_when_ready()
  if not greeted and reaper.time_precise() - start_time >= GREETING_DELAY then
    speak("Key test ready. Press keys to hear their codes. F2 opens a prompt. Escape quits.")
    greeted = true
  end
end

local had_focus = nil

local function check_focus()
  local focused = gfx.getchar(65536) & 2 ~= 0
  if focused ~= had_focus then
    if had_focus ~= nil then
      speak(focused and "Key test has focus" or "Key test lost focus")
    end
    log("focus\t" .. tostring(focused))
    had_focus = focused
  end
end

local function prompt_test()
  local ok, text = reaper.GetUserInputs("Key test prompt", 1, "Type anything", "")
  log("prompt\t" .. tostring(ok) .. "\t" .. tostring(text))
  if ok then
    speak("You typed " .. (text ~= "" and text or "nothing") .. ". Now press any key.")
  else
    speak("Prompt cancelled. Now press any key.")
  end
end

local function loop()
  local code = gfx.getchar()
  if code < 0 then return end

  check_focus()
  greet_when_ready()

  if code > 0 then
    -- REAPER returns floats; convert so the log reads 3, not 3.0.
    code = math.tointeger(code) or code
    local cap = math.tointeger(gfx.mouse_cap) or 0
    local msg = describe(code, cap)
    log(code .. "\t" .. cap .. "\t" .. msg)

    if code == KEY_ESCAPE and cap == 0 then
      speak("Key test closed")
      gfx.quit()
      return
    elseif code == KEY_F2 and cap == 0 then
      prompt_test()
    else
      speak(msg)
    end
  end

  reaper.defer(loop)
end

if not reaper.osara_outputMessage then
  reaper.ShowMessageBox("OSARA is not loaded, so the key test cannot speak.", "Key test", 0)
  return
end

if reaper.set_action_options then
  reaper.set_action_options(1)
end

log("---- key test started " .. os.date() ..
  ", js_ReaScriptAPI " .. (reaper.JS_VKeys_GetState and "present" or "missing"))
gfx.init("Parameter Organizer key test", 1, 1, 0, -32000, -32000)
reaper.atexit(gfx.quit)
reaper.defer(loop)
