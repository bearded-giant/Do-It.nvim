if exists('g:loaded_doit') | finish | endif
let g:loaded_doit = 1

lua << EOF
local doit = require('doit')
doit.setup()
-- Ensure module commands are registered in Vim
doit.register_module_commands()
EOF
