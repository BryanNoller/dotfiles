set t_Co=256 "Terminal Colors
syntax on

set ts=4 "TabSpacing
set sw=4 "ShiftWidth
set softtabstop=4

set tw=79 "TextWidth
set fo-=t "Turn off Auto Text Wrapping

nnoremap ; :
inoremap jk <ESC>

set viminfo=
set nobackup
set nowritebackup
set noswapfile

set noautoindent
set nocindent
set expandtab
set hidden

filetype indent off
filetype plugin off

if has("gui_running")
    colorscheme darkblue
    set guioptions=
    set guifont=Consolas:h10:cANSI
endif

let g:proj_flags = 'cgS'

let g:incpy#WindowPosition = "below"
let g:incpy#WindowRatio = 1.0/8
let g:incpy#WindowFixed = 1
"let g:incpy#Program = "C:\\Windows\\system32\\cmd.exe"
