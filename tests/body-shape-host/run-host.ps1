param([string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$bodyRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$bodyOutput=Join-Path $bodyRoot '.tooling/body128/host-final'
$bodyClasses=Join-Path $bodyOutput 'classes'
[IO.Directory]::CreateDirectory($bodyClasses)|Out-Null
$bodySources=@(Get-ChildItem -LiteralPath (Join-Path $bodyRoot 'app/src/main/java/cc/huevia/ncp') -Filter '*.java' -File|ForEach-Object FullName)
foreach($name in @('PhotoEditStore','PhotoRecipeStore','PhotoAdjustmentCopy')){$bodySources+=Join-Path $bodyRoot "app/src/main/java/cc/huevia/album/$name.java"}
foreach($directory in @('body-shape-host/cc/huevia/ncp','portrait-host/cc/huevia/ncp','cleanup-host/cc/huevia/ncp','palette-host/cc/huevia/ncp','editor-java/cc/huevia/album','adjustment-region-host/cc/huevia/ncp')){
    $bodySources+=@(Get-ChildItem -LiteralPath (Join-Path $bodyRoot "tests/$directory") -Filter '*.java' -File|ForEach-Object FullName)
}
$bodySources+=Join-Path $bodyRoot 'tests/java/cc/huevia/ncp/NcpCompatibilityFixtures.java'
& (Join-Path $JdkRoot 'bin/javac.exe') '-encoding' 'UTF-8' '-d' $bodyClasses @bodySources
if($LASTEXITCODE -ne 0){throw 'Body host compilation failed'}
$bodyResults=@()
foreach($name in @('PhotoBodyShapeTest','CleanupLegacyVectors','PaletteLegacyVectors','PortraitModelTest','PortraitPipelineTest','PortraitGlobalToneTest','PortraitSkinMaskTest','PhotoCleanupTest','PhotoColorPaletteTest','AdjustmentRegionTest')){
    $bodyText=(& (Join-Path $JdkRoot 'bin/java.exe') '-Xmx96m' '-cp' $bodyClasses "cc.huevia.ncp.$name" 2>&1)-join "`n"
    $bodyExit=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $bodyOutput "$name.log"),$bodyText+"`n",[Text.UTF8Encoding]::new($false))
    if($bodyExit -ne 0){throw "$name failed: $bodyText"}
    $bodyGolden=$null
    if($name.EndsWith('LegacyVectors')){
        $bodyGolden=if($name.StartsWith('Cleanup')){'tests/cleanup-host/legacy-vectors.txt'}else{'tests/palette-host/legacy-vectors.txt'}
        if($bodyText.Trim() -ne [IO.File]::ReadAllText((Join-Path $bodyRoot $bodyGolden)).Replace("`r`n","`n").Trim()){throw "$name legacy bytes or pixels changed"}
    }
    $bodyResults+=[ordered]@{test=$name;exitCode=$bodyExit;golden=$bodyGolden;log="$name.log";sha256=(Get-FileHash -LiteralPath (Join-Path $bodyOutput "$name.log") -Algorithm SHA256).Hash.ToLowerInvariant()}
    Write-Output "$name PASS"
}
$bodyInputs=@($bodySources)+@($PSCommandPath)
[IO.File]::WriteAllText((Join-Path $bodyOutput 'result.json'),([ordered]@{pass=$true;heapLimitMiB=96;tests=$bodyResults;inputs=@($bodyInputs|ForEach-Object{[ordered]@{path=$_.Substring($bodyRoot.Length).TrimStart([char[]]'\/').Replace('\','/');sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()}})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
