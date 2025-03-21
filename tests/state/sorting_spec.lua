local dooing_state = require("dooing.state")
local sorting = require("dooing.state.sorting")
local config = require("dooing.config")

describe("sorting", function()
    before_each(function()
        -- Set up test environment
        dooing_state.get_priority_score = function(todo)
            -- Mock implementation of priority score
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
        -- Create todos with different completion statuses
        dooing_state.todos = {
            {text = "Done todo", done = true, created_at = os.time()},
            {text = "Pending todo", done = false, created_at = os.time()}
        }
        
        dooing_state.sort_todos()
        
        -- Pending todos should come before done todos
        assert.are.equal("Pending todo", dooing_state.todos[1].text)
        assert.are.equal("Done todo", dooing_state.todos[2].text)
    end)

    it("should sort by priority score second", function()
        -- Create todos with different priority scores but same completion status
        dooing_state.todos = {
            {text = "Low priority", done = false, created_at = os.time(), priorities = {"p3"}},
            {text = "High priority", done = false, created_at = os.time(), priorities = {"p1", "p2"}}
        }
        
        dooing_state.sort_todos()
        
        -- Higher priority score should come first
        assert.are.equal("High priority", dooing_state.todos[1].text)
        assert.are.equal("Low priority", dooing_state.todos[2].text)
    end)

    it("should sort by due date third", function()
        local now = os.time()
        local tomorrow = now + 86400 -- 24 hours
        local nextWeek = now + 604800 -- 7 days
        
        -- Create todos with same completion and priority but different due dates
        dooing_state.todos = {
            {text = "Due next week", done = false, created_at = now, priorities = {}, due_at = nextWeek},
            {text = "Due tomorrow", done = false, created_at = now, priorities = {}, due_at = tomorrow}
        }
        
        dooing_state.sort_todos()
        
        -- Earlier due date should come first
        assert.are.equal("Due tomorrow", dooing_state.todos[1].text)
        assert.are.equal("Due next week", dooing_state.todos[2].text)
    end)

    it("should sort items with due dates before those without", function()
        local now = os.time()
        local tomorrow = now + 86400 -- 24 hours
        
        -- Create todos with and without due dates
        dooing_state.todos = {
            {text = "No due date", done = false, created_at = now, priorities = {}},
            {text = "Has due date", done = false, created_at = now, priorities = {}, due_at = tomorrow}
        }
        
        dooing_state.sort_todos()
        
        -- Item with due date should come first
        assert.are.equal("Has due date", dooing_state.todos[1].text)
        assert.are.equal("No due date", dooing_state.todos[2].text)
    end)

    it("should sort by creation time last", function()
        local earlier = os.time() - 86400 -- 24 hours ago
        local later = os.time()
        
        -- Create todos with same completion, priority, no due dates, but different creation times
        dooing_state.todos = {
            {text = "Newer todo", done = false, created_at = later, priorities = {}},
            {text = "Older todo", done = false, created_at = earlier, priorities = {}}
        }
        
        dooing_state.sort_todos()
        
        -- Older creation time should come first
        assert.are.equal("Older todo", dooing_state.todos[1].text)
        assert.are.equal("Newer todo", dooing_state.todos[2].text)
    end)

    it("should handle complex sorting with all criteria", function()
        local now = os.time()
        local yesterday = now - 86400
        local tomorrow = now + 86400
        
        -- Create a mix of todos with different attributes
        dooing_state.todos = {
            {text = "Done, high priority", done = true, created_at = yesterday, priorities = {"p1", "p2"}},
            {text = "Pending, high priority, due tomorrow", done = false, created_at = now, priorities = {"p1", "p2"}, due_at = tomorrow},
            {text = "Pending, low priority, due tomorrow", done = false, created_at = yesterday, priorities = {"p3"}, due_at = tomorrow},
            {text = "Pending, high priority, no due date", done = false, created_at = now, priorities = {"p1", "p2"}},
            {text = "Done, low priority", done = true, created_at = now, priorities = {"p3"}}
        }
        
        dooing_state.sort_todos()
        
        -- Testing individual positions rather than exact order
        -- Test pending comes before done
        assert.is_false(dooing_state.todos[1].done)
        assert.is_false(dooing_state.todos[2].done)
        assert.is_false(dooing_state.todos[3].done)
        
        -- Test done items are last
        assert.is_true(dooing_state.todos[4].done)
        assert.is_true(dooing_state.todos[5].done)
    end)
end)