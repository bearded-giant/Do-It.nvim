---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Explicitly declare vim as a global variable
local vim = vim

--------------------------------------------------------------------------------
-- DoingUI: Main entry point for all UI functionality in the Dooing plugin
-- This aggregator requires each submodule (help_window, tag_window, etc.)
-- and returns them as a single table (M). That way, you can do:
--     local ui = require("dooing.ui")
-- and access every piece of UI logic (main_window, help_window, etc.)
--------------------------------------------------------------------------------

---@class DoingUI
---@field main_window table  # The main to-do window logic (open/close/render).
---@field help_window table  # The "help" popup window logic.
---@field tag_window table   # The "tags" popup window logic.
---@field search_window table  # The "search" popup window logic.
---@field scratchpad table   # The scratchpad logic for editing notes.
---@field todo_actions table # The set of actions that can be performed on a to-do.
---@field highlights table   # Highlighting utilities for the UI.
local M = {}

-- Submodules
M.highlights = require("dooing.ui.highlights")
M.todo_actions = require("dooing.ui.todo_actions")
M.help_window = require("dooing.ui.help_window")
M.tag_window = require("dooing.ui.tag_window")
M.search_window = require("dooing.ui.search_window")
M.scratchpad = require("dooing.ui.scratchpad")
M.main_window = require("dooing.ui.main_window")

return M
