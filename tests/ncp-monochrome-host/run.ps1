param([string]$JdkHome='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $PSScriptRoot '.build/classes'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$javaRoot=Join-Path $root 'app/src/main/java/cc/huevia/ncp'
$sources=@(Get-ChildItem -LiteralPath $javaRoot -Filter '*.java' | ForEach-Object FullName)
$sources+=Join-Path $root 'app/src/main/java/cc/huevia/library/LibraryJson.java'
$sources+=Join-Path $root 'app/src/main/java/cc/huevia/library/PresetFile.java'
foreach($test in @('NcpCompatibilityFixtures','NcpFileTest','NcpPreviewProfileTest','NcpPictureControlConverterTest')){$sources+=Join-Path $root ('tests/java/cc/huevia/ncp/'+$test+'.java')}
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'cc') -Recurse -Filter '*.java' | ForEach-Object FullName)
& (Join-Path $JdkHome 'bin/javac.exe') '-J-Xmx256m' --release 17 -encoding UTF-8 -d $output @sources
if($LASTEXITCODE -ne 0){throw 'NCP monochrome host compilation failed.'}
foreach($test in @('NcpMonochromePreviewProfileTest','NcpFileTest','NcpPreviewProfileTest','NcpPictureControlConverterTest')){
    & (Join-Path $JdkHome 'bin/java.exe') '-Dfile.encoding=UTF-8' '-Xmx96m' -cp $output ('cc.huevia.ncp.'+$test)
    if($LASTEXITCODE -ne 0){throw ('NCP monochrome regression failed: '+$test)}
}
