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
    util.log(vim.log.levels.ERROR, true, "GEMINI_API_KEY environment variable not set.")
    if callback then
      callback({ stdout = '', stderr = "GEMINI_API_KEY not set", code = -1 })
    end
    return '' 
  end

  local api_url = API .. model_name .. ':generateContent?key=' .. api_key
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

  local json_request_body = vim.json.encode(data)
  util.log(vim.log.levels.DEBUG, false, "API Request (generateContent) URL: ", api_url)
  util.log(vim.log.levels.DEBUG, false, "API Request (generateContent) Body: ", json_request_body)

  local cmd = { 'curl', '-s', '-X', 'POST', api_url, '-H', 'Content-Type: application/json', '--data-binary', '@-' }
  local opts = { stdin = json_request_body }

  if callback then
    local wrapped_callback = function(result)
      util.log(vim.log.levels.DEBUG, false, "API Response (generateContent) Code: ", result.code)
      util.log(vim.log.levels.DEBUG, false, "API Response (generateContent) STDOUT: ", result.stdout)
      if result.stderr and #result.stderr > 0 then
        util.log(vim.log.levels.DEBUG, false, "API Response (generateContent) STDERR: ", result.stderr)
      end
      callback(result)
    end
    return vim.system(cmd, opts, wrapped_callback)
  else
    return vim.system(cmd, opts)
  end
end

M.gemini_generate_content_stream = function(user_text, system_text, model_name, generation_config, callback)
  util.log(vim.log.levels.DEBUG, false, "gemini_generate_content_stream called. User text (first 100 chars): ", string.sub(user_text or "nil", 1, 100))

  local api_key = os.getenv("GEMINI_API_KEY")
  if not api_key then
    util.log(vim.log.levels.ERROR, true, "GEMINI_API_KEY environment variable not set.")
    if callback then callback(nil, true) end 
    return
  end

  if not callback then
    util.log(vim.log.levels.ERROR, true, "Callback function is required for streaming.")
    return
  end

  local api_url = API .. model_name .. ':streamGenerateContent?alt=sse&key=' .. api_key
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

  local json_request_body = vim.json.encode(data)
  util.log(vim.log.levels.DEBUG, false, "API Request (streamGenerateContent) URL: ", api_url)
  util.log(vim.log.levels.DEBUG, false, "API Request (streamGenerateContent) Body (first 100 chars): ", string.sub(json_request_body, 1, 100))

  local stdin_pipe = uv.new_pipe(false)
  local stdout_pipe = uv.new_pipe(false)
  local stderr_pipe = uv.new_pipe(false)

  if not stdin_pipe or not stdout_pipe or not stderr_pipe then
    util.log(vim.log.levels.ERROR, true, "Failed to create one or more UV pipes for streaming.")
    if stdin_pipe and not stdin_pipe:is_closing() then uv.close(stdin_pipe) end
    if stdout_pipe and not stdout_pipe:is_closing() then uv.close(stdout_pipe) end
    if stderr_pipe and not stderr_pipe:is_closing() then uv.close(stderr_pipe) end
    callback(nil, true) 
    return
  end

  local command_args = {
    '-s',
    '-X', 'POST',
    api_url,
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

    callback(nil, code ~= 0) 
  end)

  -- Check if proc is a valid handle with expected methods
  if not proc or type(proc.getpid) ~= "function" or type(proc.is_closing) ~= "function" then
    util.log(vim.log.levels.ERROR, true, "uv.spawn for curl failed to return a valid process handle. Proc: ", vim.inspect(proc))
    if stdin_pipe and not stdin_pipe:is_closing() then uv.close(stdin_pipe) end
    if stdout_pipe and not stdout_pipe:is_closing() then uv.close(stdout_pipe) end
    if stderr_pipe and not stderr_pipe:is_closing() then uv.close(stderr_pipe) end
    callback(nil, true)
    return
  end

  -- Check if the process closed immediately
  if proc:is_closing() then
    util.log(vim.log.levels.ERROR, true, "curl process for streaming closed immediately after spawn. Check curl command and URL.")
    -- The on_exit callback for uv.spawn should handle pipe cleanup and calling the main callback.
    -- Thus, we just return here and let on_exit do its job.
    return 
  end

  util.log(vim.log.levels.DEBUG, false, "curl process spawned for streaming. PID: ", tostring(proc:getpid()))


  uv.write(stdin_pipe, json_request_body, function(err_write)
    if err_write then
      util.log(vim.log.levels.ERROR, true, "Error writing JSON to curl stdin: ", vim.inspect(err_write))
      if stdin_pipe and not stdin_pipe:is_closing() then uv.shutdown(stdin_pipe) end
      return
    end
    util.log(vim.log.levels.DEBUG, false, "Successfully wrote JSON to curl stdin.")
    if stdin_pipe and not stdin_pipe:is_closing() then
      uv.shutdown(stdin_pipe, function(err_shutdown)
        if err_shutdown then
          util.log(vim.log.levels.ERROR, true, "Error shutting down curl stdin pipe: ", vim.inspect(err_shutdown))
        else
          util.log(vim.log.levels.DEBUG, false, "Successfully shut down curl stdin pipe.")
        end
      end)
    end
  end)

  local streamed_data_buffer = ''
  uv.read_start(stdout_pipe, function(err_read_stdout, data_chunk)
    if err_read_stdout then
      util.log(vim.log.levels.ERROR, true, "Error reading from curl stdout: ", vim.inspect(err_read_stdout))
      if stdout_pipe and not stdout_pipe:is_closing() then uv.read_stop(stdout_pipe) end
      return
    end

    if not data_chunk then
      util.log(vim.log.levels.DEBUG, false, "EOF reached on curl stdout.")
      if stdout_pipe and not stdout_pipe:is_closing() then uv.read_stop(stdout_pipe) end
      if #streamed_data_buffer > 0 then
         util.log(vim.log.levels.DEBUG, false, "Remaining data in stdout buffer at EOF: ", streamed_data_buffer)
      end
      return
    end

    streamed_data_buffer = streamed_data_buffer .. data_chunk
    local pattern = "data: ([^\n]-)\n\n"
    local match_start, match_end, json_content

    repeat
      match_start, match_end, json_content = string.find(streamed_data_buffer, pattern, 1, true)
      if match_start then
        util.log(vim.log.levels.DEBUG, false, "SSE message received (response chunk): ", json_content)
        callback(json_content, false) 
        streamed_data_buffer = string.sub(streamed_data_buffer, match_end + 1)
      end
    until not match_start
  end)

  uv.read_start(stderr_pipe, function(err_read_stderr, data_stderr)
    if err_read_stderr then
      util.log(vim.log.levels.ERROR, true, "Error reading from curl stderr: ", vim.inspect(err_read_stderr))
      if stderr_pipe and not stderr_pipe:is_closing() then uv.read_stop(stderr_pipe) end
      return
    end

    if data_stderr then
      util.log(vim.log.levels.WARN, "Curl STDERR: [", data_stderr, "]")
    else
      util.log(vim.log.levels.DEBUG, false, "EOF reached on curl stderr.")
      if stderr_pipe and not stderr_pipe:is_closing() then uv.read_stop(stderr_pipe) end
    end
  end)
end

return M
