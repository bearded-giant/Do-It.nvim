-- Minimal init.lua for dooing plugin testing

-- Add the plugin to runtime path
vim.opt.rtp:append("/plugin")

-- Load dooing plugin
require("dooing").setup()

-- Basic Neovim settings for testing
vim.opt.termguicolors = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"

-- For debugging
vim.opt.verbosefile = "/tmp/nvim.log"
