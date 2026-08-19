@echo off
cd /d C:\Users\hp\Desktop\GLAMEA\frontend
set API_BASE_URL=http://192.168.1.3:8080/api/v1
C:\src\flutter\bin\flutter.bat run -d web-server --web-port=3001 --web-hostname=0.0.0.0 --dart-define=API_BASE_URL=%API_BASE_URL%
