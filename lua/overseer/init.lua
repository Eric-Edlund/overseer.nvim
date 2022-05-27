local commands = require("overseer.commands")
local config = require("overseer.config")
local constants = require("overseer.constants")
local task_bundle = require("overseer.task_bundle")
local task_list = require("overseer.task_list")
local Task = require("overseer.task")
local window = require("overseer.window")
local M = {}

-- TODO
-- * OverseerSaveBundle should prompt before overwrite
-- * { } to navigate task list
-- * Integration with system notifications
-- * Create a task history. Save history to file, and add command to quick-rerun tasks from history
-- * Save task should prompt to append to existing bundle file
-- * Bump task to top when rerunning
-- * Statusline integration for task status
-- * Many more task templates, especially for tests
-- * Load VSCode task definitions
-- * Add tests
-- * keybinding help in float
-- * More schema validations (callback, non-empty list, number greater than, enum, list[enum])
-- * List fields should allow configurable sep (e.g. ' ' for cmd, but ', ' for others)
-- * Pull as much logic out of the closures as possible
-- * Add nearest-test support detecting via treesitter
-- * Dynamic window sizing for task editor
-- * integrate with vim-test as a strategy
-- * Basic Readme
-- * Vim help docs
-- * Architecture doc (Template / Task / Component)
-- * Extension doc (how to make your own template/component)

M.setup = function(opts)
  config.setup(opts)
  commands.create_commands()
  vim.cmd([[
    hi default link OverseerPENDING Normal
    hi default link OverseerRUNNING Constant
    hi default link OverseerSUCCESS DiagnosticInfo
    hi default link OverseerCANCELED DiagnosticWarn
    hi default link OverseerFAILURE DiagnosticError
    hi default link OverseerTask Title
    hi default link OverseerTaskBorder FloatBorder
    hi default link OverseerOutput Normal
    hi default link OverseerSlot String
    hi default link OverseerComponent Constant
    hi default link OverseerField Keyword
  ]])
  local aug = vim.api.nvim_create_augroup("Overseer", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = "SessionSavePre",
    desc = "Save task state when vim-session saves",
    group = aug,
    callback = function()
      local cmds = vim.g.session_save_commands
      local tasks = task_list.serialize_tasks()
      if vim.tbl_isempty(tasks) then
        return
      end
      table.insert(cmds, '" overseer.nvim')
      local data = string.gsub(vim.json.encode(tasks), "\\/", "/")
      data = string.gsub(data, "'", "\\'")
      table.insert(
        cmds,
        -- For some reason, vim.json.encode encodes / as \/.
        string.format("lua require('overseer')._start_tasks('%s')", data)
      )
      vim.g.session_save_commands = cmds
    end,
  })
end

M.new_task = Task.new

M.toggle = window.toggle
M.open = window.open
M.close = window.close

M.list_task_bundles = task_bundle.list_task_bundles
M.load_task_bundle = task_bundle.load_task_bundle
M.save_task_bundle = task_bundle.save_task_bundle
M.delete_task_bundle = task_bundle.delete_task_bundle

M.run_template = commands.run_template

-- Re-export the constants
for k, v in pairs(constants) do
  M[k] = v
end

-- Used for vim-session integration.
local timer_active = false
M._start_tasks = function(str)
  -- HACK for some reason vim-session first SessionSavePre multiple times, which
  -- can lead to multiple 'load' lines in the same session file. We need to make
  -- sure we only take the first one.
  if timer_active then
    return
  end
  timer_active = true
  vim.defer_fn(function()
    local data = vim.json.decode(str)
    for _, params in ipairs(data) do
      local task = Task.new(params)
      task:start()
    end
    timer_active = false
  end, 100)
end

setmetatable(M, {
  __index = function(t, key)
    local ok, val = pcall(require, string.format("overseer.%s", key))
    if ok then
      rawset(t, key, val)
      return val
    else
      error(string.format("Error requiring overseer.%s: %s", key, val))
    end
  end,
})

return M
