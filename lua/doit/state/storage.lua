-- Handles loading/saving from disk, plus importing/exporting.

local vim = vim

local Storage = {}

function Storage.setup(M, config)
	function M.save_to_disk()
		if not config.options.save_path then
			config.options.save_path = vim.fn.stdpath("data") .. "/doit_todos.json"
		end

		local file = io.open(config.options.save_path, "w")
		if file then
			file:write(vim.fn.json_encode(M.todos))
			file:close()
		end
	end

	function M.load_from_disk()
		if not config.options.save_path then
			config.options.save_path = vim.fn.stdpath("data") .. "/doit_todos.json"
		end

		local file = io.open(config.options.save_path, "r")
		if file then
			local content = file:read("*all")
			file:close()
			if content and content ~= "" then
				M.todos = vim.fn.json_decode(content)

				local needs_migration = false
				for i, todo in ipairs(M.todos) do
					if not todo.order_index then
						todo.order_index = i
						needs_migration = true
					end
				end

				if needs_migration then
					M.save_to_disk()
				end
			end
		end
	end

	function M.import_todos(file_path)
		local file = io.open(file_path, "r")
		if not file then
			return false, "Could not open file: " .. file_path
		end
		local content = file:read("*all")
		file:close()

		local status, imported_todos = pcall(vim.fn.json_decode, content)
		if not status then
			return false, "Error parsing JSON file"
		end

		-- Merge
		for _, todo in ipairs(imported_todos) do
			table.insert(M.todos, todo)
		end

		M.sort_todos() -- from sorting.lua
		M.save_to_disk()
		return true, string.format("Imported %d todos", #imported_todos)
	end

	function M.export_todos(file_path)
		local file = io.open(file_path, "w")
		if not file then
			return false, "Could not open file for writing: " .. file_path
		end

		local json_content = vim.fn.json_encode(M.todos)
		file:write(json_content)
		file:close()
		return true, string.format("Exported %d todos to %s", #M.todos, file_path)
	end
end

return Storage
