# Put spider.jar into app internal cache.
# pm install -r wipes cache/ ; after that TVBox sources silently return n=0.
# Idempotent: download from jsdelivr when missing, always overwrite, verify bytes inside cache.
#
# Usage:
#   .\push_spider.ps1                        # first connected device
#   .\push_spider.ps1 -dev 0676xxxxxxxx      # specific device
#   .\push_spider.ps1 -jar D:\path\spider.jar
param(
  [string]$dev = '',
  [string]$jar = ''
)

if (-not $jar) { $jar = Join-Path $env:TEMP 'spider.jar' }
$pkg = 'top.yiqikan.app.debug'
$sel = @()
if ($dev) { $sel = @('-s', $dev) }

if (-not (Test-Path $jar)) {
  Write-Host '[push_spider] local jar missing, download from jsdelivr'
  Invoke-WebRequest 'https://cdn.jsdelivr.net/gh/qist/tvbox@master/jar/spider.jar' -OutFile $jar
}
$want = (Get-Item $jar).Length
adb @sel push $jar /data/local/tmp/spider.jar | Out-Null
adb @sel shell "run-as $pkg cp /data/local/tmp/spider.jar cache/spider.jar" | Out-Null
$r = (adb @sel shell "run-as $pkg ls -l cache/spider.jar") -join "`n"
Write-Host "[push_spider] $r"

if ($r -notmatch 'spider\.jar') { throw '[push_spider] copy into cache failed: spider.jar not found' }
$m = [regex]::Match($r, '(\d+)\s+\d{4}-\d{2}-\d{2}')
$got = if ($m.Success) { [int64]$m.Groups[1].Value } else { -1 }
if ($got -ne $want) { throw "[push_spider] size mismatch: local $want / device $got" }
Write-Host "[push_spider] OK bytes=$got"
