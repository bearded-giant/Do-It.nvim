if exists('g:loaded_doit') | finish | endif
let g:loaded_doit = 1

lua require('doit').setup()
