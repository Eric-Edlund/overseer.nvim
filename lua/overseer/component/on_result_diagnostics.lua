local util = require("overseer.util")

-- Looks for a result value of 'diagnostics' that is a list of quickfix items
return {
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
