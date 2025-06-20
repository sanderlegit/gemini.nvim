# gemini.nvim

This plugin try to interface Google's Gemini API into neovim.


## Features

- Code Complete
- Code Explain
- Unit Test Generation
- Code Review
- Hints
- Chat

### Code Complete
https://github.com/user-attachments/assets/11ae6719-4f3f-41db-8ded-56db20e6e9f4

https://github.com/user-attachments/assets/34c38078-a028-47d2-acb1-49e03d0b4330

### Do some changes
https://github.com/user-attachments/assets/c0a001a2-a5fe-469d-ae01-3468d05b041c




### Code Explain
https://github.com/user-attachments/assets/6b2492ee-7c70-4bbc-937b-27bfa50f8944

### Unit Test generation
https://github.com/user-attachments/assets/0620a8a4-5ea6-431d-ba17-41c7d553f742

### Code Review
https://github.com/user-attachments/assets/9100ab70-f107-40de-96e2-fb4ea749c014

### Hints
https://github.com/user-attachments/assets/a36804e9-073f-4e3e-9178-56b139fd0c62

### Chat
https://github.com/user-attachments/assets/d3918d2a-4cf7-4639-bc21-689d4225ba6d


## Installation

- install `curl`

```
sudo apt install curl
```





```shell
export GEMINI_API_KEY="<your API key here>"
```

* [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'kiddos/gemini.nvim',
  opts = {}
}
```


* [packer.nvim](https://github.com/wbthomason/packer.nvim)


```lua
use { 'kiddos/gemini.nvim', opts = {} }
```

## Settings

Default settings:
```lua
{
  model_config = {
    model_id = "gemini-2.0-flash", -- See `lua/gemini/api.lua` for M.MODELS
    temperature = 0.1,
    top_k = 128,
    response_mime_type = 'text/plain',
  },
  chat_config = {
    enabled = true,
  },
  hints = {
    enabled = true,
    hints_delay = 2000,
    insert_result_key = '<S-Tab>',
    get_prompt = function(node, bufnr)
      -- Default prompt function for hints
    end
  },
  completion = {
    enabled = true,
    blacklist_filetypes = { 'help', 'qf', 'json', 'yaml', 'toml', 'xml' },
    blacklist_filenames = { '.env' },
    completion_delay = 1000,
    insert_result_key = '<S-Tab>',
    move_cursor_end = true,
    can_complete = function()
      return vim.fn.pumvisible() ~= 1
    end,
    get_system_text = function()
      -- Default system text for completion
    end,
    get_prompt = function(bufnr, pos)
      -- Default prompt function for completion
    end
  },
  instruction = {
    enabled = true,
    menu_key = '<Leader><Leader><Leader>g',
    prompts = {
      -- Default instruction prompts (Unit Test, Code Review, Code Explain)
    }
  },
  task = {
    enabled = true,
    get_system_text = function()
      -- Default system text for task
    end,
    get_prompt = function(bufnr, user_prompt)
      -- Default prompt function for task
    end
  },
  logging = {
    -- Path to the log file. If nil, file logging is disabled.
    -- Example: file_path = vim.fn.stdpath('cache') .. '/gemini.nvim.log'
    file_path = nil,
    -- Log level for the file. Uses vim.log.levels.
    -- (ERROR, WARN, INFO, DEBUG, TRACE)
    level = vim.log.levels.INFO,
  }
}
```

For detailed default prompt implementations, please refer to `lua/gemini/config.lua`.

To enable file logging, you can set `logging.file_path` in your setup options:
```lua
require('gemini').setup({
  logging = {
    file_path = vim.fn.stdpath('cache') .. '/gemini.nvim.log',
    level = vim.log.levels.DEBUG, -- Log DEBUG messages and above
  }
})
```
