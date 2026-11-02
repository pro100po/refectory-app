@echo off
chcp 65001 >nul
cd /d "%~dp0"
git checkout -- .
echo.
echo Pravki GPT otmeneny, fayl vozvrashchen k proshloy versii.
pause
