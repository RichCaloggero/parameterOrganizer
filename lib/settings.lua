-- User settings: their definitions, current values, and how they're spoken.
-- Plain Lua with no REAPER calls; values are kept in a store supplied by
-- the caller ({ get = function(key), set = function(key, text) }), which in
-- REAPER is its persistent ExtState, so settings survive script updates.

local M = {}

-- Each setting is a switch for now; more kinds can be added as needed.
-- on_text and off_text are what is spoken for the value.
M.DEFINITIONS = {
  {
    key = "swap_home_end",
    label = "Home and End",
    default = true,
    on_text = "swapped, Home goes down",
    off_text = "standard, Home goes up",
  },
}

local by_key = {}
for _, def in ipairs(M.DEFINITIONS) do by_key[def.key] = def end

function M.new(store)
  local self = {}

  function self.get(key)
    local text = store.get(key)
    if text == "1" then return true end
    if text == "0" then return false end
    return by_key[key].default
  end

  function self.set(key, value)
    store.set(key, value and "1" or "0")
  end

  -- direction 1 turns a switch on, -1 turns it off.
  function self.step(key, direction)
    self.set(key, direction > 0)
  end

  function self.value_text(key)
    local def = by_key[key]
    return self.get(key) and def.on_text or def.off_text
  end

  return self
end

return M
