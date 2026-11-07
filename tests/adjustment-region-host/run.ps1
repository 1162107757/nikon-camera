param([string]$JdkHome='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $PSScriptRoot '.build/classes'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$javaRoot=Join-Path $root 'app/src/main/java/cc/huevia'
$sources=@(Get-ChildItem -LiteralPath (Join-Path $javaRoot 'ncp') -Filter '*.java' | ForEach-Object FullName)
foreach($source in @('PhotoEditStore','PhotoRecipeStore','PhotoAdjustmentCopy')){$sources+=Join-Path $javaRoot ('album/'+$source+'.java')}
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'cc') -Recurse -Filter '*.java' | ForEach-Object FullName)
& (Join-Path $JdkHome 'bin/javac.exe') '-J-Xmx256m' --release 17 -encoding UTF-8 -d $output @sources
if($LASTEXITCODE -ne 0){throw 'Adjustment region compilation failed.'}
& (Join-Path $JdkHome 'bin/java.exe') '-Xmx96m' '-XX:+UseSerialGC' -cp $output cc.huevia.ncp.AdjustmentRegionTest
if($LASTEXITCODE -ne 0){throw 'Adjustment region regression failed.'}
