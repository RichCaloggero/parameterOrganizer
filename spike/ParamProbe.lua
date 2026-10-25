-- @description Parameter Organizer probe: REAPER's built-in FX parameters
--
-- Throwaway diagnostic. On the selected track's first effect (or the first
-- track with effects), logs what REAPER reports for the last three
-- parameters (normally Bypass, Wet and Delta), tries to flip each one,
-- logs the result, then restores the original value.
-- Output goes to ParamProbe.log next to this script.

local script_dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
local log_file = io.open(script_dir .. "ParamProbe.log", "a")

local function log(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  log_file:write(table.concat(parts, "\t"), "\n")
end

local function find_track()
  local track = reaper.GetSelectedTrack(0, 0)
  if track and reaper.TrackFX_GetCount(track) > 0 then return track end
  for i = 0, reaper.CountTracks(0) - 1 do
    track = reaper.GetTrack(0, i)
    if reaper.TrackFX_GetCount(track) > 0 then return track end
  end
  return nil
end

local function describe(track, fx, p, label)
  local _, shown = reaper.TrackFX_GetFormattedParamValue(track, fx, p, "")
  local value, min, max = reaper.TrackFX_GetParamEx(track, fx, p)
  log(label, "normalized", reaper.TrackFX_GetParamNormalized(track, fx, p),
    "value", value, "min", min, "max", max, "shown", shown,
    "fx enabled", reaper.TrackFX_GetEnabled(track, fx))
end

local track = find_track()
if not track then
  reaper.osara_outputMessage("Probe: no track with effects")
  log_file:close()
  return
end

local fx = 0
local _, fx_name = reaper.TrackFX_GetFXName(track, fx, "")
local count = reaper.TrackFX_GetNumParams(track, fx)
log("---- probe " .. os.date(), fx_name, "params", count)

for p = math.max(0, count - 3), count - 1 do
  local _, name = reaper.TrackFX_GetParamName(track, fx, p, "")
  log("param", p, name, "step sizes", reaper.TrackFX_GetParameterStepSizes(track, fx, p))
  describe(track, fx, p, "  before")

  local original = reaper.TrackFX_GetParamNormalized(track, fx, p)
  local flipped = original < 0.5 and 1 or 0

  log("  SetParamNormalized", flipped, "returned", reaper.TrackFX_SetParamNormalized(track, fx, p, flipped))
  describe(track, fx, p, "  after normalized")
  reaper.TrackFX_SetParamNormalized(track, fx, p, original)

  local _, min, max = reaper.TrackFX_GetParamEx(track, fx, p)
  local target = original < 0.5 and max or min
  log("  SetParam", target, "returned", reaper.TrackFX_SetParam(track, fx, p, target))
  describe(track, fx, p, "  after SetParam")
  reaper.TrackFX_SetParamNormalized(track, fx, p, original)

  describe(track, fx, p, "  restored")
end

log_file:close()
reaper.osara_outputMessage("Probe done")
