-- Finds the setting of a parameter that matches a typed value.
-- Plain Lua with no REAPER calls: the plugin's display text for a
-- setting comes from a callback, format_at(x) for x from 0 to 1.

local M = {}

local SEARCH_STEPS = 40
local TEXT_SAMPLES = 1000
local SCAN_STEP = 0.001
M.SCAN_STEP = SCAN_STEP

-- The number in a display text such as "2.50 kHz", "-6.0 dB" or "-inf",
-- in base units: a "k" straight after the number multiplies by 1000,
-- so "2.5 kHz" and "2500 Hz" compare equal.
function M.parse_number(text)
  if not text then return nil end
  if text:lower():match("^%s*%-%s*inf") then return -math.huge end
  local number, rest = text:match("([-+]?%d*%.?%d+)%s*(.*)$")
  number = tonumber(number)
  if not number then return nil end
  if rest:match("^[kK]") then number = number * 1000 end
  return number
end

-- Binary search for the setting whose displayed number is closest to
-- target, assuming the display rises or falls steadily across the range.
-- Returns nil when the display has no numbers to compare.
function M.find_normalized(target, format_at)
  local low_value = M.parse_number(format_at(0))
  local high_value = M.parse_number(format_at(1))
  if not low_value or not high_value then return nil end

  local rising = high_value >= low_value
  if (rising and target <= low_value) or (not rising and target >= low_value) then return 0 end
  if (rising and target >= high_value) or (not rising and target <= high_value) then return 1 end

  local low, high = 0, 1
  for _ = 1, SEARCH_STEPS do
    local mid = (low + high) / 2
    local value = M.parse_number(format_at(mid))
    if not value then return nil end
    if (value < target) == rising then low = mid else high = mid end
  end

  -- The display is rounded, so pick whichever end of the final interval
  -- displays closer to the target; on a tie, the end that reaches it.
  local low_gap = math.abs(M.parse_number(format_at(low)) - target)
  local high_gap = math.abs(M.parse_number(format_at(high)) - target)
  if low_gap < high_gap then return low end
  return high
end

-- One step from x, by size in direction (1 or -1), that is guaranteed to
-- change what the plugin displays. If the plain step lands on the same
-- display (a "reverb type" slider whose choices each span a wide range,
-- or a step too small to show), keep looking further in small increments
-- until the display changes. Only display text is queried; nothing is set.
-- Returns the new setting, false when the display can't change any more
-- in that direction, or nil when the plugin can't describe settings.
function M.step_until_changed(x, direction, size, format_at)
  local current = format_at(x)
  if not current then return nil end

  local target = math.max(0, math.min(1, x + direction * size))
  if format_at(target) ~= current then return target end

  -- Jump further each time, starting small so a nearby change is found
  -- at once and a distant one in few tries.
  local same, jump = target, SCAN_STEP
  local changed
  while true do
    local t = same + direction * jump
    -- Past the end: the end itself may still show a different choice.
    if t < 0 or t > 1 then t = direction > 0 and 1 or 0 end
    if format_at(t) ~= current then
      changed = t
      break
    end
    if t == 0 or t == 1 then return false end
    same, jump = t, jump * 2
  end

  -- Narrow down between the last setting that looked the same and the
  -- first that didn't, to the first different one.
  while math.abs(changed - same) > SCAN_STEP do
    local mid = (same + changed) / 2
    if format_at(mid) ~= current then changed = mid else same = mid end
  end
  return changed
end

-- For displays such as "Sine" or "Off": the first setting whose display
-- text matches, ignoring case and surrounding spaces.
function M.find_by_text(text, format_at)
  local wanted = text:lower():match("^%s*(.-)%s*$")
  for i = 0, TEXT_SAMPLES do
    local x = i / TEXT_SAMPLES
    local shown = format_at(x)
    if shown and shown:lower():match("^%s*(.-)%s*$") == wanted then return x end
  end
  return nil
end

return M
