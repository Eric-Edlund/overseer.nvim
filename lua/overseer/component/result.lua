local constants = require("overseer.constants")
local parser = require("overseer.parser")
local parsers = require("overseer.parsers")
local util = require("overseer.util")
local STATUS = constants.STATUS
local M = {}

M.result_exit_code = {
  name = "result_exit_code",
  description = "Sets status based on exit code",
  params = {
    success_codes = { type = "list", optional = true },
    parser = { optional = true },
  },
  constructor = function(params)
    local success_codes = vim.tbl_map(function(code)
      return tonumber(code)
    end, params.success_codes or {})
    table.insert(success_codes, 0)
    return {
      parser = parsers.get_parser(params.parser),
      on_init = function(self, task)
        if self.parser then
          local cb = function(key, result)
            task:dispatch("on_stream_result", key, result)
          end
          self.parser:subscribe(cb)
          self.parser_sub = cb
        end
      end,
      on_dispose = function(self)
        if self.parser and self.parser_sub then
          self.parser:unsubscribe(self.parser_sub)
          self.parser_sub = nil
        end
      end,
      on_reset = function(self)
        if self.parser then
          self.parser:reset()
        end
      end,
      on_output_lines = function(self, task, lines)
        if self.parser then
          self.parser:ingest(lines)
        end
      end,
      on_exit = function(self, task, code)
        local status = vim.tbl_contains(success_codes, code) and STATUS.SUCCESS or STATUS.FAILURE
        local result
        if self.parser then
          result = self.parser:get_result()
        else
          result = task.result or {}
        end
        task:set_result(status, result)
      end,
    }
  end,
}

M.result_with_parser_constructor = function(parser_defn)
  return function()
    return {
      parser = parser.new(parser_defn),
      on_reset = function(self)
        self.parser:reset()
      end,
      on_output_lines = function(self, task, lines)
        self.parser:ingest(lines)
      end,
      on_exit = function(self, task, code)
        local status = code == 0 and STATUS.SUCCESS or STATUS.FAILURE
        task:set_result(status, self.parser:get_result())
      end,
    }
  end
end

-- Looks for a result value of 'diagnostics' that is a list of quickfix items
M.on_result_diagnostics_quickfix = {
  name = "on_result_diagnostics_quickfix",
  description = "Put result diagnostics into the quickfix",
  params = {
    use_loclist = { type = "bool", optional = true },
  },
  constructor = function(params)
    return {
      on_result = function(self, task, status, result)
        if not result.diagnostics or vim.tbl_isempty(result.diagnostics) then
          return
        end
        if params.use_loclist then
          vim.fn.setloclist(0, result.diagnostics)
        else
          vim.fn.setqflist(result.diagnostics)
        end
      end,
    }
  end,
}

-- Looks for a result value of 'stacktrace' that is a list of quickfix items
M.on_result_stacktrace_quickfix = {
  name = "on_result_stacktrace_quickfix",
  description = "Put result stacktrace into the quickfix",
  constructor = function()
    return {
      on_result = function(self, task, status, result)
        if not result.stacktrace or vim.tbl_isempty(result.stacktrace) then
          return
        end
        vim.fn.setqflist(result.stacktrace)
      end,
    }
  end,
}

-- Looks for a result value of 'diagnostics' that is a list of quickfix items
M.on_result_diagnostics = {
  name = "on_result_diagnostics",
  description = "Display the result diagnostics",
  params = {
    virtual_text = { type = "bool", optional = true },
    signs = { type = "bool", optional = true },
    underline = { type = "bool", optional = true },
    remove_during_rerun = {
      type = "bool",
      optional = true,
      description = "Remove diagnostics while task is rerunning",
    },
  },
  constructor = function(params)
    local function remove_diagnostics(self)
      for _, bufnr in ipairs(self.bufnrs) do
        vim.diagnostic.reset(self.ns, bufnr)
      end
      self.bufnrs = {}
    end
    return {
      bufnrs = {},
      on_init = function(self, task)
        self.ns = vim.api.nvim_create_namespace(task.name)
      end,
      on_result = function(self, task, status, result)
        remove_diagnostics(self)
        if not result.diagnostics or vim.tbl_isempty(result.diagnostics) then
          return
        end
        local grouped = util.tbl_group_by(result.diagnostics, "filename")
        for filename, items in pairs(grouped) do
          local diagnostics = {}
          for _, item in ipairs(items) do
            table.insert(diagnostics, {
              message = item.text,
              severity = item.type == "W" and vim.diagnostic.severity.WARN
                or vim.diagnostic.severity.ERROR,
              lnum = (item.lnum or 1) - 1,
              end_lnum = item.end_lnum and (item.end_lnum - 1),
              col = item.col or 0,
              end_col = item.end_col,
              source = task.name,
            })
          end
          local bufnr = vim.fn.bufadd(filename)
          if bufnr then
            vim.diagnostic.set(self.ns, bufnr, diagnostics, {
              virtual_text = params.virtual_text,
              signs = params.signs,
              underline = params.underline,
            })
            table.insert(self.bufnrs, bufnr)
            if not vim.api.nvim_buf_is_loaded(bufnr) then
              util.set_bufenter_callback(bufnr, "diagnostics_show", function()
                vim.diagnostic.show(self.ns, bufnr)
              end)
            end
          else
            vim.notify(string.format("Could not find file '%s'", filename), vim.log.levels.WARN)
          end
        end
      end,
      on_reset = function(self, task)
        if params.remove_during_rerun then
          remove_diagnostics(self)
        end
      end,
      on_dispose = function(self, task)
        remove_diagnostics(self)
      end,
    }
  end,
}

return M
