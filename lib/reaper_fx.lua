-- Reads tracks, effects and parameters from the current REAPER project.

local tree = require("tree")
local value_search = require("value_search")

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

-- REAPER adds Bypass, Wet and Delta as the last three parameters of every
-- effect. Bypass and Delta are on/off switches, but REAPER reports them as
-- plain sliders with no step sizes, so they are recognised by name here.
local BUILTIN_SWITCHES = { Bypass = true, Delta = true }

local function track_label(track, is_master)
  if is_master then return "Master" end
  local number = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if name == "" then return "Track " .. number end
  return "Track " .. number .. " " .. name
end

-- The addresses of the effects inside a container (REAPER 7), or nil when
-- fx is not a container. The addresses work with every TrackFX_ function,
-- including for containers nested inside containers.
local function container_items(track, fx)
  if not reaper.TrackFX_GetNamedConfigParm then return nil end
  local ok, count = reaper.TrackFX_GetNamedConfigParm(track, fx, "container_count")
  if not ok then return nil end
  local items = {}
  for i = 0, (tonumber(count) or 0) - 1 do
    local found, address = reaper.TrackFX_GetNamedConfigParm(track, fx, "container_item." .. i)
    if found and tonumber(address) then items[#items + 1] = tonumber(address) end
  end
  return items
end

-- What identifies the plugin type, the same for every instance of it, so
-- that one saved layout serves them all: REAPER's plugin identifier when
-- available (it ignores renamed instances), otherwise the plugin's name.
local function plugin_key(track, fx, fx_name)
  if reaper.TrackFX_GetNamedConfigParm then
    local ok, ident = reaper.TrackFX_GetNamedConfigParm(track, fx, "fx_ident")
    if ok and ident ~= "" then return ident end
  end
  return fx_name
end

-- Adds an effect under parent: for a container, first the effects it
-- holds (each added the same way), then its own parameters.
local function add_fx(parent, track, fx)
  local _, fx_name = reaper.TrackFX_GetFXName(track, fx, "")
  local fx_guid = reaper.TrackFX_GetFXGUID(track, fx)
  local items = container_items(track, fx)
  local fx_node = tree.add_child(parent, tree.new_node("fx", clean_fx_name(fx_name), {
    track = track,
    fx = fx,
    guid = fx_guid,
    is_container = items ~= nil,
    plugin_key = plugin_key(track, fx, fx_name),
  }))

  for _, item in ipairs(items or {}) do
    add_fx(fx_node, track, item)
  end

  local param_count = reaper.TrackFX_GetNumParams(track, fx)
  for param = 0, param_count - 1 do
    local _, param_name = reaper.TrackFX_GetParamName(track, fx, param, "")
    tree.add_child(fx_node, tree.new_node("param", param_name, {
      track = track,
      fx = fx,
      fx_guid = fx_guid,
      index = param,
      original_name = param_name,
      builtin_switch = param >= param_count - 3 and BUILTIN_SWITCHES[param_name],
    }))
  end
end

local function add_track(root, track, is_master)
  local fx_count = reaper.TrackFX_GetCount(track)
  local track_node = tree.add_child(root, tree.new_node("track", track_label(track, is_master), {
    track = track,
    guid = reaper.GetTrackGUID(track),
  }))

  for fx = 0, fx_count - 1 do
    add_fx(track_node, track, fx)
  end
end

-- Builds the source tree: master, then each track, each with its effects
-- and their parameters. Tracks without effects are included, so effects
-- can be pasted onto them.
function M.build_source_tree()
  local root = tree.new_node("root", "")
  add_track(root, reaper.GetMasterTrack(0), true)
  for i = 0, reaper.CountTracks(0) - 1 do
    add_track(root, reaper.GetTrack(0, i), false)
  end
  return root
end

-- An effect's bypass state, read from REAPER each time so a change made
-- elsewhere is heard.
function M.is_bypassed(fx_node)
  local d = fx_node.data
  return not reaper.TrackFX_GetEnabled(d.track, d.fx)
end

-- Bypasses the effect, or brings it back. Returns the new state.
function M.toggle_bypass(fx_node)
  local d = fx_node.data
  local bypassed = not M.is_bypassed(fx_node)
  reaper.TrackFX_SetEnabled(d.track, d.fx, not bypassed)
  return bypassed
end

-- The track's whole effect chain bypassed (its FX button, which OSARA's B
-- toggles), read from REAPER each time like an effect's bypass.
function M.is_chain_bypassed(track_node)
  return reaper.GetMediaTrackInfo_Value(track_node.data.track, "I_FXEN") == 0
end

-- Bypasses the track's effect chain, or brings it back. Returns the new state.
function M.toggle_chain_bypass(track_node)
  local bypassed = not M.is_chain_bypassed(track_node)
  reaper.SetMediaTrackInfo_Value(track_node.data.track, "I_FXEN", bypassed and 0 or 1)
  return bypassed
end

-- The position of the effect with this guid in the track's chain, or nil.
-- Effects are found by guid, since positions change as they move.
local function chain_index(track, guid)
  if not reaper.ValidatePtr2(0, track, "MediaTrack*") then return nil end
  for i = 0, reaper.TrackFX_GetCount(track) - 1 do
    if reaper.TrackFX_GetFXGUID(track, i) == guid then return i end
  end
  return nil
end

