-- Sorting and filtering an effect's unplaced parameters (its default
-- branch). Plain Lua with no REAPER calls.

local M = {}

-- Splits text into runs of digits and runs of anything else.
local function chunks(text)
  local list = {}
  for digits, other in text:lower():gmatch("(%d*)(%D*)") do
    if digits ~= "" then list[#list + 1] = { number = true, text = digits } end
    if other ~= "" then list[#list + 1] = { text = other } end
  end
  return list
end

-- Compares two digit runs as numbers, without converting them, so runs of
-- any length work. Returns -1, 0 or 1.
local function compare_digits(a, b)
  a, b = a:gsub("^0+", ""), b:gsub("^0+", "")
  if #a ~= #b then return #a < #b and -1 or 1 end
  if a == b then return 0 end
  return a < b and -1 or 1
end

-- Natural order, ignoring case: band1, band2, band10. Returns -1, 0 or 1;
-- names that compare equal (such as "band01" and "band1") return 0, so
-- the caller can keep them in source order.
function M.natural_compare(a, b)
  local ca, cb = chunks(a), chunks(b)
  for i = 1, math.min(#ca, #cb) do
    local x, y = ca[i], cb[i]
    local result
    if x.number and y.number then
      result = compare_digits(x.text, y.text)
    elseif x.text ~= y.text then
      result = x.text < y.text and -1 or 1
    else
      result = 0
    end
    if result ~= 0 then return result end
  end
  if #ca == #cb then return 0 end
  return #ca < #cb and -1 or 1
end

-- Case folded, every run of whitespace made one space, ends trimmed.
function M.normalize(text)
  return (text:lower():gsub("%s+", " "):match("^ ?(.-) ?$"))
end

-- True when name contains the filter text, as typed (a plain substring,
-- so characters such as "(" or "%" mean themselves).
function M.matches(name, filter)
  return M.normalize(name):find(M.normalize(filter), 1, true) ~= nil
end

-- The parameters (source data tables, in source order) that the view
-- shows: those passing the filter, in natural order when sorted.
-- view is { sorted = boolean, filter = text or nil }.
function M.apply(params, view)
  local shown = {}
  for i, p in ipairs(params) do
    if not view.filter or M.matches(p.original_name, view.filter) then
      shown[#shown + 1] = { data = p, position = i }
    end
  end
  if view.sorted then
    table.sort(shown, function(x, y)
      local result = M.natural_compare(x.data.original_name, y.data.original_name)
      if result ~= 0 then return result < 0 end
      return x.position < y.position
    end)
  end
  for i, entry in ipairs(shown) do shown[i] = entry.data end
  return shown
end

return M
