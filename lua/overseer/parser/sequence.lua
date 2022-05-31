local parser = require("overseer.parser")
local util = require("overseer.util")
local Sequence = {}

function Sequence.new(opts, ...)
  local children
  if opts.ingest then
    children = util.pack(opts, ...)
    opts = {}
  elseif vim.tbl_islist(opts) then
    -- children are passed in as a list
    children = opts
    opts = {}
  else
    if select("#", ...) == 1 then
      local arg1 = select(1, ...)
      -- we got opts, and children are passed in as a list
      if vim.tbl_islist(arg1) then
        children = arg1
      end
    end
    if not children then
      -- children are passed in as args
      children = util.pack(...)
    end
  end
  vim.validate({
    break_on_first_failure = { opts.break_on_first_failure, "b", true },
    break_on_first_success = { opts.break_on_first_success, "b", true },
  })
  opts = vim.tbl_deep_extend("keep", opts, {
    break_on_first_failure = true,
    break_on_first_success = false,
  })
  return setmetatable({
    idx = 1,
    any_failures = false,
    break_on_first_success = opts.break_on_first_success,
    break_on_first_failure = opts.break_on_first_failure,
    children = children,
  }, { __index = Sequence })
end

function Sequence:reset()
  self.idx = 1
  self.any_failures = false
  for _, child in ipairs(self.children) do
    child:reset()
  end
end

function Sequence:ingest(...)
  while self.idx <= #self.children do
    local child = self.children[self.idx]
    local st = child:ingest(...)
    if st == parser.STATUS.SUCCESS then
      if self.break_on_first_success then
        return st
      end
    elseif st == parser.STATUS.FAILURE then
      self.any_failures = true
      if self.break_on_first_failure then
        return st
      end
    elseif st == parser.STATUS.RUNNING then
      return st
    end
    self.idx = self.idx + 1
  end

  if self.any_failures then
    return parser.STATUS.FAILURE
  else
    return parser.STATUS.SUCCESS
  end
end

return Sequence.new
