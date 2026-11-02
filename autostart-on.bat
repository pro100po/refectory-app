@echo off
set "VBS=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\claude-gpt-watcher.vbs"
> "%VBS%" echo CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File ""%~dp0watch.ps1""", 7, False
echo Avtozapusk vklyuchen. Nablyudatel budet startovat pri vhode v Windows (svernutym oknom).
pause
