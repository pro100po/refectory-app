# Наблюдатель: запускает GPT (Codex) и git по сигнальным файлам от Claude.
# После принятой правки: коммит, копия приложения в versions/, обновление versions.html, отправка на GitHub.
Set-Location $PSScriptRoot
$Host.UI.RawUI.WindowTitle = "Claude + GPT watcher"
$utf8 = New-Object System.Text.UTF8Encoding $false

function Build-VersionsPage {
  $rows = @()
  if (Test-Path "versions\list.txt") {
    $lines = [System.IO.File]::ReadAllLines((Join-Path $PSScriptRoot "versions\list.txt"), $utf8)
    [array]::Reverse($lines)
    foreach ($line in $lines) {
      if (-not $line.Trim()) { continue }
      $p = $line.Split("`t")
      $stamp = $p[0]; $subj = [System.Net.WebUtility]::HtmlEncode($p[1])
      $d = $stamp.Substring(8,2) + "." + $stamp.Substring(5,2) + "." + $stamp.Substring(0,4) + " " + $stamp.Substring(11,2) + ":" + $stamp.Substring(13,2)
      $rows += "<tr><td class='d'>$d</td><td>$subj</td><td><a href='versions/$stamp.html' target='_blank'>открыть</a></td></tr>"
    }
  }
  $html = @"
<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Кухня трапезной — история версий</title>
<style>
:root{--bg:#faf8f4;--fg:#222;--mut:#777;--line:#e4dfd6;--acc:#8a5a2b}
@media (prefers-color-scheme:dark){:root{--bg:#1c1b19;--fg:#eee;--mut:#999;--line:#3a3833;--acc:#d9a46b}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,Segoe UI,sans-serif}
main{max-width:900px;margin:0 auto;padding:24px 16px}
h1{font-size:22px;margin:0 0 4px}p{color:var(--mut);margin:0 0 20px}
a{color:var(--acc)}table{width:100%;border-collapse:collapse}
td{padding:8px 6px;border-bottom:1px solid var(--line);vertical-align:top}
td.d{white-space:nowrap;color:var(--mut)}
</style></head><body><main>
<h1>Кухня трапезной — история версий</h1>
<p><a href="./">← Текущая версия</a> · новые сверху · каждая версия открывается как рабочее приложение</p>
<table>
$($rows -join "`n")
</table>
</main></body></html>
"@
  [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot "versions.html"), $html, $utf8)
}

function Archive-Version($subject) {
  if (-not (Test-Path "versions")) { New-Item -ItemType Directory "versions" | Out-Null }
  $stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
  Copy-Item "index.html" "versions\$stamp.html" -Force
  $line = "$stamp`t$subject`r`n"
  [System.IO.File]::AppendAllText((Join-Path $PSScriptRoot "versions\list.txt"), $line, $utf8)
  Build-VersionsPage
}

function Push-Site {
  cmd /c 'git push origin main >> git-log.txt 2>&1'
  if ($LASTEXITCODE -eq 0) { Write-Host "$(Get-Date -Format HH:mm:ss)  Published to GitHub." }
  else { Write-Host "$(Get-Date -Format HH:mm:ss)  PUSH FAILED - see git-log.txt" -ForegroundColor Red }
}

function Show-Note($text) {
  # всплывающее уведомление Windows (значок в трее)
  try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    if ($script:note) { $script:note.Dispose() }
    $script:note = New-Object System.Windows.Forms.NotifyIcon
    $script:note.Icon = [System.Drawing.SystemIcons]::Information
    $script:note.Text = "Claude + GPT"
    $script:note.Visible = $true
    $script:note.ShowBalloonTip(15000, "Claude + GPT", $text, [System.Windows.Forms.ToolTipIcon]::Info)
  } catch { Write-Host "Notification failed: $_" -ForegroundColor Yellow }
  Write-Host "$(Get-Date -Format HH:mm:ss)  NOTE: $text" -ForegroundColor Cyan
}

Write-Host "Watcher started. Keep this window open while working with Claude."

# Первый запуск: заводим историю версий с текущей версии приложения.
if (-not (Test-Path "versions\list.txt")) {
  Set-Content "git-log.txt" "" -Encoding UTF8
  Archive-Version "Исходная версия"
  $msg = "История версий: исходная версия`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`nClaude-Session: https://claude.ai/code/session_01DPNhGBEzvv9cX6aLb4yjvL`n"
  [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot "commit-msg.txt"), $msg, $utf8)
  cmd /c 'git add -A >> git-log.txt 2>&1 && git commit -F commit-msg.txt >> git-log.txt 2>&1'
  Push-Site
  Write-Host "$(Get-Date -Format HH:mm:ss)  Version history initialised."
}

while ($true) {
  if (Test-Path "notify.txt") {
    $t = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "notify.txt"), $utf8)
    Remove-Item "notify.txt" -ErrorAction SilentlyContinue
    Show-Note $t.Trim()
  }
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
    Set-Content "git-log.txt" "" -Encoding UTF8
    cmd /c 'git add -A >> git-log.txt 2>&1'
    $changed = cmd /c "git diff --cached --name-only"
    if ($changed -contains "index.html") {
      $subject = ([System.IO.File]::ReadAllLines((Join-Path $PSScriptRoot "commit-msg.txt"), $utf8))[0]
      Archive-Version $subject
      cmd /c 'git add versions versions.html >> git-log.txt 2>&1'
      Write-Host "$(Get-Date -Format HH:mm:ss)  Version saved to history."
    }
    cmd /c 'git commit -F commit-msg.txt >> git-log.txt 2>&1'
    if ($LASTEXITCODE -eq 0) { Push-Site }
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
