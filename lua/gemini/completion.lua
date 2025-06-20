local config = require('gemini.config')
local util = require('gemini.util')
local api = require('gemini.api')

local M = {}

local context = {
  namespace_id = nil,
  completion = nil,
}

M.setup = function()
  if not config.get_config({ 'completion', 'enabled' }) then
    return
  end

  local blacklist_filetypes = config.get_config({ 'completion', 'blacklist_filetypes' }) or {}
  local blacklist_filenames = config.get_config({ 'completion', 'blacklist_filenames' }) or {}

  context.namespace_id = vim.api.nvim_create_namespace('gemini_completion')

  if config.get_config({ 'completion', 'auto_trigger' }) then
    vim.api.nvim_create_autocmd('CursorMovedI', {
      callback = function()
        local buf = vim.api.nvim_get_current_buf()
        local filetype = vim.api.nvim_get_option_value('filetype', { buf = buf })
        local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
        if util.is_blacklisted(blacklist_filetypes, filetype) or util.is_blacklisted(blacklist_filenames, filename) then
          return
        end
        M.gemini_complete()
      end,
    })
  end

  vim.api.nvim_set_keymap('i', config.get_config({ 'completion', 'insert_result_key' }) or '<S-Tab>', '', {
    callback = function()
      M.insert_completion_result()
    end,
  })
end

local get_prompt_text = function(bufnr, pos)
  local get_prompt = config.get_config({ 'completion', 'get_prompt' })
  if not get_prompt then
    util.log(vim.log.levels.WARN, true, 'Completion prompt function (get_prompt) is not found in config.')
    return nil
  end
  return get_prompt(bufnr, pos)
end

M._gemini_complete = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local pos = vim.api.nvim_win_get_cursor(win)
  local user_text = get_prompt_text(bufnr, pos)
  if not user_text then
    util.log(vim.log.levels.DEBUG, false, "GeminiCompletion: User text for prompt is nil, aborting.")
    return
  end

  local system_text = nil
  local get_system_text = config.get_config({ 'completion', 'get_system_text' })
  if get_system_text then
    system_text = get_system_text()
  end

  local generation_config = config.get_gemini_generation_config()
  local model_id = config.get_config({ 'model', 'model_id' })

  util.log(vim.log.levels.DEBUG, false, "GeminiCompletion: Sending request to API.")
  api.gemini_generate_content(user_text, system_text, model_id, generation_config, function(result)
    util.log(vim.log.levels.DEBUG, false, "GeminiCompletion: Received API response. Code: ", tostring(result.code))

    if result.code ~= 0 then
      util.log(vim.log.levels.ERROR, true, "GeminiCompletion API error. Code: ", result.code)
    end
    if result.stderr and #result.stderr > 0 then
      util.log(vim.log.levels.WARN, true, "GeminiCompletion API stderr: ", result.stderr)
    end

    local json_text = result.stdout
    if not json_text or #json_text == 0 then
      if result.code == 0 and (not result.stderr or #result.stderr == 0) then
        util.log(vim.log.levels.WARN, true, "GeminiCompletion API returned empty stdout without other errors.")
      elseif result.code ~=0 or (result.stderr and #result.stderr > 0) then
        -- Error already logged, do nothing more here for empty stdout
      else
        util.log(vim.log.levels.DEBUG, false, "GeminiCompletion API returned empty stdout. Raw result: ", vim.inspect(result))
      end
      return
    end

    local model_response_decoded = vim.json.decode(json_text)
    if not model_response_decoded then
        util.log(vim.log.levels.WARN, true, "GeminiCompletion: Failed to decode JSON response: ", json_text)
        return
    end

    local model_response_text = util.table_get(model_response_decoded, { 'candidates', 1, 'content', 'parts', 1, 'text' })
    if model_response_text ~= nil and #model_response_text > 0 then
      vim.schedule(function()
        if model_response_text then 
          M.show_completion_result(model_response_text, win, pos)
        end
      end)
    else
      util.log(vim.log.levels.DEBUG, false, "GeminiCompletion: Extracted text from model response is nil or empty. Full response: ", json_text)
    end
  end)
end

M.gemini_complete = util.debounce(function()
  if vim.fn.mode() ~= 'i' then
    return
  end

  local can_complete = config.get_config({'completion', 'can_complete'})
  if not can_complete or not can_complete() then
    return
  end

  util.log(vim.log.levels.INFO, true, '-- gemini complete --')
  M._gemini_complete()
end, config.get_config({ 'completion', 'completion_delay' }) or 1000)

M.manual_complete = function()
  if vim.fn.mode() ~= 'i' then
    return
  end

  local can_complete = config.get_config({ 'completion', 'can_complete' })
  if not can_complete or not can_complete() then
    return
  end

  util.log(vim.log.levels.INFO, true, '-- gemini complete (manual) --')
  M._gemini_complete()
end

M.show_completion_result = function(result, win_id, pos)
  local win = vim.api.nvim_get_current_win()
  if win ~= win_id then
    return
  end

  local current_pos = vim.api.nvim_win_get_cursor(win)
  if current_pos[1] ~= pos[1] or current_pos[2] ~= pos[2] then
    return
  end

  if vim.fn.mode() ~= 'i' then
    return
  end

  local can_complete = config.get_config({'completion', 'can_complete'})
  if not can_complete or not can_complete() then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local options = {
    id = 1,
    virt_text = {},
    virt_lines = {},
    hl_mode = 'combine',
    virt_text_pos = 'inline',
  }

  local content = result:match("^%s*(.-)%s*$")
  for i, l in pairs(vim.split(content, '\n')) do
    if i == 1 then
      options.virt_text[1] = { l, 'Comment' }
    else
      options.virt_lines[i - 1] = { { l, 'Comment' } }
    end
  end
  local row = pos[1]
  local col = pos[2]
  local id = vim.api.nvim_buf_set_extmark(bufnr, context.namespace_id, row - 1, col, options)

  context.completion = {
    content = content,
    row = row,
    col = col,
    bufnr = bufnr,
  }

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertLeavePre' }, {
    buffer = bufnr,
    callback = function()
      context.completion = nil
      vim.api.nvim_buf_del_extmark(bufnr, context.namespace_id, id)
      vim.api.nvim_command('redraw')
    end,
    once = true,
  })
end

M.insert_completion_result = function()
  if not context.completion then
    M.manual_complete()
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if not context.completion.bufnr == bufnr then
    return
  end

  local row = context.completion.row - 1
  local col = context.completion.col
  local first_line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
  local lines = vim.split(context.completion.content, '\n')
  lines[1] = string.sub(first_line, 1, col) .. lines[1] .. string.sub(first_line, col + 1)
  vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, lines)

  if config.get_config({ 'completion', 'move_cursor_end' }) == true then
    local new_row = row + #lines
    local new_col = #vim.api.nvim_buf_get_lines(0, new_row - 1, new_row, false)[1]
    vim.api.nvim_win_set_cursor(0, { new_row, new_col })
  end

  context.completion = nil
end

return M
