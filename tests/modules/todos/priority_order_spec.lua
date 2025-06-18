local doit_state = require("doit.state")
local priorities = require("doit.state.priorities")
local config = require("doit.config")

describe("priority ordering", function()
    before_each(function()
        -- Reset state
        doit_state.todos = {}
        
        -- Set up the config with our test priorities
        config.options = {
            priorities = {
                {
                    name = "urgent",
                    weight = 8,
                },
                {
                    name = "important",
                    weight = 4,
                },
            },
        }

        -- Initialize priority weights
        doit_state.update_priority_weights()
    end)

    it("should sort urgent items before important ones", function()
        doit_state.todos = {
            { 
                text = "Important only", 
                done = false, 
                created_at = os.time(), 
                priorities = "important"
            },
            { 
                text = "Urgent only", 
                done = false, 
                created_at = os.time(), 
                priorities = "urgent"
            },
            { 
                text = "Both urgent and important (should be treated as urgent)", 
                done = false, 
                created_at = os.time(), 
                priorities = "urgent" -- Now single priority
            },
            { 
                text = "No priority", 
                done = false, 
                created_at = os.time(), 
                priorities = nil
            },
        }

        doit_state.sort_todos()

        assert.are.equal("Urgent only", doit_state.todos[1].text)
        assert.are.equal("Both urgent and important (should be treated as urgent)", doit_state.todos[2].text)
        assert.are.equal("Important only", doit_state.todos[3].text)
        assert.are.equal("No priority", doit_state.todos[4].text)
    end)

    it("should prioritize in-progress items at the top, then sorted by priority", function()
        doit_state.todos = {
            { 
                text = "Important only", 
                done = false, 
                created_at = os.time(), 
                priorities = "important"
            },
            { 
                text = "Urgent only (in progress)", 
                done = false, 
                in_progress = true,
                created_at = os.time(), 
                priorities = "urgent"
            },
            { 
                text = "Important only (in progress)", 
                done = false, 
                in_progress = true,
                created_at = os.time(), 
                priorities = "important"
            },
            { 
                text = "Urgent only", 
                done = false, 
                created_at = os.time(), 
                priorities = "urgent"
            },
        }

        doit_state.sort_todos()

        assert.are.equal("Urgent only (in progress)", doit_state.todos[1].text)
        assert.are.equal("Important only (in progress)", doit_state.todos[2].text)
        assert.are.equal("Urgent only", doit_state.todos[3].text)
        assert.are.equal("Important only", doit_state.todos[4].text)
    end)

    it("should prioritize by weight even with order_index", function()
        doit_state.todos = {
            { 
                text = "Important only", 
                done = false, 
                created_at = os.time(), 
                priorities = "important",
                order_index = 1
            },
            { 
                text = "Urgent only", 
                done = false, 
                created_at = os.time(), 
                priorities = "urgent",
                order_index = 2
            },
            { 
                text = "Both urgent and important", 
                done = false, 
                created_at = os.time(), 
                priorities = "urgent",
                order_index = 3
            },
            { 
                text = "No priority", 
                done = false, 
                created_at = os.time(), 
                priorities = nil,
                order_index = 4
            },
        }

        doit_state.sort_todos()

        assert.are.equal("Urgent only", doit_state.todos[1].text)
        assert.are.equal("Both urgent and important", doit_state.todos[2].text)
        assert.are.equal("Important only", doit_state.todos[3].text)
        assert.are.equal("No priority", doit_state.todos[4].text)
    end)
end)