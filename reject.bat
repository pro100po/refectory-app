@echo off
chcp 65001 >nul
echo Отклонение без удаления правок: pwsh -NoProfile -File "%~dp0watch.ps1" -Command reject -Id ^<ID^>
echo Автоматического отката нет. Сначала сохраните и разберите изменения с ведущим.
