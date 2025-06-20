local config = require('gemini.config')
local util = require('gemini.util')
local api = require('gemini.api')

local M = {}

M.setup = function()
  if not config.get_config({ 'chat', 'enabled' }) then
    return
  end

  vim.api.nvim_create_user_command('GeminiChat', M.start_chat, {
    force = true,
    desc = 'Google Gemini',
    nargs = 1,
  })
end

M.start_chat = function(context)
  vim.api.nvim_command('tabnew')
  local user_text = context.args
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value('ft', 'markdown', { buf = bufnr })
  local lines = { 'Generating response...' }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local generation_config = config.get_gemini_generation_config()
  local text = ''
  local model_id = config.get_config({ 'model', 'model_id' })

  api.gemini_generate_content_stream(user_text, nil, model_id, generation_config, function(json_text, is_error)
    if is_error then
      vim.notify("GeminiChat stream error indicated by API.", vim.log.levels.ERROR)
      vim.schedule(function()
        -- Check if lines is still valid in case of multiple error signals
        if type(lines) == "table" then
            table.insert(lines, "\nError during streaming. Check :messages for details.")
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        else
            -- Fallback if lines is not a table (e.g. if error occurs very late)
            local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            table.insert(current_lines, "\nError during streaming. Check :messages for details.")
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_lines)
        end
      end)
      return
    end

    if not json_text then
      -- Stream finished (successfully or error already handled by is_error check)
      vim.notify("GeminiChat: Stream finished or json_text is nil.", vim.log.levels.DEBUG)
      return
    end

    local model_response = vim.json.decode(json_text)
    if not model_response then
      vim.notify("GeminiChat: Failed to decode JSON: " .. vim.inspect(json_text), vim.log.levels.WARN)
      return
    end

    model_response = util.table_get(model_response, { 'candidates', 1, 'content', 'parts', 1, 'text' })
    if not model_response then
      vim.notify("GeminiChat: Could not extract text from model response: " .. vim.inspect(json_text), vim.log.levels.DEBUG)
      return
    end

    text = text .. model_response
    vim.schedule(function()
      -- Ensure lines is updated correctly if it was modified by an error path
      -- Or, more simply, always re-split the accumulated text
      local current_display_lines = vim.split(text, '\n')
      -- Prepend the initial "Generating response..." if it's the first real update
      if #lines == 1 and lines[1] == 'Generating response...' and #current_display_lines > 0 then
          lines = current_display_lines
      else
          -- This logic might become complex if errors interleave; safer to just set
          lines = current_display_lines
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end)
  end)
end

return M
