$ErrorActionPreference = 'Stop'
$env:PATH = "C:\src\flutter\bin;$env:PATH"
$renderUrl = "https://glameabackend.onrender.com/api/v1"
Set-Location "C:\Users\hp\Desktop\GLAMEA\frontend"
if ($args.Count -eq 0) {
  & "C:\src\flutter\bin\flutter.bat" run --dart-define=API_BASE_URL=$renderUrl
} else {
  & "C:\src\flutter\bin\flutter.bat" run -d $args[0] --dart-define=API_BASE_URL=$renderUrl
}
