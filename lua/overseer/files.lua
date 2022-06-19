local util = require("overseer.util")
local M = {}

---@type boolean
M.is_windows = vim.loop.os_uname().version:match("Windows")

---@type boolean
M.is_mac = vim.loop.os_uname().sysname == "Darwin"

---@type string
M.sep = M.is_windows and "\\" or "/"

---@param filepath string
---@return boolean
M.exists = function(filepath)
  local stat = vim.loop.fs_stat(filepath)
  return stat ~= nil and stat.type ~= nil
end

---@return string
M.join = function(...)
  return table.concat({ ... }, M.sep)
end

---@param dir string
---@param path string
---@return boolean
M.is_subpath = function(dir, path)
  return string.sub(path, 0, string.len(dir)) == dir
end

M.get_stdpath_filename = function(stdpath, ...)
  local ok, dir = pcall(vim.fn.stdpath, stdpath)
  if not ok then
    if stdpath == "log" then
      return M.get_stdpath_filename("cache", ...)
    elseif stdpath == "state" then
      return M.get_stdpath_filename("data", ...)
    else
      error(dir)
    end
  end
  return M.join(dir, ...)
end

---@param filepath string
---@return string?
M.read_file = function(filepath)
  if not M.exists(filepath) then
    return nil
  end
  local fd = vim.loop.fs_open(filepath, "r", 420) -- 0644
  local stat = vim.loop.fs_fstat(fd)
  local content = vim.loop.fs_read(fd, stat.size)
  vim.loop.fs_close(fd)
  return content
end

---@param data_dir "cache"|"config"|"data"|"log"
---@param basename string
---@return string
M.gen_random_filename = function(data_dir, basename)
  local num = 0
  for _ = 1, 5 do
    num = 10 * num + math.random(0, 9)
  end
  return M.get_stdpath_filename(data_dir, "overseer", basename:format(num))
end

---@param filepath string
---@return any?
M.load_json_file = function(filepath)
  local content = M.read_file(filepath)
  if content then
    return util.decode_json(content)
  end
end

---@param dirname string
---@param perms? number
M.mkdir = function(dirname, perms)
  if not perms then
    perms = 493 -- 0755
  end
  if not M.exists(dirname) then
    local parent = vim.fn.fnamemodify(dirname, ":h")
    if not M.exists(parent) then
      M.mkdir(parent)
    end
    vim.loop.fs_mkdir(dirname, perms)
  end
end

---@param filename string
---@param contents string
M.write_file = function(filename, contents)
  M.mkdir(vim.fn.fnamemodify(filename, ":h"))
  local fd = vim.loop.fs_open(filename, "w", 420) -- 0644
  vim.loop.fs_write(fd, contents)
  vim.loop.fs_close(fd)
end

---@param filename string
M.delete_file = function(filename)
  if M.exists(filename) then
    vim.loop.fs_unlink(filename)
    return true
  end
end

---@param filename string
---@param obj any
M.write_json_file = function(filename, obj)
  M.write_file(filename, vim.json.encode(obj))
end

return M
