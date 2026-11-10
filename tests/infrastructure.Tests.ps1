[CmdletBinding()]
param([string]$TestRoot=(Join-Path ([IO.Path]::GetTempPath()) ('refectory-infra-'+[guid]::NewGuid().ToString('N'))),[ValidateSet('All','Remaining','ArchiveRetry')][string]$Section='All')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$src=Split-Path $PSScriptRoot -Parent
$utf8=[Text.UTF8Encoding]::new($false);$script:passed=0
function Assert($Condition,$Message){if(!$Condition){throw "ASSERT: $Message"};$script:passed++}
function Put($p,$text){[void][IO.Directory]::CreateDirectory((Split-Path $p -Parent));[IO.File]::WriteAllText($p,$text,$utf8)}
function N($exe,[string[]]$a,$cwd){$si=[Diagnostics.ProcessStartInfo]::new();$si.FileName=$exe;$si.WorkingDirectory=$cwd;$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true;$si.StandardOutputEncoding=$utf8;$si.StandardErrorEncoding=$utf8;foreach($v in $a){$si.ArgumentList.Add($v)};$p=[Diagnostics.Process]::new();$p.StartInfo=$si;[void]$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();$p.WaitForExit();@{code=$p.ExitCode;out=$o.GetAwaiter().GetResult();err=$e.GetAwaiter().GetResult()}}
function Git([string[]]$a,[switch]$Fail){$r=N git (@('-C',$script:repo)+$a) $script:repo;if($r.code -ne 0 -and !$Fail){throw "git: $($r.err)"};$r}
function W([hashtable]$p,[switch]$Fail){$p.Repo=$script:repo;$r=& $script:watch @p 2>&1;$ok=$?;if($LASTEXITCODE -ne 0 -and !$ok){$ok=$false};if(!$ok -and !$Fail){throw "workflow: $r"};if($Fail){Assert (!$ok) "Expected failure: $($p.Command)"};$r}
# Invoke watch in independent pwsh: exit 1 must not exit this test process.
function Invoke-TestCli([string[]]$a,[switch]$Fail){$r=N (Get-Command pwsh).Source (@('-NoProfile','-File',$script:watch,'-Repo',$script:repo)+$a) $script:repo;if($Fail){Assert ($r.code -ne 0) "Expected rejection: $a"}elseif($r.code -ne 0){throw "workflow: $($r.out) $($r.err)"};$r}
function State($id){Get-Content -LiteralPath (Join-Path $script:repo ".codex-runs/$id/state.json") -Raw|ConvertFrom-Json -AsHashtable}
function Wait-Run($id){$until=[datetime]::UtcNow.AddSeconds(35);do{$s=State $id;if($s.status -notin @('starting','running')){return $s};if([datetime]::UtcNow -gt $until){throw "Worker timeout $id"};Start-Sleep -Milliseconds 150}while($true)}
function Fresh($name){
 $script:repo=Join-Path $TestRoot "$name русский пробел";[void][IO.Directory]::CreateDirectory($script:repo)
 foreach($f in @('watch.ps1','.gitignore','scripts/Workflow.psm1','scripts/cli-adapter.ps1')){$dest=Join-Path $script:repo $f;[void][IO.Directory]::CreateDirectory((Split-Path $dest -Parent));Copy-Item -LiteralPath (Join-Path $src $f) -Destination $dest}
 $script:watch=Join-Path $script:repo 'watch.ps1'
 [void](Git @('init','-b','main'));[void](Git @('config','user.name','Fixture'));[void](Git @('config','user.email','fixture@example.invalid'));[void](Git @('config','core.autocrlf','false'))
 Put (Join-Path $script:repo 'a.txt') 'baseline';Put (Join-Path $script:repo 'index.html') '<style>@font-face{src:url(fonts/test.woff2)}</style>fixture'
 Put (Join-Path $script:repo 'versions/list.txt') "2026-11-09_1621`tСтарая версия`n";Put (Join-Path $script:repo 'versions/2026-11-09_1621.html') 'old immutable archive';Put (Join-Path $script:repo 'versions.html') '<p>old history</p>'
 [void](Git @('add','--','watch.ps1','.gitignore','scripts','a.txt','index.html','versions','versions.html'));[void](Git @('commit','-m','fixture baseline'))
 $remote=Join-Path $TestRoot "$name remote.git";$r=N git @('init','--bare',$remote) $TestRoot;if($r.code){throw $r.err};[void](Git @('remote','add','origin',$remote));[void](Git @('push','-u','origin','main'))
 $script:task=Join-Path $TestRoot "$name task.md";Put $script:task "# Проверка $name`nНе меняй постороннее."
 $script:evidence=Join-Path $TestRoot "$name evidence.md";Put $script:evidence 'Проверено независимым тестом. Решение: принять.'
 $script:remote=$remote
}
function Run($fake,$extra=@()){$r=Invoke-TestCli (@('-Command','run','-TaskFile',$script:task,'-Files','a.txt','-TestMode','-TestCli',$fake)+$extra);$id=$r.out.Trim();Assert ($id -match '^\d{8}T\d{9}Z-[a-f0-9]{8}$') "Run ID output: $id";$id}
function Review($id){[void](Invoke-TestCli @('-Command','review','-Id',$id,'-Evidence',$script:evidence))}
function Accept($id){Review $id;[void](Invoke-TestCli @('-Command','accept-step','-Id',$id,'-Message','Принят fixture шаг'))}
function Manual([string]$file='a.txt'){$head=(Git @('rev-parse','HEAD')).out.Trim();(Invoke-TestCli @('-Command','manual','-TaskFile',$script:task,'-Files',$file,'-Baseline',$head)).out.Trim()}
[void][IO.Directory]::CreateDirectory($TestRoot)
$fake=Join-Path $TestRoot 'fake Invoke-TestCli русский.ps1'
Put $fake @'
$ErrorActionPreference='Stop'
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
$argv=$args;$repo=$argv[[array]::IndexOf($argv,'-C')+1];$report=$argv[[array]::IndexOf($argv,'--output-last-message')+1]
$prompt=[Console]::In.ReadToEnd()
if(!$prompt.Contains('исполнитель')){throw 'UTF8 prompt lost'}
if(Test-Path (Join-Path $repo '.codex-runs/sleep')){Start-Sleep -Seconds 20}
if(!(Test-Path (Join-Path $repo '.codex-runs/nochange'))){[IO.File]::WriteAllText((Join-Path $repo 'a.txt'),'работа русского исполнителя')}
if(Test-Path (Join-Path $repo '.codex-runs/outside')){[IO.File]::WriteAllText((Join-Path $repo 'foreign.txt'),'чужое')}
[IO.File]::WriteAllText($report,'Проверка завершена; отчёт UTF8.')
'{"type":"thread.started","thread_id":"fixture"}'
'{"type":"item.completed","item":{"type":"agent_message","text":"готово"}}'
if(Test-Path (Join-Path $repo '.codex-runs/fail')){[Console]::Error.WriteLine('fixture stderr ошибка');exit 7}
'{"type":"turn.completed"}'
exit 0
'@
$shim=Join-Path $TestRoot 'fake shim русский.cmd'
Put $shim ('@echo off'+"`r`n"+'"'+(Get-Command pwsh).Source+'" -NoProfile -File "'+$fake+'" %*'+"`r`n"+'exit /b %errorlevel%'+"`r`n")
try {
 if($Section -eq 'All'){
 Fresh 'one'
 Write-Output 'STAGE: routing, real background CLI, review, local acceptance'
 $before=(Git @('rev-parse','HEAD')).out
 [void](Invoke-TestCli @('-Command','status'));Assert ((Git @('rev-parse','HEAD')).out -eq $before) 'status never commits'
 foreach($pair in @(@('banana','medium'),@('luna','high'),@('sol','ultra'),@('astra','max'))){[void](Invoke-TestCli @('-Command','run','-TaskFile',$task,'-Files','a.txt','-Model',$pair[0],'-Effort',$pair[1],'-TestMode','-TestCli',$fake) -Fail);Assert (!(Test-Path (Join-Path $repo '.codex-runs/active.json'))) 'invalid route no stale lock'}
 foreach($bad in @('../escape','C:/outside','./a.txt','.git/config','.codex-runs/x')){[void](Invoke-TestCli @('-Command','run','-TaskFile',$task,'-Files',$bad,'-TestMode','-TestCli',$fake) -Fail)}
 Assert (!(Test-Path (Join-Path $repo '.codex-runs/active.json'))) 'invalid paths no stale lock'
 $op=[IO.File]::Open((Join-Path $repo '.codex-runs/operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 try{[void](Invoke-TestCli @('-Command','run','-TaskFile',$task,'-Files','a.txt','-TestMode','-TestCli',$fake) -Fail)}finally{$op.Dispose()}
 Assert (!(Test-Path (Join-Path $repo '.codex-runs/active.json'))) 'operation lock refusal creates no active owner'
 $id=Run $shim;$s=Wait-Run $id;Assert ($s.status -eq 'awaiting-review') "shim succeeded: $($s.error)"
 Assert ($s.exitCode -eq 0) 'zero exit captured';Assert ((Get-Content (Join-Path $repo ".codex-runs/$id/report.md") -Raw).Contains('UTF8')) 'report Russian text'
 Assert ((Get-FileHash (Join-Path $repo ".codex-runs/$id/task.md")).Hash -eq (Get-FileHash $task).Hash) 'immutable independent task copy'
 Assert ((Get-Content (Join-Path $repo ".codex-runs/$id/events.jsonl") -Raw).Contains('item.completed')) 'real Invoke-TestCli event recorded'
 Assert ((Git @('rev-parse','HEAD')).out -eq $before) 'executor never commits'
 [void](Invoke-TestCli @('-Command','run','-TaskFile',$task,'-Files','a.txt','-TestMode','-TestCli',$fake) -Fail)
 [void](Invoke-TestCli @('-Command','monitor','-Once'));Review $id
 [void](Invoke-TestCli @('-Command','record-stage','-Stage','Проверка fixture','-StageAction','start','-Message','Начало проверки'))
 [void](Invoke-TestCli @('-Command','record-stage','-Stage','Проверка fixture','-StageAction','end','-Message','Проверки пройдены'))
 $monitor=Invoke-TestCli @('-Command','monitor','-Once');Assert ($monitor.out.Contains('Проверки пройдены') -and $monitor.out.Contains('Завершён')) 'readable registered stages in monitor'
 Put (Join-Path $repo 'a.txt') 'changed after review';[void](Invoke-TestCli @('-Command','accept-step','-Id',$id,'-Message','must fail') -Fail)
 Review $id;[void](Invoke-TestCli @('-Command','accept-step','-Id',$id,'-Message','Шаг принят'));$s=State $id
 Assert ($s.status -eq 'accepted' -and $s.commit) 'scoped commit accepted';Assert (!$s.pushed) 'local acceptance no push';Assert (!(Test-Path (Join-Path $repo '.codex-runs/active.json'))) 'accept releases lock'
 Assert ((Git @('ls-remote','origin','refs/heads/main')).out.Split("`t")[0] -ne $s.commit) 'intermediate commit absent remote'
 [void](Invoke-TestCli @('-Command','publish','-CompleteItem','-Message','Инфраструктура','-TestMode','-TestSkipDeployment'))
 $p=Get-Content (Join-Path $repo '.codex-runs/publication.json') -Raw|ConvertFrom-Json -AsHashtable;Assert ($p.pushed -and !$p.deployed -and $p.deployStatus -eq 'skipped-test') 'push truthful deployment skipped'
 Assert (@(Get-ChildItem (Join-Path $repo 'versions') -Filter '*.html').Count -eq 1) 'infra publication creates no release'
 [void](Invoke-TestCli @('-Command','publish','-CompleteItem','-TestMode','-TestSkipDeployment'))
 $status=Join-Path $TestRoot 'status source.md';Put $status '# Состояние проекта: цель, завершено, проверки, текущий шаг, вопросы, далее, дата, ссылки.'
 $branchBefore=(Git @('branch','--show-current')).out;$indexBefore=(Git @('write-tree')).out
 [void](Invoke-TestCli @('-Command','update-status','-StatusFile',$status));[void](Invoke-TestCli @('-Command','update-status','-StatusFile',$status))
 Assert ((Git @('branch','--show-current')).out -eq $branchBefore) 'status branch update no checkout';Assert ((Git @('write-tree')).out -eq $indexBefore) 'status update preserves index'
 [void](Git @('fetch','origin','project-status'));Assert ((Git @('ls-tree','--name-only','FETCH_HEAD')).out.Trim() -eq 'PROJECT_STATUS.md') 'status branch only intended file'
 Put (Join-Path $repo '.codex-runs/nochange') '1';$id=Run $fake;$s=Wait-Run $id;Accept $id;Assert ((State $id).status -eq 'accepted-no-changes') 'read only smoke closes truthfully'
 Remove-Item (Join-Path $repo '.codex-runs/nochange');Put (Join-Path $repo '.codex-runs/fail') '1';$id=Run $fake;$s=Wait-Run $id;Assert ($s.status -eq 'failed' -and $s.exitCode -eq 7) 'nonzero exit is failure, not done';Assert ((Get-Content (Join-Path $repo ".codex-runs/$id/stderr.log") -Raw).Contains('ошибка')) 'stderr captured'
 [void](Invoke-TestCli @('-Command','reject','-Id',$id));Assert ((Get-Content (Join-Path $repo 'a.txt') -Raw).Contains('исполнителя')) 'reject preserves changes'
 [void](Git @('restore','--','a.txt'));Remove-Item (Join-Path $repo '.codex-runs/fail')
 Put (Join-Path $repo '.codex-runs/outside') '1';$id=Run $fake;$s=Wait-Run $id;Assert ($s.status -eq 'failed') 'out of scope worker fails';[void](Invoke-TestCli @('-Command','review','-Id',$id,'-Evidence',$evidence) -Fail);[void](Invoke-TestCli @('-Command','reject','-Id',$id));Assert (Test-Path (Join-Path $repo 'foreign.txt')) 'foreign file not deleted'
 [void](Git @('restore','--','a.txt'));Remove-Item (Join-Path $repo 'foreign.txt');Remove-Item (Join-Path $repo '.codex-runs/outside')
 Put (Join-Path $repo 'a.txt') 'manual work';$id=Manual;Assert ((State $id).kind -eq 'manual') 'manual adoption honest';Review $id
 Put (Join-Path $repo 'foreign.txt') 'untracked';[void](Invoke-TestCli @('-Command','accept-step','-Id',$id,'-Message','fail') -Fail);Remove-Item (Join-Path $repo 'foreign.txt')
 [void](Git @('add','--','a.txt'));[void](Invoke-TestCli @('-Command','review','-Id',$id,'-Evidence',$evidence) -Fail);[void](Git @('restore','--staged','--','a.txt'))
 Accept $id
 }
 if($Section -ne 'ArchiveRetry'){
 Fresh 'concurrency'
 Write-Output 'STAGE: locks, monitor independence, cancellation and safe rerun'
 Put (Join-Path $repo '.codex-runs/sleep') '1';$id=Run $fake
 [void](Invoke-TestCli @('-Command','run','-TaskFile',$task,'-Files','a.txt','-TestMode','-TestCli',$fake) -Fail)
 $mon=N (Get-Command pwsh).Source @('-NoProfile','-File',$watch,'-Repo',$repo,'-Command','monitor','-Once') $repo;Assert ($mon.code -eq 0) 'monitor independent while running'
 [void](Invoke-TestCli @('-Command','recover') -Fail)
 $s=Wait-Run $id;Accept $id;Remove-Item (Join-Path $repo '.codex-runs/sleep')
 Put (Join-Path $repo '.codex-runs/sleep') '1';$id=Run $fake
 $until=[datetime]::UtcNow.AddSeconds(10);do{$s=State $id;if($s.ContainsKey('cliPid')){break};Start-Sleep -Milliseconds 100}while([datetime]::UtcNow -lt $until)
 # Stop the whole fixture process tree, matching explicit operator cancellation.
 [void](N 'taskkill.exe' @('/PID',[string]$s.pid,'/T','/F') $repo);Start-Sleep -Milliseconds 250
 [void](Invoke-TestCli @('-Command','recover'));Assert ((State $id).status -eq 'interrupted') 'dead runner recovered as interrupted'
 [void](Invoke-TestCli @('-Command','reject','-Id',$id) -Fail)
 [void](Invoke-TestCli @('-Command','reject','-Id',$id,'-Evidence',$evidence));Remove-Item (Join-Path $repo '.codex-runs/sleep')
 $old=$id;$oldTaskHash=(Get-FileHash (Join-Path $repo ".codex-runs/$old/task.md")).Hash
 Put (Join-Path $repo 'a.txt') 'Правки сохранены для повтора';Put (Join-Path $repo '.codex-runs/nochange') '1';Put $task '# Уточнённое задание для повтора'
 $id=(Invoke-TestCli @('-Command','rerun','-Id',$old,'-TaskFile',$task,'-Files','a.txt','-Evidence',$evidence,'-TestMode','-TestCli',$fake)).out.Trim();$s=Wait-Run $id
 Assert ($s.status -eq 'awaiting-review' -and $s.previous -eq $old) 'rerun completed with new ID and linked history'
 Assert ((State $old).status -eq 'superseded') 'old run honestly superseded';Assert ((Get-FileHash (Join-Path $repo ".codex-runs/$old/task.md")).Hash -eq $oldTaskHash) 'rerun keeps old task immutable'
 Assert ((Get-Content (Join-Path $repo 'a.txt') -Raw) -eq 'Правки сохранены для повтора') 'rerun preserves existing work';Accept $id
 Fresh 'drift'
 Put (Join-Path $repo 'a.txt') 'manual';$id=Manual
 [void](Git @('commit','--allow-empty','-m','foreign drift'));[void](Invoke-TestCli @('-Command','review','-Id',$id,'-Evidence',$evidence) -Fail);[void](Invoke-TestCli @('-Command','reject','-Id',$id))
 [void](Git @('restore','--','a.txt'));[void](Invoke-TestCli @('-Command','publish','-CompleteItem','-TestMode','-TestSkipDeployment') -Fail)
 Fresh 'commitfailure'
 Put (Join-Path $repo 'a.txt') 'manual';$id=Manual;Review $id
 $hook=Join-Path $repo '.git/hooks/pre-commit';Put $hook "#!/bin/sh`nexit 1`n"
 [void](Invoke-TestCli @('-Command','accept-step','-Id',$id,'-Message','hook fail') -Fail);$s=State $id;Assert (!$s.commit -and $s.status -eq 'reviewed' -and $s.error) 'failed commit never marked accepted'
 Remove-Item $hook;[void](Git @('restore','--staged','--','a.txt'));Accept $id
 Fresh 'publication'
 Write-Output 'STAGE: archive publication, push failure and idempotent retry'
 $oldHash=(Get-FileHash (Join-Path $repo 'versions/2026-11-09_1621.html')).Hash
 Put (Join-Path $repo 'index.html') '<style>src:url(fonts/new.woff2)</style>new';$id=Manual 'index.html';Accept $id
 Put (Join-Path $remote 'hooks/pre-receive') "#!/bin/sh`nexit 1`n"
 [void](Invoke-TestCli @('-Command','publish','-CompleteItem','-Message','Новая версия','-TestMode','-TestSkipDeployment') -Fail)
 $p=Get-Content (Join-Path $repo '.codex-runs/publication.json') -Raw|ConvertFrom-Json -AsHashtable;Assert (!$p.pushed -and $p.phase -eq 'archive-committed') 'push failure truthful'
 $archiveCount=@(Get-ChildItem (Join-Path $repo 'versions') -Filter '*.html').Count;Assert ($archiveCount -eq 2) 'single new archive';$archiveCommit=(Git @('rev-parse','HEAD')).out
 Remove-Item (Join-Path $remote 'hooks/pre-receive');[void](Invoke-TestCli @('-Command','publish','-CompleteItem','-Message','Повтор','-TestMode','-TestSkipDeployment'))
 Assert ((Git @('rev-parse','HEAD')).out -eq $archiveCommit) 'retry no duplicate commit';Assert (@(Get-ChildItem (Join-Path $repo 'versions') -Filter '*.html').Count -eq $archiveCount) 'retry no duplicate archive';Assert ((Get-FileHash (Join-Path $repo 'versions/2026-11-09_1621.html')).Hash -eq $oldHash) 'old archive immutable'
 $new=Get-ChildItem (Join-Path $repo 'versions') -Filter '*.html'|Where-Object Name -ne '2026-11-09_1621.html';Assert ((Get-Content $new.FullName -Raw).Contains('../fonts/')) 'new archive font paths corrected';Assert ((Get-Content (Join-Path $repo 'versions.html') -Raw).Contains('blob/project-status/PROJECT_STATUS.md')) 'status link retained by generator'
 [void](Invoke-TestCli @('-Command','publish','-CompleteItem','-DeployTimeoutSeconds','0') -Fail)
 $p=Get-Content (Join-Path $repo '.codex-runs/publication.json') -Raw|ConvertFrom-Json -AsHashtable;Assert ($p.pushed -and !$p.deployed -and $p.error) 'missing GitHub deployment never false success'
 }
 Fresh 'archivecommitfailure'
 Put (Join-Path $repo 'index.html') 'new release fixture';$id=Manual 'index.html';Accept $id
 Put (Join-Path $repo '.git/hooks/pre-commit') "#!/bin/sh`nexit 1`n"
 [void](Invoke-TestCli @('-Command','publish','-CompleteItem','-Message','Версия','-TestMode','-TestSkipDeployment') -Fail)
 $p=Get-Content (Join-Path $repo '.codex-runs/publication.json') -Raw|ConvertFrom-Json -AsHashtable;Assert ($p.phase -eq 'archive-created' -and !$p.pushed) 'archive commit failure keeps truthful resumable phase'
 Remove-Item (Join-Path $repo '.git/hooks/pre-commit');[void](Invoke-TestCli @('-Command','publish','-CompleteItem','-Message','Версия','-TestMode','-TestSkipDeployment'))
 Assert (@(Get-ChildItem (Join-Path $repo 'versions') -Filter '*.html').Count -eq 2) 'retry failed archive commit creates no duplicate'
 Write-Output "PASS: $script:passed assertions; fixture root: $TestRoot"
}catch{Write-Error "FAILED after $script:passed assertions. Fixtures retained: $TestRoot`n$_`n$($_.ScriptStackTrace)" -ErrorAction Continue;exit 1}
