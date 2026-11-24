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
$target = if ($Architecture -eq 'x64') { 'x86_64-pc-windows-msvc' } else { 'i686-pc-windows-msvc' }
$outputName = if ($LinkTimeOptimization) {
    if ($Architecture -eq 'x64') { 'http-server-clang-lto.exe' } else { 'http-server-clang-x86-lto.exe' }
} elseif ($Architecture -eq 'x64') {
    'http-server-clang.exe'
} else {
    'http-server-clang-x86.exe'
}
$outputFile = Join-Path $outputDir $outputName
$compiler = Get-Command clang -ErrorAction Stop

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
)

if ($Architecture -eq 'x86') {
    $arguments += '-DMG_CUSTOM_ENTRY=1'
}

$arguments += @(
    "-I$sourceDir"
    (Join-Path $sourceDir 'main.c')
    (Join-Path $sourceDir 'mongoose.c')
    $resourceObject
    '-o'
    $outputFile
)

if ($Architecture -eq 'x86') {
    $libraryManager = Get-Command lib.exe -ErrorAction Stop
    $hostBin = Split-Path -Parent $libraryManager.Source
    $vcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $hostBin))
    $crtLibrary = Join-Path $vcRoot 'lib\x86\msvcrt.lib'
    if (-not (Test-Path $crtLibrary)) { throw "MSVC x86 CRT helpers not found: $crtLibrary" }
    $msvcrtImportLibrary = Join-Path $objectDir 'legacy-msvcrt.lib'
    & $libraryManager.Source "/def:$(Join-Path $sourceDir 'msvcrt-x86.def')" '/machine:x86' "/out:$msvcrtImportLibrary"
    if ($LASTEXITCODE -ne 0) { throw "lib.exe failed with exit code $LASTEXITCODE" }

    $arguments += @(
        '-nostdlib'
        '-Wl,/NODEFAULTLIB'
        '-Wl,/ENTRY:MongooseEntry@0'
        '-Wl,/SUBSYSTEM:WINDOWS'
        '-Wl,/SAFESEH:NO'
        '-Wl,/FIXED'
        '-Wl,/OPT:REF'
        '-Wl,/OPT:ICF'
        "-Wl,/MAP:$(Join-Path $objectDir 'http-server.map')"
        $msvcrtImportLibrary
        $crtLibrary
        '-lkernel32'
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

if ($LinkTimeOptimization -and $Architecture -eq 'x86') {
    $arguments += @('-flto', '-fuse-ld=lld')
}

& $compiler.Source @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Clang failed with exit code $LASTEXITCODE"
}

Copy-Item (Join-Path $projectRoot 'web_root\*') $outputDir -Recurse -Force

Write-Output "Built $outputFile"

