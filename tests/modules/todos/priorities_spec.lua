-- Tests for todos priorities module
local priorities_module = require("doit.modules.todos.state.priorities")

describe("todos priorities", function()
    local priorities
    local state

    before_each(function()
        state = {
            todos = {},
        }

        -- Mock the config module
        package.loaded["doit.modules.todos.config"] = {
            options = {
                priorities = {
                    { name = "critical", weight = 10 },
                    { name = "high", weight = 5 },
                    { name = "low", weight = 1 },
                }
            }
        }

        priorities = priorities_module.setup(state)
    end)

    after_each(function()
        package.loaded["doit.modules.todos.config"] = nil
    end)

    describe("get_priority_score", function()
        it("should return base score for incomplete todo without priority", function()
            local todo = { text = "Basic todo", done = false, in_progress = false }
            local score = priorities.get_priority_score(todo)
            -- not done => +10
            assert.are.equal(10, score)
        end)

        it("should give higher score to in_progress todos", function()
            local todo = { text = "Active", done = false, in_progress = true }
            local score = priorities.get_priority_score(todo)
            -- in_progress => +100, not done => +10
            assert.are.equal(110, score)
        end)

        it("should include priority weight", function()
            local todo = {
                text = "Critical task",
                done = false,
                in_progress = false,
                priorities = "critical",
                _priority_weight = 10,
            }
            local score = priorities.get_priority_score(todo)
            -- weight 10 + not done 10 = 20
            assert.are.equal(20, score)
        end)

        it("should return 0 for done todos", function()
            -- done todos don't get the +10 base but do get weight if set
            local todo = { text = "Done", done = true, in_progress = false }
            local score = priorities.get_priority_score(todo)
            assert.are.equal(0, score)
        end)
    end)

    describe("update_priority_weights", function()
        it("should set _priority_weight on todos with matching priorities", function()
            state.todos = {
                { text = "Critical task", priorities = "critical" },
                { text = "Low task", priorities = "low" },
                { text = "No priority" },
            }

            priorities.update_priority_weights()

            assert.are.equal(10, state.todos[1]._priority_weight)
            assert.are.equal(1, state.todos[2]._priority_weight)
            assert.is_nil(state.todos[3]._priority_weight)
        end)
    end)
end)
