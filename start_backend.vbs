Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "C:\Users\hp\Desktop\GLAMEA"
WshShell.Run "bin\api.exe", 0, False
