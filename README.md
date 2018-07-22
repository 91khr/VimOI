# VimOI

一个轻量级的编译-调试插件, 为OIer而生.

1. [Install](#install)
1. [Features](#features)
1. [Commands](#commands)
    1. [CppCompile命令](#cppcompile命令)
    1. [OIRedirect命令](#oiredirect命令)
1. [Functions](#functions)
    1. [VimOI#CppCompile函数](#vimoi#cppcompile函数)
    1. [VimOI#OIRedirect函数](#vimOI#oiredirect函数)
1. [Options](#options)
    1. [g:VimOI_CompileSys](#gvimoi_compilesys)
    1. [g:VimOI_CompileProg](#gvimoi_compileprog)
    1. [g:VimOI_PrecompileCmd](#gvimoi_precompilecmd)
    1. [g:VimOI_CompileArgs](#gvimoi_compileargs)
    1. [g:VimOI_ReuseRedirBuf](#gvimoi_reuseredirbuf)
    1. [g:VimOI_ReuseRedirTab](#gvimoi_reuseredirtab)
    1. [g:VimOI_HoldRedirTab](#gvimoi_holdredirtab)
    1. [g:VimOI_TimeLimit](#gvimoi_timelimit)
    1. [g:VimOI_AutoCompile](#gvimoi_autocompile)
1. [TODO](#todo)

## Install

安装`VimOI`及其所有依赖, 如果你使用[vim-plug](https://github.com/junegunn/vim-plug),
可以这么做:

```vim
Plug 'skywind3000/AsyncRun'
Plug '91khr/VimOI'
```

## Features

- 快速编译当前文件, 生成可执行文件;

- 灵活的重定向:

    - 重定向到文件;
    - 从文件中重定向;
    - 重定向到VIm中的缓冲区;
    - 从缓冲区中重定向;

  不仅可以重定向输入/输出, 还可以重定向Log;

- 方便地测试程序:

    - 用多组数据/答案文件测试, 记录所有测试结果;
    - 从程序/脚本中获取数据和答案, 测试直到出现错误;

  支持测试结果的重定向;

## Commands

这些命令中以Cpp开头的只用于C++源文件.
以OI开头的可以在加载插件后的任何地方使用.

### CppCompile命令

编译一个C++源文件并生成可执行文件, **不会**删除任何中间文件.

如果没有给出任何参数, 编译当前文件.
如果给出了多于一个参数, 第一个参数会被当作文件名,
剩余的参数将会被作为编译的参数传递给编译器.

使用[VimOI#CppCompile函数](#vimoicppcompile函数)实现.

Example:

```vim
CppCompile % -Wall -Wextra
```

将会调用:

```vim
VimOI#CppCompile('%', '-Wall', '-Wextra')
```

### OIRedirect命令

运行给定程序, 并执行重定向.

使用[VimOI#OIRedirect函数](#vimoiredirect函数)实现,
关于此命令的详细信息, 请查看函数文档.

Example:

```vim
OIRedirect
```

这将运行当前文件对应的可执行文件, 并打开一个vim终端窗口接受输入和输出.

## Functions

### VimOI#CppCompile函数

编译一个C++源文件并生成可执行文件, **不会**删除任何中间文件.

第一个参数将被作为文件名传递给编译器,
其余的参数将被作为编译器的额外参数传递给编译器.
如果没有提供参数, 将编译当前文件.

Example:

```vim
call VimOI#CppCompile(['%', '-Wall', '-Wextra'])
```

### VimOI#OIRedirect函数

运行一个可执行文件, 并将其结果重定向到给定的位置.

第一个参数是可执行文件的名称.
如果没有给出, 为空, 以空格开头或为`%`,
则根据`g:VimOI_CompileSys`生成可执行文件名称:

- 对于`mscl`: 将当前缓冲区中文件的后缀替换成.exe, 作为可执行文件名称;
- 对于`g++`和`clang`: 将./a.out作为可执行文件名称.

接下来的三个参数分别是将要重定向的`stdin`, `stdout`和`stderr`,
以字符串表示, 按照如下规则解释:

- 如果为空, 未给出或为`'-'`, 将不重定向这个流;
- 如果为`'!'`, 将使用上一次重定向的参数;
- 如果以`$`开头, 则解释为特殊的重定向:
    - `$buf[n]`: 重定向至缓冲区`n`, 其中`n`是缓冲区id,
      如果`n`未指定, 重定向的目标取决于[g:VimOI_ReuseRedirBuf选项](#gvimoi_reuseredirbuf);
      如果`n`为-1, 则在创建新缓冲区, 并重定向到此处.
    - `$echo`(未实现): 在Vim中输出, 如果被应用在`stdin`上, 将产生一个错误;
    - `$null`: 抛弃重定向后的结果, 如果被应用在`stdin`上, 读入将为空;
    - 否则, 将不运行程序, 并报告一个错误;
- 否则, 将这一参数作为将重定向的文件名.

如果至少有一个流没有被重定向, 则打开一个vim终端运行程序, 并将没有被重定向的流重定向到此处.
如果`g:VimOI_HoldRedirTab`选项为1, 则会在新标签页中创建新缓冲区或终端.

**注意:** 作为`stdout`或`stderr`重定向目标的文件或缓冲区中原有的内容将被清空,
所以如果自己选择缓冲区, 请小心选择一个无用的缓冲区.

如果运行过程中出现错误(如文件没有权限等), 结果是未定义的.
但是可以保证没有提及的文件和缓冲区不会被修改.

如果运行的时间超过了[限制](#gvimoi_timelimit), VimOI会强行停止这个程序.

## Options

### g:VimOI_CompileSys

指定VimOI使用的编译系统.
这一变量的值将会影响所有编译设置.

可用的值有:
`mscl`, `g++`和`clang`.
在Windows上默认为`mscl`, 否则默认为`g++`.

### g:VimOI_CompileProg

指定VimOI使用的编译器.

默认值根据[g:VimOI_CompileSys](#gvimoi_compilesys)选项的值指定.
对于不同的编译系统:

- `mscl`: `cl`;
- `g++`: `g++`;
- `clang`: `clang++`.

### g:VimOI_PrecompileCmd

指定将在编译之前运行的程序.

除非有特别需要, 否则不建议更改它的值, 因为这可能导致编译出现错误.

### g:VimOI_CompileArgs

指定除源文件名外将传递给编译器的额外参数.

默认值根据[g:VimOI_CompSys](#gvimoi_compsys)选项的值指定.
对于不同的编译系统:

- `mscl`: `['/Od', '/nologo']`;
- `g++`: `['-g', '-O0']`;
- `clang`: `['-g', '-O0']`.

### g:VimOI_ReuseRedirBuf

指定VimOI如果没有在重定向时指定缓冲区, 是否重用上一次重定向的缓冲区.
如果为0, 则使用当前缓冲区, 但仍然会记录重定向的缓冲区.

上一次重定向的缓冲区存储在`g:VimOI_StdinBuf`, `g:VimOI_StdoutBuf`
和`g:VimOI_StderrBuf`三个选项中.

只在执行重定向时被访问.

默认值: 1

### g:VimOI_ReuseRedirTab

指定VimOI在重定向时是否应该在现有的标签页中为新的缓冲区和终端创建分割.

默认值: 0

### g:VimOI_HoldRedirTab

指定VimOI是否应该为重定向的缓冲区和终端创建新的标签页.
每次重定向最多创建一个标签页.

默认值: 1

### g:VimOI_TimeLimit

指定每个测试程序运行的时间限制, 单位为毫秒.
如果测试程序打开了终端, 此限制无效.

默认值: 1000

### g:VimOI_AutoCompile

指定VimOI是否要在运行程序之前自动保存和编译.

**注意:** 现在还不支持检测源代码是否更改, 所以不建议设置.

默认值: 0

## TODO

- 实现[VimOI#OIRedirect函数](#vimoi#oiredirect函数)的`$echo`特殊重定向;
- 优化代码风格;

