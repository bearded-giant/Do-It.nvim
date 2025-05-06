-- local vim = vim
local config = require("doit.config")

-- hold the actual todo list, plus any other shared fields
local M = {
	todos = {}, -- main list of todos
	active_filter = nil, -- optional active tag filter
	active_category = nil, -- optional active category filter
	deleted_todos = {}, -- history of deleted todos for undo
	MAX_UNDO_HISTORY = 100,
	reordering_todo_index = nil, -- currently reordering todo index
}

local storage = require("doit.state.storage")
local todos_ops = require("doit.state.todos")
local priorities = require("doit.state.priorities")
local due_dates = require("doit.state.due_dates")
local search_ops = require("doit.state.search")
local sorting_ops = require("doit.state.sorting")
local tags_ops = require("doit.state.tags")
local project_ops = require("doit.state.project")

storage.setup(M, config)
todos_ops.setup(M, config)
priorities.setup(M, config)
due_dates.setup(M, config)
search_ops.setup(M, config)
sorting_ops.setup(M, config)
tags_ops.setup(M, config)
project_ops.setup(M, config)

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

-- Category filter functionality
function M.set_category_filter(category)
	if category == "" then
		category = nil
	end
	M.active_category = category
end

function M.clear_category_filter()
	M.active_category = nil
end

return M
