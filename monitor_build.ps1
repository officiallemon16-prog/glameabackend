$log = "C:\Users\hp\Desktop\GLAMEA\android_setup.log"
while ($true) {
  Clear-Host
  Write-Host "=============================================================" -ForegroundColor Cyan
  Write-Host "   GLAMEA ANDROID BUILD - LIVE MONITOR (polling every 3s)" -ForegroundColor Cyan
  Write-Host "   Ctrl+C to close. Reopen: powershell -File $PSCommandPath" -ForegroundColor Gray
  Write-Host "=============================================================" -ForegroundColor Cyan
  Write-Host ""
  Get-Content -Path $log -Tail 22 -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
}