-- Moves (or copies) the effect with src_guid on src_track to dest_track,
-- straight after the effect with after_guid, or first when after_guid is
-- nil. Returns the guid of the effect in its new place, or nil when an
-- effect or track is gone.
function M.place_fx(src_track, src_guid, dest_track, after_guid, is_move)
  local src = chain_index(src_track, src_guid)
  local after = -1
  if after_guid then
    after = chain_index(dest_track, after_guid)
  elseif not reaper.ValidatePtr2(0, dest_track, "MediaTrack*") then
    after = nil
  end
  if not src or not after then return nil end
  local same_track = src_track == dest_track
  if is_move and same_track and src == after then return src_guid end
  -- REAPER puts the effect at dest, counted after taking it out when it
  -- moves within the chain: from ahead of after, that is after's place.
  local dest = after + 1
  if is_move and same_track and src < after then dest = after end
  reaper.TrackFX_CopyToTrack(src_track, src, dest_track, dest, is_move)
  return reaper.TrackFX_GetFXGUID(dest_track, dest)
end

-- Removes the effect with this guid from the track's chain, if it is there.
function M.delete_fx(track, guid)
  local index = chain_index(track, guid)
  if index then reaper.TrackFX_Delete(track, index) end
end

-- The value of a parameter as the plugin displays it, such as "350 Hz".
function M.formatted_value(node)
  local d = node.data
  if d.missing then return "missing" end
  local ok, value = reaper.TrackFX_GetFormattedParamValue(d.track, d.fx, d.index, "")
  if ok and value ~= "" then return value end
  local normalized = reaper.TrackFX_GetParamNormalized(d.track, d.fx, d.index)
  return string.format("%d percent", math.floor(normalized * 100 + 0.5))
end

local SMALL_STEP, LARGE_STEP = 0.01, 0.1

-- Returns format_at(x): what the plugin displays at setting x (0 to 1),
-- or nil when it can't say; and whether format_at is "live".
--
-- Normally the plugin is asked without changing anything. Some plugins
-- (ValhallaVintageVerb, for one) answer every such question with their
-- current display, so that is checked first: if settings 0 and 1 would
-- display the same, format_at instead sets x and reads the real display.
-- A live search must finish by setting the final value, or the original.
local function format_at_for(d)
  local function query(x)
    local ok, shown = reaper.TrackFX_FormatParamValueNormalized(d.track, d.fx, d.index, x, "")
    if ok and shown ~= "" then return shown end
    return nil
  end
  if query(0) ~= query(1) then return query, false end

  return function(x)
    reaper.TrackFX_SetParamNormalized(d.track, d.fx, d.index, x)
    local ok, shown = reaper.TrackFX_GetFormattedParamValue(d.track, d.fx, d.index, "")
    if ok and shown ~= "" then return shown end
    return nil
  end, true
end

-- Moves a parameter one step up (direction 1) or down (direction -1).
-- Parameters with set positions, such as switches and mode menus, move
-- by the step sizes the plugin reports; others by 1% or 10% of the range.
-- No undo point is created: value changes stay out of the undo history.
function M.step_value(node, direction, large)
  local d = node.data
  if d.builtin_switch then
    reaper.TrackFX_SetParamNormalized(d.track, d.fx, d.index, direction > 0 and 1 or 0)
    return
  end

  local has_steps, step, _, large_step, is_toggle =
    reaper.TrackFX_GetParameterStepSizes(d.track, d.fx, d.index)

  if has_steps and (is_toggle or step > 0) then
    local value, min, max = reaper.TrackFX_GetParamEx(d.track, d.fx, d.index)
    local new
    if is_toggle then
      new = direction > 0 and max or min
    else
      local size = step
      if large and large_step > 0 then
        size = large_step
      elseif large then
        -- No large step reported: 10% of the range in whole steps, at least one.
        size = step * math.max(1, math.floor(LARGE_STEP * (max - min) / step + 0.5))
      end
      new = math.max(min, math.min(max, value + direction * size))
    end
    reaper.TrackFX_SetParam(d.track, d.fx, d.index, new)
  else
    local value = reaper.TrackFX_GetParamNormalized(d.track, d.fx, d.index)
    local size = large and LARGE_STEP or SMALL_STEP
    local format_at = format_at_for(d)
    local new = value_search.step_until_changed(value, direction, size, format_at)
    if new == nil then
      -- The plugin can't describe settings: a plain step.
      new = math.max(0, math.min(1, value + direction * size))
    end
    -- false means no change is possible; a live search may have moved the
    -- parameter while looking, so put the original back.
    reaper.TrackFX_SetParamNormalized(d.track, d.fx, d.index, new or value)
  end
end

-- Sets a parameter to the end (to_end true) or start of its range.
function M.set_extreme(node, to_end)
  local d = node.data
  reaper.TrackFX_SetParamNormalized(d.track, d.fx, d.index, to_end and 1 or 0)
end

-- Sets a parameter from typed text, in the plugin's own units ("2500",
-- "2.5 kHz", "-6") or as a display word ("Sine"). Falls back to treating
-- a number as a percentage when the plugin can't describe other settings.
-- Returns false when the text matched nothing.
function M.set_value_from_text(node, text)
  local d = node.data
  local original = reaper.TrackFX_GetParamNormalized(d.track, d.fx, d.index)
  local format_at = format_at_for(d)

  local target = value_search.parse_number(text)
  local x
  if target then
    x = value_search.find_normalized(target, format_at)
    if not x then x = math.max(0, math.min(1, target / 100)) end
  else
    x = value_search.find_by_text(text, format_at)
  end

  -- Also undoes any moves made by a live search that found nothing.
  reaper.TrackFX_SetParamNormalized(d.track, d.fx, d.index, x or original)
  return x ~= nil
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
