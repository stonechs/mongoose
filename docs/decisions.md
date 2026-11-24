# Project decisions

## Official executable deliverables (2026-11-24)

The official delivery set contains only these three executables:

- Clang x86: `dist/http-server-clang-x86.exe`
- Clang x86 linked with Crinkler: `dist/http-server-crinkler-x86.exe`
- Clang x64: `dist/http-server-clang.exe`

Do not include GCC, LTO, or Tiny variants in project deliveries. Existing
individual build scripts and historical files may remain for maintenance and
reference; their presence does not add them to the official delivery set.
