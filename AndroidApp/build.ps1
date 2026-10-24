# Copyright (C) CheshirCa 2026
# https://t.me/cheshircanest

$ErrorActionPreference = 'Stop'

$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$buildTools = Join-Path $sdk 'build-tools\36.1.0'
$androidJar = Join-Path $sdk 'platforms\android-34\android.jar'
$javaHome = 'C:\Program Files\Eclipse Adoptium\jdk-25.0.0.36-hotspot'
$aapt = Join-Path $buildTools 'aapt.exe'
$d8 = Join-Path $buildTools 'd8.bat'
$zipalign = Join-Path $buildTools 'zipalign.exe'
$apksigner = Join-Path $buildTools 'apksigner.bat'
$javac = Join-Path $javaHome 'bin\javac.exe'
$keytool = Join-Path $javaHome 'bin\keytool.exe'
$root = $PSScriptRoot
$temporary = Join-Path $env:TEMP 'wifi_android_kvm_apk_build'
$output = Join-Path $root 'WiFiAndroidKVM.apk'

foreach ($tool in @($aapt, $d8, $zipalign, $apksigner, $javac, $keytool, $androidJar)) {
  if (-not (Test-Path -LiteralPath $tool)) { throw "Отсутствует инструмент: $tool" }
}
if (-not (Test-Path -LiteralPath (Join-Path $root 'res\raw\wifi_android_kvm_agent'))) {
  throw 'Нет встроенного ARMv7-агента: res\raw\wifi_android_kvm_agent'
}

Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $temporary, (Join-Path $temporary 'gen'), (Join-Path $temporary 'classes'), (Join-Path $temporary 'dex') | Out-Null
$localAndroidJar = Join-Path $temporary 'android.jar'
Copy-Item -LiteralPath $androidJar -Destination $localAndroidJar

& $aapt package -f -m -J (Join-Path $temporary 'gen') -M (Join-Path $root 'AndroidManifest.xml') -S (Join-Path $root 'res') -I $localAndroidJar
if ($LASTEXITCODE -ne 0) { throw 'Ошибка генерации Android resources' }

$sources = @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -Filter '*.java' | ForEach-Object FullName)
$sources += Get-ChildItem -LiteralPath (Join-Path $temporary 'gen') -Recurse -Filter '*.java' | ForEach-Object FullName
& $javac -encoding UTF-8 -source 8 -target 8 -bootclasspath $localAndroidJar -d (Join-Path $temporary 'classes') $sources
if ($LASTEXITCODE -ne 0) { throw 'Ошибка компиляции Java' }

$classFiles = @(Get-ChildItem -LiteralPath (Join-Path $temporary 'classes') -Recurse -Filter '*.class' | ForEach-Object FullName)
if ($classFiles.Count -eq 0) { throw 'Java-компилятор не создал class-файлы' }
& $d8 --min-api 19 --lib $localAndroidJar --output (Join-Path $temporary 'dex') $classFiles
if ($LASTEXITCODE -ne 0) { throw 'Ошибка преобразования classes.dex' }

$unsigned = Join-Path $temporary 'unsigned.apk'
& $aapt package -f -M (Join-Path $root 'AndroidManifest.xml') -S (Join-Path $root 'res') -I $localAndroidJar -F $unsigned
if ($LASTEXITCODE -ne 0) { throw 'Ошибка упаковки ресурсов APK' }
Push-Location (Join-Path $temporary 'dex')
try { & $aapt add $unsigned classes.dex } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { throw 'Ошибка добавления classes.dex' }

$keystore = Join-Path $temporary 'debug.keystore'
& $keytool -genkeypair -keystore $keystore -storepass android -keypass android -alias wifiandroidkvm -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=WiFi Android KVM, OU=Local, O=Local, C=RU'
if ($LASTEXITCODE -ne 0) { throw 'Ошибка создания ключа подписи' }
$aligned = Join-Path $temporary 'aligned.apk'
& $zipalign -f -p 4 $unsigned $aligned
if ($LASTEXITCODE -ne 0) { throw 'Ошибка zipalign' }
& $apksigner sign --ks $keystore --ks-pass pass:android --key-pass pass:android --out $output --min-sdk-version 19 $aligned
if ($LASTEXITCODE -ne 0) { throw 'Ошибка подписи APK' }
& $apksigner verify --verbose --min-sdk-version 19 $output
if ($LASTEXITCODE -ne 0) { throw 'Проверка подписи APK не пройдена' }
Get-Item -LiteralPath $output | Format-List FullName,Length,LastWriteTime
