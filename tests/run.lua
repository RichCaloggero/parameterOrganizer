-- Runs the plain-Lua tests outside REAPER.
-- Usage, from the project folder:  lua55.exe tests\run.lua

local root = (arg[0]:match("^(.*)[/\\]tests[/\\]") or ".")
package.path = root .. "/lib/?.lua;" .. root .. "/tests/?.lua;" .. package.path

local passed, failed = 0, 0

-- Shared by the test files: test(name, fn) runs fn and records the result.
function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. name .. "\n  " .. tostring(err))
  end
end

function check_equal(actual, expected, what)
  if actual ~= expected then
    error((what or "value") .. ": expected " .. tostring(expected) ..
      ", got " .. tostring(actual), 2)
  end
end

require("test_tree")
require("test_autolabel")
require("test_announce")
require("test_reaper_fx")
require("test_value_search")
require("test_values")
require("test_settings")
require("test_organizer")
require("test_layout")

print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
