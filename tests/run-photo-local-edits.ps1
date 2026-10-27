param([string]$JdkHome='D:\dev\Java\jdk-17.0.19')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output=Join-Path $PSScriptRoot '.build\photo-local-edits'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$sources=@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'app\src\main\java\cc\huevia\ncp') -Filter '*.java' | ForEach-Object FullName)
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'local-edits-java') -Filter '*.java' -Recurse | ForEach-Object FullName)
& (Join-Path $JdkHome 'bin\javac.exe') '-J-Xmx256m' --release 17 -encoding UTF-8 -d $output @sources
if($LASTEXITCODE -ne 0){throw 'Local-edit regression compilation failed.'}
& (Join-Path $JdkHome 'bin\java.exe') '-Xmx64m' '-XX:+UseSerialGC' '-cp' $output 'cc.huevia.ncp.PhotoLocalEditsTest'
if($LASTEXITCODE -ne 0){throw 'Local-edit regression failed.'}
