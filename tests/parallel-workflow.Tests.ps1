[CmdletBinding()]
param([string]$MainRepo,[string]$WorkerA,[string]$WorkerB,[string]$WorkerC,[string]$Artifacts)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$src=Split-Path $PSScriptRoot -Parent;$watch=Join-Path $src 'watch.ps1';$utf8=[Text.UTF8Encoding]::new($false);$script:passed=0
function Assert($ok,$msg){if(!$ok){throw "ASSERT: $msg"};$script:passed++;"PASS: $msg"}
function Put($path,$text){[void][IO.Directory]::CreateDirectory((Split-Path $path -Parent));[IO.File]::WriteAllText($path,$text,$utf8)}
function Native($exe,[string[]]$argv,$cwd){$si=[Diagnostics.ProcessStartInfo]::new();$si.FileName=$exe;$si.WorkingDirectory=$cwd;$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true;$si.StandardOutputEncoding=$utf8;$si.StandardErrorEncoding=$utf8;foreach($a in $argv){$si.ArgumentList.Add($a)};$p=[Diagnostics.Process]::new();$p.StartInfo=$si;[void]$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();$p.WaitForExit();$r=@{code=$p.ExitCode;out=$o.GetAwaiter().GetResult();err=$e.GetAwaiter().GetResult()};$p.Dispose();$r}
function Git($repo,[string[]]$argv){$r=Native git (@('-C',$repo)+$argv) $repo;if($r.code){throw $r.err};$r.out.Trim()}
function W($repo,[string[]]$argv,[switch]$Fail){$r=Native (Get-Command pwsh).Source (@('-NoProfile','-File',$watch,'-Repo',$repo)+$argv) $repo;if($Fail){Assert ($r.code -ne 0) "rejected: $($argv -join ' ')"}elseif($r.code){throw "workflow $($argv -join ' '): $($r.out) $($r.err)"};$r}
function State($repo,$id){Get-Content -LiteralPath (Join-Path $repo ".codex-runs/$id/state.json") -Raw|ConvertFrom-Json -AsHashtable}
function Registry{Get-Content -LiteralPath (Join-Path $MainRepo '.codex-runs/coordinator/registry.json') -Raw|ConvertFrom-Json -AsHashtable}
function WaitRun($repo,$id){$deadline=[datetime]::UtcNow.AddSeconds(40);do{$s=State $repo $id;if($s.status -notin @('starting','running')){return $s};if([datetime]::UtcNow -gt $deadline){throw 'worker timeout'};Start-Sleep -Milliseconds 100}while($true)}
function Accept($repo,$id){[void](W $repo @('-Command','review','-Id',$id,'-Evidence',$evidence));[void](W $repo @('-Command','accept-step','-Id',$id,'-Message',"Fixture accepted step $(if($repo -eq $MainRepo){'Main integration'}else{'Worker source'})"))}
function Manual($repo,$file,$content){$base=Git $repo @('rev-parse','HEAD');Put (Join-Path $repo $file) $content;(W $repo @('-Command','manual','-TaskFile',$task,'-Files',$file,'-Baseline',$base)).out.Trim()}
if(!$MainRepo){
 $unit=Join-Path ([IO.Path]::GetTempPath()) ('parallel-unit-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($unit)
 [void](Git $unit @('init','-b','main'));[void](Git $unit @('config','user.name','Fixture'));[void](Git $unit @('config','user.email','fixture@example.invalid'));Put (Join-Path $unit '.gitignore') "/.codex-runs/`n";Put (Join-Path $unit 'a.txt') 'baseline';[void](Git $unit @('add','--','.gitignore','a.txt'));[void](Git $unit @('commit','-m','baseline'))
 [void](W $unit @('-Command','configure','-MaxWorkers','2'));foreach($bad in @('0','-1','1.2','2.7','banana')){[void](W $unit @('-Command','configure','-MaxWorkers',$bad) -Fail)}
 Import-Module (Join-Path $src 'scripts/Workflow.psm1') -Force;$module=Get-Module Workflow
 & $module {param($repo) Init-Repo $repo;Init-Coordination $null $null 'configure'} $unit
 $r=@{tasks=@{x=@{workerRepo=$unit}};reservations=@{missing=@{taskId='x';attemptId='missing';phase='reserved'}}}
 $failed='20260101T000000000Z-11111111';Put (Join-Path $unit ".codex-runs/$failed/state.json") (@{status='failed';ended='2026-01-01T00:00:00Z';pid=$null;processStarted=$null}|ConvertTo-Json);$r.reservations.failed=@{taskId='x';attemptId=$failed;phase='launch-failed'}
 & $module {param($r) Refresh-Reservations $r} $r;Assert ($r.reservations.missing.phase -eq 'reserved' -and $r.reservations.failed.phase -eq 'released') 'missing state preserves its slot; independent proven launch failure releases'
 $unknown='20260101T000000000Z-22222222';Put (Join-Path $unit ".codex-runs/$unknown/state.json") (@{status='failed';ended='2026-01-01T00:00:00Z';pid=$PID;processStarted=$null}|ConvertTo-Json);$r.reservations.unknown=@{taskId='x';attemptId=$unknown;phase='reserved'}
 $bad='20260101T000000000Z-33333333';Put (Join-Path $unit ".codex-runs/$bad/state.json") '"scalar"';$r.reservations.bad=@{taskId='x';attemptId=$bad;phase='reserved'}
 & $module {param($r) Refresh-Reservations $r} $r;Assert ($r.reservations.unknown.phase -eq 'reserved' -and $r.reservations.bad.phase -eq 'reserved') 'unknown process identity and malformed state fail closed independently'
 $held=& $module {Coordinator-Gate};try{[void](W $unit @('-Command','configure','-MaxWorkers','3') -Fail)}finally{$held.Dispose()}
 [void](W $unit @('-Command','register-worker','-TaskId','bad','-WorkerRepo',$unit,'-WorkerBranch','main') -Fail)
 $outside=Join-Path $unit 'outside';[void][IO.Directory]::CreateDirectory($outside);[void](Git $outside @('init','-b','worker'));[void](W $unit @('-Command','register-worker','-TaskId','other-common','-WorkerRepo',$outside,'-WorkerBranch','worker') -Fail)
 $branch=Git $unit @('branch','--show-current');Assert ($branch -eq 'main') 'rejected registration preserves main branch'
 "PASS: $script:passed isolated unit assertions; E2E requires managed -MainRepo/-WorkerA/-WorkerB/-WorkerC. Fixture retained: $unit";return
}
 if(!$WorkerA -or !$WorkerB -or !$WorkerC){throw 'E2E requires all three pre-created managed workers; this test never creates worktrees.'}
 if(!$Artifacts){$Artifacts=Join-Path $MainRepo '.codex-runs/parallel-tests'}
try{
 [void][IO.Directory]::CreateDirectory($Artifacts);$task=Join-Path $Artifacts 'task.md';$evidence=Join-Path $Artifacts 'evidence.md';Put $task '# Isolated parallel fixture';Put $evidence 'Independent fixture review: exact scope, expected content, accept.'
 $fake=Join-Path $Artifacts 'fake-cli.ps1';Put $fake @'
$ErrorActionPreference='Stop'
$argv=$args;$repo=$argv[[array]::IndexOf($argv,'-C')+1];$report=$argv[[array]::IndexOf($argv,'--output-last-message')+1]
[void][Console]::In.ReadToEnd();$plan=Get-Content -Raw (Join-Path $repo '.codex-runs/fixture-plan.json')|ConvertFrom-Json
$start=[datetime]::UtcNow.ToString('o');Start-Sleep -Seconds $plan.sleep
[IO.File]::WriteAllText((Join-Path $repo $plan.file),$plan.content)
[IO.File]::WriteAllText($report,"cwd=$repo; start=$start; end=$([datetime]::UtcNow.ToString('o'))")
'{"type":"turn.completed"}'
exit $plan.exit
'@
 $initial=Git $MainRepo @('rev-parse','HEAD')
 foreach($pair in @(@('a',$WorkerA),@('b',$WorkerB),@('c',$WorkerC))){$branch=Git $pair[1] @('branch','--show-current');[void](W $MainRepo @('-Command','register-worker','-TaskId',$pair[0],'-WorkerRepo',$pair[1],'-WorkerBranch',$branch))}
 [void](W $MainRepo @('-Command','register-worker','-TaskId','a','-WorkerRepo',$WorkerA,'-WorkerBranch',(Git $WorkerA @('branch','--show-current'))))
 [void](W $MainRepo @('-Command','register-worker','-TaskId','duplicate','-WorkerRepo',$WorkerA,'-WorkerBranch',(Git $WorkerA @('branch','--show-current'))) -Fail)
 [void](W $MainRepo @('-Command','register-worker','-TaskId','bad-main','-WorkerRepo',$MainRepo,'-WorkerBranch','main') -Fail)
 foreach($bad in @('0','-1','1.2','2.7','banana')){[void](W $MainRepo @('-Command','configure','-MaxWorkers',$bad) -Fail)}
 [void](W $MainRepo @('-Command','configure','-MaxWorkers','2'))
 foreach($pair in @(@('a',$WorkerA),@('b',$WorkerB),@('c',$WorkerC))){Put (Join-Path $pair[1] '.codex-runs/fixture-plan.json') (@{file="$($pair[0]).txt";content="worker $($pair[0])";sleep=12;exit=0}|ConvertTo-Json)}
 $a=(W $WorkerA @('-CoordinatorRepo',$MainRepo,'-TaskId','a','-Command','run','-TaskFile',$task,'-Files','a.txt','-TestMode','-TestCli',$fake)).out.Trim()
 $b=(W $WorkerB @('-CoordinatorRepo',$MainRepo,'-TaskId','b','-Command','run','-TaskFile',$task,'-Files','b.txt','-TestMode','-TestCli',$fake)).out.Trim()
 [void](W $WorkerC @('-CoordinatorRepo',$MainRepo,'-TaskId','c','-Command','run','-TaskFile',$task,'-Files','c.txt','-TestMode','-TestCli',$fake) -Fail)
 [void](W $MainRepo @('-Command','configure','-MaxWorkers','1') -Fail)
 [void](W $WorkerA @('-Command','run','-TaskFile',$task,'-Files','a.txt','-TestMode','-TestCli',$fake) -Fail)
 $sa=WaitRun $WorkerA $a;$sb=WaitRun $WorkerB $b
 Assert ($sa.status -eq 'awaiting-review' -and $sb.status -eq 'awaiting-review') 'both independent workers complete'
 Assert ([datetime]$sa.started -lt [datetime]$sb.ended -and [datetime]$sb.started -lt [datetime]$sa.ended) 'real worker time intervals overlap'
 Assert ($sa.taskId -eq 'a' -and $sb.taskId -eq 'b' -and $sa.pid -ne $sb.pid) 'task identity and runner processes isolated'
 Assert ((Get-Content -Raw (Join-Path $MainRepo 'a.txt')) -eq 'baseline' -and (Get-Content -Raw (Join-Path $WorkerB 'a.txt')) -eq 'baseline') 'worker edit absent from main and neighbour'
 [void](W $WorkerA @('-Command','review','-Id',$a,'-Evidence',$evidence));Put (Join-Path $WorkerA 'a.txt') 'changed after review';[void](W $WorkerA @('-Command','accept-step','-Id',$a,'-Message','stale') -Fail)
 Accept $WorkerA $a;Accept $WorkerB $b;$sa=State $WorkerA $a;$sb=State $WorkerB $b
 [void](W $WorkerA @('-Command','publish','-CompleteItem','-Message','forbidden','-TestMode','-TestSkipDeployment') -Fail)
 $ia=(W $MainRepo @('-Command','integrate','-TaskId','a','-Id',$a)).out.Trim()
 [void](W $MainRepo @('-Command','integrate','-TaskId','b','-Id',$b) -Fail)
 [void](W $MainRepo @('-Command','publish','-CompleteItem','-TestMode','-TestSkipDeployment') -Fail)
 [void](W $MainRepo @('-Command','accept-step','-Id',$ia,'-Message','no fresh review') -Fail)
 Accept $MainRepo $ia
 $ib=(W $MainRepo @('-Command','integrate','-TaskId','b','-Id',$b)).out.Trim();Assert ((State $MainRepo $ib).baseline -eq (State $MainRepo $ia).commit) 'B integrates on current main containing A';Accept $MainRepo $ib
 $r=Registry;$ma=$r.integrations["a/$a"];$mb=$r.integrations["b/$b"]
 Assert ($ma.sourceCommit -eq $sa.commit -and $mb.sourceCommit -eq $sb.commit -and $ma.integratedAcceptedCommit -ne $ma.sourceCommit -and $mb.integratedAcceptedCommit -ne $mb.sourceCommit) 'durable mapping preserves source and main commits separately'
 $before=Git $MainRepo @('rev-parse','HEAD');[void](W $MainRepo @('-Command','integrate','-TaskId','a','-Id',$a));Assert ((Git $MainRepo @('rev-parse','HEAD')) -eq $before) 'repeat accepted source idempotent'
 # Two independently accepted edits of the same baseline file produce an actual conflict.
 $ca=Manual $WorkerA 'shared.txt' 'shared A';Accept $WorkerA $ca;$cb=Manual $WorkerB 'shared.txt' 'shared B';Accept $WorkerB $cb
 $ica=(W $MainRepo @('-Command','integrate','-TaskId','a','-Id',$ca)).out.Trim();Accept $MainRepo $ica
 $icb=(W $MainRepo @('-Command','integrate','-TaskId','b','-Id',$cb)).out.Trim();Assert ((State $MainRepo $icb).status -eq 'conflict') 'overlapping accepted workers preserve conflict state'
 [void](W $MainRepo @('-Command','review','-Id',$icb,'-Evidence',$evidence) -Fail)
 Assert ((Git $MainRepo @('diff','--name-only','--diff-filter=U')) -eq 'shared.txt') 'unmerged index retained without reset'
 Put (Join-Path $MainRepo 'shared.txt') 'shared resolved';[void](Git $MainRepo @('add','--','shared.txt'));Accept $MainRepo $icb
 Assert ((State $MainRepo $icb).status -eq 'accepted') 'scoped conflict resolution requires and passes fresh review'
 # Commit→mapping crash injection uses a real accepted commit and durable committing intent.
 $statePath=Join-Path $MainRepo ".codex-runs/$icb/state.json";$s=State $MainRepo $icb;$commit=$s.commit;$s.status='reviewed';$s.commit=$null;Put $statePath ($s|ConvertTo-Json -Depth 30)
 $r=Registry;$r.integrations["b/$cb"].phase='committing';$r.integrations["b/$cb"].integratedAcceptedCommit=$null
 $r.owner=@{kind='integration';taskId='b';attemptId=$icb;pid=2147483000;processStarted='2020-01-01T00:00:00Z';time=[datetime]::UtcNow.ToString('o')};Put (Join-Path $MainRepo '.codex-runs/coordinator/registry.json') ($r|ConvertTo-Json -Depth 30);Put (Join-Path $MainRepo '.codex-runs/active.json') (@{id=$icb;pid=$null;processStarted=$null}|ConvertTo-Json)
 [void](W $MainRepo @('-Command','recover','-TaskId','b','-Id',$icb));Assert ((State $MainRepo $icb).commit -eq $commit -and (Git $MainRepo @('rev-parse','HEAD')) -eq $commit) 'recover commit-before-mapping creates no duplicate commit'
 # Reuse exact source already represented in current main: fresh explicit no-change acceptance.
 $nc=(W $MainRepo @('-Command','manual','-TaskFile',$task,'-Files','c.txt','-Baseline',(Git $MainRepo @('rev-parse','HEAD'))) -Fail)
 $remote=Join-Path $Artifacts 'remote.git';$res=Native git @('init','--bare',$remote) $MainRepo;if($res.code){throw $res.err};[void](Git $MainRepo @('remote','add','origin',$remote));[void](Git $MainRepo @('push','origin',"${initial}:refs/heads/main"))
 [void](W $MainRepo @('-Command','publish','-CompleteItem','-TestMode','-TestSkipDeployment'))
 $r=Registry;Assert ($r.integrations["a/$a"].pushed -and $r.integrations["b/$b"].pushed -and !$r.integrations["b/$b"].deployed) 'publication marks workers through integrated mapping and keeps deployment truthful'
 $head=Git $MainRepo @('rev-parse','HEAD');[void](W $MainRepo @('-Command','publish','-CompleteItem','-TestMode','-TestSkipDeployment'));Assert ((Git $MainRepo @('rev-parse','HEAD')) -eq $head) 'publication repeat creates no extra commit/archive'
 "PASS: $script:passed assertions. Fixtures retained: $MainRepo; $WorkerA; $WorkerB; $WorkerC"
}catch{Write-Error "FAILED after $script:passed assertions: $_`n$($_.ScriptStackTrace)" -ErrorAction Continue;exit 1}
