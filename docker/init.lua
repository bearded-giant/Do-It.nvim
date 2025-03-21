-- Minimal init.lua for dooing plugin testing

vim.opt.rtp:append("/plugin")

vim.opt.termguicolors = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Set up Neovim commands for dooing....based on my personal preferences
vim.api.nvim_create_user_command("ToDo", function()
	require("dooing").toggle_window()
end, { desc = "Toggle Dooing window" })

-- print("Dooing plugin initializing...")

local function test_file_access()
	local test_path = "/data/test_write.txt"

	print("Testing file access with: " .. test_path)
	local write_test = io.open(test_path, "w")
	if write_test then
		write_test:write("Test write at " .. os.date())
		write_test:close()
		print("✅ Successfully wrote test file")

		local read_test = io.open(test_path, "r")
		if read_test then
			local content = read_test:read("*all")
			read_test:close()
			print("✅ Successfully read test file: " .. content)
		else
			print("❌ Failed to read test file")
		end
	else
		print("❌ Failed to write test file")
	end

	-- Check the todos file
	local todos_path = "/data/dooing_todos.json"
	local todos_file = io.open(todos_path, "r")
	if todos_file then
		local content = todos_file:read("*all")
		todos_file:close()
		print("✅ Todos file exists with content length: " .. #content)

		-- Try to append to it
		local append_test = io.open(todos_path, "a")
		if append_test then
			append_test:close()
			print("✅ Can write to todos file")
		else
			print("❌ Cannot write to todos file")
		end
	else
		print("❌ Todos file not found or cannot be opened")
	end
end

test_file_access()

local dooing_storage = require("dooing.state.storage")
local original_setup = dooing_storage.setup

dooing_storage.setup = function(M, config)
	original_setup(M, config)

	-- Replace save_to_disk with our own implementation
	M.save_to_disk = function()
		local save_path = "/data/dooing_todos.json"
		print("Saving todos to: " .. save_path)

		-- Ensure todos is initialized
		if not M.todos then
			print("WARNING: M.todos is nil, initializing empty array")
			M.todos = {}
		end

		-- Convert todos to JSON
		local json_content = vim.fn.json_encode(M.todos)
		print("Encoded " .. #M.todos .. " todos to JSON (length: " .. #json_content .. ")")

		-- Write to file with explicit error handling
		local file, err = io.open(save_path, "w")
		if not file then
			print("ERROR: Failed to open file for writing: " .. (err or "unknown error"))
			return false
		end

		local ok, write_err = pcall(function()
			file:write(json_content)
		end)
		file:close()

		if not ok then
			print("ERROR: Failed to write to file: " .. (write_err or "unknown error"))
			return false
		end

		print("✅ Successfully saved todos to " .. save_path)

		-- Verify the file
		local verify_file = io.open(save_path, "r")
		if verify_file then
			local content = verify_file:read("*all")
			verify_file:close()
			print("✅ Verified file after save, size: " .. #content .. " bytes")
		else
			print("❌ Could not verify file after save")
		end

		-- Force sync to disk
		os.execute("sync")
		print("✅ Forced sync to disk")

		return true
	end

	-- Also override load from disk to be more robust
	M.load_from_disk = function()
		-- Use fixed path directly since config might not be fully initialized yet
		local save_path = "/data/dooing_todos.json"
		print("Loading todos from: " .. save_path)

		local file = io.open(save_path, "r")
		if not file then
			print("❌ Could not open todos file for reading")
			return
		end

		local content = file:read("*all")
		file:close()

		print("Read " .. #content .. " bytes from todos file")

		if content and content ~= "" then
			local ok, result = pcall(vim.fn.json_decode, content)
			if ok and result then
				M.todos = result
				print("✅ Successfully loaded " .. #M.todos .. " todos")
			else
				print("❌ Error parsing JSON: " .. (result or "unknown error"))
			end
		else
			print("⚠️ Todos file is empty")
			M.todos = {}
		end
	end
end

require("dooing").setup({
	save_path = "/data/dooing_todos.json",

	timestamp = {
		enabled = false,
	},

	window = {
		width = 140,
		height = 40,
		border = "rounded",
		position = "center",
		padding = {
			top = 1,
			bottom = 1,
			left = 2,
			right = 2,
		},
	},

	formatting = {
		pending = {
			icon = "○",
			format = { "icon", "notes_icon", "text", "due_date", "ect" },
		},
		in_progress = {
			icon = "◐",
			format = { "icon", "text", "due_date", "ect" },
		},
		done = {
			icon = "✓",
			format = { "icon", "notes_icon", "text", "due_date", "ect" },
		},
	},

	quick_keys = true,

	notes = {
		icon = "📓",
	},

	scratchpad = {
		syntax_highlight = "markdown",
	},

	keymaps = {
		toggle_window = "<leader>do",
		new_todo = "i",
		toggle_todo = "x",
		delete_todo = "d",
		delete_completed = "D",
		delete_confirmation = "<CR>",
		close_window = "<Esc>",
		undo_delete = "u",
		add_due_date = "H",
		remove_due_date = "r",
		toggle_help = "?",
		toggle_tags = "t",
		toggle_priority = "<Space>",
		clear_filter = "c",
		edit_todo = "e",
		edit_tag = "e",
		edit_priorities = "p",
		delete_tag = "d",
		search_todos = "/",
		add_time_estimation = "T",
		remove_time_estimation = "R",
		import_todos = "I",
		export_todos = "E",
		remove_duplicates = "<leader>D",
		open_todo_scratchpad = "<leader>p",
	},

	calendar = {
		language = "en",
		icon = "",
		keymaps = {
			previous_day = "h",
			next_day = "l",
			previous_week = "k",
			next_week = "j",
			previous_month = "H",
			next_month = "L",
			select_day = "<CR>",
			close_calendar = "q",
		},
	},

	priorities = {
		{
			name = "important",
			weight = 4,
		},
		{
			name = "urgent",
			weight = 2,
		},
	},
	priority_groups = {
		high = {
			members = { "important", "urgent" },
			color = nil,
			hl_group = "DiagnosticError",
		},
		medium = {
			members = { "important" },
			color = nil,
			hl_group = "DiagnosticWarn",
		},
		low = {
			members = { "urgent" },
			color = nil,
			hl_group = "DiagnosticInfo",
		},
	},
	hour_score_value = 1 / 8,
})

-- For debugging
vim.opt.verbosefile = "/tmp/nvim.log"
