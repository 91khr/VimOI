if !exists("g:VimOI_loaded")
    let g:VimOI_loaded = 1
else
    finish
endif

" {{{ Init compile arguments
if !exists("g:VimOI_CompileSys")
    if has("win32")
        let g:VimOI_CompileSys = 'mscl'
    else
        let g:VimOI_CompileSys = 'g++'
    endif
endif

let s:CompileProgList = {
            \ 'mscl'  : 'cl',
            \ 'g++'   : 'g++',
            \ 'clang' : 'clang++',
            \}
if !exists("g:VimOI_CompileProg")
    let g:VimOI_CompileProg = s:CompileProgList[g:VimOI_CompileSys]
endif

if !exists("g:VimOI_PrecompileCmd")
    if g:VimOI_CompileSys == 'mscl'
        let g:VimOI_PrecompileCmd = '"C:\\Program Files (x86)\\Microsoft Visual Studio'
                    \ . '\\2017\\Community\\VC\\Auxiliary\\Build\\vcvars64.bat" >nul'
    else
        let g:VimOI_PrecompileCmd = ''
    endif
endif

let s:CompileArgsList = {
            \ 'mscl'  : ['/Od', '/nologo'],
            \ 'g++'   : ['-g', '-O0'],
            \ 'clang' : ['-g', '-O0'],
            \}
if !exists("g:VimOI_CompileArgs")
    let g:VimOI_CompileArgs = s:CompileArgsList[g:VimOI_CompileSys]
endif

if !exists("g:VimOI_PassFilename")
    let g:VimOI_PassFilename = 1
endif
if !exists("g:VimOI_CopenOptions")
    let g:VimOI_CopenOptions = ""
endif
" }}} End compile arguments

" {{{ Function VimOI#CppCompile
function! s:GetCompileCmd(arglist)
    " Process filename
    if g:VimOI_PassFilename
        if len(a:arglist) >= 1
            let filename = a:arglist[0]
        else
            let filename = '%'
        endif
    else
        let filename = ''
    endif
    " Process arguments in option
    let args = ' '
    for i in g:VimOI_CompileArgs
        let args = args . i . ' '
    endfor
    " Process arguments in parameter
    for i in a:arglist[1:]
        let args = args . i . ' '
    endfor
    " Execute compile command by systems
    let precompile = ''
    if !empty(g:VimOI_PrecompileCmd)
        let precompile = g:VimOI_PrecompileCmd . ' && '
    endif
    return precompile . g:VimOI_CompileProg . args . filename
endfunction

function! VimOI#CppCompile(...)
    execute "AsyncRun " . s:GetCompileCmd(a:000)
endfunction
" }}} End function VimOI#CppCompile

" {{{ Init execute arguments
if !exists("g:VimOI_ReuseRedirBuf")
    let g:VimOI_ReuseRedirBuf = 1
endif
if !exists("g:VimOI_ReuseRedirTab")
    let g:VimOI_ReuseRedirTab = 1
endif
if !exists("g:VimOI_AutoCompile")
    let g:VimOI_AutoCompile = 0
endif
if !exists("g:VimOI_StdinBuf")
    let g:VimOI_StdinBuf = -1
endif
if !exists("g:VimOI_StdoutBuf")
    let g:VimOI_StdoutBuf = -1
endif
if !exists("g:VimOI_StderrBuf")
    let g:VimOI_StderrBuf = -1
endif
if !exists("g:VimOI_TimeLimit")
    let g:VimOI_TimeLimit = 1000
endif
let s:newtabid = -1
let s:testprog = v:null
let s:progtimer = v:null
let s:laststdin = ["noredir"]
let s:laststdout = ["noredir"]
let s:laststderr = ["noredir"]
let s:lastexename = ""
let s:joboption = {}
let s:redirect_running = 0
" }}} End init execute arguments

" {{{ Function VimOI#OIRedirect
" {{{ Function s:KillProg and s:OnProgEnd
function! s:OnProgEnd(...)
    let s:testprog = v:null
    if s:progtimer != v:null
        call timer_stop(s:progtimer)
    endif
    let s:redirect_running = 0
endfunction

function! s:KillProg(...)
    if s:testprog != v:null
        call job_stop(s:testprog)
    endif
endfunction
" }}} End function s:KillProg

" {{{ function s:RunProgram
function! s:RunProgram()
    " Set the starter
    if !get(s:joboption, 'in_io') || s:joboption.in_io == 'pipe'
                \|| !get(s:joboption, 'out_io') || s:joboption.out_io == 'pipe'
                \|| !get(s:joboption, 'err_io') || s:joboption.err_io == 'pipe'
        let JobStart = function('term_start')
    else
        let JobStart = function('job_start')
    endif
    " If have to open a terminal, rename it
    if JobStart == function('term_start')
        let s:joboption.term_name = "[" . s:lastexename . "]"
        if has("win32")
            let s:joboption.eof_chars = "\032"  | " Ctrl-Z
        endif
    endif
    " Start running
    let s:testprog = JobStart(s:lastexename, s:joboption)
    " Start timer
    if JobStart == function('job_start')
        let s:progtimer = timer_start(g:VimOI_TimeLimit, funcref("s:KillProg"))
    endif
endfunction
" }}} End function s:RunProgram

