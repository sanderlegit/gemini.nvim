local uv = vim.loop or vim.uv -- This is correct

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
    -- It's better to return an error or notify the user
    vim.notify("GEMINI_API_KEY environment variable not set.", vim.log.levels.ERROR)
    return ''
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
  local cmd = { 'curl', '-X', 'POST', api, '-H', 'Content-Type: application/json', '--data-binary', '@-' }
  local opts = { stdin = json_text }
  -- Debugging: print command and opts
  -- print("vim.system cmd:", vim.inspect(cmd))
  -- print("vim.system opts:", vim.inspect(opts))

  if callback then
    return vim.system(cmd, opts, callback)
  else
    return vim.system(cmd, opts)
  end
end

M.gemini_generate_content_stream = function(user_text, system_text, model_name, generation_config, callback) -- Added system_text as argument
  local api_key = os.getenv("GEMINI_API_KEY")
  if not api_key then
    vim.notify("GEMINI_API_KEY environment variable not set.", vim.log.levels.ERROR)
    return
  end

  if not callback then
    vim.notify("Callback function is required for streaming.", vim.log.levels.WARN)
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
  if system_text then -- Added system_text handling for streaming
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

  local stdin_pipe = uv.new_pipe(false)
  local stdout_pipe = uv.new_pipe(false)
  local stderr_pipe = uv.new_pipe(false)

  local args = {
    'curl',
    '-X', 'POST',
    api,
    '-H', 'Content-Type: application/json',
    '--data-binary', '@-' -- Read data from stdin
  }

  local options = {
    stdio = { stdin_pipe, stdout_pipe, stderr_pipe },
    args = args,
  }

  -- Debugging: print curl command
  -- print("curl command args:", vim.inspect(args))
  -- print("json_text to send:", json_text)

  local proc = uv.spawn('curl', options, function(code, signal)
    -- This callback is fired when the curl process exits
    -- print("gemini chat finished exit code", code, "signal", signal)

    -- Ensure all pipes are closed once the process is done
    uv.read_stop(stdout_pipe)
    uv.read_stop(stderr_pipe) -- Stop reading stderr too, if any
    uv.close(stdin_pipe)
    uv.close(stdout_pipe)
    uv.close(stderr_pipe)

    -- Optionally, notify callback that stream has ended or if there was an error
    -- if code ~= 0 then
    --   vim.notify("Curl exited with code: " .. code, vim.log.levels.ERROR)
    -- end
    callback(nil, code ~= 0) -- Pass nil for data, true if error
  end)

  -- Write the JSON data to curl's stdin
  uv.write(stdin_pipe, json_text, function(err)
    if err then
      vim.notify("Error writing to stdin_pipe: " .. err, vim.log.levels.ERROR)
    end
    -- Crucial: shutdown stdin pipe once all data is written.
    -- curl will then know it has received all input.
    uv.shutdown(stdin_pipe, function(err_shutdown)
      if err_shutdown then
        vim.notify("Error shutting down stdin_pipe: " .. err_shutdown, vim.log.levels.ERROR)
      end
    end)
  end)

  local streamed_data = ''
  uv.read_start(stdout_pipe, function(err, data)
    if err then
      vim.notify("Error reading from stdout_pipe: " .. err, vim.log.levels.ERROR)
      uv.read_stop(stdout_pipe) -- Stop reading on error
      return
    end

    if not data then -- EOF (end of file) reached
      -- print("EOF reached on stdout_pipe")
      uv.read_stop(stdout_pipe)
      -- Any remaining data in streamed_data that wasn't a full message might be discarded or processed here
      return
    end

    streamed_data = streamed_data .. data
    -- Debugging: print raw data received
    -- print("Raw chunk received:", vim.inspect(data))
    -- print("Current streamed_data:", vim.inspect(streamed_data))

    -- SSE parsing: Look for 'data:' followed by content, terminated by '\n\n'
    -- Note: Gemini API often uses `data: {json}\n\n`
    local pattern = "data: ([^\n]-)\n\n" -- Matches 'data: ' and captures content until '\n\n'
    local match_start, match_end, json_content

    repeat
      match_start, match_end, json_content = string.find(streamed_data, pattern, 1, true) -- Use raw find for efficiency
      if match_start then
        -- print("Found SSE message:", json_content)
        callback(json_content) -- Pass the extracted JSON content to the callback
        streamed_data = string.sub(streamed_data, match_end + 1) -- Remove processed part
      end
    until not match_start -- Continue until no more full messages are found in the buffer
  end)

  -- Also read stderr to catch any curl errors
  uv.read_start(stderr_pipe, function(err, data)
    if err then
      vim.notify("Error reading from stderr_pipe: " .. err, vim.log.levels.ERROR)
      uv.read_stop(stderr_pipe)
      return
    end
    if data then
      vim.notify("Curl STDERR: " .. data, vim.log.levels.WARN)
    else -- EOF on stderr
      uv.read_stop(stderr_pipe)
    end
  end)
end

return M
