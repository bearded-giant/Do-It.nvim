-- The live todos state, wherever setup registered it.
return function()
    local ok, core = pcall(require, "doit.core")
    local module = ok and core.get_module and core.get_module("todos")
    return (module and module.state) or require("doit.state")
end
