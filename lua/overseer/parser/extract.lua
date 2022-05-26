local parser = require("overseer.parser")
local util = require("overseer.util")
local Extract = {}

function Extract.new(opts, pattern, ...)
  local fields
  if type(opts) ~= "table" then
    fields = util.pack(pattern, ...)
    pattern = opts
    opts = {}
  else
    fields = util.pack(...)
  end
  opts = vim.tbl_deep_extend("keep", opts, {
    consume = true,
    append = true,
  })
  return setmetatable({
    consume = opts.consume,
    append = opts.append,
    done = nil,
    pattern = pattern,
    fields = fields,
  }, { __index = Extract })
end

function Extract:reset()
  self.done = nil
end

local function default_postprocess(value)
  if value:match("^%d+$") then
    return tonumber(value)
  end
  return value
end

function Extract:ingest(line, item, results)
  if self.done then
    return self.done
  end

  local any_match = false
  for _, pattern in util.iter_as_list(self.pattern) do
    local result
    if type(pattern) == "string" then
      result = util.pack(line:match(pattern))
    else
      result = util.pack(pattern(line))
    end
    for i, field in ipairs(self.fields) do
      if result[i] then
        any_match = true
        local key, postprocess
        if type(field) == "table" then
          key, postprocess = unpack(field)
        else
          key = field
          postprocess = default_postprocess
        end
        item[key] = postprocess(result[i], self)
      end
    end
    if any_match then
      break
    end
  end

  if not any_match then
    self.done = parser.STATUS.FAILURE
    return parser.STATUS.FAILURE
  end
  if self.append then
    if type(self.append) == "function" then
      self.append(results, vim.deepcopy(item))
    else
      table.insert(results, vim.deepcopy(item))
    end

    for k in pairs(item) do
      item[k] = nil
    end
  end
  self.done = parser.STATUS.SUCCESS
  return self.consume and parser.STATUS.RUNNING or parser.STATUS.SUCCESS
end

return Extract.new
