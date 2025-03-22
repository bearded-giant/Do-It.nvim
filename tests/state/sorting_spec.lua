local dooing_state = require("dooing.state")
local sorting = require("dooing.state.sorting")
local config = require("dooing.config")

describe("sorting", function()
    before_each(function()
        dooing_state.get_priority_score = function(todo)
            if todo.priorities then
                return #todo.priorities
            end
            return 0
        end
        
        config.options = {
            priorities = {"p1", "p2", "p3"}
        }
    end)

    it("should sort by completion status first", function()
        dooing_state.todos = {
            {text = "Done todo", done = true, created_at = os.time()},
            {text = "Pending todo", done = false, created_at = os.time()}
        }
        
        dooing_state.sort_todos()
        
        assert.are.equal("Pending todo", dooing_state.todos[1].text)
        assert.are.equal("Done todo", dooing_state.todos[2].text)
    end)

    it("should sort by priority score second", function()
        dooing_state.todos = {
            {text = "Low priority", done = false, created_at = os.time(), priorities = {"p3"}},
            {text = "High priority", done = false, created_at = os.time(), priorities = {"p1", "p2"}}
        }
        
        dooing_state.sort_todos()
        
        assert.are.equal("High priority", dooing_state.todos[1].text)
        assert.are.equal("Low priority", dooing_state.todos[2].text)
    end)

    it("should sort by due date third", function()
        local now = os.time()
        local tomorrow = now + 86400 -- 24 hours
        local nextWeek = now + 604800 -- 7 days
        
        dooing_state.todos = {
            {text = "Due next week", done = false, created_at = now, priorities = {}, due_at = nextWeek},
            {text = "Due tomorrow", done = false, created_at = now, priorities = {}, due_at = tomorrow}
        }
        
        dooing_state.sort_todos()
        
        assert.are.equal("Due tomorrow", dooing_state.todos[1].text)
        assert.are.equal("Due next week", dooing_state.todos[2].text)
    end)

    it("should sort items with due dates before those without", function()
        local now = os.time()
        local tomorrow = now + 86400 -- 24 hours
        
        dooing_state.todos = {
            {text = "No due date", done = false, created_at = now, priorities = {}},
            {text = "Has due date", done = false, created_at = now, priorities = {}, due_at = tomorrow}
        }
        
        dooing_state.sort_todos()
        
        assert.are.equal("Has due date", dooing_state.todos[1].text)
        assert.are.equal("No due date", dooing_state.todos[2].text)
    end)

    it("should sort by creation time last", function()
        local earlier = os.time() - 86400 -- 24 hours ago
        local later = os.time()
        
        dooing_state.todos = {
            {text = "Newer todo", done = false, created_at = later, priorities = {}},
            {text = "Older todo", done = false, created_at = earlier, priorities = {}}
        }
        
        dooing_state.sort_todos()
        
        assert.are.equal("Older todo", dooing_state.todos[1].text)
        assert.are.equal("Newer todo", dooing_state.todos[2].text)
    end)

    it("should handle complex sorting with all criteria", function()
        local now = os.time()
        local yesterday = now - 86400
        local tomorrow = now + 86400
        
        dooing_state.todos = {
            {text = "Done, high priority", done = true, created_at = yesterday, priorities = {"p1", "p2"}},
            {text = "Pending, high priority, due tomorrow", done = false, created_at = now, priorities = {"p1", "p2"}, due_at = tomorrow},
            {text = "Pending, low priority, due tomorrow", done = false, created_at = yesterday, priorities = {"p3"}, due_at = tomorrow},
            {text = "Pending, high priority, no due date", done = false, created_at = now, priorities = {"p1", "p2"}},
            {text = "Done, low priority", done = true, created_at = now, priorities = {"p3"}}
        }
        
        dooing_state.sort_todos()
        
        assert.is_false(dooing_state.todos[1].done)
        assert.is_false(dooing_state.todos[2].done)
        assert.is_false(dooing_state.todos[3].done)
        
        assert.is_true(dooing_state.todos[4].done)
        assert.is_true(dooing_state.todos[5].done)
    end)
end)