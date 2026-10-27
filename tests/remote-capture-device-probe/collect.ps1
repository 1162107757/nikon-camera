param([string]$CandidateApk='dist/huevia-0.20.0-beta-debug.apk')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$evidenceRoot=Join-Path $projectRoot 'docs/validation/remote-capture-95'
$candidate=Join-Path $projectRoot $CandidateApk
$sha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
$cohort=Join-Path $evidenceRoot $sha.Substring(0,8)
$matrix=@();$images=@()
foreach($mode in @('phone','font1.3','landscape','dark')){
    $runs=@(Get-ChildItem -LiteralPath $cohort -Directory|Where-Object{$_.Name.StartsWith($mode+'-')}|Sort-Object LastWriteTime -Descending)
    $selected=$null
    foreach($run in $runs){$reportPath=Join-Path $run.FullName 'run/report.json';if(Test-Path -LiteralPath $reportPath){$report=Get-Content -LiteralPath $reportPath -Raw|ConvertFrom-Json;if($report.status -eq 'PASS' -and $report.apkSha256 -eq $sha){$selected=$run;break}}}
    if(-not $selected){throw ('No passing current-cohort evidence: '+$mode)}
    if($mode -eq 'landscape' -and $report.nativeOrientation -ne 'landscape'){throw 'Landscape evidence is not landscape'}
    $capturePaths=@(Get-ChildItem -LiteralPath (Join-Path $selected.FullName 'run') -Filter '*.png'|Sort-Object Name)
    $matrix+=[ordered]@{mode=$mode;apkSha256=$sha;status=$report.status;assertions=$report.assertions.Count;nativeOrientation=$report.nativeOrientation;root=[IO.Path]::GetRelativePath($projectRoot,$selected.FullName).Replace('\','/');captures=@($capturePaths|ForEach-Object{$_.Name})}
    foreach($png in $capturePaths){$images+=[pscustomobject]@{mode=$mode;file=$png}}
}
$old=Get-Content -LiteralPath (Join-Path $projectRoot 'docs/validation/photo-detail-load-94/FINAL-IDENTITY.json') -Raw|ConvertFrom-Json
$paths=@($old.inputs.path)+@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'app/src/main') -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($projectRoot,$_.FullName).Replace('\','/')})
$inputs=@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;bytes=(Get-Item -LiteralPath (Join-Path $projectRoot $_)).Length;sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot $_) -Algorithm SHA256).Hash.ToLowerInvariant()}})
$modified=@($old.inputs|Where-Object{(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $projectRoot $_.path)).Hash.ToLowerInvariant() -ne $_.sha256}|Select-Object -ExpandProperty path)
$identity=[ordered]@{status='CANDIDATE_AWAITING_FINISH_REVIEW';versionCode=95;versionName='0.20.0-beta';apkPath=$CandidateApk;apkSha256=$sha;apkBytes=(Get-Item -LiteralPath $candidate).Length;inputCount=$inputs.Count;inputs=$inputs;modified94Inputs=$modified;baseline94ApkSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $projectRoot 'dist/huevia-0.19.3-beta-debug.apk')).Hash.ToLowerInvariant()}
[IO.File]::WriteAllText((Join-Path $evidenceRoot 'CANDIDATE-IDENTITY.json'),($identity|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $evidenceRoot 'UI-MATRIX.json'),([ordered]@{scope='Native emulator + synthetic PTP/IP peer, not camera interoperability';apkSha256=$sha;modes=$matrix}|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Add-Type -AssemblyName System.Drawing
$columns=6;$cellWidth=240;$cellHeight=360;$rows=[int][Math]::Ceiling($images.Count/[double]$columns)
$contact=[Drawing.Bitmap]::new($columns*$cellWidth,$rows*$cellHeight)
$graphics=[Drawing.Graphics]::FromImage($contact);$graphics.Clear([Drawing.Color]::FromArgb(242,239,234));$graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font=[Drawing.Font]::new('Microsoft YaHei',9);$brush=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(32,30,28))
try{for($i=0;$i -lt $images.Count;$i++){$item=$images[$i];$x=($i%$columns)*$cellWidth;$y=[int][Math]::Floor($i/$columns)*$cellHeight;$graphics.DrawString(($item.mode+' / '+$item.file.Name),$font,$brush,$x+8,$y+4);$source=[Drawing.Image]::FromFile($item.file.FullName);try{$scale=[Math]::Min(($cellWidth-16)/[double]$source.Width,($cellHeight-32)/[double]$source.Height);$w=[int]($source.Width*$scale);$h=[int]($source.Height*$scale);$graphics.DrawImage($source,$x+[int](($cellWidth-$w)/2),$y+28,$w,$h)}finally{$source.Dispose()}}$contact.Save((Join-Path $evidenceRoot 'REVIEW-CONTACT.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$brush.Dispose();$font.Dispose();$graphics.Dispose();$contact.Dispose()}
$reviewRoot=Join-Path $projectRoot '.impeccable/review/remote-capture-95'
New-Item -ItemType Directory -Force -Path $reviewRoot|Out-Null
$phone=$matrix|Where-Object{$_.mode -eq 'phone'}
Copy-Item -LiteralPath (Join-Path $projectRoot ($phone.root+'/run/ready.png')) -Destination (Join-Path $reviewRoot 'hero-repro.png')
[pscustomobject]@{apkSha256=$sha;inputs=$inputs.Count;captures=$images.Count;assertions=(($matrix|ForEach-Object{$_.assertions})|Measure-Object -Sum).Sum;contact=(Join-Path $evidenceRoot 'REVIEW-CONTACT.png')}|ConvertTo-Json
