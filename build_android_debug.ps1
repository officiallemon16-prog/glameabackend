$ErrorActionPreference = 'Stop'
$env:PATH = "C:\src\flutter\bin;$env:PATH"
$renderUrl = "https://glameabackend.onrender.com/api/v1"
Set-Location "C:\Users\hp\Desktop\GLAMEA\frontend"
& "C:\src\flutter\bin\flutter.bat" build apk --debug --dart-define=API_BASE_URL=$renderUrl
Write-Output ""
Write-Output "=========================================================="
Write-Output "Debug APK built for Render backend: $renderUrl"
Write-Output "Install on a connected phone / emulator with:"
Write-Output "  adb install build\app\outputs\flutter-apk\app-debug.apk"
Write-Output "=========================================================="
