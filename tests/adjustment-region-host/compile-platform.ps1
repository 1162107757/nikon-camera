param([string]$JdkHome='D:/dev/Java/jdk-17.0.19',[string]$AndroidJar='D:/dev/android-sdk/platforms/android-35/android.jar')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $PSScriptRoot '.build/platform'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$classpath=@($AndroidJar,(Join-Path $PSScriptRoot '.build/classes'),(Join-Path $root 'app/build/manual/classes'))
$classpath+=@(Get-ChildItem -LiteralPath (Join-Path $root 'app/libs') -Filter '*.jar' | ForEach-Object FullName)
$classpath+=@(Get-ChildItem -LiteralPath (Join-Path $root 'app/libs/compile-only') -Filter '*.jar' | ForEach-Object FullName)
$sources=@('PhotoPresetRenderer','PhotoDetailSource','PhotoExportPreview','PhotoPresetBatch') | ForEach-Object {Join-Path $root ('app/src/main/java/cc/huevia/album/'+$_+'.java')}
& (Join-Path $JdkHome 'bin/javac.exe') '-J-Xmx256m' --release 17 -encoding UTF-8 -cp ($classpath -join [IO.Path]::PathSeparator) -d $output @sources
if($LASTEXITCODE -ne 0){throw 'Private scratch platform integration compilation failed.'}
Write-Output 'PASS private-cache integration compile: full export, detail raster, export preview and batch callers.'
