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
  if ($LASTEXITCODE -eq 0) { Write-Host "$(Get-Date -Format HH:mm:ss)  Опубликовано на GitHub." -ForegroundColor Green }
  else { Write-Host "$(Get-Date -Format HH:mm:ss)  ОШИБКА публикации на GitHub — см. git-log.txt" -ForegroundColor Red }
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
  Write-Host "$(Get-Date -Format HH:mm:ss)  Уведомление: $text" -ForegroundColor Cyan
}

function Do-Run {
  Remove-Item "go.flag", "done.flag" -ErrorAction SilentlyContinue
  $task = ([System.IO.File]::ReadAllLines((Join-Path $PSScriptRoot "TASK.md"), $utf8) | Where-Object { $_.Trim() } | Select-Object -First 1) -replace "^#+\s*",""
  Write-Host ""
  Write-Host "$(Get-Date -Format HH:mm:ss)  Claude дал задание GPT: $task" -ForegroundColor Yellow
  Write-Host "$(Get-Date -Format HH:mm:ss)  GPT работает..."
  cmd /c 'codex exec -s workspace-write "Execute the task described in TASK.md. Follow the rules in AGENTS.md strictly." > codex-log.txt 2>&1'
  cmd /c 'git diff > review.diff'
  Set-Content "done.flag" "run"
  Write-Host "$(Get-Date -Format HH:mm:ss)  GPT закончил. Claude проверяет правку..."
}

function Do-Accept {
  Remove-Item "accept.flag", "done.flag" -ErrorAction SilentlyContinue
  $msg1 = ([System.IO.File]::ReadAllLines((Join-Path $PSScriptRoot "commit-msg.txt"), $utf8))[0]
  Write-Host "$(Get-Date -Format HH:mm:ss)  Claude принял правку: $msg1" -ForegroundColor Green
  Set-Content "git-log.txt" "" -Encoding UTF8
  cmd /c 'git add -A >> git-log.txt 2>&1'
  $changed = cmd /c "git diff --cached --name-only"
  if ($changed -contains "index.html") {
    Archive-Version $msg1
    cmd /c 'git add versions versions.html >> git-log.txt 2>&1'
    Write-Host "$(Get-Date -Format HH:mm:ss)  Версия сохранена в историю."
  }
  cmd /c 'git commit -F commit-msg.txt >> git-log.txt 2>&1'
  if ($LASTEXITCODE -eq 0) { Push-Site }
  Set-Content "done.flag" "accept"
  Write-Host "$(Get-Date -Format HH:mm:ss)  Готово."
}

function Do-Reject {
  Remove-Item "reject.flag", "done.flag" -ErrorAction SilentlyContinue
  cmd /c 'git checkout -- . > git-log.txt 2>&1'
  Set-Content "done.flag" "reject"
  Write-Host "$(Get-Date -Format HH:mm:ss)  Claude отклонил правку — файл возвращён к прежней версии." -ForegroundColor Magenta
}

# ---------- Мост с облачной сессией Claude через GitHub ----------
# Облачный Claude кладёт в свою ветку claude/* файлы bridge/cmd.txt («<id> <команда>»), bridge/task.md, bridge/commit.txt.
# Команды: run — новое задание (index.html сначала возвращается к последней принятой версии),
#          rerun — повтор с замечаниями (правки GPT сохраняются), accept — принять, reject — отклонить.
# Наблюдатель раз в ~30 с проверяет ветки, выполняет новую команду и отвечает в ту же ветку:
# bridge/result/status.txt («<id> <итог>») и файлы результата. Рабочую папку при ответе не трогает.
$BridgeState = Join-Path $PSScriptRoot "bridge-state.txt"
$script:bridgeTick = 0

function Bridge-Log($text) {
  [System.IO.File]::AppendAllText((Join-Path $PSScriptRoot "bridge-log.txt"), "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $text`r`n", $utf8)
}

function Bridge-Done {
  if (-not (Test-Path $BridgeState)) { return $null }
  return [System.IO.File]::ReadAllLines($BridgeState, $utf8)
}

function Bridge-Mark($key) { [System.IO.File]::AppendAllText($BridgeState, "$key`r`n", $utf8) }

