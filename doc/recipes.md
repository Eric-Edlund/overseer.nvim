# Recipes

Have a cool recipe to share? Open a pull request and add it to this doc!

<!-- TOC -->

- [Restart last task](#restart-last-task)
- [Run shell scripts in the current directory](#run-shell-scripts-in-the-current-directory)
- [Directory-local tasks with nvim-config-local](#directory-local-tasks-with-nvim-config-local)

<!-- /TOC -->

## Restart last task

This command restarts the most recent overseer task

```lua
vim.api.nvim_create_user_command("OverseerRestartLast", function()
  local overseer = require("overseer")
  local tasks = overseer.list_tasks({ recent_first = true })
  if vim.tbl_isempty(tasks) then
    vim.notify("No tasks found", vim.log.levels.WARN)
  else
    overseer.run_action(tasks[1], "restart")
  end
end, {})
```

## Run shell scripts in the current directory

This template will find all shell scripts in the current directory and create tasks for them

```lua
local files = require("overseer.files")

return {
  generator = function(opts, cb)
    local scripts = vim.tbl_filter(function(filename)
      return filename:match("%.sh$")
    end, files.list_files(opts.dir))
    local ret = {}
    for _, filename in ipairs(scripts) do
      table.insert(ret, {
        name = filename,
        params = {
          args = { optional = true, type = "list", delimiter = " " },
        },
        builder = function(params)
          return {
            cmd = { files.join(opts.dir, filename) },
            args = params.args,
          }
        end,
      })
    end

    cb(ret)
  end,
}
```

## Directory-local tasks with nvim-config-local

If you have [nvim-config-local](https://github.com/klen/nvim-config-local) installed, you can add directory-local tasks like so:

```lua
-- /path/to/dir/.vimrc.lua

require("overseer").register_template({
  name = "My project task",
  params = {},
  condition = {
    -- This makes the template only available in the current directory
    dir = vim.fn.getcwd(),
  },
  builder = function()
    return {
      cmd = {"echo"},
      args = {"Hello", "world"},
    }
  end,
})
```
