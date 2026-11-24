# Project status

Updated: 2026-11-24
Project version: V0.0.4

## Baseline

- Root is an independent local Git repository on branch `main`.
- `upstream/` is the pristine Cesanta Mongoose clone, with its own Git history
  and official `origin` remote; it is excluded from the root repository.
- Upstream baseline observed: `071cd50e` on `master`.

## Current work

- Official delivery set: Clang x86, Clang x86 Crinkler, and Clang x64 only.
  The policy is recorded in [decisions.md](decisions.md) and reflected in the
  README build instructions.
- Copied the Mongoose core (`mongoose.c`, `mongoose.h`) into `src/`.
- Replaced the tutorial application in `src/main.c` with a minimal IPv4 static
  file server using the executable's directory as its document root,
  with directory listing enabled and no upload/delete handler.
- Added `web_root/index.html` as the sample static page.
- Added `web_root/files/readme.txt` to demonstrate directory listing.
- Configured `Script/build.ps1` to disable IPv6, TLS, SSI, logging, MD5,
  health/Dashboard, OTA, embedded/third-party network stacks, and unused embedded
  filesystems; it uses size optimization, LTO, and linker dead-code removal.
- The original GCC build script remains for maintenance; GCC output is no
  longer part of the official delivery set.
- Added `Script/build-clang.ps1` for Clang `-Oz` x64/x86 builds and
  `Script/build-crinkler.ps1` for compressed x86 variants.
- Added `docs/mongoose_design_analysis_zh.md`, analyzing Mongoose 7.24 design,
  features, implementation choices, and feature-trimming options from the
  upstream source.

## Verification

- Compared copied source files byte-for-byte with their upstream originals.
- Previous untrimmed example build was 668,874 bytes; preserved at
  `work/http-server-before-trim.exe` for size comparison.
- Ran `Script/build.ps1` successfully with MinGW GCC 16.2.0 (x86_64 UCRT).
- Confirmed the script also builds successfully when invoked outside the project
  root.
- Produced stripped `dist/http-server.exe` (46,080 bytes, 45.0 KiB) with LTO.
- Repeated builds from the project root and `C:\Windows\Temp` both produced
  46,080-byte executables.
- The pre-LTO trimmed build was 113,664 bytes; the previous tutorial build was
  668,874 bytes. These are not controlled macro-only comparisons: the
  application and optimization options changed as well.
- Built a Clang 23.1.5 `-Oz` x64 variant: `dist/http-server-clang.exe`,
  180,224 bytes. `-Oz -flto` produced 177,152 bytes. The `-Oz` x86 variant is
  152,064 bytes.
- Crinkler 3.0b accepted the x86 COFF objects, producing a normal compressed
  executable of 15,928 bytes and a `/TINYHEADER /TINYIMPORT` variant of 13,241
  bytes. The latter uses Crinkler's documented fragile tiny-import mode.
- Confirmed the Clang and Crinkler scripts reproduce those output sizes.
- Crinkler rejected the x64 COFF object as unsupported; its current object
-  loader accepts x86 (`IMAGE_FILE_MACHINE_I386`) objects only.
- Ran each generated server and requested `/` and `/files/` over IPv4. The GCC
  x64, Clang x64 (with and without LTO), Clang x86, and regular Crinkler x86
  builds stayed running and returned HTTP 200 for both paths; the directory
  response included `readme.txt`.
- The Crinkler Tiny Header/Tiny Import process stayed alive but did not open the
  listener, returned no response, and spun CPU. It is unusable in this
  environment and is now opt-in in the Crinkler script.
- Added explicit startup/error console messages to `src/main.c` while keeping
  Mongoose's general logging disabled.
- The build copies `index.html` and `files/` beside `dist/http-server.exe`. Ran the latest
  build from `C:\Windows\Temp`: startup succeeded, `/` returned HTTP 200 with
  the expected page title, and `/files/` returned HTTP 200 with `readme.txt`.
  Stopped the test server after verification.
- Changed executable-path discovery to `GetModuleFileNameW` and converted the
  executable directory to UTF-8 for Mongoose's Windows filesystem layer. Copied
  the built server into `work/中文路径测试/`, launched it with
  `C:\Windows\Temp` as the working directory, and verified `/` and `/files/`
  both returned HTTP 200. Stopped the test server.
- Rebuilt the Clang x64, x64 LTO, x86, and x86 LTO outputs, plus the regular and
  Tiny Import Crinkler x86 outputs from the Unicode-path-aware source. The
  build scripts now copy the document-root contents beside each executable.
  Manually launched all four Clang builds from `C:\Windows\Temp`; each returned
  HTTP 200 for `/` and `/files/`, with `readme.txt` in the listing. The regular
  and Tiny Import Crinkler outputs from that build were not usable.
