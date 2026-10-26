-- Tests reaper_fx against a small fake of the REAPER API.

local master = { name = "", number = -1, guid = "{M}", fx = {
  { name = "VST3: Limiter (Acme)", guid = "{FX-M1}", params = { "Ceiling" } },
} }
local tracks = {
  { name = "Vocals", number = 1, guid = "{T1}", fx = {
    { name = "JS: Stereo Phaser", guid = "{FX-1}",
      params = { "left Q attack", "right Q attack", "Bypass", "Wet", "Delta" } },
  } },
  { name = "", number = 2, guid = "{T2}", fx = {} },
  { name = "", number = 3, guid = "{T3}", fx = {
    { name = "VSTi: Synth", guid = "{FX-3}", params = { "Cutoff" } },
    { name = "Drums: comp", guid = "{FX-4}", params = { "Ratio" } },
  } },
  -- A container holding ReaEQ and a nested container holding ReaComp.
  -- Effects inside containers are reached by address, as in REAPER 7.
  { name = "Bus", number = 4, guid = "{T4}", fx = {
    { name = "Container", guid = "{C1}", items = { 100, 101 }, params = { "Bypass", "Wet", "Delta" } },
  }, by_address = {
    [100] = { name = "VST: ReaEQ (Cockos)", guid = "{FX-EQ}", params = { "Gain" } },
    [101] = { name = "Inner", guid = "{C2}", items = { 200 }, params = { "Bypass", "Wet", "Delta" } },
    [200] = { name = "VST: ReaComp (Cockos)", guid = "{FX-COMP}", params = { "Ratio" } },
  } },
}

local function fx_at(t, fx)
  return (t.by_address and t.by_address[fx]) or t.fx[fx + 1]
end

reaper = {
  GetMasterTrack = function() return master end,
  CountTracks = function() return #tracks end,
  GetTrack = function(_, i) return tracks[i + 1] end,
  GetTrackGUID = function(t) return t.guid end,
  GetMediaTrackInfo_Value = function(t) return t.number end,
  GetSetMediaTrackInfo_String = function(t) return true, t.name end,
  TrackFX_GetCount = function(t) return #t.fx end,
  TrackFX_GetFXName = function(t, fx) return true, fx_at(t, fx).name end,
  TrackFX_GetFXGUID = function(t, fx) return fx_at(t, fx).guid end,
  TrackFX_GetNumParams = function(t, fx) return #fx_at(t, fx).params end,
  TrackFX_GetParamName = function(t, fx, p) return true, fx_at(t, fx).params[p + 1] end,
  TrackFX_GetNamedConfigParm = function(t, fx, name)
    local items = fx_at(t, fx).items
    if not items then return false, "" end
    if name == "container_count" then return true, tostring(#items) end
    local i = tonumber(name:match("^container_item%.(%d+)$"))
    if i and items[i + 1] then return true, tostring(items[i + 1]) end
    return false, ""
  end,
  TrackFX_GetFormattedParamValue = function(_, _, p) return true, p == 0 and "350 Hz" or "" end,
  TrackFX_GetParamNormalized = function() return 0.426 end,
}

local reaper_fx = require("reaper_fx")

local function labels(node)
  local list = {}
  for _, child in ipairs(node.children) do list[#list + 1] = child.label end
  return table.concat(list, "|")
end

test("source tree: master first, empty tracks included", function()
  local root = reaper_fx.build_source_tree()
  check_equal(labels(root), "Master|Track 1 Vocals|Track 2|Track 3|Track 4 Bus")
  check_equal(#root.children[3].children, 0, "empty track")
end)

test("source tree: plugin type prefixes are removed", function()
  local root = reaper_fx.build_source_tree()
  check_equal(labels(root.children[1]), "Limiter (Acme)")
  check_equal(labels(root.children[2]), "Stereo Phaser")
  check_equal(labels(root.children[4]), "Synth|Drums: comp")
end)

test("source tree: parameters with their indexes", function()
  local root = reaper_fx.build_source_tree()
  local phaser = root.children[2].children[1]
  check_equal(labels(phaser), "left Q attack|right Q attack|Bypass|Wet|Delta")
  check_equal(phaser.children[2].data.index, 1, "index")
  check_equal(phaser.children[2].kind, "param")
end)

test("only REAPER's own Bypass and Delta are marked as switches", function()
  local phaser = reaper_fx.build_source_tree().children[2].children[1]
  local marked = {}
  for _, p in ipairs(phaser.children) do
    if p.data.builtin_switch then marked[#marked + 1] = p.label end
  end
  check_equal(table.concat(marked, "|"), "Bypass|Delta")
end)

test("formatted value, with a percent fallback", function()
  local root = reaper_fx.build_source_tree()
  local phaser = root.children[2].children[1]
  check_equal(reaper_fx.formatted_value(phaser.children[1]), "350 Hz")
  check_equal(reaper_fx.formatted_value(phaser.children[2]), "43 percent")
end)

test("identity survives a rebuild", function()
  local a = reaper_fx.build_source_tree().children[2].children[1].children[2]
  local b = reaper_fx.build_source_tree().children[2].children[1].children[2]
  check_equal(reaper_fx.identity(a), reaper_fx.identity(b))
  check_equal(reaper_fx.identity(a), "param {FX-1} 1")
end)

test("containers hold their effects first, then their own parameters", function()
  local container = reaper_fx.build_source_tree().children[5].children[1]
  check_equal(container.data.is_container, true, "is container")
  check_equal(labels(container), "ReaEQ (Cockos)|Inner|Bypass|Wet|Delta")
  local inner = container.children[2]
  check_equal(labels(inner), "ReaComp (Cockos)|Bypass|Wet|Delta")
  local ratio = inner.children[1].children[1]
  check_equal(ratio.data.fx, 200, "nested address")
  check_equal(ratio.data.fx_guid, "{FX-COMP}")
  check_equal(container.children[3].data.fx, 0, "container's own parameter")
end)

test("plain effects are not containers", function()
  local phaser = reaper_fx.build_source_tree().children[2].children[1]
  check_equal(phaser.data.is_container, false)
end)

reaper = nil
