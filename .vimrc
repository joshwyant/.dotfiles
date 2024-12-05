" turn on relative line numbers
:set number relativenumber
:set expandtab
:set tabstop=2
:set softtabstop=2
:set shiftwidth=2
:set mouse=

" Check TERM variable and adjust settings
if $TERM != "xterm-256color"
    " Force plain ASCII characters
    set guifont=
    let &termencoding="ascii"
    let g:ascii_mode = 1

    " Optional: Set other terminal-safe options
    " set termguicolors
    " set t_Co=16
endif
