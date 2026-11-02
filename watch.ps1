# Watcher: runs GPT (Codex) and git on signal files written by Claude.
Set-Location $PSScriptRoot
$Host.UI.RawUI.WindowTitle = "Claude + GPT watcher"
Write-Host "Watcher started. Keep this window open while working with Claude."
while ($true) {
  if (Test-Path "go.flag") {
    Remove-Item "go.flag", "done.flag" -ErrorAction SilentlyContinue
    Write-Host "$(Get-Date -Format HH:mm:ss)  GPT is working on TASK.md ..."
    cmd /c 'codex exec -s workspace-write "Execute the task described in TASK.md. Follow the rules in AGENTS.md strictly." > codex-log.txt 2>&1'
    cmd /c 'git diff > review.diff'
    Set-Content "done.flag" "run"
    Write-Host "$(Get-Date -Format HH:mm:ss)  GPT finished."
  }
  if (Test-Path "accept.flag") {
    Remove-Item "accept.flag", "done.flag" -ErrorAction SilentlyContinue
    cmd /c 'git add -A > git-log.txt 2>&1 && git commit -F commit-msg.txt >> git-log.txt 2>&1'
    Set-Content "done.flag" "accept"
    Write-Host "$(Get-Date -Format HH:mm:ss)  Changes accepted (commit)."
  }
  if (Test-Path "reject.flag") {
    Remove-Item "reject.flag", "done.flag" -ErrorAction SilentlyContinue
    cmd /c 'git checkout -- . > git-log.txt 2>&1'
    Set-Content "done.flag" "reject"
    Write-Host "$(Get-Date -Format HH:mm:ss)  Changes rejected (restored)."
  }
  Start-Sleep -Seconds 3
}
