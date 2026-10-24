-- Reads tracks, effects and parameters from the current REAPER project.

local tree = require("tree")

local M = {}

-- REAPER prefixes plugin names with their type, as in "VST3: ReaEQ (Cockos)".
-- Only known types are removed, so a renamed "Drums: comp" keeps its name.
local FX_TYPES = {
  VST = true, VSTi = true, VST3 = true, VST3i = true, JS = true,
  AU = true, AUi = true, CLAP = true, CLAPi = true,
  LV2 = true, LV2i = true, DX = true, DXi = true,
}

local function clean_fx_name(name)
  local prefix, rest = name:match("^(%w+):%s*(.*)$")
  if prefix and FX_TYPES[prefix] then return rest end
  return name
end

local function track_label(track, is_master)
  if is_master then return "Master" end
  local number = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if name == "" then return "Track " .. number end
  return "Track " .. number .. " " .. name
end

local function add_track(root, track, is_master)
  local fx_count = reaper.TrackFX_GetCount(track)
  if fx_count == 0 then return end

  local track_node = tree.add_child(root, tree.new_node("track", track_label(track, is_master), {
    track = track,
    guid = reaper.GetTrackGUID(track),
  }))

  for fx = 0, fx_count - 1 do
    local _, fx_name = reaper.TrackFX_GetFXName(track, fx, "")
    local fx_guid = reaper.TrackFX_GetFXGUID(track, fx)
    local fx_node = tree.add_child(track_node, tree.new_node("fx", clean_fx_name(fx_name), {
      track = track,
      fx = fx,
      guid = fx_guid,
    }))

    for param = 0, reaper.TrackFX_GetNumParams(track, fx) - 1 do
      local _, param_name = reaper.TrackFX_GetParamName(track, fx, param, "")
      tree.add_child(fx_node, tree.new_node("param", param_name, {
        track = track,
        fx = fx,
        fx_guid = fx_guid,
        index = param,
        original_name = param_name,
      }))
    end
  end
end

-- Builds the source tree: master, then each track, each with its effects
-- and their parameters. Tracks without effects are left out.
function M.build_source_tree()
  local root = tree.new_node("root", "")
  add_track(root, reaper.GetMasterTrack(0), true)
  for i = 0, reaper.CountTracks(0) - 1 do
    add_track(root, reaper.GetTrack(0, i), false)
  end
  return root
end

-- The value of a parameter as the plugin displays it, such as "350 Hz".
function M.formatted_value(node)
  local d = node.data
  local ok, value = reaper.TrackFX_GetFormattedParamValue(d.track, d.fx, d.index, "")
  if ok and value ~= "" then return value end
  local normalized = reaper.TrackFX_GetParamNormalized(d.track, d.fx, d.index)
  return string.format("%d percent", math.floor(normalized * 100 + 0.5))
end

-- A key that identifies the same item after the tree is rebuilt.
-- Uses only values stored at build time, because the track may since
-- have been deleted.
function M.identity(node)
  local d = node.data
  if node.kind == "track" then return "track " .. d.guid end
  if node.kind == "fx" then return "fx " .. d.guid end
  if node.kind == "param" then return "param " .. d.fx_guid .. " " .. d.index end
  return nil
end

return M
