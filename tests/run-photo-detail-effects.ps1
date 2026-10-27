param([string]$JdkHome='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output=Join-Path $PSScriptRoot '.build/photo-detail-effects'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$sources=@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'app/src/main/java/cc/huevia/ncp') -Filter '*.java' | ForEach-Object FullName)
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'detail-effects-java') -Filter '*.java' -Recurse | ForEach-Object FullName)
& (Join-Path $JdkHome 'bin/javac.exe') -J-Xmx256m --release 17 -encoding UTF-8 -d $output @sources
if($LASTEXITCODE -ne 0){throw 'Photo detail effects core compilation failed.'}
& (Join-Path $JdkHome 'bin/java.exe') -Xmx64m -cp $output cc.huevia.ncp.PhotoDetailEffectsTest
if($LASTEXITCODE -ne 0){throw 'Photo detail effects verification failed.'}
