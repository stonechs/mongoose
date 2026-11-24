param(
    [ValidateSet('x64', 'x86')]
    [string]$Architecture = 'x64'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $projectRoot 'src'
$outputDir = Join-Path $projectRoot 'dist'
$resourceDir = Join-Path $projectRoot 'build'
$outputName = if ($Architecture -eq 'x86') { 'http-server-gcc-x86.exe' } else { 'http-server.exe' }
$outputFile = Join-Path $outputDir $outputName

$compilerPath = if ($Architecture -eq 'x86') {
    $i686Compiler = 'D:\tools\winlibs-i686\toolchain\mingw32\bin\gcc.exe'
    if (-not (Test-Path $i686Compiler)) {
        throw "i686 GCC not found: $i686Compiler"
    }
    $i686Compiler
} else {
    (Get-Command gcc -ErrorAction Stop).Source
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
New-Item -ItemType Directory -Path $resourceDir -Force | Out-Null
$resourceCompiler = if ($Architecture -eq 'x86') { Join-Path (Split-Path -Parent $compilerPath) 'windres.exe' } else { (Get-Command windres -ErrorAction Stop).Source }
$resourceObject = Join-Path $resourceDir "tray-$Architecture.o"
$resourceTarget = if ($Architecture -eq 'x86') { 'pe-i386' } else { 'pe-x86-64' }
& $resourceCompiler -I $sourceDir -F $resourceTarget -O coff -i (Join-Path $sourceDir 'tray.rc') -o $resourceObject
if ($LASTEXITCODE -ne 0) { throw "windres failed with exit code $LASTEXITCODE" }

$arguments = @(
    '-std=c11'
    '-Wall'
    '-Wextra'
    '-Os'
    '-flto'
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
    '-mwindows'
    '-lws2_32'
    '-lshell32'
    '-ladvapi32'
    '-Wl,--gc-sections'
    '-Wl,--disable-dynamicbase'
    '-Wl,--disable-reloc-section'
    '-s'
    '-o'
    $outputFile
)

& $compilerPath @arguments
if ($LASTEXITCODE -ne 0) {
    throw "GCC failed with exit code $LASTEXITCODE"
}

Copy-Item (Join-Path $projectRoot 'web_root\*') $outputDir -Recurse -Force

Write-Output "Built $outputFile"

