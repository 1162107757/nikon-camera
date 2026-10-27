param([string]$JdkHome='D:\dev\Java\jdk-17.0.19',[switch]$Benchmark)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output=Join-Path $PSScriptRoot '.build\image-performance-108'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$sources=@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'app\src\main\java\cc\huevia\ncp') -Filter '*.java' | ForEach-Object FullName)
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'image-performance-java') -Filter '*.java' -Recurse | ForEach-Object FullName)
& (Join-Path $JdkHome 'bin\javac.exe') '-J-Xmx256m' --release 17 -encoding UTF-8 -d $output @sources
if($LASTEXITCODE -ne 0){throw 'Image performance regression compilation failed.'}
$runArgs=@('-Xmx256m','-XX:+UseSerialGC','-cp',$output,'cc.huevia.ncp.ImagePerformanceTest')
if($Benchmark){$runArgs+='--bench'}
& (Join-Path $JdkHome 'bin\java.exe') @runArgs
if($LASTEXITCODE -ne 0){throw 'Image performance regression failed.'}
