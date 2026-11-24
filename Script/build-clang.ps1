param(
    [ValidateSet('x64', 'x86')]
    [string]$Architecture = 'x64',
    [switch]$LinkTimeOptimization
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $projectRoot 'src'
$outputDir = Join-Path $projectRoot 'dist'
$objectDir = Join-Path $projectRoot "build\clang-$Architecture"
$target = if ($Architecture -eq 'x64') { 'x86_64-pc-windows-msvc' } else { 'i686-w64-windows-gnu' }
$outputName = if ($LinkTimeOptimization) {
    if ($Architecture -eq 'x64') { 'http-server-clang-lto.exe' } else { 'http-server-clang-x86-lto.exe' }
} elseif ($Architecture -eq 'x64') {
    'http-server-clang.exe'
} else {
    'http-server-clang-x86.exe'
}
$outputFile = Join-Path $outputDir $outputName
$compiler = Get-Command clang -ErrorAction Stop

if ($Architecture -eq 'x86' -and $LinkTimeOptimization) {
    throw 'Clang x86 uses the GNU target to link the dynamic msvcrt.dll runtime; the installed linker does not support LLVM LTO for this target.'
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
New-Item -ItemType Directory -Path $objectDir -Force | Out-Null
$resourceObject = Join-Path $objectDir 'tray.o'
$resourceTarget = if ($Architecture -eq 'x86') { 'pe-i386' } else { 'pe-x86-64' }
& (Get-Command windres -ErrorAction Stop).Source -I $sourceDir -F $resourceTarget -O coff -i (Join-Path $sourceDir 'tray.rc') -o $resourceObject
if ($LASTEXITCODE -ne 0) { throw "windres failed with exit code $LASTEXITCODE" }

$arguments = @(
    "--target=$target"
    '-Oz'
    '-fno-stack-protector'
    '-ffunction-sections'
    '-fdata-sections'
    '-DMG_ENABLE_IPV6=0'
    '-DMG_ENABLE_SSI=0'
    '-DMG_ENABLE_LOG=0'
    '-DMG_ENABLE_MD5=0'
    '-DMG_ENABLE_HEALTH=0'
    '-DMG_ENABLE_MDASH=0'
    '-DMG_ENABLE_TCPIP=0'
    '-DMG_ENABLE_LWIP=0'
    '-DMG_ENABLE_FREERTOS_TCP=0'
    '-DMG_ENABLE_RL=0'
    '-DMG_ENABLE_FREERTOS=0'
    '-DMG_ENABLE_FATFS=0'
    '-DMG_ENABLE_LFS=0'
    '-DMG_ENABLE_POSIX_FS=1'
    '-DMG_TLS=MG_TLS_NONE'
    '-DMG_OTA=MG_OTA_NONE'
    "-I$sourceDir"
    (Join-Path $sourceDir 'main.c')
    (Join-Path $sourceDir 'mongoose.c')
    $resourceObject
    '-o'
    $outputFile
)

if ($Architecture -eq 'x86') {
    $toolchainRoot = 'D:\tools\winlibs-i686\toolchain\mingw32'
    $toolchainBin = Join-Path $toolchainRoot 'bin'
    $i686Compiler = Join-Path $toolchainBin 'gcc.exe'
    if (-not (Test-Path $i686Compiler)) {
        throw "i686 WinLibs toolchain not found: $toolchainRoot"
    }
    $arguments += @(
        "--sysroot=$toolchainRoot"
        '-B'
        $toolchainBin
        '-fno-asynchronous-unwind-tables'
        '-fno-unwind-tables'
        '-mwindows'
        '-Wl,--gc-sections'
        '-Wl,--disable-dynamicbase'
        '-Wl,--disable-reloc-section'
        '-Wl,--strip-all'
        '-lmsvcrt-os'
        '-lws2_32'
        '-luser32'
        '-lshell32'
        '-ladvapi32'
    )
} else {
    $arguments += @(
        '-fms-runtime-lib=dll'
        '-Wl,/SUBSYSTEM:WINDOWS'
        '-lws2_32'
        '-luser32'
        '-lshell32'
        '-ladvapi32'
        '-Wl,/OPT:REF'
        '-Wl,/OPT:ICF'
        '-Wl,/FIXED'
    )
    if ($LinkTimeOptimization) {
        $arguments += @('-flto', '-fuse-ld=lld')
    }
}

& $compiler.Source @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Clang failed with exit code $LASTEXITCODE"
}

Copy-Item (Join-Path $projectRoot 'web_root\*') $outputDir -Recurse -Force

Write-Output "Built $outputFile"

