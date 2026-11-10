$ErrorActionPreference='Stop'
$root='D:/dev/ai-project/nikon-camera'
$destination=Join-Path $root 'docs/validation/raw-android16-158'
New-Item -ItemType Directory -Force -Path $destination|Out-Null
$adb='D:/dev/Android/Sdk/platform-tools/adb.exe'
$checks=[Collections.Generic.List[object]]::new()
function A([string[]]$Arguments){$v=(& $adb -s emulator-5586 @Arguments 2>&1|Out-String).Trim();if($LASTEXITCODE -ne 0){throw $v};return $v}
function Check([string]$Name,[bool]$Pass){$checks.Add([ordered]@{name=$Name;pass=$Pass});if(-not $Pass){throw $Name}}
function ReadUi([string]$Name){A @('shell','uiautomator','dump','/sdcard/raw158-window.xml')|Out-Null;$s=A @('shell','cat','/sdcard/raw158-window.xml');[IO.File]::WriteAllText((Join-Path $destination ($Name+'.xml')),$s,[Text.UTF8Encoding]::new($false));return [xml]$s}
function TapNode([xml]$Ui,[string]$Value){$n=$Ui.SelectNodes('//node')|Where-Object{$_.'content-desc' -eq $Value -or $_.text -eq $Value}|Select-Object -First 1;if(-not $n){throw ('Missing node '+$Value)};$m=[regex]::Match($n.bounds,'\[(\d+),(\d+)\]\[(\d+),(\d+)\]');if(-not $m.Success){throw 'Missing bounds'};$x=[int](($m.Groups[1].Value -as [int])+($m.Groups[3].Value -as [int]))/2;$y=[int](($m.Groups[2].Value -as [int])+($m.Groups[4].Value -as [int]))/2;A @('shell','input','tap',[string][int]$x,[string][int]$y)|Out-Null}
Check 'owned-emulator' ((A @('shell','getprop','ro.hardware')) -in @('ranchu','goldfish'))
Check 'android16-api36' ((A @('shell','getprop','ro.build.version.sdk')) -eq '36')
$base=(A @('shell','pm','path','cc.huevia')) -replace '^package:',''
Check 'installed-frozen158' (((A @('shell','sha256sum',$base)) -split '\s+')[0] -eq '31a5be2a9818fa1b859753d702078ec0a13d8971a274b08d5446c538f8767971')
$appProcessId=A @('shell','pidof','cc.huevia')
$ui=ReadUi '158-main'
TapNode $ui '相册'
$ui=ReadUi '158-album'
for($i=1;$i -le 2;$i++){
    TapNode $ui '相册更多操作'
    $menu=ReadUi ('158-menu-'+$i)
    TapNode $menu 'RAW 显影'
    $deadline=(Get-Date).AddSeconds(10)
    do{$top=(A @('shell','dumpsys','activity','activities')) -split "`r?`n"|Where-Object{$_ -match 'topResumedActivity='}|Select-Object -First 1;if($top -match 'documentsui.*PickActivity'){break};Start-Sleep -Milliseconds 200}while((Get-Date) -lt $deadline)
    Check ('real-menu-opens-system-picker-'+$i) ($top -match 'documentsui.*PickActivity')
    Check ('raw-launch-keeps-app-process-'+$i) ((A @('shell','pidof','cc.huevia')) -eq $appProcessId)
    A @('shell','input','keyevent','KEYCODE_BACK')|Out-Null
    $ui=ReadUi ('158-raw-after-cancel-'+$i)
    Check ('cancel-returns-to-raw-'+$i) ([bool]($ui.SelectNodes('//node')|Where-Object{$_.text -eq 'RAW 显影'}))
    Check ('empty-export-disabled-'+$i) ([bool]($ui.SelectNodes('//node')|Where-Object{$_.text -eq '保存 PNG' -and $_.enabled -eq 'false'}))
    if($i -eq 1){A @('shell','screencap','-p','/sdcard/raw158-entry.png')|Out-Null;A @('pull','/sdcard/raw158-entry.png',(Join-Path $destination '158-raw-after-cancel.png'))|Out-Null}
    A @('shell','input','keyevent','KEYCODE_BACK')|Out-Null
    $ui=ReadUi ('158-album-return-'+$i)
    Check ('back-returns-to-album-'+$i) ([bool]($ui.SelectNodes('//node')|Where-Object{$_.'content-desc' -eq '相册更多操作'}))
}
$crash=A @('logcat','-b','crash','--pid',$appProcessId,'-d','AndroidRuntime:E','*:S')
[IO.File]::WriteAllText((Join-Path $destination '158-current-process-crash.txt'),$crash,[Text.UTF8Encoding]::new($false))
Check 'no-fatal-exception-in-current-process' (-not $crash.Contains('FATAL EXCEPTION'))
$proof=[ordered]@{pass=$true;at=[DateTimeOffset]::Now.ToString('o');serial='emulator-5586';release=(A @('shell','getprop','ro.build.version.release'));sdk=36;fingerprint=(A @('shell','getprop','ro.build.fingerprint'));apkSha256='31a5be2a9818fa1b859753d702078ec0a13d8971a274b08d5446c538f8767971';processId=$appProcessId;checks=$checks;scope='Actual MainActivity album menu, real system DocumentsUI, cancel, RAW workspace and back navigation twice; no injected picker or reflection'}
[IO.File]::WriteAllText((Join-Path $destination 'manual-entry.json'),($proof|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
A @('shell','am','force-stop','cc.huevia')|Out-Null
A @('shell','rm','-f','/sdcard/raw158-window.xml','/sdcard/raw158-entry.png')|Out-Null
Write-Output ('PASS '+$checks.Count+' real-menu Android16 checks')
