-- local vim = vim
local config = require("dooing.config")

-- hold the actual todo list, plus any other shared fields
local M = {
	todos = {}, -- main list of todos
	active_filter = nil, -- optional active tag filter
	deleted_todos = {}, -- history of deleted todos for undo
	MAX_UNDO_HISTORY = 100,
}

local storage = require("dooing.state.storage")
local todos_ops = require("dooing.state.todos")
local priorities = require("dooing.state.priorities")
local due_dates = require("dooing.state.due_dates")
local search_ops = require("dooing.state.search")
local sorting_ops = require("dooing.state.sorting")
local tags_ops = require("dooing.state.tags")

storage.setup(M, config)
todos_ops.setup(M, config)
priorities.setup(M, config)
due_dates.setup(M, config)
search_ops.setup(M, config)
sorting_ops.setup(M, config)
tags_ops.setup(M, config)

-- alias/convienence
function M.load_todos()
	-- load from disk, then update priority weights
	M.load_from_disk() -- from storage.lua
	M.update_priority_weights() -- from priorities.lua
end

-- alias for initial refactoring
function M.save_todos()
	M.save_to_disk()
end

return M
