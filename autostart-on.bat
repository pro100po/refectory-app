@echo off
setlocal
set "REFECTORY_AUTOSTART_ROOT=%~dp0"
powershell -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; try { $startup=[Environment]::GetFolderPath('Startup'); $target=Join-Path $env:REFECTORY_AUTOSTART_ROOT 'watch.bat'; if(!(Test-Path -LiteralPath $target)){throw 'watch.bat not found'}; $q=[char]34; $line='CreateObject('+$q+'WScript.Shell'+$q+').Run Chr(34) & '+$q+$target+$q+' & Chr(34), 1, False'; Set-Content -LiteralPath (Join-Path $startup 'refectory-codex-monitor.vbs') -Value $line -Encoding Unicode; $old=Join-Path $startup 'claude-gpt-watcher.vbs'; if(Test-Path -LiteralPath $old){Remove-Item -LiteralPath $old}; Write-Host 'Codex monitor autostart enabled. No executors started.' } catch { Write-Error $_; exit 1 }"
if errorlevel 1 echo Autostart setup failed.
pause
endlocal
