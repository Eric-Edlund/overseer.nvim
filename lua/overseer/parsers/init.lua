local parser = require("overseer.parser")
local M = {}

local registry = {}

local builtin_modules = {}

M.register_builtin = function()
  for _, path in ipairs(builtin_modules) do
    local mod = require(string.format("overseer.parsers.%s", path))
    for k, v in pairs(mod) do
      registry[k] = v
    end
  end
end

M.register_parser = function(name, factory)
  registry[name] = factory
end

M.get_parser = function(name, config)
  if registry[name] then
    return parser.new(registry[name](config))
  end
end

return M
