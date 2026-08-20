$ErrorActionPreference = 'Stop'
$log = "C:\Users\hp\Desktop\GLAMEA\android_setup.log"
function Log($m) {
  $t = Get-Date -Format "HH:mm:ss"
  $line = "$t $m"
  for ($i = 0; $i -lt 8; $i++) {
    try { Add-Content -Path $log -Value $line; return }
    catch { Start-Sleep -Milliseconds 250 }
  }
}
Log "=== Android toolchain setup started ==="

$root = "C:\Android"
$jdkParent = "$root\jdk"
$sdkRoot = "$root\Sdk"
$cmdlineTools = "$sdkRoot\cmdline-tools"
$dl = "C:\Users\hp\Desktop\GLAMEA\downloads"
New-Item -ItemType Directory -Force -Path $root, $jdkParent, $sdkRoot, $dl | Out-Null

$env:PATH = "C:\src\flutter\bin;$env:PATH"

# ---- 1. Download JDK 17 (Adoptium API redirect) ----
$jdkZip = "$dl\jdk17.zip"
if (-not (Test-Path $jdkZip)) {
  Log "Downloading JDK 17 ..."
  $jdkUrl = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse"
  Invoke-WebRequest -Uri $jdkUrl -OutFile $jdkZip -UseBasicParsing -TimeoutSec 600
  Log "JDK downloaded: $((Get-Item $jdkZip).Length) bytes"
} else { Log "JDK zip already present" }

Log "Extracting JDK ..."
if (Test-Path "$jdkParent\jdk") { Remove-Item "$jdkParent\jdk" -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$jdkParent\jdk" | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($jdkZip, "$jdkParent\jdk")
$jdkHome = (Get-ChildItem "$jdkParent\jdk" -Directory | Select-Object -First 1).FullName
Log "JDK home: $jdkHome"
$env:JAVA_HOME = $jdkHome
try { [Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkHome, "User") } catch {}
Log "JAVA_HOME set"

# ---- 2. Download Android cmdline-tools ----
$ctZip = "$dl\cmdline-tools.zip"
if (-not (Test-Path $ctZip)) {
  Log "Downloading cmdline-tools ..."
  $ctUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
  Invoke-WebRequest -Uri $ctUrl -OutFile $ctZip -UseBasicParsing -TimeoutSec 600
  Log "cmdline-tools downloaded: $((Get-Item $ctZip).Length) bytes"
} else { Log "cmdline-tools zip already present" }

Log "Extracting cmdline-tools ..."
$ctTmp = "$dl\ct_extract"
if (Test-Path $ctTmp) { Remove-Item $ctTmp -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ctTmp | Out-Null
[System.IO.Compression.ZipFile]::ExtractToDirectory($ctZip, $ctTmp)
# sdkmanager expects <sdk>/cmdline-tools/latest/bin
if (Test-Path "$cmdlineTools\latest") { Remove-Item "$cmdlineTools\latest" -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$cmdlineTools\latest" | Out-Null
Copy-Item -Path "$ctTmp\cmdline-tools\*" -Destination "$cmdlineTools\latest" -Recurse -Force
Log "cmdline-tools placed at $cmdlineTools\latest"

# ---- 3. Set ANDROID_HOME + PATH (process + machine) ----
$env:ANDROID_HOME = $sdkRoot
try { [Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdkRoot, "User") } catch {}
$currPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($currPath -notlike "*$sdkRoot*") {
  try { [Environment]::SetEnvironmentVariable("PATH", "$currPath;$sdkRoot\platform-tools;$cmdlineTools\latest\bin", "User") } catch {}
}
$env:PATH = "$sdkRoot\platform-tools;$cmdlineTools\latest\bin;$env:PATH"
Log "ANDROID_HOME set to $sdkRoot"

# ---- 4. Accept licenses + install SDK packages ----
$sdkmanager = "$cmdlineTools\latest\bin\sdkmanager.bat"
Log "Accepting SDK licenses ..."
(1..100 | ForEach-Object { 'y' }) | & $sdkmanager --licenses 2>&1 | ForEach-Object { Log "lic: $_" }
Log "Installing SDK packages (this downloads a lot) ..."
& $sdkmanager --install "platform-tools" "platforms;android-35" "build-tools;35.0.0" "platforms;android-34" "build-tools;34.0.0" "ndk;28.2.13676358" 2>&1 | ForEach-Object { Log "sdk: $_" }
Log "SDK packages installed"

# ---- 5. Flutter config + build ----
Set-Location "C:\Users\hp\Desktop\GLAMEA\frontend"
Log "flutter config --android-sdk"
& "C:\src\flutter\bin\flutter.bat" config --android-sdk "$sdkRoot" 2>&1 | ForEach-Object { Log "cfg: $_" }
$renderUrl = "https://glameabackend.onrender.com/api/v1"
$apk = "C:\Users\hp\Desktop\GLAMEA\frontend\build\app\outputs\flutter-apk\app-debug.apk"
$built = $false
$ErrorActionPreference = 'SilentlyContinue'
for ($t = 1; $t -le 3; $t++) {
  Log "flutter build apk attempt $t (Render: $renderUrl) ..."
  & "C:\src\flutter\bin\flutter.bat" build apk --debug --dart-define=API_BASE_URL=$renderUrl *> "C:\Users\hp\Desktop\GLAMEA\flutter_build.log"
  Log "build attempt $t exited with code $LASTEXITCODE"
  if (Test-Path $apk) { $built = $true; break }
  Log "attempt $t failed; retrying in 15s"
  Start-Sleep -Seconds 15
}
$ErrorActionPreference = 'Stop'
Log "=== BUILD STEP DONE (built=$built) ==="
if (Test-Path $apk) { Log "APK EXISTS: $apk ($([math]::Round((Get-Item $apk).Length/1MB,1)) MB)" } else { Log "APK NOT FOUND - see flutter_build.log" }
