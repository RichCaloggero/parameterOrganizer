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
}

reaper = {
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
  TrackFX_GetParamName = function(t, fx, p) return true, t.fx[fx + 1].params[p + 1] end,
  TrackFX_GetFormattedParamValue = function(_, _, p) return true, p == 0 and "350 Hz" or "" end,
  TrackFX_GetParamNormalized = function() return 0.426 end,
}

local reaper_fx = require("reaper_fx")

local function labels(node)
  local list = {}
  for _, child in ipairs(node.children) do list[#list + 1] = child.label end
  return table.concat(list, "|")
end

test("source tree: master first, empty tracks left out", function()
  local root = reaper_fx.build_source_tree()
  check_equal(labels(root), "Master|Track 1 Vocals|Track 3")
end)

test("source tree: plugin type prefixes are removed", function()
  local root = reaper_fx.build_source_tree()
  check_equal(labels(root.children[1]), "Limiter (Acme)")
  check_equal(labels(root.children[2]), "Stereo Phaser")
  check_equal(labels(root.children[3]), "Synth|Drums: comp")
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

reaper = nil
