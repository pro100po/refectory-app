@echo off
chcp 65001 >nul
cd /d "%~dp0"
git add -A
git commit -F commit-msg.txt
echo.
echo Pravka prinyata i sohranena.
pause
