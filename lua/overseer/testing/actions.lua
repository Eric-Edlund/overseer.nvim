local data = require("overseer.testing.data")
local integrations = require("overseer.testing.integrations")
local layout = require("overseer.layout")
local util = require("overseer.util")
local tutils = require("overseer.testing.utils")
local TEST_STATUS = data.TEST_STATUS

local M

M = {
  rerun = {
    condition = function(entry)
      return entry.type ~= "test" or entry.test.status ~= TEST_STATUS.RUNNING
    end,
    run = function(entry)
      if entry.type == "test" then
        local test = entry.test
        local integ = integrations.get_by_name(test.integration)
        integrations.create_and_start_task(integ, integ:run_single_test(test), { tests = { test } })
      elseif entry.type == "group" then
        local integ = integrations.get_by_name(entry.integration)
        if integ.run_test_group then
          integrations.create_and_start_task(
            integ,
            integ:run_test_group(entry.path),
            { group = entry.path }
          )
        else
          -- FIXME run test groups for integrations with no built-in support
          data.reset_group_status(entry.integration, entry.path, TEST_STATUS.NONE)
        end
      end
    end,
  },
  ["open vsplit"] = {
    description = "open test result in a vertical split",
    condition = function(entry)
      return entry.type == "test"
    end,
    run = function(entry)
      vim.cmd([[vsplit]])
      vim.api.nvim_win_set_buf(0, tutils.create_test_result_buffer(entry.test))
    end,
  },
  ["open float"] = {
    description = "open test result in a floating window",
    condition = function(entry)
      return entry.type == "test"
    end,
    run = function(entry)
      local bufnr = tutils.create_test_result_buffer(entry.test)
      layout.open_fullscreen_float(bufnr)
    end,
  },
  ["set quickfix stacktrace"] = {
    description = "put the stacktrace result into quickfix",
    condition = function(entry)
      return entry.type == "test" and entry.test.stacktrace
    end,
    run = function(entry)
      vim.fn.setqflist(entry.test.stacktrace)
    end,
  },
  ["set loclist stacktrace"] = {
    description = "put the stacktrace result into loclist",
    condition = function(entry)
      return entry.type == "test" and entry.test.stacktrace
    end,
    run = function(entry)
      local winid = util.find_code_window()
      vim.fn.setloclist(winid, entry.test.stacktrace)
    end,
  },
}

return M
