-- Autolabeling: shortens a parameter's name by removing words that already
-- appear in the names of the branches above it.
-- Plain Lua with no REAPER calls, so it can be tested outside REAPER.

local M = {}

-- Splits a label into words. Anything that is not a letter or digit
-- separates words, and so do lower-to-upper case changes ("LeftQ"),
-- an upper case run before a capitalised word ("QAttack") and
-- letter/digit changes ("Band1Gain").
function M.split_words(label)
  local words = {}
  for run in label:gmatch("%w+") do
    local spaced = run:gsub("(%l)(%u)", "%1 %2")
                      :gsub("(%u)(%u%l)", "%1 %2")
                      :gsub("(%a)(%d)", "%1 %2")
                      :gsub("(%d)(%a)", "%1 %2")
    for word in spaced:gmatch("%S+") do
      words[#words + 1] = word
    end
  end
  return words
end

-- original: the parameter's name as the plugin reports it.
-- branch_labels: labels of the user-created branches above the parameter.
-- Returns the remaining words joined by spaces, or the original unchanged
-- when nothing matches or nothing would be left.
function M.label(original, branch_labels)
  local remove = {}
  for _, branch in ipairs(branch_labels) do
    for _, word in ipairs(M.split_words(branch)) do
      remove[word:lower()] = true
    end
  end

  local words = M.split_words(original)
  local kept = {}
  for _, word in ipairs(words) do
    if not remove[word:lower()] then kept[#kept + 1] = word end
  end

  if #kept == #words or #kept == 0 then return original end
  return table.concat(kept, " ")
end

return M
