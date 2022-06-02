-- Utilities for parsing lines of output
local Enum = require("overseer.enum")
local M = {}

local debug = false
local depth = 0

setmetatable(M, {
  __index = function(_, key)
    if debug and key ~= "util" then
      local constructor = require(string.format("overseer.parser.%s", key))
      return function(...)
        local node = constructor(...)
        local ingest = node.ingest
        node.ingest = function(self, line, ...)
          print(string.format("%s<%s: '%s'>", string.rep("  ", depth), key, line))
          depth = depth + 1
          local st = ingest(self, line, ...)
          depth = depth - 1
          print(string.format("%s</%s %s>", string.rep("  ", depth), key, st))
          return st
        end
        return node
      end
    else
      return require(string.format("overseer.parser.%s", key))
    end
  end,
})

M.STATUS = Enum.new({
  "RUNNING",
  "SUCCESS",
  "FAILURE",
})

local ListParser = {}

function ListParser.new(children)
  return setmetatable({
    tree = M.loop({ ignore_failure = true }, M.sequence(unpack(children))),
    results = {},
    item = {},
  }, { __index = ListParser })
end

function ListParser:reset()
  self.tree:reset()
  self.results = {}
  self.item = {}
end

function ListParser:ingest(lines)
  local num_results = #self.results
  local ctx = { item = self.item, results = self.results, default_values = {} }
  for _, line in ipairs(lines) do
    if debug then
      print(string.format("ingest: %s", line))
    end
    self.tree:ingest(line, ctx)
    if debug then
      print(string.format("results: %s", vim.inspect(ctx.results)))
      print(string.format("item: %s", vim.inspect(ctx.item)))
    end
  end
  return #self.results ~= num_results
end

function ListParser:get_result()
  return self.results
end

local MapParser = {}

function MapParser.new(children)
  local results = {}
  local items = {}
  local wrapped_children = {}
  for k, v in pairs(children) do
    results[k] = {}
    items[k] = {}
    wrapped_children[k] = M.loop({ ignore_failure = true }, M.sequence(unpack(v)))
  end
  return setmetatable({
    children = wrapped_children,
    results = results,
    items = items,
  }, { __index = MapParser })
end

function MapParser:reset()
  for k, v in pairs(self.children) do
    self.results[k] = {}
    self.items[k] = {}
    v:reset()
  end
end

function MapParser:ingest(lines)
  local any_changed = false
  for _, line in ipairs(lines) do
    for k, v in pairs(self.children) do
      local ctx = { item = self.items[k], results = self.results[k], default_values = {} }
      local num_results = #ctx.results
      if debug then
        print(string.format("ingest(%s): %s", k, line))
      end
      v:ingest(line, ctx)
      if debug then
        print(string.format("results(%s): %s", k, vim.inspect(ctx.results)))
        print(string.format("item(%s): %s", k, vim.inspect(ctx.item)))
      end
      any_changed = any_changed or #ctx.results ~= num_results
    end
  end
  return any_changed
end

function MapParser:get_result()
  return self.results
end

M.new = function(config)
  vim.validate({
    config = { config, "t" },
  })
  if vim.tbl_islist(config) then
    return ListParser.new(config)
  else
    return MapParser.new(config)
  end
end

M.trace = function(enabled)
  debug = enabled
end

return M
