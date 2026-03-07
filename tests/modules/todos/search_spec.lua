-- Tests for todos search module
local search_module = require("doit.modules.todos.state.search")

describe("todos search", function()
    local search
    local state

    before_each(function()
        state = {
            todos = {
                { text = "Buy groceries", done = false, in_progress = false },
                { text = "Write unit tests", done = false, in_progress = true },
                { text = "Fix login bug", done = true, in_progress = false },
                { text = "Update documentation", done = false, in_progress = false },
                { text = "Review pull request", done = true, in_progress = false },
            }
        }
        search = search_module.setup(state)
    end)

    describe("search_todos", function()
        it("should find todos matching query", function()
            local results = search.search_todos("bug")
            assert.are.equal(1, #results)
            assert.are.equal("Fix login bug", results[1].text)
        end)

        it("should be case-insensitive", function()
            local results = search.search_todos("BUY")
            assert.are.equal(1, #results)
            assert.are.equal("Buy groceries", results[1].text)
        end)

        it("should return multiple matches", function()
            local results = search.search_todos("u")
            -- "Buy groceries", "Write unit tests", "Fix login bug", "Update documentation", "Review pull request"
            assert.is_true(#results >= 3)
        end)

        it("should return all todos for empty query", function()
            local results = search.search_todos("")
            assert.are.equal(5, #results)
        end)

        it("should return all todos for nil query", function()
            local results = search.search_todos(nil)
            assert.are.equal(5, #results)
        end)

        it("should return empty for no matches", function()
            local results = search.search_todos("zzzznotfound")
            assert.are.equal(0, #results)
        end)
    end)

    describe("fuzzy_search", function()
        it("should match characters in order", function()
            -- "wut" should match "Write unit tests" (W...u...t)
            local results = search.fuzzy_search("wut")
            local found = false
            for _, r in ipairs(results) do
                if r.text == "Write unit tests" then found = true end
            end
            assert.is_true(found)
        end)

        it("should return all todos for empty query", function()
            local results = search.fuzzy_search("")
            assert.are.equal(5, #results)
        end)

        it("should return empty for impossible match", function()
            local results = search.fuzzy_search("zzz")
            assert.are.equal(0, #results)
        end)
    end)

    describe("filter_by_status", function()
        it("should filter done todos", function()
            local results = search.filter_by_status("done")
            assert.are.equal(2, #results)
            for _, r in ipairs(results) do
                assert.is_true(r.done)
            end
        end)

        it("should filter pending todos", function()
            local results = search.filter_by_status("pending")
            -- pending = not done (3 items: groceries, tests, documentation)
            assert.are.equal(3, #results)
            for _, r in ipairs(results) do
                assert.is_false(r.done)
            end
        end)

        it("should filter in_progress todos", function()
            local results = search.filter_by_status("in_progress")
            assert.are.equal(1, #results)
            assert.are.equal("Write unit tests", results[1].text)
        end)
    end)
end)
