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
                { text = "Done", done = true, in_progress = false, timestamp = 1 },
                { text = "Not done", done = false, in_progress = false, timestamp = 2 },
            }

            sorting.sort_todos()

            assert.are.equal("Not done", state.todos[1].text)
            assert.are.equal("Done", state.todos[2].text)
        end)

        it("should sort in_progress before pending", function()
            state.todos = {
                { text = "Pending", done = false, in_progress = false, timestamp = 1 },
                { text = "Active", done = false, in_progress = true, timestamp = 2 },
            }

            sorting.sort_todos()

            assert.are.equal("Active", state.todos[1].text)
            assert.are.equal("Pending", state.todos[2].text)
        end)

        it("should sort by priority score within same status", function()
            state.todos = {
                { text = "Low", done = false, in_progress = false, _priority_weight = 1, timestamp = 1 },
                { text = "High", done = false, in_progress = false, _priority_weight = 10, timestamp = 2 },
            }

            sorting.sort_todos()

            assert.are.equal("High", state.todos[1].text)
            assert.are.equal("Low", state.todos[2].text)
        end)

        it("should sort by order_index as tiebreaker", function()
            state.todos = {
                { text = "Second", done = false, in_progress = false, order_index = 2, timestamp = 1 },
                { text = "First", done = false, in_progress = false, order_index = 1, timestamp = 2 },
            }

            sorting.sort_todos()

            assert.are.equal("First", state.todos[1].text)
            assert.are.equal("Second", state.todos[2].text)
        end)

        it("should sort by timestamp when all else is equal", function()
            state.todos = {
                { text = "Newer", done = false, in_progress = false, timestamp = 200 },
                { text = "Older", done = false, in_progress = false, timestamp = 100 },
            }

            sorting.sort_todos()

            assert.are.equal("Older", state.todos[1].text)
            assert.are.equal("Newer", state.todos[2].text)
        end)

        it("should handle full sort with mixed statuses", function()
            state.todos = {
                { text = "Done", done = true, in_progress = false, timestamp = 1 },
                { text = "Active high", done = false, in_progress = true, _priority_weight = 10, timestamp = 2 },
                { text = "Pending low", done = false, in_progress = false, _priority_weight = 1, timestamp = 3 },
                { text = "Active low", done = false, in_progress = true, _priority_weight = 1, timestamp = 4 },
                { text = "Pending high", done = false, in_progress = false, _priority_weight = 10, timestamp = 5 },
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
                { text = "Todo #work", done = false, in_progress = false, timestamp = 1 },
                { text = "Todo #home", done = false, in_progress = false, timestamp = 2 },
            }
            state.active_filter = nil

            local filtered = sorting.get_filtered_todos()
            assert.are.equal(2, #filtered)
        end)

        it("should filter by tag when filter is set", function()
            state.todos = {
                { text = "Todo #work stuff", done = false, in_progress = false, timestamp = 1 },
                { text = "Todo #home stuff", done = false, in_progress = false, timestamp = 2 },
                { text = "Another #work item", done = false, in_progress = false, timestamp = 3 },
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
                { text = "Done #tag", done = true, in_progress = false, timestamp = 1 },
                { text = "Active #tag", done = false, in_progress = true, timestamp = 2 },
            }
            state.active_filter = "tag"

            local filtered = sorting.get_filtered_todos()
            assert.are.equal(2, #filtered)
            assert.are.equal("Active #tag", filtered[1].text)
            assert.are.equal("Done #tag", filtered[2].text)
        end)
    end)
end)
