@echo off
chcp 65001 >nul
echo Запуск: pwsh -NoProfile -File "%~dp0watch.ps1" -Command run -TaskFile ^<файл^> -Files ^<точные файлы^> -Model sol -Effort medium
echo Используйте явные параметры PowerShell. TASK.md и старые флаги автоматически не читаются.
