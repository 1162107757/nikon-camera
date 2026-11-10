param([string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output=Join-Path $PSScriptRoot '.build/raw-development'
New-Item -ItemType Directory -Force -Path $output|Out-Null
$sources=@((Join-Path $root 'app/src/main/java/cc/huevia/ncp/RawDevelopmentSettings.java'),(Join-Path $root 'app/src/main/java/cc/huevia/ncp/RawJpegColorMatch.java'),(Join-Path $PSScriptRoot 'raw-development-device-probe/src/cc/huevia/rawdevelopmentqa/SyntheticDng.java'),(Join-Path $PSScriptRoot 'raw-development-java/cc/huevia/ncp/RawDevelopmentSettingsTest.java'),(Join-Path $PSScriptRoot 'raw-development-java/cc/huevia/ncp/RawJpegColorMatchTest.java'))
$sources+=Join-Path $PSScriptRoot 'raw-development-java/cc/huevia/ncp/RawHighlightColorTest.java'
& (Join-Path $JdkRoot 'bin/javac.exe') -J-Xmx128m --release 17 -encoding UTF-8 -d $output @sources
if($LASTEXITCODE -ne 0){throw 'RAW settings host compilation failed'}
& (Join-Path $JdkRoot 'bin/java.exe') -Xmx64m -cp $output cc.huevia.ncp.RawDevelopmentSettingsTest $output
if($LASTEXITCODE -ne 0){throw 'RAW settings/fixture host verification failed'}
& (Join-Path $JdkRoot 'bin/java.exe') -Xmx128m -cp $output cc.huevia.ncp.RawJpegColorMatchTest
if($LASTEXITCODE -ne 0){throw 'RAW JPEG color match verification failed'}
& (Join-Path $JdkRoot 'bin/java.exe') -Xmx128m -cp $output cc.huevia.ncp.RawHighlightColorTest
if($LASTEXITCODE -ne 0){throw 'RAW highlight color verification failed'}
