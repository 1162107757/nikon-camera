param([string]$JdkHome='D:/dev/Java/jdk-17.0.19',[string]$AndroidJar='D:/dev/android-sdk/platforms/android-35/android.jar')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$classes=Join-Path $PSScriptRoot '.build/preset-home-filter182/classes'
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$sources=@(Get-ChildItem -LiteralPath (Join-Path $root 'app/src/main/java/cc/huevia/library') -Filter '*.java' | ForEach-Object FullName)
$sources+=Join-Path $root 'app/src/main/java/cc/huevia/ncp/NcpFile.java'
foreach($test in @('PresetHomeFilterTest','OnlinePresetSearchTest')){$sources+=Join-Path $PSScriptRoot ('library-java/cc/huevia/library/'+$test+'.java')}
& (Join-Path $JdkHome 'bin/javac.exe') --release 17 -encoding UTF-8 -cp $AndroidJar -sourcepath (Join-Path $root 'app/src/main/java') -d $classes @sources
if($LASTEXITCODE -ne 0){throw 'Home filter compilation failed'}
foreach($test in @('PresetHomeFilterTest','OnlinePresetSearchTest')){
 & (Join-Path $JdkHome 'bin/java.exe') '-Dfile.encoding=UTF-8' -cp ($classes+[IO.Path]::PathSeparator+$AndroidJar) ('cc.huevia.library.'+$test)
 if($LASTEXITCODE -ne 0){throw ('Home filter regression failed: '+$test)}
}
