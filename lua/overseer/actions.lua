local config = require("overseer.config")
local constants = require("overseer.constants")
local layout = require("overseer.layout")
local task_bundle = require("overseer.task_bundle")
local task_list = require("overseer.task_list")
local task_editor = require("overseer.task_editor")
local util = require("overseer.util")
local STATUS = constants.STATUS
local SLOT = constants.SLOT

local M = {}

M.actions = {
  start = {
    condition = function(task)
      return task.status == STATUS.PENDING
    end,
    run = function(task)
      task:start()
    end,
  },
  stop = {
    condition = function(task)
      return task.status == STATUS.RUNNING
    end,
    run = function(task)
      task:stop()
    end,
  },
  save = {
    description = "save the task to a bundle file",
    condition = function(task)
      return true
    end,
    run = function(task)
      task_bundle.save_task_bundle(nil, { task })
    end,
  },
  rerun = {
    condition = function(task)
      return task:has_component("on_rerun_handler")
        and task.status ~= STATUS.PENDING
        and task.status ~= STATUS.RUNNING
    end,
    run = function(task)
      task:rerun()
    end,
  },
  dispose = {
    condition = function(task)
      return true
    end,
    run = function(task)
      task:dispose(true)
    end,
  },
  edit = {
    condition = function(task)
      return task.status ~= STATUS.RUNNING
    end,
    run = function(task)
      task_editor.open(task, function(t)
        if t then
          task_list.update(t)
        end
      end)
    end,
  },
  ensure = {
    description = "rerun the task if it fails",
    condition = function(task)
      return true
    end,
    run = function(task)
      task:add_components({ "on_rerun_handler", "on_result_rerun" })
      if task.status == STATUS.FAILURE then
        task:rerun()
      end
    end,
  },
  watch = {
    description = "rerun the task when you save a file",
    condition = function(task)
      return task:has_component("on_rerun_handler") and not task:has_component("rerun_on_save")
    end,
    run = function(task)
      vim.ui.input({
        prompt = "Directory (watch these files)",
        completion = "file",
        default = vim.fn.getcwd(0),
      }, function(dir)
        task:remove_by_slot(SLOT.DISPOSE)
        task:set_components({
          { "on_rerun_handler", interrupt = true },
          { "rerun_on_save", dir = dir },
        })
        task_list.update(task)
      end)
    end,
  },
  ["open float"] = {
    description = "open terminal in a floating window",
    condition = function(task)
      return task.bufnr and vim.api.nvim_buf_is_valid(task.bufnr)
    end,
    run = function(task)
      local padding = 2
      local width = layout.get_editor_width() - 2 - 2 * padding
      local height = layout.get_editor_height() - 2 * padding
      local row = padding
      local col = padding
      local winid = vim.api.nvim_open_win(task.bufnr, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        border = "rounded",
        style = "minimal",
      })
      vim.api.nvim_win_set_option(winid, "winblend", 10)
      vim.api.nvim_create_autocmd("BufLeave", {
        desc = "Close float on BufLeave",
        buffer = task.bufnr,
        once = true,
        nested = true,
        callback = function()
          pcall(vim.api.nvim_win_close, winid, true)
        end,
      })
    end,
  },
  open = {
    description = "open terminal in the current window",
    condition = function(task)
      return task.bufnr and vim.api.nvim_buf_is_valid(task.bufnr)
    end,
    run = function(task)
      vim.cmd([[normal! m']])
      vim.api.nvim_win_set_buf(0, task.bufnr)
    end,
  },
  ["open vsplit"] = {
    description = "open terminal in a vertical split",
    condition = function(task)
      return task.bufnr and vim.api.nvim_buf_is_valid(task.bufnr)
    end,
    run = function(task)
      vim.cmd([[vsplit]])
      vim.api.nvim_win_set_buf(0, task.bufnr)
    end,
  },
  ["set quickfix diagnostics"] = {
    description = "put the diagnostics results into quickfix",
    condition = function(task)
      return task.result
        and task.result.diagnostics
        and not vim.tbl_isempty(task.result.diagnostics)
    end,
    run = function(task)
      vim.fn.setqflist(task.result.diagnostics)
    end,
  },
  ["set loclist diagnostics"] = {
    description = "put the diagnostics results into loclist",
    condition = function(task)
      return task.result
        and task.result.diagnostics
        and not vim.tbl_isempty(task.result.diagnostics)
    end,
    run = function(task)
      local winid = util.find_code_window()
      vim.fn.setloclist(winid, task.result.diagnostics)
    end,
  },
  ["set quickfix stacktrace"] = {
    description = "put the stacktrace result into quickfix",
    condition = function(task)
      return task.result and task.result.stacktrace and not vim.tbl_isempty(task.result.stacktrace)
    end,
    run = function(task)
      vim.fn.setqflist(task.result.stacktrace)
    end,
  },
  ["set loclist stacktrace"] = {
    description = "put the stacktrace result into loclist",
    condition = function(task)
      return task.result and task.result.stacktrace and not vim.tbl_isempty(task.result.stacktrace)
    end,
    run = function(task)
      local winid = util.find_code_window()
      vim.fn.setloclist(winid, task.result.stacktrace)
    end,
  },
}

M.run_action = function(task, name)
  local actions = {}
  local longest_name = 1
  for k, action in pairs(config.actions) do
    if action.condition(task) then
      if k == name then
        action.run(task)
        task_list.update(task)
        return
      end
      action.name = k
      local name_len = vim.api.nvim_strwidth(k)
      if name_len > longest_name then
        longest_name = name_len
      end
      table.insert(actions, action)
    end
  end
  if name then
    vim.notify(string.format("Cannot %s task", name), vim.log.levels.WARN)
    return
  end
  table.sort(actions, function(a, b)
    return a.name < b.name
  end)

  task:inc_reference()
  vim.ui.select(actions, {
    prompt = string.format("Actions: %s", task.name),
    kind = "overseer_task_options",
    format_item = function(action)
      if action.description then
        return string.format("%s (%s)", util.ljust(action.name, longest_name), action.description)
      else
        return action.name
      end
    end,
  }, function(action)
    task:dec_reference()
    if action then
      if action.condition(task) then
        action.run(task)
        task_list.update(task)
      else
        vim.notify(
          string.format("Can no longer perform action '%s' on task", action.name),
          vim.log.levels.WARN
        )
      end
    end
  end)
end

return M
