local constants = require("overseer.constants")
local STATUS = constants.STATUS
local CATEGORY = constants.CATEGORY
local M = {}

M.NOTIFY = {
  NEVER = 'never',
  SUCCESS_FAILURE = 'success_failure',
  ALWAYS = 'always',
  SUCCESS = 'success',
  FAILURE = 'failure',
}

M.new_on_result_notifier = function(opts)
  opts = opts or {}
  vim.validate({
    when = { opts.when, 's', true},
    format = { opts.format, 'f', true},
  })
  return {
    name = 'notify on result',
    category = CATEGORY.NOTIFY,
    when = opts.when or M.NOTIFY.SUCCESS_FAILURE,
    format = opts.format,
    on_result = function(self, task, status)
      M.vim_notify_from_status(task, status, self.when, self.format)
    end
  }
end

M.get_level_from_status = function(status)
  if status == STATUS.FAILURE then
    return vim.log.levels.ERROR
  elseif status == STATUS.STOPPED then
    return vim.log.levels.WARN
  else
    return vim.log.levels.INFO
  end
end

M.vim_notify_from_status = function(task, status, enum, format)
  enum = enum or M.NOTIFY.ALWAYS
  if enum == M.NOTIFY.ALWAYS or ((enum == M.NOTIFY.SUCCESS or enum == M.NOTIFY.SUCCESS_FAILURE) and status == STATUS.SUCCESS) or ((enum == M.NOTIFY.FAILURE or enum == M.NOTIFY.SUCCESS_FAILURE) and status == STATUS.FAILURE) then
    local level = M.get_level_from_status(status)
    if format then
      vim.notify(format(task), level)
    else
      vim.notify(string.format("%s %s", status, task.name), level)
    end
    return true
  end
  return false
end

return M
