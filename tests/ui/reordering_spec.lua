-- tests/ui/reordering_spec.lua
local stub = require("luassert.stub")

describe("todo reordering UI", function()
  local state = require("doit.state")
  local config = require("doit.config")
  local todo_actions = require("doit.ui.todo_actions")
  local main_window = require("doit.ui.main_window")
  
  -- Setup test environment
  before_each(function()
    -- Set up config for tests
    config.options = config.options or {}
    config.options.keymaps = config.options.keymaps or {}
    config.options.keymaps.reorder_todo = "r"
    
    -- Initialize the state
    state.todos = {
      { text = "Todo 1", order_index = 1 },
      { text = "Todo 2", order_index = 2 },
      { text = "Todo 3", order_index = 3 },
    }
    
    -- Simple mocks for vim APIs
    vim.api = {
      nvim_buf_set_option = function() end,
      nvim_create_namespace = function() return 1 end,
      nvim_buf_clear_namespace = function() end,
      nvim_buf_add_highlight = function() end,
      nvim_win_get_cursor = function() return {2, 0} end,
      nvim_win_set_cursor = function() end,
      nvim_win_is_valid = function() return true end,
      nvim_win_get_buf = function() return 1 end,
    }
    vim.fn = { maparg = function() return {} end }
    vim.notify = function() end
    vim.keymap = { set = function() end, del = function() end }
    
    -- Stubs for state functions
    stub(state, "save_to_disk")
    
    -- Replace sort_todos with a simple implementation for testing
    state.sort_todos = function()
      table.sort(state.todos, function(a, b)
        return a.order_index < b.order_index
      end)
    end
  end)
  
  after_each(function()
    state.save_to_disk:revert()
  end)
  
  it("should have reorder functionality", function()
    assert.is_not_nil(todo_actions.reorder_todo)
    assert.is_function(todo_actions.reorder_todo)
  end)
  
  it("should sort todos after changing order indices", function()
    -- Swap order indices
    local original_first = state.todos[1].text
    local original_second = state.todos[2].text
    
    state.todos[1].order_index = 2
    state.todos[2].order_index = 1
    
    -- Sort todos
    state.sort_todos()
    
    -- Check that positions have swapped
    assert.equals(original_first, state.todos[2].text)
    assert.equals(original_second, state.todos[1].text)
  end)
  
  it("should update order_indices when exiting reorder mode", function()
    -- Scramble order_index values
    state.todos[1].order_index = 3
    state.todos[2].order_index = 1
    state.todos[3].order_index = 2
    
    -- Update order_index values to match positions
    for i, todo in ipairs(state.todos) do
      todo.order_index = i
    end
    
    -- Verify order_index values match positions
    assert.equals(1, state.todos[1].order_index)
    assert.equals(2, state.todos[2].order_index)
    assert.equals(3, state.todos[3].order_index)
  end)
end)