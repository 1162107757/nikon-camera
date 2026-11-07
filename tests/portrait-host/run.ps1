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
if($LASTEXITCODE -ne 0){throw 'Portrait regression compilation failed.'}
foreach($test in @('cc.huevia.ncp.PortraitModelTest','cc.huevia.ncp.PortraitLandmarksTest','cc.huevia.ncp.PortraitSkinMaskTest','cc.huevia.ncp.PortraitLandmarkMaskTest','cc.huevia.ncp.PortraitSemanticMaskTest','cc.huevia.ncp.PortraitPipelineTest','cc.huevia.ncp.PortraitToneTest','cc.huevia.ncp.PortraitGlobalToneTest','cc.huevia.ncp.SkinBodyRegionsTest')){
    & (Join-Path $JdkHome 'bin/java.exe') '-Xmx128m' '-XX:+UseSerialGC' -cp $output $test
    if($LASTEXITCODE -ne 0){throw ('Portrait regression failed: '+$test)}
}
