local uv = vim.loop or vim.uv -- This is correct
local util = require('gemini.util')

local M = {}

local API = "https://generativelanguage.googleapis.com/v1beta/models/";

M.MODELS = {
  GEMINI_2_5_FLASH_PREVIEW = 'gemini-2.5-flash-preview-04-17',
  GEMINI_2_5_PRO_PREVIEW = 'gemini-2.5-pro-preview-03-25',
  GEMINI_2_0_FLASH = 'gemini-2.0-flash',
  GEMINI_2_0_FLASH_LITE = 'gemini-2.0-flash-lite',
  GEMINI_2_0_FLASH_EXP = 'gemini-2.0-flash-exp',
  GEMINI_2_0_FLASH_THINKING_EXP = 'gemini-2.0-flash-thinking-exp-1219',
  GEMINI_1_5_PRO = 'gemini-1.5-pro',
  GEMINI_1_5_FLASH = 'gemini-1.5-flash',
  GEMINI_1_5_FLASH_8B = 'gemini-1.5-flash-8b',
}

M.gemini_generate_content = function(user_text, system_text, model_name, generation_config, callback)
  local api_key = os.getenv("GEMINI_API_KEY")
  if not api_key then
    util.log(vim.log.levels.ERROR, "GEMINI_API_KEY environment variable not set.")
    -- Ensure callback is called with an error indication if provided
    if callback then
      callback({ stdout = '', stderr = "GEMINI_API_KEY not set", code = -1 })
    end
    return '' -- Return empty for synchronous calls or if no callback
  end

  local api = API .. model_name .. ':generateContent?key=' .. api_key
  local contents = {
    {
      role = 'user',
      parts = {
        {
          text = user_text
        }
      }
    }
  }
  local data = {
    contents = contents,
    generationConfig = generation_config,
  }
  if system_text then
    data.systemInstruction = {
      role = 'user',
      parts = {
        {
          text = system_text,
        }
      }
    }
  end

  local json_text = vim.json.encode(data)
  local cmd = { 'curl', '-s', '-X', 'POST', api, '-H', 'Content-Type: application/json', '--data-binary', '@-' }
  local opts = { stdin = json_text }

  -- The callback passed to vim.system will receive {stdout, stderr, code}
  -- Logging for these should be handled by the module calling this function,
  -- as it owns the final callback logic.
  if callback then
    return vim.system(cmd, opts, callback)
  else
    return vim.system(cmd, opts) -- Returns stdout for sync, errors might need v:shell_error check by caller
  end
end

