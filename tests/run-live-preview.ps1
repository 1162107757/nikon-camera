param([string]$JdkHome='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$classes=Join-Path $PSScriptRoot '.build/live-preview'
New-Item -ItemType Directory -Force -Path $classes|Out-Null
& (Join-Path $JdkHome 'bin/javac.exe') --release 17 -encoding UTF-8 -d $classes (Join-Path $root 'app/src/main/java/cc/huevia/ui/LatestPreviewQueue.java') (Join-Path $PSScriptRoot 'live-preview-java/cc/huevia/ui/LatestPreviewQueueTest.java')
if($LASTEXITCODE -ne 0){throw 'Preview queue compilation failed'}
& (Join-Path $JdkHome 'bin/java.exe') -cp $classes cc.huevia.ui.LatestPreviewQueueTest
if($LASTEXITCODE -ne 0){throw 'Preview queue checks failed'}
