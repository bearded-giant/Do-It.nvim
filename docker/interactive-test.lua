-- Interactive test script for Docker container
-- This loads the full configuration and sets up the plugin for manual testing

-- Load the test configuration
local test_config = require("docker.test-config")

-- Setup the plugin with the test configuration
require("doit").setup(test_config)

-- Set up keymaps for testing
vim.keymap.set("n", "<leader>do", "<cmd>DoIt<CR>", { desc = "Toggle DoIt Todos" })
vim.keymap.set("n", "<leader>dn", "<cmd>DoItNotes<CR>", { desc = "Toggle DoIt Notes" })
vim.keymap.set("n", "<leader>dl", "<cmd>DoItList<CR>", { desc = "Toggle DoIt List" })

-- Print instructions
print([[
=== Do-It.nvim Interactive Test Environment ===

Available commands:
- <leader>do : Open todos window
- <leader>dn : Open notes window  
- <leader>dl : Open todo list window

Inside todos window:
- i : Add new todo
- x : Toggle todo status
- d : Delete todo
- H : Add due date
- t : Toggle tags
- p : Edit priorities
- ? : Show help
- q : Close window

Inside notes window:
- m : Switch between project/global mode
- q : Close window

To test different window sizes/positions:
:lua require("doit").setup({ modules = { notes = { ui = { window = { use_relative = false, width = 100, height = 40 } } } } })

Press any key to continue...
]])

-- Wait for user input
vim.fn.getchar()

-- Clear the screen
vim.cmd("normal! :clear\n")

print("Ready for testing! Use the keymaps above to test the UI.")