- Added GCC x86 selection to `Script/build.ps1`, using the installed i686 WinLibs
  GCC toolchain. Built `dist/http-server-gcc-x86.exe` (50,688 bytes), confirmed
  it is PE32/i386, and launched it from `work/GCC-GCC中文路径/` while using
  `C:\Windows\Temp` as the working directory. `/` and `/files/` returned HTTP
  200 and the listing included `readme.txt`; stopped the server afterward.
- Directly linking GCC x86 objects with Crinkler 3.0b produced a 23,157-byte
  executable using Windows SDK imports plus MinGW `libgcc.a`, but it exited
  with `0xC0000096` before producing console output. Captured logs are in
  `work/crinkler-gcc-x86-link.log` and `work/crinkler-gcc-x86-run.log`.
- Working Crinkler x86 build uses `clang-cl` with the `i686-pc-windows-msvc`
  target, `/MT`, `/Zl`, and `-Oz`; the object uses a custom `CrinklerEntry`, and
  Crinkler links Windows SDK libraries plus `libcmt.lib` while retaining its
  default `msvcrt.dll` imports. `Script/build-crinkler.ps1` captures the linker
  output under `build/crinkler-x86/`. The resulting
  `dist/http-server-crinkler-x86.exe` is 17,996 bytes. Launched from
  `work/Crinkler-中文路径/` with `C:\Windows\Temp` as the working directory;
  startup succeeded, `/` and `/files/` returned HTTP 200, and `readme.txt` was
  listed. The server was stopped after the test. The optional Tiny Import
  variant remains experimental and is not covered by this successful test.
- Stopped all test processes after each run. No server was left listening on
  port 8000.

## Next steps

- Crinkler Tiny Import is not requested and will not be generated.
- Clang x86 now depends on the dynamic UCRT and `VCRUNTIME140.dll`; the runtime
  dependency was present during local headless verification.

## Tray application update

- Replaced the console entry with a hidden-window Windows tray application,
  following the historical Mongoose server menu and settings layout.
- Added the historical Mongoose tray icon resource (`src/systray.ico`) with its
  MIT attribution in `src/tray.rc`.
- Tray menu provides the classic version header and service status, service
  install/uninstall, **Start browser**, **Edit Settings**, and **Exit** actions.
- Settings persist `port` and `directory_listing` in `mongoose.conf`; the site
  root remains the executable directory. Settings changes restart the listener.
- Windows service mode runs the same server without a tray window and stops on
  SCM stop/shutdown requests.
- Updated GCC, Clang, and Crinkler scripts to build GUI executables and include
  the tray icon and required Windows libraries.
- Crinkler embeds the icon bytes in the executable; no icon sidecar is needed.
- Rebuilt GCC x64/x86, Clang x64/x86 and LTO variants, and regular Crinkler x86.
  Each independently started and returned HTTP 200 for `/` and `/files/`; the
  page title and `readme.txt` were verified. Every test process was stopped and
  port 8000 had no remaining listener.
- PE checks confirmed the GCC/Clang architecture and embedded icon resources.
  Service installation/uninstallation was not run.
- Before the V0.0.1 baseline, the root repository had no commits or tags.
  Pre-tray source, build scripts, README, and status page are preserved under
  `work/pre-tray-ui/`; the
  `restore-pre-tray.ps1` script also removes the two tray-only source assets.

## x86 size and relocation update (2026-11-24)

- Clang x86 now uses `-fms-runtime-lib=dll`, selecting the dynamic MSVC/UCRT
  runtime. GCC already imports the UCRT. Clang's PE imports include UCRT API
  sets and `VCRUNTIME140.dll`; the latter was available in the local test
  environment.
- GCC and Clang x86 link as fixed-base executables. Crinkler already emitted a
  fixed-base executable. PE inspection found no `.reloc` section, no
  `DYNAMIC_BASE` flag, and a zero base-relocation directory in all three.
- Current x86 sizes at this checkpoint: GCC 75,776 B, Clang 55,296 B, regular
  Crinkler 22,413 B.
  The previous Clang x86 output was 172,544 B; the dynamic-runtime build is
  117,248 B smaller (68% reduction) and 20,480 B smaller than current GCC x86.
- Rebuilt only GCC x86, Clang x86, and regular Crinkler x86. No x64 or Tiny
  output was generated. Removed `dist/systray.ico`; the Crinkler icon is
  embedded in its EXE.
- Headless tests independently started all three outputs. `/` and `/files/`
  returned HTTP 200 with the expected page title and `readme.txt`; all test
  processes were stopped, and port 8000 had no listener afterward.

## Versioning

- Current project version: V0.0.2. The tray menu displays this application
  version; increment the patch component by 0.0.1 for each code change.
- After a code change builds and its applicable runtime checks pass, record it
  in a local Git commit and create the matching version tag.
