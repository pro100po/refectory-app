@echo off
setlocal
chcp 65001 >nul
set "REFECTORY_MONITOR_ROOT=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; try { $exe=$null; $found=Get-Command pwsh.exe -ErrorAction SilentlyContinue; if($found){$exe=$found.Source}; if(!$exe){$standard=Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'; if(Test-Path -LiteralPath $standard){$exe=$standard}}; if(!$exe){foreach($package in @(Get-AppxPackage '*CodexPrimaryRuntime*' | Sort-Object Version -Descending)){$candidate=Join-Path $package.InstallLocation 'dependencies\native\powershell\pwsh.exe'; if(Test-Path -LiteralPath $candidate){$exe=$candidate; break}}}; if(!$exe){throw 'PowerShell 7 не найден. Откройте Codex для проверки установки.'}; $launchArgs=@('-NoLogo','-NoProfile','-File',(Join-Path $env:REFECTORY_MONITOR_ROOT 'watch.ps1'),'-Command','monitor'); if($env:REFECTORY_MONITOR_ONCE -eq '1'){$launchArgs+='-Once'}; & $exe @launchArgs; exit $LASTEXITCODE } catch { Write-Host $_ -ForegroundColor Red; exit 1 }"
if errorlevel 1 pause
endlocal
