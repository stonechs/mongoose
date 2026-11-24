# x86 静态链接内容分析

日期：2026-11-24。范围仅包括 GCC x86、Clang x86、Crinkler x86 三个
PE32 构建；不分析 x64。

## 结论

三种构建都把 Mongoose 源文件 `mongoose.c` 和应用代码直接编译进 EXE；
`mg_mgr_poll`、`mg_vxprintf` 等是 Mongoose 自身函数，不是 CRT 库函数。
它们的 CRT 差异如下：

| 构建 | CRT / 静态库情况 | 主要静态链接内容 |
| --- | --- | --- |
| GCC x86 | UCRT 函数通过 API Set DLL 导入；另有 MinGW 启动代码和 libgcc | `libmingw32.a` 的启动、TLS、异常处理和伪重定位支持；`libgcc.a` 的栈探测和 64 位除法帮助函数；少量 UCRT 导入适配器 |
| Clang x86 V0.0.2 | 由 `-fms-runtime-lib=dll` 使用动态 VCRUNTIME/UCRT | Windows CRT 启动和异常处理所需的少量 glue/stub；常用 CRT 函数实现从 `VCRUNTIME140.dll` 和 UCRT API Set 导入 |
| Clang x86 V0.0.3 | MinGW GNU ABI 启动代码；CRT 函数从动态 `msvcrt.dll` 导入 | MinGW CRT startup glue；`memchr`、`memcmp`、`memcpy`、`memmove`、`memset`、`strchr`、`wcsrchr` 均由 `msvcrt.dll` 提供，不导入 VCRUNTIME/UCRT |
| Clang x86 V0.0.4 | MSVC ABI，自定义入口；C 函数从动态 `msvcrt.dll` 导入 | 少量编译器辅助成员，如 `__aulldiv`、`_fltused` 和 CFG/security-cookie 支持；无 CRT startup、无 VCRUNTIME/UCRT，也无 MinGW 伪重定位 |
| Crinkler x86 | `/MT` 链入静态 `libcmt.lib`；Windows API 由 Crinkler 的压缩导入机制解析 | 报告中从 `libcmt.lib` 实际选入的公开函数为 `__aulldiv`，未压入完整 CRT 启动流程 |

## GCC x86

链接映射显示，`libgcc.a` 中实际贡献代码的对象为：

- `__chkstk_ms`：x86 栈探测，44 字节。
- `__udivdi3`、`__udivmoddi4`：无符号 64 位除法帮助函数，共 848 字节。

`libmingw32.a` 贡献约 5,376 字节代码，包括 GUI CRT 启动、全局构造/析构、
参数和 TLS 初始化、异常处理，以及 `_pei386_runtime_relocator` 所在的
MinGW 伪重定位支持对象（该对象 0x6e4 字节）。这里的“伪重定位”是 MinGW
用于导入 DLL 数据的运行时修补代码，和 PE `.reloc` 基址重定位表不同；本构建
没有 `.reloc` 节或 `DYNAMIC_BASE` 标志。

`libmsvcrt.a` 中选入的 `strcmp`、`strncpy`、`fwrite`、`putchar`、`memchr`、
`memcmp` 等 8 字节导入桩，以及 `fprintf`/`vfprintf` 等少量 MinGW-UCRT 适配
代码，不代表把整套 CRT 实现静态复制进 EXE。实际 CRT 函数仍从 UCRT API Set
DLL 导入。`libkernel32.a`、`libuser32.a`、`libws2_32.a`、`libshell32.a`、
`libadvapi32.a` 中绝大多数也是 Windows DLL 导入桩，不是这些系统库的实现代码。

## Clang x86

V0.0.2 的 `lld-link` 映射列出 `_WinMainCRTStartup`、`__scrt_*` 初始化、TLS、SEH、
安全 cookie 检查等 CRT 启动/异常处理 glue。映射中的具体符号包括
`___scrt_initialize_crt`、`___scrt_initialize_onexit_tables`、
`___scrt_get_dyn_tls_init_callback`、`___scrt_set_unhandled_exception_filter`、
`__SEH_prolog4`、`__except_handler4`、`@__security_check_cookie@4` 和
`___report_gsfailure`。它们体积有限；CRT 函数实现没有整体静态链接。
在 V0.0.2 中，`memcmp`、`memcpy`、`memmove`、`memset`、`memchr` 等来自
`VCRUNTIME140.dll`；stdio、heap、string、filesystem、runtime 等函数从
`api-ms-win-crt-*.dll` 导入。Windows API 则从 `KERNEL32.dll`、`USER32.dll`、
`SHELL32.dll`、`ADVAPI32.dll` 和 `WS2_32.dll` 导入。

V0.0.3 将 Clang x86 改为 `i686-w64-windows-gnu` 目标，并显式链接 WinLibs
的 `libmsvcrt-os.a` 导入库。导入检查确认 CRT 函数来自系统的动态
`msvcrt.dll`，不含 `VCRUNTIME140.dll` 或 UCRT API Set DLL。该构建仍有 MinGW
启动代码，并非静态 CRT；Windows API 仍由对应系统 DLL 提供。PE 为固定基址，
没有 `.reloc` 节或基址重定位目录。最终 EXE 为 66,048 B。

V0.0.4 保留 `i686-pc-windows-msvc` 目标，但用 `/NODEFAULTLIB` 和自定义
`MongooseEntry@0` 直接进入应用逻辑。`src/msvcrt-x86.def` 为所需的 C 函数生成
MSVC 格式导入库，函数实现仍由系统 `msvcrt.dll` 提供。链接映射中没有
`WinMainCRTStartup`、`__scrt_*`、`__current_exception*`、
`_except_handler4_common` 或 MinGW `_pei386_runtime_relocator`。MSVC `msvcrt.lib`
只贡献编译器辅助成员，包括 112 字节的 `__aulldiv`、`_fltused` 标记，以及
少量 CFG/security-cookie 支持；没有静态链接整套 CRT。PE 基址重定位目录为零，
产物为 49,664 B。

## Crinkler x86

Crinkler `/REPORT` 中唯一列出的 `LIBCMT.LIB` 公开函数是 `__aulldiv`：未压缩
代码 104 字节，属于 64 位无符号除法帮助例程。其余 Windows SDK `.lib` 输入是
导入库；Windows API 的实现仍在系统 DLL 中。Crinkler 自己压缩并解析导入，
因此普通 `dumpbin /imports` 看不到传统 PE 导入表，不能据此判断它没有 DLL 依赖。

## 证据和边界

- GCC：`work/gcc-x86-v002.map`，由 x86 参数生成的链接映射。
- Clang V0.0.2：`work/clang-x86-v002.map`，MSVC-target x86 `/MAP` 链接映射。
- Clang V0.0.3：`dist/http-server-clang-x86.exe` 的 PE 导入表和节表检查。
- Clang V0.0.4：`build/clang-x86/http-server.map` 和最终 PE 导入表检查。
- Crinkler：`work/crinkler-x86-v002.html`，当前 x86 `/REPORT`。
- GCC/Clang 的 DLL 导入由 `dumpbin /imports` 交叉检查。Crinkler 的函数来源
  根据其压缩链接报告判断。

这些结果区分了“静态库成员被链接器选中”和“库函数实现被静态复制进 EXE”。
导入库成员通常只有跳转桩或导入描述符，实际函数由对应 DLL 提供。
