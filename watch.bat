@echo off
chcp 65001 >nul
start "Монитор Codex — трапезная" pwsh -NoLogo -NoProfile -NoExit -File "%~dp0watch.ps1" -Command monitor
