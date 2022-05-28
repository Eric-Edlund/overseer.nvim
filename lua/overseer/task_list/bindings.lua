local M = {}

M.keys = {
  {
    lhs = "?",
    mode = "n",
    desc = "Show default key bindings",
    rhs = function(sidebar)
      sidebar:show_bindings()
    end,
  },
  {
    lhs = "<CR>",
    mode = "n",
    desc = "Open task action menu",
    rhs = function(sidebar)
      sidebar:run_action()
    end,
  },
  {
    lhs = "<C-e>",
    mode = "n",
    desc = "Edit task",
    rhs = function(sidebar)
      sidebar:run_action("edit")
    end,
  },
  {
    lhs = "o",
    mode = "n",
    desc = "Open task terminal in current window",
    rhs = function(sidebar)
      sidebar:run_action("open")
    end,
  },
  {
    lhs = "<C-v>",
    mode = "n",
    desc = "Open task terminal in a vsplit",
    rhs = function(sidebar)
      sidebar:run_action("open vsplit")
    end,
  },
  {
    lhs = "<C-f>",
    mode = "n",
    desc = "Open task terminal in a floating window",
    rhs = function(sidebar)
      sidebar:run_action("open float")
    end,
  },
  {
    lhs = "p",
    mode = "n",
    desc = "Toggle task terminal in a preview window",
    rhs = function(sidebar)
      sidebar:toggle_preview()
    end,
  },
  {
    lhs = "<C-l>",
    mode = "n",
    desc = "Increase task detail level",
    rhs = function(sidebar)
      sidebar:change_task_detail(1)
    end,
  },
  {
    lhs = "<C-h>",
    mode = "n",
    desc = "Decrease task detail level",
    rhs = function(sidebar)
      sidebar:change_task_detail(-1)
    end,
  },
  {
    lhs = "L",
    mode = "n",
    desc = "Increase all task detail levels",
    rhs = function(sidebar)
      sidebar:change_default_detail(1)
    end,
  },
  {
    lhs = "H",
    mode = "n",
    desc = "Decrease all task detail levels",
    rhs = function(sidebar)
      sidebar:change_default_detail(-1)
    end,
  },
  {
    lhs = "[",
    mode = "n",
    desc = "Decrease window width",
    rhs = function()
      local width = vim.api.nvim_win_get_width(0)
      vim.api.nvim_win_set_width(0, math.max(10, width - 10))
    end,
  },
  {
    lhs = "]",
    mode = "n",
    desc = "Increase window width",
    rhs = function()
      local width = vim.api.nvim_win_get_width(0)
      vim.api.nvim_win_set_width(0, math.max(10, width + 10))
    end,
  },
  {
    lhs = "{",
    mode = { "n", "v" },
    desc = "Jump to previous task",
    rhs = function(sidebar)
      sidebar:jump(-1)
    end,
  },
  {
    lhs = "}",
    mode = { "n", "v" },
    desc = "Jump to next task",
    rhs = function(sidebar)
      sidebar:jump(1)
    end,
  },
}

return M
