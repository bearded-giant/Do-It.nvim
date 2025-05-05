-- UI components for the todos module
local M = {}

-- Setup function for the todos UI
function M.setup()
    -- Load all UI components
    M.highlights = require("doit.modules.todos.ui.highlights")
    M.todo_actions = require("doit.modules.todos.ui.todo_actions")
    M.help_window = require("doit.modules.todos.ui.help_window")
    M.tag_window = require("doit.modules.todos.ui.tag_window")
    M.search_window = require("doit.modules.todos.ui.search_window")
    M.scratchpad = require("doit.modules.todos.ui.scratchpad")
    M.main_window = require("doit.modules.todos.ui.main_window")
    M.list_window = require("doit.modules.todos.ui.list_window")
    
    return M
end

return M