# Mongoose HTTP Server Project

This repository is the local project workspace for work based on the
[Cesanta Mongoose](https://github.com/cesanta/mongoose) embedded networking
library, which includes an HTTP server.

## Upstream source

The original upstream clone is kept in `upstream/` as a local reference. It is
an independent Git repository and is excluded from this repository's history.

## Current state

Project version: **V0.0.1**. Increment the patch component by `0.0.1` for each
code change; successful changes are recorded in local Git commits and matching
version tags.

See [docs/project_status.md](docs/project_status.md) for the checkout baseline
and current work status.

For a Chinese overview of Mongoose's architecture, features, platform choices,
and compile-time feature trimming, see
[docs/mongoose_design_analysis_zh.md](docs/mongoose_design_analysis_zh.md).

## Build and run on Windows

With MinGW GCC installed and available on `PATH`, run:

```powershell
.\Script\build.ps1
```

Use `.\Script\build.ps1 -Architecture x86` to build the GCC 32-bit
variant at `dist/http-server-gcc-x86.exe` (using the installed i686 WinLibs
toolchain).

The executable is written to `dist/http-server.exe`, and the build copies
`index.html` and `files/` beside it. The tray icon is embedded in the executable.
The server starts in the notification area;
open the tray menu and choose **Start browser** to open the site. The tray menu
also provides **Edit Settings**, **Install service**, **Deinstall service**, and
**Exit**, following the classic Mongoose Windows server interface.

The site root is the executable's directory, regardless of the working
directory. The settings dialog can change the port and directory listing; it
keeps the site root fixed at the executable directory. Saved settings are in
`mongoose.conf` beside the executable. The default URL is
`http://127.0.0.1:8000/`; a sample listing is at `/files/`. The server binds to
IPv4 on all interfaces.
This is plain HTTP without TLS or authentication; the listener is reachable
through every IPv4 network interface on the machine.

For a Clang size-optimized build, use `Script/build-clang.ps1`; pass `-Architecture x86`
to create the 32-bit variant, or `-LinkTimeOptimization` to enable LTO. Crinkler only accepts 32-bit COFF inputs, so run
`Script/build-crinkler.ps1` for the compressed x86 build. This compiles MSVC-ABI
x86 objects with `clang-cl` and links them with Crinkler; it does not compress
the already-linked GCC executable. The Crinkler build embeds the tray icon in
the executable. Tiny variants are not generated.
The Crinkler script looks for Crinkler on `PATH` or in the sibling
`D:\2026work\Crinkler` checkout; pass `-CrinklerPath` to use another copy.
