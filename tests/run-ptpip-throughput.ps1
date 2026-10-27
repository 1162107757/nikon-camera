param([string]$JdkHome='D:/dev/Java/jdk-17.0.19',[string]$ClassesDirectory,[int]$Trials=3)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$classes=if($ClassesDirectory){$ClassesDirectory}else{Join-Path $PSScriptRoot '.build/ptpip-throughput'}
New-Item -ItemType Directory -Force -Path $classes|Out-Null
$javaRoot=Join-Path $projectRoot 'app/src/main/java/cc/huevia'
$sources=@(Get-ChildItem -LiteralPath (Join-Path $javaRoot 'ptp') -Filter '*.java'|ForEach-Object FullName)
foreach($name in @('PictureControlData','PictureControlWriteValidation')){$sources+=Join-Path $javaRoot ('picturecontrol/'+$name+'.java')}
foreach($name in @('PhotoCameraClient','PtpIpClient','ConnectionTrace')){$sources+=Join-Path $javaRoot ('album/'+$name+'.java')}
$sources+=Join-Path $PSScriptRoot 'java/cc/huevia/album/PtpIpTcpThroughputBenchmark.java'
& (Join-Path $JdkHome 'bin/javac.exe') --release 17 -encoding UTF-8 -d $classes @sources
if($LASTEXITCODE -ne 0){throw 'TCP throughput benchmark compilation failed.'}
& (Join-Path $JdkHome 'bin/java.exe') -cp $classes cc.huevia.album.PtpIpTcpThroughputBenchmark $Trials
if($LASTEXITCODE -ne 0){throw 'TCP throughput benchmark failed.'}
