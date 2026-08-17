local normalize = require("doit.modules.todos.state.normalize")

-- These fixtures are mirrored in mcp/todo-text.test.mjs. Any change here must
-- land there in the same commit, or nvim and MCP silently disagree about what
-- counts as a duplicate.
local FIXTURES = {
	{ "buy milk", "buy milk" },
	{ "claude: [chore] 3. buy milk (dep on #1)", "buy milk" },
	{ "Claude: [Chore] 3. Buy Milk (Dep On #1)", "buy milk" },
	{ "  buy   milk  ", "buy milk" },
	{ "buy\nmilk", "buy milk" },
	-- a note-link prefix is not a type tag and must survive
	{ "[[my note]] buy milk", "[[my note]] buy milk" },
	-- a rank needs the trailing space, so these keep their leading number
	{ "1.5x throughput fix", "1.5x throughput fix" },
	{ "3.buy milk", "3.buy milk" },
	-- lettered rank suffixes are still ranks
	{ "5b. audit ops", "audit ops" },
	{ "", "" },
	{ "claude: [gate] 12.", "12." },
}

describe("todo text normalization", function()
	it("matches the shared fixture set", function()
		for _, case in ipairs(FIXTURES) do
			local input, want = case[1], case[2]
			assert.are.equal(want, normalize.normalize(input))
		end
	end)

	it("collapses nvim-typed and MCP-created forms of the same todo", function()
		assert.are.equal(
			normalize.normalize("buy milk"),
			normalize.normalize("claude: [chore] 3. buy milk (dep on #1)")
		)
	end)

	it("keeps genuinely different bodies apart", function()
		assert.are_not.equal(normalize.normalize("buy milk"), normalize.normalize("buy bread"))
	end)

	it("handles nil", function()
		assert.are.equal("", normalize.normalize(nil))
	end)
end)