- Built only the GCC x86, Clang x86, and regular Crinkler x86 executables for
  V0.0.1. All three independently returned HTTP 200 for `/` and `/files/`;
  the homepage and `readme.txt` listing content were checked, and each process
  was stopped with port 8000 clear afterward.
- V0.0.1 builds: GCC x86 (75,776 B), Clang x86 (55,296 B), and Crinkler x86
  (22,413 B). No x64 or Tiny outputs were generated for this version.

## V0.0.2 update (2026-11-24)

- The settings dialog now explicitly handles `WM_CLOSE` with `EndDialog`, so
  its title-bar X closes it. Dialog width was reduced from 400 to 200 dialog
  units and controls were rearranged to fit.
- A hidden-desktop test opened the actual dialog resource, sent `SC_CLOSE`, and
  confirmed `DialogBoxParamW` returned `IDCANCEL` without showing the window.
- Rebuilt only the GCC x86, Clang x86, and regular Crinkler x86 outputs. Sizes:
  75,776 B, 55,296 B, and 22,144 B respectively. No x64 or Tiny output was
  generated. Each final dist EXE returned HTTP 200 for `/` and `/files/`, the
  page title and `readme.txt` were checked, and every test process was stopped.
- Added [x86_static_link_analysis.md](x86_static_link_analysis.md), based on
  current x86 linker maps, the Crinkler report, and PE import inspection.

## V0.0.3 update (2026-11-24)

- Changed only the Clang x86 build to target MinGW GNU ABI and link the dynamic
  `msvcrt.dll` import library (`libmsvcrt-os.a`). No CRT implementation is
  statically linked. Clang x64 keeps its existing MSVC/UCRT configuration.
- The x86 executable imports the seven available memory/string functions from
  `msvcrt.dll` and no longer imports `VCRUNTIME140.dll` or UCRT API Set DLLs.
- The output is 66,048 B (previous MSVC-target Clang x86 was 55,296 B). It is
  PE32/i386, has no base-relocation directory or `.reloc` section, and imports
  the expected Windows system DLLs.
- Built only `dist/http-server-clang-x86.exe`. Background runtime check kept
  the process alive, returned HTTP 200 for `/` and `/files/`, confirmed the
  homepage title and `readme.txt`, then stopped the process and confirmed port
  8000 had no remaining listener.
- LLVM LTO is not available for this GNU-target build with the installed linker;
  the build script now reports this if x86 LTO is requested. No x64 or Tiny
  outputs were rebuilt.

## V0.0.4 update (2026-11-24)

- Restored the Clang x86 MSVC target and added the custom `MongooseEntry`
  startup. The linker uses `/NODEFAULTLIB` and `/ENTRY:MongooseEntry@0`, so it
  bypasses both MSVC and MinGW CRT startup code.
- Added a small x86 import definition for C functions used by the server;
  `lib.exe` builds an import library that directs them to dynamic `msvcrt.dll`.
  The import table has no `VCRUNTIME140.dll` or UCRT API Set.
- The linker map contains no CRT startup entry, MSVC exception helpers, or
  MinGW pseudo-relocator. It retains only small compiler-support members from
  `msvcrt.lib`, including `__aulldiv` and `_fltused`; this is not a static CRT.
- Built only `dist/http-server-clang-x86.exe` (49,664 B). It is PE32/i386 with
  the base-relocation table removed. Background runtime testing returned HTTP
  200 for `/` and `/files/`, checked the homepage title and `readme.txt`, then
  stopped the server and confirmed port 8000 was clear.
- No x64 or Tiny artifact was rebuilt. Tray interaction and Windows service
  installation were not re-tested in this build.
- Built the standard Crinkler x86 output with
  `Script/build-crinkler.ps1`; `dist/http-server-crinkler-x86.exe` is 22,145 B
  (PE32/i386). The complete linker log records a 1 MB hash table, with both
  Tiny compressor and Tiny import disabled. Crinkler emitted one forwarded
  `DefWindowProcW` warning and replaced it with `NtdllDefWindowProc_W`.
- Headless checks launched the standard output from the repository root (not
  its `dist` directory). `/` and `/files/` returned HTTP 200; the homepage
  title and `readme.txt` listing were verified. The test process was stopped
  and port 8000 was confirmed clear. No x64 or Tiny output was built.

## Three-artifact rebuild (2026-11-24)

- Rebuilt only the official delivery set: Clang x86 (49,664 B), Crinkler x86
  (22,145 B), and Clang x64 (64,000 B). PE inspection identified i386, i386,
  and x86-64 respectively.
- Independently launched each EXE from `C:\Windows\Temp`. For every artifact,
  `/` and `/files/` returned HTTP 200; the homepage title and `readme.txt`
  listing were checked. Test processes were stopped and port 8000 was clear.
- The Crinkler link log records a 1 MB hash table and both Tiny options disabled.
- The three executables remain ignored build outputs under `dist/`; no GCC,
  LTO, or Tiny artifact was built.
