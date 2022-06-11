local default_config = {
  list_sep = "────────────────────────────────────────",
  extensions = { "builtin" },
  auto_detect_success_color = true,
  sidebar = {
    default_detail = 1,
    max_width = { 100, 0.2 },
    min_width = { 40, 0.1 },
  },
  log = {
    {
      type = "echo",
      level = vim.log.levels.WARN,
    },
    {
      type = "file",
      filename = "overseer.log",
      level = vim.log.levels.WARN,
    },
  },
  actions = {},
  form = {
    border = "rounded",
    min_width = 80,
    max_width = 0.9,
    min_height = 10,
    max_height = 0.9,
    winblend = 10,
  },
  -- Configuration for task and test result floating windows
  float_win = {
    padding = 2,
    border = "rounded",
    winblend = 10,
  },
  component_sets = {
    default = {
      "on_output_summarize",
      "result_exit_code",
      "on_result_notify",
      "on_rerun_handler",
      "dispose_delay",
    },
    default_persist = {
      "on_output_summarize",
      "result_exit_code",
      "on_result_notify",
      "on_rerun_handler",
      "rerun_on_result",
    },
  },
}

local M = vim.deepcopy(default_config)

local function merge_actions(default_actions, user_actions)
  local actions = {}
  for k, v in pairs(default_actions) do
    actions[k] = v
  end
  for k, v in pairs(user_actions or {}) do
    if not v then
      actions[k] = nil
    else
      actions[k] = v
    end
  end
  return actions
end

M.setup = function(opts)
  local component = require("overseer.component")
  local log = require("overseer.log")
  local parsers = require("overseer.parsers")
  local extensions = require("overseer.extensions")
  local util = require("overseer.util")
  opts = opts or {}
  local newconf = vim.tbl_deep_extend("force", default_config, opts)
  for k, v in pairs(newconf) do
    M[k] = v
  end

  log.set_root(log.new({ handlers = M.log }))

  M.actions = merge_actions(require("overseer.task_list.actions"), newconf.actions)

  for _, v in util.iter_as_list(M.extensions) do
    extensions.register(v)
  end

  component.register_builtin()
  parsers.register_builtin()
  for k, v in pairs(M.component_sets) do
    component.alias(k, v)
  end
end

return M
