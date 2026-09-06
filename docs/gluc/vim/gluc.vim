" The vim reporter.
"
" One of gluc's five, and the only one that runs inside the tool it reports
" for: vim can say what it is looking at, so nothing has to watch it from
" outside the way Explorer and the terminal are watched.
"
" It lived in _vimrc until now, which put a gluc component inside newbox's
" workstation configuration - the only forwarder not in gluc. Installed
" alongside gluc-shell.ps1 and sourced the same way $PROFILE sources that, so
" gluc installs its own hooks and neither half has to know the other's files.
"
" Sends on three transitions and no samples: entering a buffer, leaving one,
" and writing. There is deliberately no autocmd on CursorMoved or TextChanged -
" those are samples, and a producer firing them more often would move a
" consumer's ranking, which is the failure the vocabulary exists to prevent.

if exists('g:loaded_gluc')
    finish
endif
let g:loaded_gluc = 1

function! s:GlucDir() abort
    return has('win32') ? $LOCALAPPDATA . '/gluc' : expand('~/.local/share/gluc')
endfunction

function! s:GlucSend(verb, payload) abort
    let l:file = s:GlucDir() . '/endpoint'
    if !filereadable(l:file) | return | endif
    let l:endpoint = readfile(l:file, '', 2)
    if len(l:endpoint) < 2 | return | endif
    try
        let l:channel = ch_open('127.0.0.1:' . l:endpoint[0],
            \ { 'mode': 'raw', 'waittime': 200 })
    catch
        return
    endtry
    if ch_status(l:channel) !=# 'open' | return | endif
    let l:body = json_encode(a:payload)
    call ch_sendraw(l:channel, join([
        \ 'POST /' . a:verb . ' HTTP/1.1',
        \ 'Host: 127.0.0.1',
        \ 'Authorization: Bearer ' . l:endpoint[1],
        \ 'Content-Type: application/json',
        \ 'Content-Length: ' . strlen(l:body),
        \ 'Connection: close',
        \ '', l:body], "\r\n"))
endfunction

function! s:GlucEvent(kind) abort
    if &buftype !=# '' | return | endif
    let l:file = expand('%:p')
    if empty(l:file) || !filereadable(l:file) | return | endif
    call s:GlucSend('event', {
        \ 'kind': a:kind,
        \ 'source': 'vim',
        \ 'osObject': { 'pid': getpid() },
        \ 'path': l:file,
        \ 'bag': { 'line': line('.') } })
endfunction

augroup GlucRecent
    autocmd!
    autocmd BufEnter * silent! call s:GlucEvent('select')
    autocmd BufLeave,VimLeavePre * silent! call s:GlucEvent('close')
    autocmd BufWritePost * silent! call s:GlucEvent('write')
augroup END