M.gemini_generate_content_stream = function(user_text, system_text, model_name, generation_config, callback)
  util.log(vim.log.levels.DEBUG, "gemini_generate_content_stream called. User text (first 100 chars): ", string.sub(user_text or "nil", 1, 100))

  local api_key = os.getenv("GEMINI_API_KEY")
  if not api_key then
    util.log(vim.log.levels.ERROR, "GEMINI_API_KEY environment variable not set.")
    if callback then callback(nil, true) end -- Signal error
    return
  end

  if not callback then
    util.log(vim.log.levels.ERROR, "Callback function is required for streaming.")
    return
  end

  local api = API .. model_name .. ':streamGenerateContent?alt=sse&key=' .. api_key
  local data = {
    contents = {
      {
        role = 'user',
        parts = {
          {
            text = user_text
          }
        }
      }
    },
    generationConfig = generation_config,
  }
  if system_text then
    data.systemInstruction = {
      role = 'user',
      parts = {
        {
          text = system_text,
        }
      }
    }
  end

  local json_text = vim.json.encode(data)
  util.log(vim.log.levels.DEBUG, "Streaming API JSON payload (first 100 chars): ", string.sub(json_text, 1, 100))

  local stdin_pipe = uv.new_pipe(false)
  local stdout_pipe = uv.new_pipe(false)
  local stderr_pipe = uv.new_pipe(false)

  if not stdin_pipe or not stdout_pipe or not stderr_pipe then
    util.log(vim.log.levels.ERROR, "Failed to create one or more UV pipes for streaming.")
    if stdin_pipe and not stdin_pipe:is_closing() then uv.close(stdin_pipe) end
    if stdout_pipe and not stdout_pipe:is_closing() then uv.close(stdout_pipe) end
    if stderr_pipe and not stderr_pipe:is_closing() then uv.close(stderr_pipe) end
    callback(nil, true) -- Signal error
    return
  end

  local command_args = {
    '-s',
    '-X', 'POST',
    api,
    '-H', 'Content-Type: application/json',
    '--data-binary', '@-'
  }

  local options = {
    stdio = { stdin_pipe, stdout_pipe, stderr_pipe },
    args = command_args,
  }

  local proc = uv.spawn('curl', options, function(code, signal)
    util.log(code == 0 and vim.log.levels.DEBUG or vim.log.levels.ERROR, "Stream process exited. Code: ", tostring(code), ", Signal: ", tostring(signal))

    if stdout_pipe and not stdout_pipe:is_closing() then uv.read_stop(stdout_pipe) end
    if stderr_pipe and not stderr_pipe:is_closing() then uv.read_stop(stderr_pipe) end
    if stdin_pipe and not stdin_pipe:is_closing() then uv.close(stdin_pipe) end
    if stdout_pipe and not stdout_pipe:is_closing() then uv.close(stdout_pipe) end
    if stderr_pipe and not stderr_pipe:is_closing() then uv.close(stderr_pipe) end

    callback(nil, code ~= 0) -- Final callback: nil data, error status based on exit code
  end)

  if not proc then
    util.log(vim.log.levels.ERROR, "uv.spawn for curl failed to return a process handle.")
    if stdin_pipe and not stdin_pipe:is_closing() then uv.close(stdin_pipe) end
    if stdout_pipe and not stdout_pipe:is_closing() then uv.close(stdout_pipe) end
    if stderr_pipe and not stderr_pipe:is_closing() then uv.close(stderr_pipe) end
    callback(nil, true)
    return
  elseif proc:is_closing() then
    util.log(vim.log.levels.ERROR, "curl process for streaming closed immediately after spawn. Check curl command and URL.")
    return -- on_exit will handle the callback.
  end
  util.log(vim.log.levels.DEBUG, "curl process spawned for streaming. PID: ", tostring(proc:getpid()))


  uv.write(stdin_pipe, json_text, function(err_write)
    if err_write then
      util.log(vim.log.levels.ERROR, "Error writing JSON to curl stdin: ", vim.inspect(err_write))
      if stdin_pipe and not stdin_pipe:is_closing() then uv.shutdown(stdin_pipe) end
      return
    end
    util.log(vim.log.levels.DEBUG, "Successfully wrote JSON to curl stdin.")
    if stdin_pipe and not stdin_pipe:is_closing() then
      uv.shutdown(stdin_pipe, function(err_shutdown)
        if err_shutdown then
          util.log(vim.log.levels.ERROR, "Error shutting down curl stdin pipe: ", vim.inspect(err_shutdown))
        else
          util.log(vim.log.levels.DEBUG, "Successfully shut down curl stdin pipe.")
        end
      end)
    end
  end)

  local streamed_data_buffer = ''
  uv.read_start(stdout_pipe, function(err_read_stdout, data_chunk)
    if err_read_stdout then
      util.log(vim.log.levels.ERROR, "Error reading from curl stdout: ", vim.inspect(err_read_stdout))
      if stdout_pipe and not stdout_pipe:is_closing() then uv.read_stop(stdout_pipe) end
      return
    end

    if not data_chunk then
      util.log(vim.log.levels.DEBUG, "EOF reached on curl stdout.")
      if stdout_pipe and not stdout_pipe:is_closing() then uv.read_stop(stdout_pipe) end
      if #streamed_data_buffer > 0 then
         util.log(vim.log.levels.DEBUG, "Remaining data in stdout buffer at EOF: ", streamed_data_buffer)
      end
      return
    end

    streamed_data_buffer = streamed_data_buffer .. data_chunk
    local pattern = "data: ([^\n]-)\n\n"
    local match_start, match_end, json_content

    repeat
      match_start, match_end, json_content = string.find(streamed_data_buffer, pattern, 1, true)
      if match_start then
        util.log(vim.log.levels.DEBUG, "SSE message received: ", json_content)
        callback(json_content, false) -- false for is_error
        streamed_data_buffer = string.sub(streamed_data_buffer, match_end + 1)
      end
    until not match_start
  end)

  uv.read_start(stderr_pipe, function(err_read_stderr, data_stderr)
    if err_read_stderr then
      util.log(vim.log.levels.ERROR, "Error reading from curl stderr: ", vim.inspect(err_read_stderr))
      if stderr_pipe and not stderr_pipe:is_closing() then uv.read_stop(stderr_pipe) end
      return
    end

    if data_stderr then
      util.log(vim.log.levels.WARN, "Curl STDERR: [", data_stderr, "]")
    else
      util.log(vim.log.levels.DEBUG, "EOF reached on curl stderr.")
      if stderr_pipe and not stderr_pipe:is_closing() then uv.read_stop(stderr_pipe) end
    end
  end)
end

return M
