-- Mine/Claude split: the classifier, the sort that puts Mine first, and the
-- banner rows build_render_rows emits only when both blocks have open items.
describe("origin blocks", function()
    local sorting = require("doit.modules.todos.state.sorting")

    describe("sorting.origin", function()
        local cases = {
            { { text = "plain", twin = { list = "daily", id = "x" } }, "claude" },
            { { text = "claude: x" }, "claude" },
            { { text = "[gate] 3. x" }, "claude" },
            { { text = "4. x" }, "claude" },
            { { text = "12b. x" }, "claude" },
            { { text = "  claude: indented" }, "claude" },
            { { text = "[[note]] x" }, "mine" },
            { { text = "1.5x faster" }, "mine" },
            { { text = "3.buy milk" }, "mine" },
            { { text = "plain" }, "mine" },
            { { text = "- inv: from the vault" }, "mine" },
            { { text = "plain", source = "mcp" }, "claude" },
            { { text = "5. x", source = "user" }, "mine" },
            { { text = "plain", twin = vim.NIL }, "mine" },
        }
        for _, c in ipairs(cases) do
            it(vim.inspect(c[1]) .. " -> " .. c[2], function()
                assert.are.equal(c[2], sorting.origin(c[1]))
            end)
        end
    end)

    -- runs before the render block, which swaps doit.core for a mock
    describe("nvim add path", function()
        it("stamps source user so a hand-typed rank stays Mine", function()
            package.loaded["doit.state"] = nil
            local doit = require("doit")
            doit.setup({ modules = { todos = { enabled = true } } })
            local doit_state = require("doit.state")
            doit_state.todos = {}
            doit_state.save_to_disk = function() end
            doit_state.save_todos = function() end

            local todo = doit_state.add_todo("3. typed by hand", {})
            assert.are.equal("user", todo.source)
            assert.are.equal("mine", sorting.origin(todo))
        end)
    end)

    describe("render", function()
        local mock_state

        local function displays()
            local out = {}
            for _, row in ipairs(require("doit.ui.main_window").build_render_rows()) do
                out[#out + 1] = row.display
            end
            return out
        end

        local function index_of(lines, needle)
            for i, l in ipairs(lines) do
                if l:find(needle, 1, true) then
                    return i
                end
            end
        end

        before_each(function()
            package.loaded["doit.ui.main_window"] = nil
            package.loaded["doit.ui.todo_actions"] = nil
            package.loaded["doit.config"] = nil
            require("doit.config").setup({})
            package.loaded["doit.calendar"] = {}

            mock_state = { todos = {}, active_filter = nil }
            mock_state.sort_todos = function()
                local ordered = sorting.structure_aware(mock_state.todos)
                for i, t in ipairs(ordered) do
                    mock_state.todos[i] = t
                end
            end
            package.loaded["doit.core"] = {
                get_module = function(name)
                    if name == "todos" then
                        return { state = mock_state }
                    end
                end,
            }
        end)

        it("puts a Mine banner above a Claude banner when both have open items", function()
            mock_state.todos = {
                { id = "c1", text = "[gate] 1. claude thing", done = false, order_index = 1, priorities = "critical" },
                { id = "m1", text = "my thing", done = false, order_index = 2 },
                { id = "m2", text = "my other thing", done = false, order_index = 3 },
            }
            local lines = displays()
            local mine, claude = index_of(lines, "── Mine "), index_of(lines, "── Claude ")
            assert.is_not_nil(mine)
            assert.is_not_nil(claude)
            assert.is_true(mine < claude)
            assert.truthy(lines[mine]:match(" 2$"))
            assert.truthy(lines[claude]:match(" 1$"))
            assert.are.equal("", lines[claude - 1])
            assert.is_true(index_of(lines, "my other thing") < claude)
            assert.is_true(index_of(lines, "claude thing") > claude)
            -- the first group in a block gets no blank before its header
            assert.are.equal("  Default", lines[mine + 1])
            assert.are.equal("  Critical", lines[claude + 1])
        end)

        it("keeps a plain child under its claude parent", function()
            mock_state.todos = {
                { id = "c1", text = "[gate] 1. parent", done = false, order_index = 1 },
                { id = "k1", text = "plain child", done = false, order_index = 2, parent_id = "c1" },
                { id = "m1", text = "mine", done = false, order_index = 3 },
            }
            local lines = displays()
            local claude = index_of(lines, "── Claude ")
            assert.is_true(index_of(lines, "plain child") > claude)
            assert.truthy(lines[claude]:match(" 2$"))
        end)

        it("renders in-progress items inside their own block", function()
            mock_state.todos = {
                { id = "c1", text = "claude: [bug] 1. started", done = false, in_progress = true, order_index = 1 },
                { id = "m1", text = "mine", done = false, order_index = 2 },
            }
            local lines = displays()
            local claude = index_of(lines, "── Claude ")
            assert.is_true(index_of(lines, "mine") < claude)
            assert.is_true(index_of(lines, "started") > claude)
        end)

        it("shows no banners when only one origin has open items", function()
            mock_state.todos = {
                { id = "c1", text = "[gate] 1. a", done = false, order_index = 1 },
                { id = "c2", text = "[gate] 2. b", done = false, order_index = 2 },
                { id = "m1", text = "mine but done", done = true, order_index = 3 },
            }
            local lines = displays()
            assert.is_nil(index_of(lines, "── Mine "))
            assert.is_nil(index_of(lines, "── Claude "))
        end)

        it("leaves done items in one shared section", function()
            mock_state.todos = {
                { id = "c1", text = "[gate] 1. open", done = false, order_index = 1 },
                { id = "m1", text = "mine open", done = false, order_index = 2 },
                { id = "c2", text = "[gate] 2. closed", done = true, order_index = 3 },
                { id = "m2", text = "mine closed", done = true, order_index = 4 },
            }
            local lines = displays()
            local claude = index_of(lines, "── Claude ")
            local divider
            for i, row in ipairs(require("doit.ui.main_window").build_render_rows()) do
                if row.kind == "divider" then
                    divider = i
                end
            end
            assert.is_true(divider > claude)
            assert.is_true(index_of(lines, "closed") > divider)
            assert.is_true(index_of(lines, "mine closed") > divider)
        end)
    end)
end)
