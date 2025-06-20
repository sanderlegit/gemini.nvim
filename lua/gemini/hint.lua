local config = require('gemini.config')
local util = require('gemini.util')
local api = require('gemini.api')

local M = {}

local context = {
  hint = nil,
  namespace_id = nil,
}

M.setup = function()
  if not config.get_config({ 'hints', 'enabled' }) then
    return
  end

  vim.api.nvim_create_user_command('GeminiFunctionHint', M.show_function_hints, {
    force = true,
    desc = 'Google Gemini function explaination',
  })

  context.namespace_id = vim.api.nvim_create_namespace('gemini_hints')

  vim.api.nvim_set_keymap('n', config.get_config({ 'hints', 'insert_result_key' }) or '<S-Tab>', '', {
    callback = function()
      M.insert_hint_result()
    end,
  })
end

M.show_function_hints = function()
  local bufnr = vim.api.nvim_get_current_buf()
  if not util.treesitter_has_lang(bufnr) then
    vim.notify("GeminiHints: Treesitter language not available for current buffer.", vim.log.levels.DEBUG)
    return
  end

  local node = util.find_node_by_type('function')
  if node then
    M.show_quick_hints(node, bufnr)
    return
  else
    vim.notify("GeminiHints: No 'function' node found at cursor.", vim.log.levels.DEBUG)
  end
end

M.show_quick_hints = util.debounce(function(node, bufnr)
  local mode = vim.api.nvim_get_mode()
  if mode.mode ~= 'n' then
    return
  end

  local get_prompt = config.get_config({ 'hints', 'get_prompt' })
  if not get_prompt then
    vim.notify("GeminiHints: Prompt function (get_prompt) not found in config.", vim.log.levels.WARN)
    return
  end

  local win = vim.api.nvim_get_current_win()
  local row = node:range() -- This gets the start row, end row, start col, end col
  local user_text = get_prompt(node, bufnr)
  if not user_text then
    vim.notify("GeminiHints: User text for prompt is nil, aborting.", vim.log.levels.DEBUG)
    return
  end

  local generation_config = config.get_gemini_generation_config()
  local model_id = config.get_config({ 'model', 'model_id' })

  vim.notify("GeminiHints: Sending request to API.", vim.log.levels.DEBUG)
  api.gemini_generate_content(user_text, nil, model_id, generation_config, function(result)
    vim.notify("GeminiHints: Received API response. Code: " .. tostring(result.code), vim.log.levels.DEBUG)

    if result.code ~= 0 then
      vim.notify("GeminiHints API error. Code: " .. result.code, vim.log.levels.ERROR)
    end
    if result.stderr and #result.stderr > 0 then
      vim.notify("GeminiHints API stderr: " .. result.stderr, vim.log.levels.WARN)
    end

    local json_text = result.stdout
    if not json_text or #json_text == 0 then
      if result.code == 0 and (not result.stderr or #result.stderr == 0) then
        vim.notify("GeminiHints API returned empty stdout without other errors.", vim.log.levels.WARN)
      end
      return
    end

    local model_response_decoded = vim.json.decode(json_text)
    if not model_response_decoded then
        vim.notify("GeminiHints: Failed to decode JSON response: " .. json_text, vim.log.levels.WARN)
        return
    end
    
    local model_response_text = util.table_get(model_response_decoded, { 'candidates', 1, 'content', 'parts', 1, 'text' })
    if model_response_text ~= nil and #model_response_text > 0 then
      vim.schedule(function()
        if #model_response_text > 0 then -- Re-check after schedule
          -- node:range() returns {start_row, start_col, end_row, end_col} (0-indexed)
          -- We want to display the hint above the function, so use start_row.
          -- The extmark position is 0-indexed row, 0-indexed col.
          -- show_quick_hint_text expects {1-indexed row, 1-indexed col} for its pos argument.
          local start_row, _, _, _ = node:range()
          M.show_quick_hint_text(model_response_text, win, { start_row + 1, 1 })
        end
      end)
    else
      vim.notify("GeminiHints: Extracted text from model response is nil or empty. Full response: " .. json_text, vim.log.levels.DEBUG)
    end
  end)
end, config.get_config({ 'hints', 'hints_delay' }) or 2000)

M.show_quick_hint_text = function(content, win, pos)
  local mode = vim.api.nvim_get_mode()
  if mode.mode ~= 'n' then
    return
  end

  local row = pos[1] -- 1-indexed
  local col = pos[2] -- 1-indexed

  local current_win = vim.api.nvim_get_current_win()
  if current_win ~= win then
    return
  end

  local options = {
    id = 2, -- Unique ID for this extmark type
    virt_lines = {},
    hl_mode = 'combine',
    virt_text_pos = 'overlay', -- Not a valid value, should be e.g. 'eol' or removed for virt_lines
    virt_lines_above = true,
  }
  -- Remove virt_text_pos if using virt_lines, as it's for virt_text
  options.virt_text_pos = nil


  for i, l in pairs(vim.split(content, '\n')) do
    options.virt_lines[i-1] = { { l, 'Comment' } } -- virt_lines is 0-indexed array of lines
  end
  if #options.virt_lines == 0 then
    vim.notify("GeminiHints: No lines to display for hint.", vim.log.levels.DEBUG)
    return
  end

  -- extmark row is 0-indexed
  local id = vim.api.nvim_buf_set_extmark(0, context.namespace_id, row - 1, col - 1, options)
  vim.notify("GeminiHints: Displaying hint extmark ID " .. id .. " at row " .. (row-1), vim.log.levels.DEBUG)


  local bufnr = vim.api.nvim_get_current_buf()
  context.hints = {
    content = content,
    row = row, -- Store 1-indexed row for consistency with how it was passed
    col = col,
    bufnr = bufnr,
  }

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertLeavePre' }, {
    buffer = bufnr,
    callback = function()
      if context.hints and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_extmark_by_id(bufnr, context.namespace_id, id, {}) then
        vim.api.nvim_buf_del_extmark(bufnr, context.namespace_id, id)
        vim.notify("GeminiHints: Cleared hint extmark ID " .. id, vim.log.levels.DEBUG)
      end
      context.hints = nil
      vim.api.nvim_command('redraw') -- May not be necessary if extmark removal triggers redraw
    end,
    once = true,
  })
end

M.insert_hint_result = function()
  if not context.hints then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if not context.hints.bufnr == bufnr then
    return
  end

  local row = context.hints.row - 1 -- Convert to 0-indexed for nvim_buf_set_lines
  local lines = vim.split(context.hints.content, '\n')
  vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines) -- Insert lines *at* 'row', replacing 0 lines.
  vim.notify("GeminiHints: Inserted hint content at row " .. row, vim.log.levels.DEBUG)
  context.hints = nil -- Clear hint after insertion
end

return M
