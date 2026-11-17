# build_check.ps1 —— 构建门禁：编译失败、或 APK 比源码旧，都拦下来
# 用法：
#   pwsh -File scripts\build_check.ps1              # 正常构建 + 校验
#   pwsh -File scripts\build_check.ps1 -SkipBuild   # 只校验（调试门禁本身用）
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$apkPath = Join-Path $root 'build\app\outputs\flutter-apk\app-debug.apk'
$srcRoot = Join-Path $root 'android\app\src\main\java'

if (-not $SkipBuild) {
    Write-Host '[gate] flutter build apk --debug ...'
    Push-Location $root
    try {
        flutter build apk --debug
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($code -ne 0) {
        Write-Host "[gate] FAIL 编译失败（flutter build 退出码 $code）—— 不要把旧包当新包装" -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path $apkPath)) {
    Write-Host "[gate] FAIL 没有产物：$apkPath" -ForegroundColor Red
    exit 1
}

$apk = Get-Item $apkPath

# 三组扫描取全局最新：java（Android 侧）、dart（lib）、test（test\lib）。
# 只扫 java 会漏掉「只改了 dart、没重新构建」的情况 —— 那时 APK 看着比 java 新，
# 实际不含新 dart，门禁照样放行（坑：apk 21:24 晚于全部 java，却晚于新 dart 才有意义）。
$groups = @(
    @{ Name = 'java'; Root = $srcRoot;                 Filter = @('*.java', '*.kt') },
    @{ Name = 'dart'; Root = (Join-Path $root 'lib');  Filter = @('*.dart') },
    @{ Name = 'test'; Root = (Join-Path $root 'test'); Filter = @('*.dart') }
)
$newest = $null
$newestGroup = ''
foreach ($g in $groups) {
    if (-not (Test-Path $g.Root)) { continue }
    $f = Get-ChildItem -Path $g.Root -Recurse -Include $g.Filter -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -ne $f -and ($null -eq $newest -or $f.LastWriteTime -gt $newest.LastWriteTime)) {
        $newest = $f
        $newestGroup = $g.Name
    }
}

if ($null -eq $newest) {
    Write-Host '[gate] FAIL 源码目录里找不到 .java / .kt / .dart' -ForegroundColor Red
    exit 1
}

Write-Host ("[gate] apk   = {0}  {1:N0} B" -f $apk.LastWriteTime, $apk.Length)
Write-Host ("[gate] src   = {0}  {1}  ({2} 组)" -f $newest.LastWriteTime, $newest.Name, $newestGroup)

if ($apk.LastWriteTime -lt $newest.LastWriteTime) {
    Write-Host ("[gate] FAIL APK 比源码旧：这次的包没包含最新源码（{0} 组 {1}）" -f $newestGroup, $newest.Name) -ForegroundColor Red
    exit 1
}

Write-Host '[gate] OK 产物包含最新源码' -ForegroundColor Green
exit 0
