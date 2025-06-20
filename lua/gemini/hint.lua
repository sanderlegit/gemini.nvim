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
    util.log(vim.log.levels.DEBUG, "GeminiHints: Treesitter language not available for current buffer.")
    return
  end

  local node = util.find_node_by_type('function')
  if node then
    M.show_quick_hints(node, bufnr)
    return
  else
    util.log(vim.log.levels.DEBUG, "GeminiHints: No 'function' node found at cursor.")
  end
end

M.show_quick_hints = util.debounce(function(node, bufnr)
  local mode = vim.api.nvim_get_mode()
  if mode.mode ~= 'n' then
    return
  end

  local get_prompt = config.get_config({ 'hints', 'get_prompt' })
  if not get_prompt then
    util.log(vim.log.levels.WARN, "GeminiHints: Prompt function (get_prompt) not found in config.")
    return
  end

  local win = vim.api.nvim_get_current_win()
  local user_text = get_prompt(node, bufnr)
  if not user_text then
    util.log(vim.log.levels.DEBUG, "GeminiHints: User text for prompt is nil, aborting.")
    return
  end

  local generation_config = config.get_gemini_generation_config()
  local model_id = config.get_config({ 'model', 'model_id' })

  util.log(vim.log.levels.DEBUG, "GeminiHints: Sending request to API.")
  api.gemini_generate_content(user_text, nil, model_id, generation_config, function(result)
    util.log(vim.log.levels.DEBUG, "GeminiHints: Received API response. Code: ", tostring(result.code))

    if result.code ~= 0 then
      util.log(vim.log.levels.ERROR, "GeminiHints API error. Code: ", result.code)
    end
    if result.stderr and #result.stderr > 0 then
      util.log(vim.log.levels.WARN, "GeminiHints API stderr: ", result.stderr)
    end

    local json_text = result.stdout
    if not json_text or #json_text == 0 then
      if result.code == 0 and (not result.stderr or #result.stderr == 0) then
        util.log(vim.log.levels.WARN, "GeminiHints API returned empty stdout without other errors.")
      end
      return
    end

    local model_response_decoded = vim.json.decode(json_text)
    if not model_response_decoded then
        util.log(vim.log.levels.WARN, "GeminiHints: Failed to decode JSON response: ", json_text)
        return
    end
    
    local model_response_text = util.table_get(model_response_decoded, { 'candidates', 1, 'content', 'parts', 1, 'text' })
    if model_response_text ~= nil and #model_response_text > 0 then
      vim.schedule(function()
        if #model_response_text > 0 then -- Re-check after schedule
          local start_row, _, _, _ = node:range()
          M.show_quick_hint_text(model_response_text, win, { start_row + 1, 1 })
        end
      end)
    else
      util.log(vim.log.levels.DEBUG, "GeminiHints: Extracted text from model response is nil or empty. Full response: ", json_text)
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
    virt_lines_above = true,
  }
  options.virt_text_pos = nil


  for i, l in pairs(vim.split(content, '\n')) do
    options.virt_lines[i-1] = { { l, 'Comment' } } 
  end
  if #options.virt_lines == 0 then
    util.log(vim.log.levels.DEBUG, "GeminiHints: No lines to display for hint.")
    return
  end

  local id = vim.api.nvim_buf_set_extmark(0, context.namespace_id, row - 1, col - 1, options)
  util.log(vim.log.levels.DEBUG, "GeminiHints: Displaying hint extmark ID ", id, " at row ", (row-1))


  local bufnr = vim.api.nvim_get_current_buf()
  context.hints = {
    content = content,
    row = row, 
    col = col,
    bufnr = bufnr,
  }

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertLeavePre' }, {
    buffer = bufnr,
    callback = function()
      if context.hints and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_extmark_by_id(bufnr, context.namespace_id, id, {}) then
        vim.api.nvim_buf_del_extmark(bufnr, context.namespace_id, id)
        util.log(vim.log.levels.DEBUG, "GeminiHints: Cleared hint extmark ID ", id)
      end
      context.hints = nil
      vim.api.nvim_command('redraw') 
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

  local row = context.hints.row - 1 
  local lines = vim.split(context.hints.content, '\n')
  vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines) 
  util.log(vim.log.levels.DEBUG, "GeminiHints: Inserted hint content at row ", row)
  context.hints = nil 
end

return M
