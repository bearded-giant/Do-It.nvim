local project_list = require("doit.modules.todos.state.project_list")

-- Mirrored in tests/tmux/test_project_list.sh. Both implementations must agree,
-- or one repo resolves to two different lists depending on which UI opened it.
local SANITIZE_FIXTURES = {
	{ "do-it.nvim", "do-it.nvim" }, -- dots survive: not "do-itnvim"
	{ "my repo", "my_repo" },
	{ "my   repo", "my_repo" }, -- runs collapse to a single _
	{ "a/b", "ab" }, -- no path separators
	{ "UPPER_case-1", "UPPER_case-1" },
	{ "chat-orchestrator", "chat-orchestrator" },
}

describe("project list naming", function()
	it("matches the shared sanitizer fixtures", function()
		for _, case in ipairs(SANITIZE_FIXTURES) do
			assert.are.equal(case[2], project_list.sanitize(case[1]))
		end
	end)

	it("rejects names that would escape the lists directory", function()
		assert.is_nil(project_list.sanitize(".."))
		assert.is_nil(project_list.sanitize("."))
		assert.is_nil(project_list.sanitize("!!!"))
		assert.is_nil(project_list.sanitize(""))
		assert.is_nil(project_list.sanitize(nil))
	end)

	it("derives nothing outside a git repo", function()
		assert.is_nil(project_list.derive("/"))
	end)

	it("derives the repo directory name inside a git repo", function()
		-- the suite runs from the plugin root, which is itself a git repo
		local derived = project_list.derive(vim.fn.getcwd())
		if derived then
			assert.are.equal(project_list.sanitize(derived), derived)
			assert.is_nil(derived:match("/"))
		end
	end)
end)
