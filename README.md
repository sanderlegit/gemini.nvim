# gemini.nvim

This plugin provides an interface to Google's Gemini API within Neovim.

## Features

- Code Completion
- Code Explanation
- Unit Test Generation
- Code Review
- Function Hints
- AI-assisted Tasks and Refactoring
- Chat Interface

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

## Prerequisites

Before installing, make sure you have the following:

1.  **Neovim**: Version 0.9.1 or later.
2.  **cURL**: The plugin uses `curl` to make API requests. Install it using your system's package manager (e.g., `sudo apt install curl`).
3.  **Gemini API Key**: You need to obtain an API key from [Google AI Studio](https://aistudio.google.com/app/apikey).

Once you have the API key, you must export it as an environment variable:

```shell
export GEMINI_API_KEY="<your API key here>"
```
It's recommended to add this line to your shell's startup file (e.g., `.bashrc`, `.zshrc`).

## Installation

You can install `gemini.nvim` using your favorite plugin manager.

* [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'kiddos/gemini.nvim',
  opts = {} -- Optional: pass setup options here
}
```

* [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use { 'kiddos/gemini.nvim', config = function() require('gemini').setup({}) end }
```

## Configuration

The plugin comes with sensible defaults. You can override them by passing an options table to the `setup()` function.

For a full list of configurable options and their default values, please see [lua/gemini/config.lua](lua/gemini/config.lua).

Here is an example of how to customize the configuration, such as enabling file logging:

```lua
-- in your init.lua or equivalent
require('gemini').setup({
  -- For example, to enable logging for troubleshooting
  logging = {
    file_path = vim.fn.stdpath('cache') .. '/gemini.nvim.log',
    level = vim.log.levels.DEBUG, -- Log DEBUG messages and above
  },
  -- You can override any other configuration tables here
  -- model_config = {
  --   model_id = "gemini-1.5-pro",
  -- }
})
```

## Usage

### Commands

- `:GeminiTask <user_prompt>`: Ask Gemini to complete a task using open buffers as context. Opens a diff view to see proposed changes.
- `:GeminiApply`: Apply the changes from the `:GeminiTask` diff view.
- `:GeminiChat <user_prompt>`: Start a chat with Gemini in a new tab. This does not use your code as context.
- `:GeminiCodeExplain`: (Visually select code first) Ask Gemini to explain the selected code.
- `:GeminiCodeReview`: (Visually select code first) Ask Gemini to review the selected code.
- `:GeminiUnitTest`: (Visually select code first) Ask Gemini to write unit tests for the selected code.
- `:GeminiFunctionHint`: Show a quick hint/documentation for the function under the cursor.
- `:GeminiOpenLogs`: Open the plugin's log file in a new vertical split (requires `logging.file_path` to be configured).

### Mappings

- `<Leader><Leader><Leader>g`: (Normal mode) Open a popup menu to select an instruction task (Code Explain, Review, Unit Test).
- `<S-Tab>`: (Insert mode) Accept and insert the current inline completion suggestion.
- `<S-Tab>`: (Normal mode) When a function hint is visible, insert the hint content into the buffer.

## Troubleshooting

If you encounter issues like hangs or commands not being available, follow these steps:

1.  **Enable Logging**: The most helpful step is to enable logging. Configure the `logging` option in your setup as shown in the [Configuration](#configuration) section. Set the level to `DEBUG` for maximum detail.

    ```lua
    require('gemini').setup({
      logging = {
        file_path = vim.fn.stdpath('cache') .. '/gemini.nvim.log',
        level = vim.log.levels.DEBUG,
      }
    })
    ```

2.  **Check the Logs**: Restart Neovim, reproduce the issue, and then use the `:GeminiOpenLogs` command to view the log file. Look for any `ERROR` or `WARN` messages that could indicate the problem. You can also check Neovim's standard messages with `:messages`.

3.  **Check Prerequisites**: Ensure all items in the [Prerequisites](#prerequisites) section are met. Verify that your `GEMINI_API_KEY` is correctly exported and available within your Neovim session by running `:echo $GEMINI_API_KEY`.

4.  **Check for Keymap Conflicts**: If a specific key (like `<C-l>`) causes issues, it might be a conflict. This plugin does not map `<C-l>`, but another plugin might. You can check what a key is mapped to by running `:verbose nmap <C-l>` (for normal mode). If there is a conflict, you may need to change your mappings.
