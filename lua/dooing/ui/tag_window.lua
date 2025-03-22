local vim = vim

local state = require("doit.state")
state.load_todos()

local config = require("doit.config")

local M = {}

local tag_win_id = nil
local tag_buf_id = nil

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
	local ui = vim.api.nvim_list_uis()[1]
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

	local tags = state.get_all_tags()
	if #tags == 0 then
		tags = { "No tags found" }
	end

	vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, tags)
	vim.api.nvim_buf_set_option(tag_buf_id, "modifiable", true)

	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if tag ~= "No tags found" then
			state.set_filter(tag)
			vim.api.nvim_win_close(tag_win_id, true)
			tag_win_id = nil
			tag_buf_id = nil
			if main_win_id then
				vim.api.nvim_set_current_win(main_win_id)
			end
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", config.options.keymaps.edit_tag, function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local old_tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if old_tag ~= "No tags found" then
			vim.ui.input({ prompt = "Edit tag: ", default = old_tag }, function(new_tag)
				if new_tag and new_tag ~= "" and new_tag ~= old_tag then
					state.rename_tag(old_tag, new_tag)
					local updated_tags = state.get_all_tags()
					if #updated_tags == 0 then
						updated_tags = { "No tags found" }
					end
					vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, updated_tags)
				end
			end)
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", config.options.keymaps.delete_tag, function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if tag ~= "No tags found" then
			state.delete_tag(tag)
			local updated_tags = state.get_all_tags()
			if #updated_tags == 0 then
				updated_tags = { "No tags found" }
			end
			vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, updated_tags)
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", "q", function()
		if vim.api.nvim_win_is_valid(tag_win_id) then
			vim.api.nvim_win_close(tag_win_id, true)
		end
		tag_win_id = nil
		tag_buf_id = nil
		if main_win_id then
			vim.api.nvim_set_current_win(main_win_id)
		end
	end, { buffer = tag_buf_id })
end

return M
