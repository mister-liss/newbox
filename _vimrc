"Steven Liss
"18 June 09
"_vimrc
"
set nocompatible     "use vim extras not available in vi
source $VIMRUNTIME/vimrc_example.vim
behave mswin

colorscheme evening  "pretty colors
set cursorline       "set the cursor to be a line

set nowrap           "no word wrap
set number           "show line numbers

"make tabs into four spaces
set expandtab
set tabstop=4


"highlight EmptyLines ctermbg=yellow guibg=yellow
"match EmptyLines /^\s*$/


"set diffexpr=MyDiff()
"function MyDiff()
"    let opt = ''
"    if &diffopt =~ 'icase' | let opt = opt . '-i ' | endif
"    if &diffopt =~ 'iwhite' | let opt = opt . '-b ' | endif
"    silent execute '\"!C:\Program Files\vim\diff\" -a ' . opt . v:fname_in . ' ' . v:fname_new . ' > ' . v:fname_out
"endfunction


if has("gui_running")
    set guifont=Intel\ One\ Mono:h8
    set guioptions-=T
    if has("directx")
        set renderoptions=type:directx
    endif
    let s:geom = has("win32") ? expand("~/vimfiles/geometry.vim") : expand("~/.vim/geometry.vim")
    if filereadable(s:geom)
        execute "source" fnameescape(s:geom)
    endif
endif

"keep the caret in the middle half, both axes
set sidescroll=1
augroup ScrollMargins
    autocmd!
    autocmd VimEnter,VimResized * let &scrolloff = &lines / 4 | let &sidescrolloff = &columns / 4
augroup END
