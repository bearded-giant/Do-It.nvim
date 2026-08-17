local vim = vim

local core = require("doit.core")

-- Resolved lazily: this module is required while the todos module is still
-- registering, so capturing state at require time yields an empty table.
local function get_state()
    local todo_module = core.get_module("todos")
    if not todo_module then
        local ok, doit = pcall(require, "doit")
        if ok and doit.load_module then
            todo_module = doit.load_module("todos", {})
        end
    end
    return (todo_module and todo_module.state) or {}
end

local config = require("doit.config")
local todos_config = require("doit.modules.todos.config")

local M = {}

local tag_win_id = nil
local tag_buf_id = nil

function M.is_tag_window_open()
	return tag_win_id ~= nil and vim.api.nvim_win_is_valid(tag_win_id)
end

function M.close_tag_window()
	if M.is_tag_window_open() then
		vim.api.nvim_win_close(tag_win_id, true)
		tag_win_id = nil
		tag_buf_id = nil
		return true
	end
	return false
end

function M.create_tag_window(main_win_id)
	if tag_win_id and vim.api.nvim_win_is_valid(tag_win_id) then
		vim.api.nvim_win_close(tag_win_id, true)
		tag_win_id = nil
		tag_buf_id = nil
		return
	end

	tag_buf_id = vim.api.nvim_create_buf(false, true)

	local width = 30
	local height = 10
	-- headless has no attached UI, so fall back to the editor grid
	local ui = vim.api.nvim_list_uis()[1] or { width = vim.o.columns, height = vim.o.lines }
	local main_width = 40
	local main_col = math.floor((ui.width - main_width) / 2)
	local col = main_col - width - 2
	local row = math.floor((ui.height - height) / 2)

	tag_win_id = vim.api.nvim_open_win(tag_buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " tags ",
		title_pos = "center",
	})

	local state = get_state()

	-- get_all_tags returns { name = , count = } records, so the display string and
	-- the tag itself are kept apart: rows render with counts, actions look the tag
	-- up by line number instead of re-parsing what is on screen.
	local tag_names = {}

	local function render_tags()
		local tags = state.get_all_tags()
		local lines = {}
		tag_names = {}

		for _, tag in ipairs(tags) do
			table.insert(lines, string.format("#%s  (%d)", tag.name, tag.count))
			table.insert(tag_names, tag.name)
		end

		if #lines == 0 then
			lines = { "No tags found" }
		end

		vim.api.nvim_buf_set_option(tag_buf_id, "modifiable", true)
		vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, lines)
	end

	local function tag_at_cursor()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		return tag_names[cursor[1]]
	end

	render_tags()

	vim.keymap.set("n", "<CR>", function()
		local tag = tag_at_cursor()
		if tag then
			state.set_tag_filter(tag)
			M.close_tag_window()
			if main_win_id and vim.api.nvim_win_is_valid(main_win_id) then
				vim.api.nvim_set_current_win(main_win_id)
			end
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", todos_config.resolve_key("edit_tag"), function()
		local old_tag = tag_at_cursor()
		if old_tag then
			vim.ui.input({ prompt = "Edit tag: ", default = old_tag }, function(new_tag)
				if new_tag and new_tag ~= "" and new_tag ~= old_tag then
					state.rename_tag(old_tag, new_tag)
					render_tags()
				end
			end)
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", todos_config.resolve_key("delete_tag"), function()
		local tag = tag_at_cursor()
		if tag then
			state.delete_tag(tag)
			render_tags()
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", todos_config.resolve_key("close_window"), function()
		M.close_tag_window()
		if main_win_id and vim.api.nvim_win_is_valid(main_win_id) then
			vim.api.nvim_set_current_win(main_win_id)
		end
	end, { buffer = tag_buf_id, nowait = true })
	
	-- Always allow Esc to close
	vim.keymap.set("n", "<Esc>", function()
		M.close_tag_window()
		if main_win_id and vim.api.nvim_win_is_valid(main_win_id) then
			vim.api.nvim_set_current_win(main_win_id)
		end
	end, { buffer = tag_buf_id, nowait = true })
end

return M

