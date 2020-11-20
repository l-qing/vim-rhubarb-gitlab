" rhubarb_gitlab.vim - fugitive.vim extension for Gitlab
" Maintainer:   Tim Pope <http://tpo.pe/>

if exists("g:loaded_rhubarb_gitlab") || v:version < 700 || &cp
  finish
endif
let g:loaded_rhubarb_gitlab = 1

if !exists('g:dispatch_compilers')
  let g:dispatch_compilers = {}
endif
let g:dispatch_compilers['hub'] = 'git'

if get(g:, 'fugitive_git_command', 'git') ==# 'git' && executable('hub')
  let g:fugitive_git_command = 'hub'
endif

function! s:Config() abort
  if exists('*FugitiveFind')
    let dir = FugitiveFind('.git/config')[0:-8]
  else
    let dir = get(b:, 'git_dir', '')
    let common_dir = b:git_dir . '/commondir'
    if filereadable(dir . '/commondir')
      let dir .= '/' . readfile(common_dir)[0]
    endif
  endif
  return filereadable(dir . '/config') ? readfile(dir . '/config') : []
endfunction

augroup rhubarb_gitlab
  autocmd!
  autocmd User Fugitive
        \ if expand('%:p') =~# '\.git[\/].*MSG$' &&
        \   exists('+omnifunc') &&
        \   &omnifunc =~# '^\%(syntaxcomplete#Complete\)\=$' &&
        \   !empty(filter(s:Config(),
        \     '!empty(rhubarb_gitlab#HomepageForUrl(matchstr(v:val, ''^\s*url\s*=\s*"\=\zs\S*'')))')) |
        \   setlocal omnifunc=rhubarb_gitlab#Complete |
        \ endif
  autocmd BufEnter *
        \ if expand('%') ==# '' && &previewwindow && pumvisible() && getbufvar('#', '&omnifunc') ==# 'rhubarb_gitlab#omnifunc' |
        \    setlocal nolist linebreak filetype=markdown |
        \ endif
  autocmd BufNewFile,BufRead *.git/{PULLREQ_EDIT,ISSUE_EDIT,RELEASE_EDIT}MSG
        \ if &ft ==# '' || &ft ==# 'conf' |
        \   set ft=gitcommit |
        \ endif
augroup END

if !exists('g:fugitive_browse_handlers')
  let g:fugitive_browse_handlers = []
endif

if index(g:fugitive_browse_handlers, function('rhubarb_gitlab#FugitiveUrl')) < 0
  call insert(g:fugitive_browse_handlers, function('rhubarb_gitlab#FugitiveUrl'))
endif