function! VimOI#OIRedirect(...)
    if s:redirect_running
        echohl Error
        echom "Already had program running!"
        echohl Normal
        return
    else
        let s:redirect_running = 1
    endif

    " {{{ Get executable name
    function! s:GetExeName()
        if g:VimOI_CompileSys == 'mscl'
            return expand('%:t:r') . '.exe'
        else
            return './a.out'
        endif
    endfunction
    if a:0 == 0 || empty(a:1) || a:1[0] == ' ' || a:1 == '!'
        if !empty(s:lastexename)
            let exename = s:lastexename
        else
            let exename = s:GetExeName()
        endif
    elseif a:1 == '%'
        let exename = s:GetExeName()
    else
        let exename = a:1
    endif
    let s:lastexename = exename

    " }}} End getting executable name

    " {{{ Function s:ProcRedirOpt
    " Returns a list [RedirType, RedirPos]
    function! s:ProcRedirOpt(opt, type)
        " Use last result
        if empty(a:opt) || a:opt == '!'
            execute "return s:laststd" . a:type
            " Dont need to redirect
        elseif a:opt == '-'
            let result = ["noredir"]
            " A redirect variable
        elseif a:opt[0] == '$'
            if a:opt[1:3] == "buf"
                let result = ["buf", str2nr(a:opt[4:])]
            elseif a:opt[1:4] == "echo"
                if a:type == "in"
                    echohl Error
                    echom "Attemp to redirect stdin to $echo"
                    echohl Normal
                    finish
                endif
                let result = ["echo"]
            elseif a:opt[1:4] == "null"
                let result = ["null"]
            else
                echohl Error
                echom "Undefined redirection variable: " . a:opt
                echohl Normal
                finish
            endif
            " Filename
        else
            let result = ["file", a:opt]
        endif
        " Save result
        execute "let s:laststd" . a:type . "= result"
        return result
    endfunction
    " }}} End function s:ProcRedirOpt

    " {{{ Function s:GetRedirBuf
    " {{{ Function s:CreateBuf
    function! s:CreateBuf(type) closure
        " If dont reuse tab, clear save info to create a new tab
        if g:VimOI_ReuseRedirTab == 0
            let s:newtabid = -1
            " Reuse tab, switch to redir tab
        elseif g:VimOI_HoldRedirTab == 1
            tabfirst
            if s:newtabid > 1
                execute "normal " . s:newtabid . "gt"
            endif
        endif
        " Create new tab
        if s:newtabid == -1 && g:VimOI_HoldRedirTab == 1
            if a:type == "in"
                tabnew [Input]
            elseif a:type == "out"
                execute "tabnew [" . a:exename . " Output]"
            elseif a:type == "err"
                execute "tabnew [" . a:exename . " Log]"
            endif
            let s:newtabid = tabpagenr()
        else  | " Reuse current tab
            if a:type == "in"
                split [Input]
            elseif a:type == "out"
                execute "split [" . a:exename . " Output]"
            elseif a:type == "err"
                execute "vsplit [" . a:exename . " Log]"
            endif
        endif
        " Set buffer attributes
        set buftype=nofile
        set bufhidden=delete
        return bufnr('%')
    endfunction
    " }}} End function s:CreateBuf

    function! s:GetRedirBuf(id, type)
        if a:id == -1  | " Create a new buffer
            let result = s:CreateBuf(a:type)
        elseif a:id == 0  | " Reuse buffer
            " No reuse, use current buffer
            if g:VimOI_ReuseRedirBuf == 0
                let result = bufnr('%')
            else  | " Reuse previous buffer
                " No prev buf, create one
                if eval("g:VimOI_Std" . a:type . "Buf") == -1
                    let result = s:CreateBuf(a:type)
                else  | " OK, reuse it
                    let result = eval("g:VimOI_Std" . a:type . "Buf")
                endif
            endif
        else  | " Use specified buffer
            let result = a:id
        endif
        " Save buffer to prev used buffer...
        execute "let g:VimOI_Std" . a:type . "Buf = " . result
        return result
    endfunction
    " }}} End function s:CreateRedirBuf

    let s:joboption = {
                \ "out_modifiable" : 0,
                \ "err_modifiable" : 0,
                \ "exit_cb" : funcref("s:OnProgEnd"),}

    " {{{ Get redirect destinations
    for [index, name] in [[2, "in"], [3, "out"], [4, "err"]]
        if a:0 < index
            execute "let opt = s:laststd" . name
        else
            let opt = s:ProcRedirOpt(eval("a:".index), name)
        endif
        if opt[0] == "buf"
            execute "let s:joboption.".name."_io = \"buffer\""
            execute "let s:joboption.".name."_buf = s:GetRedirBuf(opt[1], name)"
        elseif opt[0] == "null"
            execute "let s:joboption.".name."_io = \"null\""
        elseif opt[0] == "file"
            execute "let s:joboption.".name."_io = \"file\""
            execute "let s:joboption.".name."_name = opt[1]"
        endif
    endfor
    " }}} Done get the redirect distinations

    " {{{ Compile and run
    let exetime = getftime(exename)
    echom exetime getftime(expand('%'))
    " Run after compile
    if g:VimOI_AutoCompile == 1 && exetime < getftime(expand('%'))
        if a:0 >= 1
            let compilecmd = s:GetCompileCmd([a:1])
        else
            let compilecmd = s:GetCompileCmd([expand('%')])
        endif
        echo g:VimOI_CopenOptions . "copen"
        execute g:VimOI_CopenOptions . "copen"
        let hookcmd = "call\\ " . string(function("s:RunProgram")) . "() "
        execute "AsyncRun -save=2 -post=" . hookcmd . compilecmd
    else  | " Directly run
        call s:RunProgram()
    endif
    " }}} End compile and run
endfunction
" }}} End function VimOI#OIRedirect

