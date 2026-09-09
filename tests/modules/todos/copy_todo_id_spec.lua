-- The id is what the MCP resolves across lists, so yanking it has to land in the
-- system register, not just the unnamed one.

describe("copy todo id", function()
	local main_window

	before_each(function()
		package.loaded["doit.ui.main_window"] = nil
		main_window = require("doit.ui.main_window")
		vim.fn.setreg("+", "")
		vim.fn.setreg('"', "")
	end)

	it("yanks the id of the given todo", function()
		main_window.copy_todo_id({ id = "1757012345_4821", text = "fix the thing" })

		assert.are.equal("1757012345_4821", vim.fn.getreg('"'))
		-- headless CI has no clipboard provider, so + is a no-op there
		if vim.fn.has("clipboard") == 1 then
			assert.are.equal("1757012345_4821", vim.fn.getreg("+"))
		end
	end)

	it("leaves the registers alone when there is no id", function()
		main_window.copy_todo_id({ text = "no id yet" })

		assert.are.equal("", vim.fn.getreg('"'))
	end)
end)
