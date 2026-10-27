param([string]$JdkHome='D:/dev/Java/jdk-17.0.19',[switch]$Staged)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$sourceRoot=Join-Path $projectRoot 'app/src/main/java/cc/huevia'
$remoteRoot=if($Staged){Join-Path $projectRoot '.tooling/remote-capture-95/src/cc/huevia/remote'}else{Join-Path $sourceRoot 'remote'}
$classes=Join-Path $PSScriptRoot '.build'
New-Item -ItemType Directory -Force -Path $classes|Out-Null
$sources=@(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'ptp') -Filter '*.java'|ForEach-Object FullName)
foreach($name in @('RemoteTransport','RemoteProperty','RemoteLiveFrame','NikonRemoteCamera')){$sources+=Join-Path $remoteRoot ($name+'.java')}
$sources+=Join-Path $PSScriptRoot 'cc/huevia/remote/RemoteCaptureCoreTest.java'
& (Join-Path $JdkHome 'bin/javac.exe') --release 17 -encoding UTF-8 -d $classes @sources
if($LASTEXITCODE -ne 0){throw 'Remote capture host compilation failed'}
& (Join-Path $JdkHome 'bin/java.exe') -cp $classes cc.huevia.remote.RemoteCaptureCoreTest
if($LASTEXITCODE -ne 0){throw 'Remote capture host checks failed'}
