" Location: autoload/rhubarb_gogs.vim
" Author: Tim Pope <http://tpo.pe/>

if exists('g:autoloaded_rhubarb_gogs')
  finish
endif
let g:autoloaded_rhubarb_gogs = 1

" Section: Utility

function! s:throw(string) abort
  let v:errmsg = 'rhubarb_gogs: '.a:string
  throw v:errmsg
endfunction

function! s:shellesc(arg) abort
  if a:arg =~# '^[A-Za-z0-9_/.-]\+$'
    return a:arg
  elseif &shell =~# 'cmd' && a:arg !~# '"'
    return '"'.a:arg.'"'
  else
    return shellescape(a:arg)
  endif
endfunction

function! rhubarb_gogs#HomepageForUrl(url) abort
  let domain_pattern = 'github\.com'
  let domains = get(g:, 'github_enterprise_urls', get(g:, 'fugitive_github_domains', []))
  call map(copy(domains), 'substitute(v:val, "/$", "", "")')
  for domain in domains
    let domain_pattern .= '\|' . escape(split(domain, '://')[-1], '.')
  endfor
  let base = matchstr(a:url, '^\%(https\=://\%([^@/:]*@\)\=\|git://\|git@\|ssh://git@\)\=\zs\('.domain_pattern.'\)[/:].\{-\}\ze\%(\.git\)\=/\=$')
  if index(domains, 'http://' . matchstr(base, '^[^:/]*')) >= 0
    return 'http://' . tr(base, ':', '/')
  elseif !empty(base)
    return 'https://' . tr(base, ':', '/')
  else
    return ''
  endif
endfunction

function! rhubarb_gogs#homepage_for_url(url) abort
  return rhubarb_gogs#HomepageForUrl(a:url)
endfunction

function! s:repo_homepage() abort
  if exists('b:rhubarb_homepage')
    return b:rhubarb_homepage
  endif
  if exists('*FugitiveRemoteUrl')
    let remote = FugitiveRemoteUrl()
  else
    let remote = fugitive#repo().config('remote.origin.url')
  endif
  let homepage = rhubarb_gogs#HomepageForUrl(remote)
  if !empty(homepage)
    let b:rhubarb_homepage = homepage
    return b:rhubarb_homepage
  endif
  call s:throw((len(remote) ? remote : 'origin') . ' is not a GitHub repository')
endfunction

" Section: HTTP

function! s:credentials() abort
  if !exists('g:github_user')
    let g:github_user = $GITHUB_USER
    if g:github_user ==# '' && exists('*FugitiveConfig')
      let g:github_user = FugitiveConfig('github.user', '')
    endif
    if g:github_user ==# ''
      let g:github_user = $LOGNAME
    endif
  endif
  if !exists('g:github_password')
    let g:github_password = $GITHUB_PASSWORD
    if g:github_password ==# '' && exists('*FugitiveConfig')
      let g:github_password = FugitiveConfig('github.password', '')
    endif
  endif
  return g:github_user.':'.g:github_password
endfunction

function! rhubarb_gogs#JsonDecode(string) abort
  if exists('*json_decode')
    return json_decode(a:string)
  endif
  let [null, false, true] = ['', 0, 1]
  let stripped = substitute(a:string,'\C"\(\\.\|[^"\\]\)*"','','g')
  if stripped !~# "[^,:{}\\[\\]0-9.\\-+Eaeflnr-u \n\r\t]"
    try
      return eval(substitute(a:string,"[\r\n]"," ",'g'))
    catch
    endtry
  endif
  call s:throw("invalid JSON: ".a:string)
endfunction

