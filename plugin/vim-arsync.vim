" Vim plugin to handle async rsync synchronisation between hosts
" Title: vim-arsync
" Author: Ken Hasselmann (modified)
" Date: 07/2025
" License: MIT

function! LoadConf()
  let l:conf_dict = {}
  let l:file_exists = filereadable('.vim-arsync')

  if l:file_exists > 0
    let l:conf_options = readfile('.vim-arsync')
    for i in l:conf_options
      let l:var_name = substitute(i[0:stridx(i, ' ')], '^\s*\(.\{-}\)\s*$', '\1', '')
      if l:var_name == 'ignore_path'
        let l:var_value = eval(substitute(i[stridx(i, ' '):], '^\s*\(.\{-}\)\s*$', '\1', ''))
      elseif l:var_name == 'remote_passwd'
        let l:var_value = substitute(i[stridx(i, ' '):], '^\s*\(.\{-}\)\s*$', '\1', '')
      elseif l:var_name =~ '_options$'
        try
          let l:var_value = eval(substitute(i[stridx(i, ' '):], '^\s*\(.\{-}\)\s*$', '\1', ''))
        catch
          let l:var_value = split(substitute(i[stridx(i, ' '):], '^\s*\(.\{-}\)\s*$', '\1', ''), '\s\+')
        endtry
      else
        let l:var_value = escape(substitute(i[stridx(i, ' '):], '^\s*\(.\{-}\)\s*$', '\1', ''), '%#!')
      endif
      let l:conf_dict[l:var_name] = l:var_value
    endfor
  endif

  if !has_key(l:conf_dict, "local_path")
    let l:conf_dict['local_path'] = getcwd()
  endif
  if !has_key(l:conf_dict, "remote_port")
    let l:conf_dict['remote_port'] = 22
  endif
  if !has_key(l:conf_dict, "remote_or_local")
    let l:conf_dict['remote_or_local'] = "remote"
  endif
  if !has_key(l:conf_dict, "local_options")
    let l:conf_dict['local_options'] = ["-var"]
  endif
  if !has_key(l:conf_dict, "remote_options")
    let l:conf_dict['remote_options'] = ["-vazre"]
  endif
  return l:conf_dict
endfunction

function! JobHandler(job_id, data, event_type)
  if a:event_type == 'stdout' || a:event_type == 'stderr'
    if has_key(getqflist({'id' : g:qfid}), 'id')
      call setqflist([], 'a', {'id' : g:qfid, 'lines' : a:data})
    endif
  elseif a:event_type == 'exit'
    if a:data != 0
      copen
    else
      echo "vim-arsync success."
    endif
  endif
endfunction

function! ShowConf()
  let l:conf_dict = LoadConf()
  echo l:conf_dict
  echom string(getqflist())
endfunction

function! ARsync(direction)
  let l:conf_dict = LoadConf()
  if has_key(l:conf_dict, 'remote_host')
    let l:user_passwd = ''
    if has_key(l:conf_dict, 'remote_user')
      let l:user_passwd = l:conf_dict['remote_user'] . '@'
      if has_key(l:conf_dict, 'remote_passwd')
        if !executable('sshpass')
          echoerr 'You need sshpass or use ssh-key auth.'
          return
        endif
        let sshpass_passwd = l:conf_dict['remote_passwd']
      endif
    endif

    let l:cmd = ['rsync']
    if l:conf_dict['remote_or_local'] == 'remote'
      let l:cmd += type(l:conf_dict['remote_options']) == type([]) ? l:conf_dict['remote_options'] : split(l:conf_dict['remote_options'])
      let l:cmd += ['-e', 'ssh -p ' . l:conf_dict['remote_port']]

      if a:direction == 'down'
        let l:cmd += [l:user_passwd . l:conf_dict['remote_host'] . ':' . l:conf_dict['remote_path'] . '/', l:conf_dict['local_path'] . '/']
      else
        let l:cmd += [l:conf_dict['local_path'] . '/', l:user_passwd . l:conf_dict['remote_host'] . ':' . l:conf_dict['remote_path'] . '/']
      endif
    else
      let l:cmd += type(l:conf_dict['local_options']) == type([]) ? l:conf_dict['local_options'] : split(l:conf_dict['local_options'])
      if a:direction == 'down'
        let l:cmd += [l:conf_dict['remote_path'], l:conf_dict['local_path']]
      else
        let l:cmd += [l:conf_dict['local_path'], l:conf_dict['remote_path']]
      endif
    endif

    if has_key(l:conf_dict, 'ignore_path')
      for file in l:conf_dict['ignore_path']
        let l:cmd += ['--exclude', file]
      endfor
    endif

    if get(l:conf_dict, 'ignore_dotfiles', 0) == 1
      let l:cmd += ['--exclude', '.*']
    endif

    if has_key(l:conf_dict, 'remote_passwd')
      let l:cmd = ['sshpass', '-p', sshpass_passwd] + l:cmd
    endif

    call setqflist([], ' ', {'title' : 'vim-arsync'})
    let g:qfid = getqflist({'id' : 0}).id
    let l:job_id = async#job#start(cmd, {
          \ 'on_stdout': function('JobHandler'),
          \ 'on_stderr': function('JobHandler'),
          \ 'on_exit': function('JobHandler'),
          \ })
  else
    echoerr 'No .vim-arsync config found. Aborting.'
  endif
endfunction

function! AutoSync()
  let l:conf_dict = LoadConf()
  if get(l:conf_dict, 'auto_sync_up', 0)
    if has_key(l:conf_dict, 'sleep_before_sync')
      let g:sleep_time = l:conf_dict['sleep_before_sync'] * 1000
      autocmd BufWritePost,FileWritePost * call timer_start(g:sleep_time, { -> execute("call ARsync('up')", "")})
    else
      autocmd BufWritePost,FileWritePost * ARsyncUp
    endif
  endif
endfunction

if !executable('rsync')
  echoerr 'You need to install rsync to use vim-arsync.'
  finish
endif

command! ARsyncUp call ARsync('up')
command! ARsyncUpDelete call ARsync('up')
command! ARsyncDown call ARsync('down')
command! ARshowConf call ShowConf()

augroup vimarsync
  autocmd!
  autocmd VimEnter * call AutoSync()
  autocmd DirChanged * call AutoSync()
augroup END
