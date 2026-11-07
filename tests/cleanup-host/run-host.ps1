param([string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$cleanupRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$cleanupOutput=Join-Path $cleanupRoot '.tooling/cleanup127/engine'
[IO.Directory]::CreateDirectory($cleanupOutput)|Out-Null
$cleanupClasses=Join-Path $cleanupOutput 'classes'
$cleanupSources=@(Get-ChildItem -LiteralPath (Join-Path $cleanupRoot 'app/src/main/java/cc/huevia/ncp') -Filter '*.java' -File|ForEach-Object {$_.FullName})
foreach($name in @('PhotoEditStore','PhotoRecipeStore','PhotoAdjustmentCopy')){$cleanupSources+=Join-Path $cleanupRoot "app/src/main/java/cc/huevia/album/$name.java"}
foreach($name in @('CleanupLegacyVectors','PhotoCleanupTest','PhotoCleanupBoundedTest')){$cleanupSources+=Join-Path $PSScriptRoot "cc/huevia/ncp/$name.java"}
foreach($name in @('PaletteLegacyVectors','PhotoColorPaletteTest')){$cleanupSources+=Join-Path $cleanupRoot "tests/palette-host/cc/huevia/ncp/$name.java"}
foreach($name in @('PhotoAdjustmentsTest','PhotoToolsPersistenceTest','PhotoColorAdjustmentsTest')){$cleanupSources+=Join-Path $cleanupRoot "tests/editor-java/cc/huevia/album/$name.java"}
$cleanupSources+=Join-Path $cleanupRoot 'tests/adjustment-region-host/cc/huevia/ncp/AdjustmentRegionTest.java'
$cleanupSources+=Join-Path $cleanupRoot 'tests/java/cc/huevia/ncp/NcpCompatibilityFixtures.java'
& (Join-Path $JdkRoot 'bin/javac.exe') '-encoding' 'UTF-8' '-d' $cleanupClasses @cleanupSources
if($LASTEXITCODE -ne 0){throw 'cleanup host compile failed'}
foreach($name in @('cc.huevia.ncp.CleanupLegacyVectors','cc.huevia.ncp.PaletteLegacyVectors','cc.huevia.ncp.PhotoCleanupTest','cc.huevia.ncp.PhotoCleanupBoundedTest','cc.huevia.ncp.PhotoColorPaletteTest','cc.huevia.album.PhotoAdjustmentsTest','cc.huevia.album.PhotoToolsPersistenceTest','cc.huevia.album.PhotoColorAdjustmentsTest','cc.huevia.ncp.AdjustmentRegionTest')){
    $cleanupText=(& (Join-Path $JdkRoot 'bin/java.exe') '-Xmx96m' '-cp' $cleanupClasses $name 2>&1)-join "`n"
    $cleanupExit=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $cleanupOutput ($name.Split('.')[-1]+'.log')),$cleanupText+"`n",(New-Object Text.UTF8Encoding($false)))
    if($cleanupExit -ne 0){throw "$name failed: $cleanupText"}
    if($name.EndsWith('LegacyVectors')){
        $cleanupGolden=if($name.EndsWith('CleanupLegacyVectors')){Join-Path $PSScriptRoot 'legacy-vectors.txt'}else{Join-Path $cleanupRoot 'tests/palette-host/legacy-vectors.txt'}
        if($cleanupText.Trim() -ne [IO.File]::ReadAllText($cleanupGolden).Replace("`r`n","`n").Trim()){throw "$name legacy bytes/pixels changed"}
        Write-Output "$name exact golden match"
    }else{Write-Output $cleanupText}
}
