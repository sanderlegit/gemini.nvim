local config = require('gemini.config')
local util = require('gemini.util')

local M = {}

local function is_nvim_version_ge(major, minor, patch)
  local v = vim.version()
  if v.major > major then
    return true
  elseif v.major == major then
    if v.minor > 9 then -- Note: This should likely be v.minor > minor, or handle 0.10.0 correctly
      return true
    elseif v.minor == minor and v.patch >= patch then
      return true
    end
  end
  return false
end

M.setup = function(opts)
  config.set_config(opts) -- Set config early so util.log can access it

  if not vim.fn.executable('curl') then
    util.log(vim.log.levels.WARN, true, 'curl is not found')
    return
  end

  if not is_nvim_version_ge(0, 9, 1) then
    util.log(vim.log.levels.WARN, true, 'neovim version too old, requires 0.9.1+')
    return
  end

  util.log(vim.log.levels.INFO, true, "gemini.nvim setup initiated.")

  require('gemini.chat').setup()
  require('gemini.instruction').setup()
  require('gemini.hint').setup()
  require('gemini.completion').setup()
  require('gemini.task').setup()

  vim.api.nvim_create_user_command('GeminiOpenLogs', function()
    local log_file_path = config.get_config({ 'logging', 'file_path' })
    if log_file_path and #log_file_path > 0 then
      vim.cmd('vsplit ' .. vim.fn.fnameescape(log_file_path))
    else
      util.log(vim.log.levels.WARN, true, "Gemini log file path is not configured. Set 'logging.file_path' in your setup options.")
    end
  end, {
    force = true,
    desc = 'Open the gemini.nvim log file, if configured.',
  })

  util.log(vim.log.levels.INFO, true, "gemini.nvim setup complete.")
end

return M
