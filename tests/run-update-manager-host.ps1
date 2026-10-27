param([string]$JdkHome = 'D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$classes = Join-Path $PSScriptRoot '.build/update-manager-host/classes'
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$fixtures = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'update-manager-host/stubs') -Recurse -Filter '*.java' | ForEach-Object { $_.FullName })
$sources = @(
    (Join-Path $root 'app/src/main/java/cc/huevia/updates/UpdatePolicy.java'),
    (Join-Path $root 'app/src/main/java/cc/huevia/updates/AppUpdateManager.java'),
    (Join-Path $PSScriptRoot 'update-manager-host/src/cc/huevia/updates/AppUpdateManagerHostTest.java')
)
& (Join-Path $JdkHome 'bin/javac.exe') --release 17 -encoding UTF-8 -d $classes $fixtures $sources
if ($LASTEXITCODE -ne 0) { throw 'Update manager host compilation failed.' }
& (Join-Path $JdkHome 'bin/java.exe') -cp $classes cc.huevia.updates.AppUpdateManagerHostTest
if ($LASTEXITCODE -ne 0) { throw 'Update manager host regression failed.' }
