if !exists("g:VimOI_loaded")
    let g:VimOI_loaded = 1
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
        let g:VimOI_PrecompileCmd = '"C:\\Program Files (x86)\\VS2017\\VC\\Auxiliary\\Build\\vcvars64.bat" >nul'
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
" Preprocess compile argument list
let s:CompileArgStr = ''
for i in g:VimOI_CompileArgs
    let s:CompileArgStr = s:CompileArgStr . ' ' . i
endfor

" }}} End compile arguments

" {{{ Function VimOI#CppCompile
function! VimOI#CppCompile(...)
    " Process filename
    if a:0 >= 1
        let filename = a:1
    else
        let filename = '%'
    endif
    " Process arguments
    let args = ' '
    for i in a:000[1:]
        let args = args . i . ' '
    endfor
    " Execute compile command by systems
    let precompile = ''
    if !empty(g:VimOI_PrecompileCmd)
        let precompile = g:VimOI_PrecompileCmd . ' && '
    endif
    execute "AsyncRun " . precompile . g:VimOI_CompileProg . s:CompileArgStr . args . filename
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
let s:laststdout = ["noredir"]
let s:lastexename = ""
" }}} End init execute arguments

" {{{ Function VimOI#OIRedirect
" {{{ Function s:KillProg and s:OnProgEnd
function! s:OnProgEnd(...)
    let s:testprog = v:null
    if s:progtimer != v:null
        call timer_stop(s:progtimer)
    endif
endfunction

function! s:KillProg(...)
    if s:testprog != v:null
        call job_stop(s:testprog)
    endif
endfunction
" }}} End function s:KillProg

function! VimOI#OIRedirect(...)
    " {{{ Compile and get the executable name
    if g:VimOI_AutoCompile == 1
        if a:0 >= 1
            execute "CppCompile " . a:1
        else
            CppCompile
        endif
    endif

    " Get the executable name
    if a:0 == 0 || empty(a:1) || a:1[0] == ' ' || a:1 == '%'
        if !empty(s:lastexename)
            let exename = s:lastexename
        elseif g:VimOI_CompileSys == 'mscl'
            let exename = expand('%:r') . '.exe'
        else
            let exename = './a.out'
        endif
    elseif a:1 == '-'
        let exename = s:lastexename
    else
        let exename = a:1
    endif
    let s:lastexename = exename
    " }}} Done get the executable name

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
        " If dont reuse tab, it's no need to save it
        if g:VimOI_ReuseRedirTab == 0
            let s:newtabid = -1
            " Switch to redir tab
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
                execute "tabnew [" . exename . " Output]"
            elseif a:type == "err"
                execute "tabnew [" . exename . " Log]"
            endif
            let s:newtabid = tabpagenr()
        else  | " Reuse current tab
            if a:type == "in"
                split [Input]
            elseif a:type == "out"
                execute "split [" . exename . " Output]"
            elseif a:type == "err"
                execute "vsplit [" . exename . " Log]"
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

    let joboption = {
                \ "out_modifiable" : 0,
                \ "err_modifiable" : 0,
                \ "exit_cb" : funcref("s:OnProgEnd"),}

    " {{{ Get redirect destinations
    " Stdin
    if a:0 < 2
        let arg = "!"
    else
        let arg = a:2
    endif
    let opt = s:ProcRedirOpt(arg, "in")
    if opt[0] == "buf"
        let joboption.in_io = "buffer"
        let joboption.in_buf = s:GetRedirBuf(opt[1], "in")
    elseif opt[0] == "null"
        let joboption.in_io = "null"
    elseif opt[0] == "file"
        let joboption.in_io = "file"
        let joboption.in_name = opt[1]
    endif
    " Stdout
    if a:0 < 3
        let arg = "!"
    else
        let arg = a:3
    endif
    let opt = s:ProcRedirOpt(arg, "out")
    if opt[0] == "buf"
        let joboptioin.out_io = "buffer"
        let joboption.out_buf = s:GetRedirBuf(opt[1], "out")
    elseif opt[0] == "null"
        let joboption.out_io = "null"
    elseif opt[0] == "file"
        let joboption.out_io = "file"
        let joboption.out_name = opt[1]
    endif
    " Stderr
    if a:0 >= 4
        let arg = "!"
    else
        let arg = a:4
    endif
    let opt = s:ProcRedirOpt(arg, "err")
    if opt[0] == "buf"
        let joboptioin.err_io = "buffer"
        let joboption.err_buf = s:GetRedirBuf(opt[1], "err")
    elseif opt[0] == "null"
        let joboption.err_io = "null"
    elseif opt[0] == "file"
        let joboption.err_io = "file"
        let joboption.err_name = opt[1]
    endif
    " }}} Done get the redirect distinations

    " {{{ Run program
    " Set the starter
    if !get(joboption, 'in_io') || joboption.in_io == 'pipe'
                \|| !get(joboption, 'out_io') || joboption.out_io == 'pipe'
                \|| !get(joboption, 'err_io') || joboption.err_io == 'pipe'
        let JobStart = function('term_start')
    else
        let JobStart = function('job_start')
    endif
    " If have to open a terminal, rename it
    if JobStart == function('term_start')
        let joboption.term_name = "[" . exename . "]"
        if has("win32")
            let joboption.eof_chars = "\032"  | " Ctrl-Z
        endif
    endif
    " Start running
    echo JobStart exename joboption
    let s:testprog = JobStart(exename, joboption)
    " Start timer
    if JobStart == function('job_start')
        let s:progtimer = timer_start(g:VimOI_TimeLimit, funcref("s:KillProg"))
    endif
    " }}} Done run program
endfunction
" }}} End function VimOI#OIRedirect

