local capability = require("overseer.capability")
local constants = require("overseer.constants")
local registry = require("overseer.registry")
local util = require("overseer.util")

local STATUS = constants.STATUS

local Task = {}

local next_id = 1

function Task.new(opts)
  opts = opts or {}
  vim.validate({
    cmd = { opts.cmd, "t" },
    cwd = { opts.cwd, "s", true },
    name = { opts.name, "s", true },
    capabilities = { opts.capabilities, "t", true },
  })

  if not opts.capabilities then
    opts.capabilities = { "default" }
  end
  -- Build the instance data for the task
  local data = {
    id = next_id,
    summary = "",
    result = nil,
    disposed = false,
    status = STATUS.PENDING,
    cmd = opts.cmd,
    cwd = opts.cwd,
    name = opts.name or table.concat(opts.cmd, " "),
    str_capabilities = capability.resolve(opts.capabilities),
    capabilities = capability.load(opts.capabilities),
  }
  next_id = next_id + 1
  local task = setmetatable(data, { __index = Task })
  task:dispatch("on_init")
  return task
end

-- Returns the arguments require to create a clone of this task
function Task:serialize()
  return {
    name = self.name,
    cmd = self.cmd,
    cwd = self.cwd,
    capabilities = self.str_capabilities,
  }
end

function Task:add_capability(cap)
  self:add_capabilities({ cap })
end

function Task:add_capabilities(capabilities)
  vim.validate({
    capabilities = { capabilities, "t" },
  })
  local new_caps = capability.resolve(capabilities, self.str_capabilities)
  for _, v in ipairs(capability.load(new_caps)) do
    table.insert(self.capabilities, v)
    if v.on_init then
      v:on_init(self)
    end
  end
  for _, v in ipairs(new_caps) do
    table.insert(self.str_capabilities, v)
  end
end

function Task:has_capability(name)
  vim.validate({ name = { name, "s" } })
  local new_caps = capability.resolve({ name }, self.str_capabilities)
  return vim.tbl_isempty(new_caps)
end

function Task:is_running()
  return self.status == STATUS.RUNNING
end

function Task:is_complete()
  return self.status ~= STATUS.PENDING and self.status ~= STATUS.RUNNING
end

function Task:reset()
  if self:is_running() then
    error("Cannot reset task while running")
    return
  end
  self.status = STATUS.PENDING
  self.result = nil
  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
  self.bufnr = nil
  self.summary = ""
  self:dispatch("on_reset")
end

function Task:dispatch(name, ...)
  for _, cap in ipairs(self.capabilities) do
    if type(cap[name]) == "function" then
      cap[name](cap, self, ...)
    end
  end
  registry.update_task(self)
end

function Task:_set_result(status, data)
  vim.validate({
    status = { status, "s" },
    data = { data, "t", true },
  })
  if not self:is_running() then
    return
  end
  self.status = status
  self.result = data
  self:dispatch("on_result", status, data)

  -- Cleanup
  -- Forcibly stop here because if we set the result before the process has
  -- exited, then we need to stop the process. Otherwise if we re-run the task
  -- the previous job may still be ongoing, and its callbacks will interfere
  -- with ours.
  vim.fn.jobstop(self.chan_id)
  self.chan_id = nil
  self:dispatch("on_finalize")
end

function Task:dispose()
  if self.disposed then
    return
  end
  self.disposed = true
  if self:is_running() then
    error("Cannot call dispose on running task")
  end
  self:dispatch("on_dispose")
  registry.remove_task(self)
  if vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
end

function Task:rerun(force_stop)
  vim.validate({ force_stop = { force_stop, "b", true } })
  if force_stop and self:is_running() then
    self:stop()
  end
  self:dispatch("on_request_rerun")
end

function Task:__on_exit(_job_id, code)
  if not self:is_running() then
    -- We've already finalized, so we probably canceled this task
    return
  end
  self:dispatch("on_exit", code)
  -- We shouldn't hit this unless the capabilities are missing a finalizer or
  -- they errored
  if self:is_running() then
    self:_set_result(STATUS.FAILURE, { error = "Task did not produce a result before exiting" })
  end
end

function Task:start()
  if self:is_complete() then
    vim.notify("Cannot start a task that has completed", vim.log.levels.ERROR)
    return false
  end
  if self:is_running() then
    return false
  end
  self.bufnr = vim.api.nvim_create_buf(false, true)
  local chan_id
  local mode = vim.api.nvim_get_mode().mode
  local stdout_iter = util.get_stdout_line_iter()
  local stderr_iter = util.get_stdout_line_iter()
  vim.api.nvim_buf_call(self.bufnr, function()
    chan_id = vim.fn.termopen(self.cmd, {
      stdin = "null",
      cwd = self.cwd,
      on_stdout = function(j, d)
        self:dispatch("on_stdout", d)
        local lines = stdout_iter(d)
        if not vim.tbl_isempty(lines) then
          self:dispatch("on_stdout_lines", lines)
        end
      end,
      on_stderr = function(j, d)
        self:dispatch("on_stderr", d)
        local lines = stderr_iter(d)
        if not vim.tbl_isempty(lines) then
          self:dispatch("on_stderr_lines", lines)
        end
      end,
      on_exit = function(j, c)
        self:__on_exit(j, c)
      end,
    })
  end)

  -- It's common to have autocmds that enter insert mode when opening a terminal
  -- This is a hack so we don't end up in insert mode after starting a task
  vim.defer_fn(function()
    local new_mode = vim.api.nvim_get_mode().mode
    if new_mode ~= mode then
      if string.find(new_mode, "i") == 1 then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, true, true), "n", false)
        if string.find(mode, "v") == 1 or string.find(mode, "V") == 1 then
          vim.cmd([[normal! gv]])
        end
      end
    end
  end, 10)

  if chan_id == 0 then
    vim.notify(string.format("Invalid arguments for task '%s'", self.name), vim.log.levels.ERROR)
    return false
  elseif chan_id == -1 then
    vim.notify(
      string.format("Command '%s' not executable", vim.inspect(self.cmd)),
      vim.log.levels.ERROR
    )
    return false
  else
    self.chan_id = chan_id
    self.status = STATUS.RUNNING
    self:dispatch("on_start")
    return true
  end
end

function Task:stop()
  if not self:is_running() then
    return false
  end
  self:_set_result(STATUS.CANCELED)
  return true
end

return Task
