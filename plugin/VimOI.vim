command! -nargs=* CppCompile call VimOI#CppCompile(<f-args>)
command! -nargs=* OIRedirect call VimOI#OIRedirect(<f-args>)
command! OIStop call VimOI#OIStop()