function Bridge-Reply($branch, $id, $status, $files) {
  $tmpIdx = Join-Path $env:TEMP "refectory-bridge-index"
  $tmpStatus = Join-Path $env:TEMP "refectory-bridge-status.txt"
  [System.IO.File]::WriteAllText($tmpStatus, "$id $status`n", $utf8)
  for ($try = 1; $try -le 3; $try++) {
    & git fetch -q origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" 2>$null
    $parent = (& git rev-parse "refs/remotes/origin/$branch" 2>$null)
    if (-not $parent) { Bridge-Log "ответ: ветка $branch не найдена"; return }
    Remove-Item $tmpIdx -ErrorAction SilentlyContinue
    $env:GIT_INDEX_FILE = $tmpIdx
    try {
      & git read-tree $parent
      & git rm -r -q --cached --ignore-unmatch bridge/result 2>$null | Out-Null
      $all = @(@{ src = $tmpStatus; dst = "bridge/result/status.txt" })
      foreach ($f in $files) { if (Test-Path $f) { $all += @{ src = (Join-Path $PSScriptRoot $f); dst = "bridge/result/$f" } } }
      foreach ($x in $all) {
        $blob = (& git hash-object -w --no-filters $x.src)
        & git update-index --add --cacheinfo "100644,$blob,$($x.dst)"
      }
      $tree = (& git write-tree)
    } finally { Remove-Item Env:\GIT_INDEX_FILE -ErrorAction SilentlyContinue }
    $commit = (& git commit-tree $tree -p $parent -m "bridge: $id $status")
    & git push -q origin "${commit}:refs/heads/$branch" 2>$null
    if ($LASTEXITCODE -eq 0) { Bridge-Log "ответ $id $status → $branch"; return }
    Start-Sleep -Seconds (2 * $try)
  }
  Bridge-Log "ОШИБКА: не удалось отправить ответ $id $status в $branch"
  Write-Host "$(Get-Date -Format HH:mm:ss)  ОШИБКА: ответ облаку не отправлен — см. bridge-log.txt" -ForegroundColor Red
}

function Bridge-Check {
  & git fetch -q --prune origin "+refs/heads/claude/*:refs/remotes/origin/claude/*" 2>$null
  if ($LASTEXITCODE -ne 0) { return }
  $refs = @(& git for-each-ref --format='%(refname:short)' refs/remotes/origin/claude/)
  $cmds = @()
  foreach ($ref in $refs) {
    $line = (& git show "${ref}:bridge/cmd.txt" 2>$null | Select-Object -First 1)
    if (-not $line) { continue }
    $p = $line.Trim().Split(" ")
    if ($p.Count -lt 2) { continue }
    $cmds += @{ ref = $ref; branch = $ref.Substring("origin/".Length); id = $p[0]; action = $p[1]; key = "$($ref.Substring('origin/'.Length)) $($p[0])" }
  }
  $done = Bridge-Done
  if ($null -eq $done) {
    # первый запуск моста: старые команды не выполняем
    Set-Content $BridgeState "" -Encoding UTF8
    foreach ($c in $cmds) { Bridge-Mark $c.key }
    return
  }
  foreach ($c in $cmds) {
    if ($done -contains $c.key) { continue }
    Bridge-Mark $c.key
    $ref = $c.ref
    Write-Host ""
    Write-Host "$(Get-Date -Format HH:mm:ss)  Облачный Claude: $($c.action) ($($c.id), $($c.branch))" -ForegroundColor Cyan
    Bridge-Log "команда $($c.key) $($c.action)"
    switch ($c.action) {
      { $_ -in "run", "rerun" } {
        if ($_ -eq "run") { cmd /c 'git checkout -- index.html >nul 2>&1' }
        cmd /c "git show ${ref}:bridge/task.md > TASK.md"
        if ((Get-Item "TASK.md").Length -eq 0) { Bridge-Reply $c.branch $c.id "error-no-task" @(); break }
        Do-Run
        Bridge-Reply $c.branch $c.id "done" @("index.html", "review.diff", "codex-log.txt")
      }
      "accept" {
        cmd /c "git show ${ref}:bridge/commit.txt > commit-msg.txt"
        cmd /c "git checkout $ref -- notes >nul 2>&1"   # заметки облачных сессий — в main
        Do-Accept
        Bridge-Reply $c.branch $c.id "accepted" @("git-log.txt")
      }
      "reject" {
        Do-Reject
        Bridge-Reply $c.branch $c.id "rejected" @()
      }
      default { Bridge-Reply $c.branch $c.id "error-unknown-command" @() }
    }
    return   # одна команда за проход
  }
}

Write-Host "Наблюдатель запущен. Не закрывайте это окно и не щёлкайте внутри него (иначе оно встанет на паузу)."

# Первый запуск: заводим историю версий с текущей версии приложения.
if (-not (Test-Path "versions\list.txt")) {
  Set-Content "git-log.txt" "" -Encoding UTF8
  Archive-Version "Исходная версия"
  $msg = "История версий: исходная версия`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`nClaude-Session: https://claude.ai/code/session_01DPNhGBEzvv9cX6aLb4yjvL`n"
  [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot "commit-msg.txt"), $msg, $utf8)
  cmd /c 'git add -A >> git-log.txt 2>&1 && git commit -F commit-msg.txt >> git-log.txt 2>&1'
  Push-Site
  Write-Host "$(Get-Date -Format HH:mm:ss)  История версий заведена."
}

while ($true) {
  if (Test-Path "notify.txt") {
    $t = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "notify.txt"), $utf8)
    Remove-Item "notify.txt" -ErrorAction SilentlyContinue
    Show-Note $t.Trim()
  }
  if (Test-Path "go.flag") { Do-Run }
  if (Test-Path "accept.flag") { Do-Accept }
  if (Test-Path "reject.flag") { Do-Reject }
  $script:bridgeTick++
  if ($script:bridgeTick -ge 10) {
    $script:bridgeTick = 0
    try { Bridge-Check } catch { Bridge-Log "ошибка моста: $_" }
  }
  Start-Sleep -Seconds 3
}
