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
      util.log(vim.log.levels.ERROR, 'GeminiChat stream error indicated by API.')
      vim.schedule(function()
        local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        table.insert(current_lines, '')
        table.insert(current_lines, 'Error during streaming. Check :messages for details.')
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_lines)
      end)
      return
    end

    if not json_text then
      util.log(vim.log.levels.DEBUG, false, 'GeminiChat: Stream finished or json_text is nil.')
      return
    end

    local model_response = vim.json.decode(json_text)
    if not model_response then
      util.log(vim.log.levels.WARN, 'GeminiChat: Failed to decode JSON: ', vim.inspect(json_text))
      return
    end

    model_response = util.table_get(model_response, { 'candidates', 1, 'content', 'parts', 1, 'text' })
    if not model_response then
      util.log(vim.log.levels.DEBUG, false, 'GeminiChat: Could not extract text from model response: ', vim.inspect(json_text))
      return
    end

    text = text .. model_response
    vim.schedule(function()
      -- To prevent issues with CRLF, normalize to LF
      local display_text = text:gsub('\r\n', '\n')
      local current_display_lines = vim.split(display_text, '\n')
      -- Overwrite the buffer with the updated full text
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_display_lines)
    end)
  end)
end

return M
