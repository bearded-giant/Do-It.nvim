-- Tests for todos sorting module
local sorting_module = require("doit.modules.todos.state.sorting")

describe("todos sorting", function()
    local sorting
    local state

    before_each(function()
        state = {
            todos = {},
            active_filter = nil,
            get_priority_score = function(todo)
                return todo._priority_weight or 0
            end,
        }
        sorting = sorting_module.setup(state)
    end)

    describe("sort_todos", function()
        it("should sort incomplete before done", function()
            state.todos = {
                { text = "Done", done = true, in_progress = false, created_at = 1 },
                { text = "Not done", done = false, in_progress = false, created_at = 2 },
            }

            sorting.sort_todos()

            assert.are.equal("Not done", state.todos[1].text)
            assert.are.equal("Done", state.todos[2].text)
        end)

        it("should sort in_progress before pending", function()
            state.todos = {
                { text = "Pending", done = false, in_progress = false, created_at = 1 },
                { text = "Active", done = false, in_progress = true, created_at = 2 },
            }

            sorting.sort_todos()

            assert.are.equal("Active", state.todos[1].text)
            assert.are.equal("Pending", state.todos[2].text)
        end)

        it("should sort by priority rank within same status", function()
            state.todos = {
                { text = "None", done = false, in_progress = false, created_at = 1 },
                { text = "Critical", done = false, in_progress = false, priorities = "critical", created_at = 2 },
            }

            sorting.sort_todos()

            assert.are.equal("Critical", state.todos[1].text)
            assert.are.equal("None", state.todos[2].text)
        end)

        it("should order critical > urgent > important > none (tmux parity)", function()
            -- regression guard: nvim list order must match the tmux view.
            -- pending items ranked by priority string, independent of weighted config.
            state.todos = {
                { text = "none", done = false, in_progress = false, created_at = 1 },
                { text = "important", done = false, in_progress = false, priorities = "important", created_at = 2 },
                { text = "critical", done = false, in_progress = false, priorities = "critical", created_at = 3 },
                { text = "urgent", done = false, in_progress = false, priorities = "urgent", created_at = 4 },
            }

            sorting.sort_todos()

            assert.are.equal("critical", state.todos[1].text)
            assert.are.equal("urgent", state.todos[2].text)
            assert.are.equal("important", state.todos[3].text)
            assert.are.equal("none", state.todos[4].text)
        end)

        it("should keep in_progress ahead of higher-priority pending (tmux parity)", function()
            -- in_progress leads the list even when a pending item outranks it
            state.todos = {
                { text = "pending critical", done = false, in_progress = false, priorities = "critical", created_at = 1 },
                { text = "active none", done = false, in_progress = true, created_at = 2 },
            }

            sorting.sort_todos()

            assert.are.equal("active none", state.todos[1].text)
            assert.are.equal("pending critical", state.todos[2].text)
        end)

        it("should sort by order_index as tiebreaker", function()
            state.todos = {
                { text = "Second", done = false, in_progress = false, order_index = 2, created_at = 1 },
                { text = "First", done = false, in_progress = false, order_index = 1, created_at = 2 },
            }

            sorting.sort_todos()

            assert.are.equal("First", state.todos[1].text)
            assert.are.equal("Second", state.todos[2].text)
        end)

        it("should sort by created_at when all else is equal", function()
            state.todos = {
                { text = "Newer", done = false, in_progress = false, created_at = 200 },
                { text = "Older", done = false, in_progress = false, created_at = 100 },
            }

            sorting.sort_todos()

            assert.are.equal("Older", state.todos[1].text)
            assert.are.equal("Newer", state.todos[2].text)
        end)

        it("should handle full sort with mixed statuses", function()
            state.todos = {
                { text = "Done", done = true, in_progress = false, created_at = 1 },
                { text = "Active high", done = false, in_progress = true, _priority_weight = 10, created_at = 2 },
                { text = "Pending low", done = false, in_progress = false, _priority_weight = 1, created_at = 3 },
                { text = "Active low", done = false, in_progress = true, _priority_weight = 1, created_at = 4 },
                { text = "Pending high", done = false, in_progress = false, _priority_weight = 10, created_at = 5 },
            }

            sorting.sort_todos()

            -- in_progress comes first, then pending, then done
            assert.is_true(state.todos[1].in_progress)
            assert.is_true(state.todos[2].in_progress)
            assert.is_false(state.todos[3].in_progress)
            assert.is_false(state.todos[3].done)
            assert.is_false(state.todos[4].in_progress)
            assert.is_false(state.todos[4].done)
            assert.is_true(state.todos[5].done)
        end)
    end)

    describe("get_filtered_todos", function()
        it("should return all todos when no filter set", function()
            state.todos = {
                { text = "Todo #work", done = false, in_progress = false, created_at = 1 },
                { text = "Todo #home", done = false, in_progress = false, created_at = 2 },
            }
            state.active_filter = nil

            local filtered = sorting.get_filtered_todos()
            assert.are.equal(2, #filtered)
        end)

        it("should filter by tag when filter is set", function()
            state.todos = {
                { text = "Todo #work stuff", done = false, in_progress = false, created_at = 1 },
                { text = "Todo #home stuff", done = false, in_progress = false, created_at = 2 },
                { text = "Another #work item", done = false, in_progress = false, created_at = 3 },
            }
            state.active_filter = "work"

            local filtered = sorting.get_filtered_todos()
            assert.are.equal(2, #filtered)
            for _, todo in ipairs(filtered) do
                assert.truthy(todo.text:find("#work"))
            end
        end)

        it("should return sorted results", function()
            state.todos = {
                { text = "Done #tag", done = true, in_progress = false, created_at = 1 },
                { text = "Active #tag", done = false, in_progress = true, created_at = 2 },
            }
            state.active_filter = "tag"

            local filtered = sorting.get_filtered_todos()
            assert.are.equal(2, #filtered)
            assert.are.equal("Active #tag", filtered[1].text)
            assert.are.equal("Done #tag", filtered[2].text)
        end)
    end)

    describe("sequence", function()
        local function texts(todos)
            local out = {}
            for i, t in ipairs(todos) do
                out[i] = t.text
            end
            return out
        end

        it("runs sequenced pending items first, across priority", function()
            state.todos = {
                { text = "critical", done = false, in_progress = false, priorities = "critical", order_index = 1 },
                { text = "seq 2", done = false, in_progress = false, sequence = 2, order_index = 2 },
                { text = "seq 1 important", done = false, in_progress = false, priorities = "important", sequence = 1, order_index = 3 },
                { text = "active seq", done = false, in_progress = true, sequence = 1, order_index = 4 },
            }

            sorting.sort_todos()

            assert.are.same({ "active seq", "seq 1 important", "seq 2", "critical" }, texts(state.todos))
        end)

        it("shifts only the colliding run when setting a position", function()
            local a = { text = "a", sequence = 1 }
            local b = { text = "b", sequence = 2 }
            local c = { text = "c", sequence = 5 }
            local x = { text = "x" }
            local todos = { a, b, c, x }

            sorting_module.set_sequence(todos, x, 2)
            assert.are.same({ 1, 3, 5, 2 }, { a.sequence, b.sequence, c.sequence, x.sequence })

            sorting_module.set_sequence(todos, x, nil)
            assert.is_nil(x.sequence)
        end)
    end)
end)
