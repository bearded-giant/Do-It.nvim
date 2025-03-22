local dooing_state = require("dooing.state")
local tags = require("dooing.state.tags")

describe("tags", function()
    before_each(function()
        dooing_state.todos = {
            {text = "Todo with #tag1", done = false},
            {text = "Todo with #tag2 and #tag3", done = false},
            {text = "Another #tag1 todo", done = true},
            {text = "No tags here", done = false}
        }
        dooing_state.save_to_disk = function() end -- Mock save_to_disk
    end)

    it("should get all unique tags", function()
        local all_tags = dooing_state.get_all_tags()
        
        assert.are.equal(3, #all_tags)
        
        assert.are.equal("tag1", all_tags[1])
        assert.are.equal("tag2", all_tags[2])
        assert.are.equal("tag3", all_tags[3])
    end)

    it("should set tag filter", function()
        assert.is_nil(dooing_state.active_filter)
        
        dooing_state.set_filter("tag1")
        assert.are.equal("tag1", dooing_state.active_filter)
        
        dooing_state.set_filter(nil)
        assert.is_nil(dooing_state.active_filter)
    end)

    it("should rename tags in all todos", function()
        dooing_state.rename_tag("tag1", "newtag")
        
        assert.are.equal("Todo with #newtag", dooing_state.todos[1].text)
        assert.are.equal("Another #newtag todo", dooing_state.todos[3].text)
        
        assert.are.equal("Todo with #tag2 and #tag3", dooing_state.todos[2].text)
    end)

    it("should delete tags from all todos", function()
        dooing_state.delete_tag("tag1")
        
        assert.are.equal("Todo with ", dooing_state.todos[1].text)
        assert.are.equal("Another  todo", dooing_state.todos[3].text)
        
        assert.are.equal("Todo with #tag2 and #tag3", dooing_state.todos[2].text)
    end)

    it("should delete tag at the end of a line", function()
        table.insert(dooing_state.todos, {text = "Todo with tag at end #tagend", done = false})
        
        dooing_state.delete_tag("tagend")
        
        assert.are.equal("Todo with tag at end ", dooing_state.todos[5].text)
    end)
end)