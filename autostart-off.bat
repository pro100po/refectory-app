@echo off
setlocal
powershell -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; try { $startup=[Environment]::GetFolderPath('Startup'); foreach($name in @('refectory-codex-monitor.vbs','claude-gpt-watcher.vbs')){ $file=Join-Path $startup $name; if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file} }; Write-Host 'Codex monitor autostart disabled. Running processes unchanged.' } catch { Write-Error $_; exit 1 }"
if errorlevel 1 echo Autostart removal failed.
pause
endlocal
