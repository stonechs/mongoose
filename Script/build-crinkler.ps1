param(
    [string]$CrinklerPath,
    [switch]$BuildTinyImport
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $projectRoot 'src'
$objectDir = Join-Path $projectRoot 'build\crinkler-x86'
$outputDir = Join-Path $projectRoot 'dist'
$programFilesX86 = ${env:ProgramFiles(x86)}

if ([string]::IsNullOrWhiteSpace($CrinklerPath)) {
    $crinklerCommand = Get-Command Crinkler.exe -ErrorAction SilentlyContinue
    if ($null -ne $crinklerCommand) {
        $CrinklerPath = $crinklerCommand.Source
    } else {
        $siblingCrinkler = Join-Path (Split-Path -Parent $projectRoot) 'Crinkler\releases\crinkler30b\Win32\Crinkler.exe'
        if (Test-Path $siblingCrinkler) {
            $CrinklerPath = $siblingCrinkler
        } else {
            throw 'Pass -CrinklerPath or add Crinkler.exe to PATH.'
        }
    }
}
if (-not (Test-Path $CrinklerPath)) {
    throw "Crinkler executable not found: $CrinklerPath"
}

$sdkLibRoot = Join-Path $programFilesX86 'Windows Kits\10\Lib'
$sdkDirs = Get-ChildItem $sdkLibRoot -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName 'um\x86\WS2_32.Lib')
}
$sdkDir = $sdkDirs | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if ($null -eq $sdkDir) {
    throw 'Could not find the Windows SDK x86 import libraries.'
}
$umLibDir = Join-Path $sdkDir.FullName 'um\x86'

$vsRoot = Join-Path $programFilesX86 'Microsoft Visual Studio\2022'
$vcLibDirs = foreach ($edition in Get-ChildItem $vsRoot -Directory) {
    $toolsRoot = Join-Path $edition.FullName 'VC\Tools\MSVC'
    if (Test-Path $toolsRoot) {
        Get-ChildItem $toolsRoot -Directory | ForEach-Object {
            Join-Path $_.FullName 'lib\x86'
        }
    }
}
$vcLibDir = $vcLibDirs | Where-Object { Test-Path (Join-Path $_ 'libcmt.lib') } | Select-Object -First 1
if ($null -eq $vcLibDir) {
    throw 'Could not find the Visual C++ x86 libcmt.lib runtime helper library.'
}

$compiler = Get-Command clang-cl -ErrorAction Stop
New-Item -ItemType Directory -Path $objectDir, $outputDir -Force | Out-Null

$defines = @(
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
    '-DMG_CRINKLER=1'
)

foreach ($unit in @('main', 'mongoose')) {
    $compileArgs = @(
        '--target=i686-pc-windows-msvc'
        '/nologo'
        '/c'
        '/O1'
        '/clang:-Oz'
        '/GS-'
        '/Zl'
        '/MT'
        '/TC'
        '/std:c11'
    ) + $defines + @(
        "/I$sourceDir"
        (Join-Path $sourceDir "$unit.c")
        "/Fo:$(Join-Path $objectDir "$unit.obj")"
    )
    & $compiler.Source @compileArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Clang failed to compile $unit.c with exit code $LASTEXITCODE"
    }
}

$resourceCompiler = (Get-Command windres -ErrorAction Stop).Source
& $resourceCompiler -DMG_CRINKLER=1 -I $sourceDir -F pe-i386 -O coff -i (Join-Path $sourceDir 'tray.rc') -o (Join-Path $objectDir 'tray.obj')
if ($LASTEXITCODE -ne 0) { throw "windres failed with exit code $LASTEXITCODE" }

$iconBytes = [IO.File]::ReadAllBytes((Join-Path $sourceDir 'systray.ico'))
$iconValues = ($iconBytes | ForEach-Object { '0x{0:X2}' -f $_ }) -join ', '
$iconSource = "const unsigned char mg_systray_ico[] = {$iconValues};`r`nconst unsigned int mg_systray_ico_size = $($iconBytes.Length);`r`n"
$iconSourceFile = Join-Path $objectDir 'icon-data.c'
[IO.File]::WriteAllText($iconSourceFile, $iconSource, [Text.Encoding]::ASCII)
$iconCompileArgs = @(
    '--target=i686-pc-windows-msvc', '/nologo', '/c', '/O1', '/clang:-Oz', '/GS-', '/Zl',
    '/MT', '/TC', '/std:c11', "/Fo:$(Join-Path $objectDir 'icon-data.obj')", $iconSourceFile
)
& $compiler.Source @iconCompileArgs
if ($LASTEXITCODE -ne 0) { throw "Clang failed to compile embedded tray icon with exit code $LASTEXITCODE" }

$linkInputs = @(
    (Join-Path $objectDir 'main.obj')
    (Join-Path $objectDir 'mongoose.obj')
    (Join-Path $objectDir 'icon-data.obj')
    (Join-Path $objectDir 'tray.obj')
    (Join-Path $umLibDir 'WS2_32.Lib')
    (Join-Path $umLibDir 'kernel32.Lib')
    (Join-Path $umLibDir 'User32.Lib')
    (Join-Path $umLibDir 'Shell32.Lib')
    (Join-Path $umLibDir 'Advapi32.Lib')
    (Join-Path $vcLibDir 'libcmt.lib')
)

$variants = @(@{ Name = 'http-server-crinkler-x86.exe'; Extra = @() })
if ($BuildTinyImport) {
    $variants += @{ Name = 'http-server-crinkler-tiny-x86.exe'; Extra = @('/TINYHEADER', '/TINYIMPORT') }
}

foreach ($variant in $variants) {
    $outputFile = Join-Path $outputDir $variant.Name
    $logFile = Join-Path $objectDir ($variant.Name + '.link.log')
    $linkArgs = @(
        '/CRINKLER'
        '/ENTRY:CrinklerEntry'
        '/SUBSYSTEM:WINDOWS'
        '/HASHSIZE:1'
        '/COMPMODE:SLOW'
    ) + $variant.Extra + @('/OUT:' + $outputFile) + $linkInputs
    & $CrinklerPath @linkArgs *> $logFile
    $linkExit = $LASTEXITCODE
    Get-Content $logFile
    if ($linkExit -ne 0) {
        throw "Crinkler failed to build $($variant.Name) with exit code $linkExit. See $logFile"
    }
    Write-Output "Built $outputFile"
}

Copy-Item (Join-Path $projectRoot 'web_root\*') $outputDir -Recurse -Force