function! rhubarb_gogs#JsonEncode(object) abort
  if exists('*json_encode')
    return json_encode(a:object)
  endif
  if type(a:object) == type('')
    return '"' . substitute(a:object, "[\001-\031\"\\\\]", '\=printf("\\u%04x", char2nr(submatch(0)))', 'g') . '"'
  elseif type(a:object) == type([])
    return '['.join(map(copy(a:object), 'rhubarb_gogs#JsonEncode(v:val)'),', ').']'
  elseif type(a:object) == type({})
    let pairs = []
    for key in keys(a:object)
      call add(pairs, rhubarb_gogs#JsonEncode(key) . ': ' . rhubarb_gogs#JsonEncode(a:object[key]))
    endfor
    return '{' . join(pairs, ', ') . '}'
  else
    return string(a:object)
  endif
endfunction

function! s:curl_arguments(path, ...) abort
  let options = a:0 ? a:1 : {}
  let args = ['-q', '--silent']
  call extend(args, ['-H', 'Accept: application/json'])
  call extend(args, ['-H', 'Content-Type: application/json'])
  call extend(args, ['-A', 'rhubarb_gogs.vim'])
  if get(options, 'auth', '') =~# ':'
    call extend(args, ['-u', options.auth])
  elseif has_key(options, 'auth')
    call extend(args, ['-H', 'Authorization: bearer ' . options.auth])
  elseif exists('g:RHUBARB_TOKEN')
    call extend(args, ['-H', 'Authorization: bearer ' . g:RHUBARB_TOKEN])
  elseif s:credentials() !~# '^[^:]*:$'
    call extend(args, ['-u', s:credentials()])
  elseif has('win32') && filereadable(expand('~/.netrc'))
    call extend(args, ['--netrc-file', expand('~/.netrc')])
  else
    call extend(args, ['--netrc'])
  endif
  if has_key(options, 'method')
    call extend(args, ['-X', toupper(options.method)])
  endif
  for header in get(options, 'headers', [])
    call extend(args, ['-H', header])
  endfor
  if type(get(options, 'data', '')) != type('')
    call extend(args, ['-d', rhubarb_gogs#JsonEncode(options.data)])
  elseif has_key(options, 'data')
    call extend(args, ['-d', options.data])
  endif
  call add(args, a:path)
  return args
endfunction

function! rhubarb_gogs#Request(path, ...) abort
  if !executable('curl')
    call s:throw('cURL is required')
  endif
  if a:path =~# '://'
    let path = a:path
  elseif a:path =~# '^/'
    let path = 'https://api.github.com' . a:path
  else
    let base = s:repo_homepage()
    let path = substitute(a:path, '%s', matchstr(base, '[^/]\+/[^/]\+$'), '')
    if base =~# '//github\.com/'
      let path = 'https://api.github.com/' . path
    else
      let path = substitute(base, '[^/]\+/[^/]\+$', 'api/v3/', '') . path
    endif
  endif
  let options = a:0 ? a:1 : {}
  let args = s:curl_arguments(path, options)
  let raw = system('curl '.join(map(copy(args), 's:shellesc(v:val)'), ' '))
  if raw ==# ''
    return raw
  else
    return rhubarb_gogs#JsonDecode(raw)
  endif
endfunction

function! rhubarb_gogs#request(...) abort
  return call('rhubarb_gogs#Request', a:000)
endfunction

function! rhubarb_gogs#RepoRequest(...) abort
  return rhubarb_gogs#Request('repos/%s' . (a:0 && a:1 !=# '' ? '/' . a:1 : ''), a:0 > 1 ? a:2 : {})
endfunction

function! rhubarb_gogs#repo_request(...) abort
  return call('rhubarb_gogs#RepoRequest', a:000)
endfunction

function! s:url_encode(str) abort
  return substitute(a:str, '[?@=&<>%#/:+[:space:]]', '\=submatch(0)==" "?"+":printf("%%%02X", char2nr(submatch(0)))', 'g')
endfunction

function! rhubarb_gogs#RepoSearch(type, q) abort
  return rhubarb_gogs#Request('search/'.a:type.'?per_page=100&q=repo:%s'.s:url_encode(' '.a:q))
endfunction

function! rhubarb_gogs#repo_search(...) abort
  return call('rhubarb_gogs#RepoSearch', a:000)
endfunction

" Section: Issues

let s:reference = '\<\%(\c\%(clos\|resolv\|referenc\)e[sd]\=\|\cfix\%(e[sd]\)\=\)\>'
function! rhubarb_gogs#Complete(findstart, base) abort
  if a:findstart
    let existing = matchstr(getline('.')[0:col('.')-1],s:reference.'\s\+\zs[^#/,.;]*$\|[#@[:alnum:]-]*$')
    return col('.')-1-strlen(existing)
  endif
  try
    if a:base =~# '^@'
      return map(rhubarb_gogs#RepoRequest('collaborators'), '"@".v:val.login')
    else
      if a:base =~# '^#'
        let prefix = '#'
        let query = ''
      else
        let prefix = s:repo_homepage().'/issues/'
        let query = a:base
      endif
      let response = rhubarb_gogs#RepoSearch('issues', 'state:open '.query)
      if type(response) != type({})
        call s:throw('unknown error')
      elseif has_key(response, 'message')
        call s:throw(response.message)
      else
        let issues = get(response, 'items', [])
      endif
      return map(issues, '{"word": prefix.v:val.number, "abbr": "#".v:val.number, "menu": v:val.title, "info": substitute(v:val.body,"\\r","","g")}')
    endif
  catch /^rhubarb_gogs:.*is not a GitHub repository/
    return []
  catch /^\%(fugitive\|rhubarb_gogs\):/
    echoerr v:errmsg
  endtry
endfunction

function! rhubarb_gogs#omnifunc(findstart, base) abort
  return rhubarb_gogs#Complete(a:findstart, a:base)
endfunction

" Section: Fugitive :Gbrowse support

function! rhubarb_gogs#FugitiveUrl(...) abort
  if a:0 == 1 || type(a:1) == type({})
    let opts = a:1
    let root = rhubarb_gogs#HomepageForUrl(get(opts, 'remote', ''))
  else
    return ''
  endif
  if empty(root)
    return ''
  endif
  let path = substitute(opts.path, '^/', '', '')
  if path =~# '^\.git/refs/heads/'
    return root . '/commits/' . path[16:-1]
  elseif path =~# '^\.git/refs/tags/'
    return root . '/releases/tag/' . path[15:-1]
  elseif path =~# '^\.git/refs/remotes/[^/]\+/.'
    return root . '/commits/' . matchstr(path,'remotes/[^/]\+/\zs.*')
  elseif path =~# '^\.git/\%(config$\|hooks\>\)'
    return root . '/admin'
  elseif path =~# '^\.git\>'
    return root
  endif
  if opts.commit =~# '^\d\=$'
    return ''
  else
    let commit = opts.commit
  endif
  if get(opts, 'type', '') ==# 'tree' || opts.path =~# '/$'
    let url = substitute(root . '/tree/' . commit . '/' . path, '/$', '', 'g')
  elseif get(opts, 'type', '') ==# 'blob' || opts.path =~# '[^/]$'
    let escaped_commit = substitute(commit, '#', '%23', 'g')
    let url = root . '/blob/' . escaped_commit . '/' . path
    if get(opts, 'line2') && opts.line1 == opts.line2
      let url .= '#L' . opts.line1
    elseif get(opts, 'line2')
      let url .= '#L' . opts.line1 . '-L' . opts.line2
    endif
  else
    let url = root . '/commit/' . commit
  endif
  return url
endfunction

function! rhubarb_gogs#fugitive_url(...) abort
  return call('rhubarb_gogs#FugitiveUrl', a:000)
endfunction

" Section: End
