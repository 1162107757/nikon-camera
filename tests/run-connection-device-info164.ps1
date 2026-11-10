param([string]$JdkRoot='D:/dev/Java/jdk-17.0.19',[string]$AndroidJar='D:/dev/android-sdk/platforms/android-35/android.jar')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$java=Join-Path $root 'app/src/main/java/cc/huevia';$out=Join-Path $PSScriptRoot '.build/connection-device-info164'
New-Item -ItemType Directory -Force -Path $out|Out-Null
$sources=@(Get-ChildItem -LiteralPath (Join-Path $java 'ptp') -Filter '*.java'|ForEach-Object FullName)
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $java 'ncp') -Filter '*.java'|ForEach-Object FullName)
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $java 'picturecontrol') -Filter '*.java'|ForEach-Object FullName)
foreach($name in @('UsbProbe','StorageAssessment','PtpDirectorySurvey','NcpTransferSession','PtpUsbTransport','PictureControlReadSession','UsbPictureControlProbe','PictureControlImportSession','PictureControlDeleteSession','UsbPictureControlImport','PresetImportOptions','WirelessPictureControl')){$sources+=Join-Path $java ('usb/'+$name+'.java')}
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $java 'usb') -Filter 'CameraParameter*.java'|ForEach-Object FullName)
foreach($name in @('PhotoCameraClient','PtpIpClient','ConnectionTrace')){$sources+=Join-Path $java ('album/'+$name+'.java')}
foreach($name in @('PresetFile','LibraryJson')){$sources+=Join-Path $java ('library/'+$name+'.java')}
$sources+=Join-Path $PSScriptRoot 'stubs/cc/huevia/usb/UsbNcpTransfer.java'
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'android-stubs') -Recurse -Filter '*.java'|ForEach-Object FullName)
$sources+=Join-Path $PSScriptRoot 'connection-device-info-java/cc/huevia/usb/UsbDeviceInfo164Test.java'
& (Join-Path $JdkRoot 'bin/javac.exe') -J-Xmx256m --release 17 -encoding UTF-8 -cp $AndroidJar -d $out @sources
if($LASTEXITCODE -ne 0){throw 'Standard USB identification test compilation failed'}
& (Join-Path $JdkRoot 'bin/java.exe') -Xmx128m -cp ($out+[IO.Path]::PathSeparator+$AndroidJar) cc.huevia.usb.UsbDeviceInfo164Test
if($LASTEXITCODE -ne 0){throw 'Standard USB identification test failed'}
