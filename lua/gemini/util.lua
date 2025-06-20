local M = {}

M.borderchars = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' }

M.open_window = function(content, options)
  local popup = require('plenary.popup')
  options.borderchars = M.borderchars
  local win_id, result = popup.create(content, options)
  local bufnr = vim.api.nvim_win_get_buf(win_id)
  local border = result.border
  vim.api.nvim_set_option_value('ft', 'markdown', { buf = bufnr })
  vim.api.nvim_set_option_value('wrap', true, { win = win_id })

  local close_popup = function()
    vim.api.nvim_win_close(win_id, true)
  end

  local keys = { '<C-q>', 'q' }
  for _, key in pairs(keys) do
    vim.api.nvim_buf_set_keymap(bufnr, 'n', key, '', {
      silent = true,
      callback = close_popup,
    })
  end
  return win_id, bufnr, border
end

M.treesitter_has_lang = function(bufnr)
  local filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  local lang = vim.treesitter.language.get_lang(filetype)
  return lang ~= nil
end

M.find_node_by_type = function(node_type)
  local node = vim.treesitter.get_node()
  while node do
    local type = node:type()
    if string.find(type, node_type) then
      return node
    end

    local parent = node:parent()
    if parent == node then
      break
    end
    node = parent
  end
  return nil
end

M.debounce = function(callback, timeout)
  local timer = nil
  local f = function(...)
    local t = { ... }
    local handler = function()
      callback(unpack(t))
    end

    if timer ~= nil then
      timer:stop()
    end
    timer = vim.defer_fn(handler, timeout)
  end
  return f
end

M.table_get = function(t, id)
  if type(id) ~= 'table' then return M.table_get(t, { id }) end
  local success, res = true, t
  for _, i in ipairs(id) do
    success, res = pcall(function() return res[i] end)
    if not success or res == nil then return end
  end
  return res
end

M.is_blacklisted = function(blacklist, filetype)
  for _, ft in ipairs(blacklist) do
    if string.find(filetype, ft, 1, true) ~= nil then
      return true
    end
  end
  return false
end

M.strip_code = function(text)
  local code_blocks = {}
  local pattern = "```(%w+)%s*(.-)%s*```"
  for _, code_block in text:gmatch(pattern) do
    table.insert(code_blocks, code_block)
  end
  return code_blocks
end

local function get_log_level_str(level_num)
  for name, num in pairs(vim.log.levels) do
    if num == level_num then
      return name
    end
  end
  return "UNKNOWN_LEVEL(" .. tostring(level_num) .. ")"
end

M.log = function(level, ...)
  local args = {...}
  local force_notify_explicit = nil -- nil means not set, true means force, false means never
  local message_start_index = 1

  if #args > 0 and type(args[1]) == "boolean" then
    force_notify_explicit = args[1]
    message_start_index = 2
  end

  local msg_parts_slice = {}
  for i = message_start_index, #args do
    table.insert(msg_parts_slice, args[i])
  end

  local msg_parts = vim.tbl_map(function(val)
    if type(val) == "table" or type(val) == "function" then
      return vim.inspect(val)
    else
      return tostring(val)
    end
  end, msg_parts_slice)
  local message = table.concat(msg_parts, " ")

  local config = require('gemini.config')
  local log_file_path = config.get_config({ 'logging', 'file_path' })
  local configured_log_level = config.get_config({ 'logging', 'level' })

  if configured_log_level == nil then
    configured_log_level = vim.log.levels.INFO
  end

  if log_file_path and level <= configured_log_level then
    local timestamp = os.date("[%Y-%m-%d %H:%M:%S]")
    local level_str = get_log_level_str(level)
    local log_line = string.format("%s [%s] %s\n", timestamp, level_str, message)

    local file, err_io = io.open(log_file_path, "a")
    if file then
      local _, err_write = file:write(log_line)
      local _, err_close = file:close()
      if err_write then
        vim.notify("gemini.nvim: Error writing to log file '" .. log_file_path .. "': " .. tostring(err_write), vim.log.levels.ERROR)
      end
      if err_close then
         vim.notify("gemini.nvim: Error closing log file '" .. log_file_path .. "': " .. tostring(err_close), vim.log.levels.ERROR)
      end
    else
      vim.notify("gemini.nvim: Failed to open log file '" .. log_file_path .. "': " .. tostring(err_io), vim.log.levels.ERROR)
    end
  end

  local should_notify_on_screen = false
  if force_notify_explicit == true then
    should_notify_on_screen = true
  elseif force_notify_explicit == false then
    should_notify_on_screen = false -- Explicitly told not to notify
  else -- force_notify_explicit is nil (not set)
    if not log_file_path or log_file_path == "" then -- File logging is off, so notify
      should_notify_on_screen = true
    else -- File logging is on, notify only for WARN or ERROR by default
      if level <= vim.log.levels.WARN then
        should_notify_on_screen = true
      end
    end
  end

  if should_notify_on_screen then
    vim.notify(message, level)
  end
end

return M
