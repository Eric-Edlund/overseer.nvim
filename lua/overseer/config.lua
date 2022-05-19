local M = {}

M.setup = function(opts)
  -- pass
  require("overseer.capability").alias(
    "default",
    { "output_summary", "exit_code", "notify_success_failure", "rerun_trigger" }
  )
end

M.get_default_notifier = function()
  local notify = require("overseer.notify")
  return notify.new_on_result_notifier()
end

M.get_default_summarizer = function()
  local result = require("overseer.result")
  return result.new_output_summarizer()
end

M.get_default_finalizer = function()
  local result = require("overseer.result")
  return result.new_exit_code_finalizer()
end

M.get_default_rerunner = function()
  local rerun = require("overseer.rerun")
  return rerun.new_rerun_on_trigger()
end

return M
