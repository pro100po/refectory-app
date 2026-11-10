param([string]$Module=(Join-Path $PSScriptRoot '../scripts/Workflow.psm1'))
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
$Module=(Resolve-Path -LiteralPath $Module).Path;$utf8=[Text.UTF8Encoding]::new($false)
$root=Join-Path ([IO.Path]::GetTempPath()) ('monitor-events-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root);$process=$null
function Assert($ok,$msg){if(!$ok){throw $msg};"PASS: $msg"}
function Shared($path){$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));$reader=[IO.StreamReader]::new($stream);try{$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}}
function Output{if(Test-Path -LiteralPath $output){Shared $output}else{''}}
function Await($token){$deadline=[datetime]::UtcNow.AddSeconds(12);while(!(Output).Contains($token) -and [datetime]::UtcNow -lt $deadline){if($process.HasExited){throw "Monitor exited: $(Shared $errors)"};Start-Sleep -Milliseconds 50};Assert ((Output).Contains($token)) "observed: $token"}
function Stable($ms=800){$before=Output;Start-Sleep -Milliseconds $ms;Assert ((Output) -ceq $before) "unchanged output for ${ms}ms"}
function State($path,$event){$s=@{id=(Split-Path (Split-Path $path) -Leaf);kind='cli';task='Test';model='sol';effort='medium';status='running';started='2026-11-10T09:00:00Z';ended=$null;commit=$null;pushed=$false;deployed=$false;lastEvent=$event;error=$null};[IO.File]::WriteAllText($path,($s|ConvertTo-Json),$utf8)}
try{
 $repo=Join-Path $root 'repo';[void][IO.Directory]::CreateDirectory($repo);& git init --quiet $repo;if($LASTEXITCODE){throw 'git init'}
 [IO.File]::WriteAllText((Join-Path $repo '.gitignore'),"/.codex-runs/`n",$utf8);$runs=Join-Path $repo '.codex-runs';[void][IO.Directory]::CreateDirectory($runs)
 $output=Join-Path $root 'stdout.txt';$errors=Join-Path $root 'stderr.txt';$runner=Join-Path $root 'runner.ps1'
 [IO.File]::WriteAllText($runner,'param($Module,$Repo,[switch]$Once)'+"`n"+'$ErrorActionPreference="Stop";[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);Import-Module $Module -Force;Invoke-Workflow -Command monitor -Repo $Repo -Once:$Once',$utf8)
 $exe=(Get-Process -Id $PID).Path;$args=@('-NoProfile','-File',('"'+$runner+'"'),'-Module',('"'+$Module+'"'),'-Repo',('"'+$repo+'"'))
 $process=Start-Process $exe -ArgumentList $args -RedirectStandardOutput $output -RedirectStandardError $errors -PassThru -WindowStyle Hidden
 Await 'Монитор Codex';Await 'Запусков пока нет';Stable 2200
 [IO.File]::WriteAllText((Join-Path $runs 'noise.log'),'noise',$utf8);Stable
 $run=Join-Path $runs '20261110T090000000Z-12345678';[void][IO.Directory]::CreateDirectory($run);$state=Join-Path $run 'state.json';$temp=Join-Path $run 'new.tmp'
 State $temp 'created-observation';[IO.File]::Move($temp,$state);Await 'created-observation'
 [IO.File]::WriteAllText($state,[IO.File]::ReadAllText($state),$utf8);Stable 2200
 $data=Get-Content -Raw $state|ConvertFrom-Json -AsHashtable;$data.internalOnly='not displayed';[IO.File]::WriteAllText($state,($data|ConvertTo-Json),$utf8);Stable
 State $state 'changed-observation';Await 'changed-observation';State $temp 'atomic replacement';[IO.File]::Move($temp,$state,$true);Await 'atomic replacement'
 foreach($i in 1..5){State $state "burst $i";Start-Sleep -Milliseconds 20};Await 'burst 5';Stable
 $stage=Join-Path $runs 'stages.jsonl';$entries=@(@{time='2026-11-10T09:00:00Z';taskId='a';attemptId='first';stage='Check';action='start';details='stage A'},@{time='2026-11-10T09:00:01Z';taskId='b';attemptId='second';stage='Check';action='end';details='stage B'})
 [IO.File]::WriteAllText($stage,(($entries|ForEach-Object {$_|ConvertTo-Json -Compress}) -join "`n")+"`n",$utf8);Await 'stage A';Await 'stage B'
 $log=Join-Path $run 'events.jsonl';$entry=@{time='2026-11-10T09:01:00Z';type='running';details='complete JSONL'}|ConvertTo-Json -Compress
 [IO.File]::WriteAllText($log,$entry,$utf8);Stable;[IO.File]::AppendAllText($log,"`n",$utf8);Await 'complete JSONL'
 # Read-only collector fixture: registry addition arms a new worker root without restart.
 $worker=Join-Path $root 'worker';$workerRuns=Join-Path $worker '.codex-runs';$workerRun=Join-Path $workerRuns '20261110T090000000Z-87654321';[void][IO.Directory]::CreateDirectory($workerRun);$workerState=Join-Path $workerRun 'state.json';State $workerState 'worker-initial'
 $coord=Join-Path $runs 'coordinator';[void][IO.Directory]::CreateDirectory($coord);$registry=@{tasks=@{remote=@{taskId='remote';workerRepo=$worker}};integrations=@{}}
 [IO.File]::WriteAllText((Join-Path $coord 'registry.json'),($registry|ConvertTo-Json -Depth 10),$utf8);Await 'worker-initial';State $workerState 'worker-live-change';Await 'worker-live-change'
 [IO.File]::WriteAllText($workerState,'"broken worker"',$utf8);Await 'Ошибка задачи remote';State $state 'main-still-visible';Await 'main-still-visible';State $workerState 'worker-restored';Await 'worker-restored'
 [IO.File]::WriteAllText($state,'"bad schema"',$utf8);Await 'Ошибка задачи /20261110T090000000Z-12345678';$errorOutput=Output;[IO.File]::WriteAllText((Join-Path $runs 'noise.log'),'different noise',$utf8);Stable
 State $state 'recovered valid state';Await 'recovered valid state'
 $publication=Join-Path $runs 'publication.json';$p=@{commit='abcdef';phase='pushed';pushed=$true;deployed=$false;deployStatus='not-checked';error=$null};[IO.File]::WriteAllText($publication,($p|ConvertTo-Json),$utf8);Await 'Отправлено на GitHub';[IO.File]::WriteAllText($publication,($p|ConvertTo-Json),$utf8);Stable
 Assert (([regex]::Matches((Output),'Монитор Codex')).Count -eq 1) 'one initial snapshot; subsequent output appends'
 Assert ((Output).Contains('created-observation') -and (Output).Contains('stage A')) 'prior events preserved'
 Assert ((Shared $errors).Length -eq 0) 'monitor has no stderr'
 $process.Kill();$process.WaitForExit();$process.Dispose();$process=$null
 $once=Start-Process $exe -ArgumentList ($args+'-Once') -RedirectStandardOutput $output -RedirectStandardError $errors -PassThru -WindowStyle Hidden
 try{Assert ($once.WaitForExit(12000)) '-Once exits';Assert ($once.ExitCode -eq 0) '-Once exit code';Assert (([regex]::Matches((Output),'Монитор Codex')).Count -eq 1) '-Once one initial snapshot'}finally{if(!$once.HasExited){$once.Kill()};$once.Dispose()}
 'ALL MONITOR EVENT TESTS PASSED'
}finally{
 if($process){if(!$process.HasExited){$process.Kill();$process.WaitForExit()};$process.Dispose()}
 $resolved=[IO.Path]::GetFullPath($root);if($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'monitor-events-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
