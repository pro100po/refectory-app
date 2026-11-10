[CmdletBinding()]
param([Parameter(Mandatory)][string]$MainRepo,[Parameter(Mandatory)][string]$WorkerA,[Parameter(Mandatory)][string]$WorkerB,[Parameter(Mandatory)][string]$WorkerC)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$src=Split-Path $PSScriptRoot -Parent;$watch=Join-Path $src 'watch.ps1';$utf8=[Text.UTF8Encoding]::new($false);$script:passed=0
function Assert($ok,$msg){if(!$ok){throw "ASSERT: $msg"};$script:passed++;"PASS: $msg"}
function Put($path,$text){[void][IO.Directory]::CreateDirectory((Split-Path $path -Parent));[IO.File]::WriteAllText($path,$text,$utf8)}
function Start-NativeJob($exe,[string[]]$argv,$cwd){$si=[Diagnostics.ProcessStartInfo]::new();$si.FileName=$exe;$si.WorkingDirectory=$cwd;$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true;$si.StandardOutputEncoding=$utf8;$si.StandardErrorEncoding=$utf8;foreach($a in $argv){$si.ArgumentList.Add($a)};$p=[Diagnostics.Process]::new();$p.StartInfo=$si;[void]$p.Start();@{process=$p;out=$p.StandardOutput.ReadToEndAsync();err=$p.StandardError.ReadToEndAsync()}}
function Complete-NativeJob($job){$job.process.WaitForExit();$r=@{code=$job.process.ExitCode;out=$job.out.GetAwaiter().GetResult();err=$job.err.GetAwaiter().GetResult()};$job.process.Dispose();$r}
function Native($exe,[string[]]$argv,$cwd){Complete-NativeJob (Start-NativeJob $exe $argv $cwd)}
function Git($repo,[string[]]$argv){$r=Native git (@('-C',$repo)+$argv) $repo;if($r.code){throw $r.err};$r.out.Trim()}
function BeginW($repo,[string[]]$argv){Start-NativeJob (Get-Command pwsh).Source (@('-NoProfile','-File',$watch,'-Repo',$repo)+$argv) $repo}
function W($repo,[string[]]$argv,[switch]$Fail){$r=Complete-NativeJob (BeginW $repo $argv);if($Fail){Assert ($r.code -ne 0) "rejected: $($argv -join ' ')"}elseif($r.code){throw "workflow: $($r.out) $($r.err)"};$r}
function State($repo,$id){Get-Content -LiteralPath (Join-Path $repo ".codex-runs/$id/state.json") -Raw|ConvertFrom-Json -AsHashtable}
function Registry{Get-Content -LiteralPath (Join-Path $MainRepo '.codex-runs/coordinator/registry.json') -Raw|ConvertFrom-Json -AsHashtable}
function WaitRun($repo,$id){$deadline=[datetime]::UtcNow.AddSeconds(40);do{$s=State $repo $id;if($s.status -notin @('starting','running')){return $s};if([datetime]::UtcNow -gt $deadline){throw 'worker timeout'};Start-Sleep -Milliseconds 100}while($true)}
function Accept($repo,$id){[void](W $repo @('-Command','review','-Id',$id,'-Evidence',$evidence));[void](W $repo @('-Command','accept-step','-Id',$id,'-Message',"Supplement $(if($repo -eq $MainRepo){'main'}else{'source'})"))}
function Manual($repo,$file,$content){$base=Git $repo @('rev-parse','HEAD');Put (Join-Path $repo $file) $content;(W $repo @('-Command','manual','-TaskFile',$task,'-Files',$file,'-Baseline',$base)).out.Trim()}
function Plan($repo,$file,$content,$sleep,$exit){Put (Join-Path $repo '.codex-runs/fixture-plan.json') (@{file=$file;content=$content;sleep=$sleep;exit=$exit}|ConvertTo-Json)}
function Run($repo,$taskId,$file){(W $repo @('-CoordinatorRepo',$MainRepo,'-TaskId',$taskId,'-Command','run','-TaskFile',$task,'-Files',$file,'-TestMode','-TestCli',$fake)).out.Trim()}
function Inject($id,$taskId,$phase){
 $module=Join-Path $src 'scripts/Workflow.psm1';$script=Join-Path $artifacts "inject-$phase.ps1"
 $text=@'
param($Module,$Repo,$TaskId,$Id,$Phase)
$ErrorActionPreference='Stop';Import-Module $Module -Force;$m=Get-Module Workflow
& $m {
 param($Repo,$TaskId,$Id,$Phase)
 Init-Repo $Repo;Init-Coordination $null $null 'integrate';$op=Acquire-Operation
 try{
  if($Phase -eq 'before-pick'){
   $script:SavedGit=${function:Git}
   function script:Git([string[]]$Arguments,[switch]$AllowFailure,[string]$InputText){if($Arguments[0] -eq 'cherry-pick'){throw 'Injected failure before cherry-pick'};& $script:SavedGit @PSBoundParameters}
  }else{function script:Normalize-IntegrationIndex($s){throw 'Injected failure after cherry-pick'}}
  Integrate-Worker $TaskId $Id
 }finally{$op.Dispose()}
} $Repo $TaskId $Id $Phase
'@
 Put $script $text;$r=Native (Get-Command pwsh).Source @('-NoProfile','-File',$script,'-Module',$module,'-Repo',$MainRepo,'-TaskId',$taskId,'-Id',$id,'-Phase',$phase) $MainRepo;Assert ($r.code -ne 0) "fault injection $phase stops without implicit recovery"
}
try{
 $artifacts=Join-Path $MainRepo '.codex-runs/parallel-tests';$task=Join-Path $artifacts 'task.md';$evidence=Join-Path $artifacts 'evidence.md';$fake=Join-Path $artifacts 'fake-cli.ps1'
 # Failed B and successful read-only C overlap; neither can affect the other's local state.
 Plan $WorkerB 'b.txt' 'supplement failed work' 10 7;Plan $WorkerC 'c.txt' 'baseline' 10 0
 $b=Run $WorkerB 'b' 'b.txt';$c=Run $WorkerC 'c' 'c.txt';$sb=WaitRun $WorkerB $b;$sc=WaitRun $WorkerC $c
 Assert ($sb.status -eq 'failed' -and $sb.exitCode -eq 7 -and $sc.status -eq 'awaiting-review') 'failed worker and successful neighbour complete independently'
 Assert ([datetime]$sc.started -lt [datetime]$sb.ended) 'failure scenario truly overlaps'
 Accept $WorkerC $c;Assert ((State $WorkerC $c).status -eq 'accepted-no-changes') 'source no-changes has no fake commit'
 $ic=(W $MainRepo @('-Command','integrate','-TaskId','c','-Id',$c)).out.Trim();Accept $MainRepo $ic;$r=Registry;Assert ($r.integrations["c/$c"].phase -eq 'accepted-no-changes' -and !$r.integrations["c/$c"].sourceCommit -and !$r.integrations["c/$c"].integratedAcceptedCommit) 'source no-change mapping requires fresh explicit acceptance'
 # An accepted source commit may apply empty because current main already contains its exact change.
 $current=Get-Content -Raw (Join-Path $MainRepo 'a.txt');$ec=Manual $WorkerC 'a.txt' $current;Accept $WorkerC $ec
 $ie=(W $MainRepo @('-Command','integrate','-TaskId','c','-Id',$ec)).out.Trim();Assert ((State $MainRepo $ie).status -eq 'awaiting-review') 'empty transfer remains unaccepted until fresh review';Accept $MainRepo $ie;$r=Registry;Assert ($r.integrations["c/$ec"].sourceCommit -and !$r.integrations["c/$ec"].integratedAcceptedCommit -and $r.integrations["c/$ec"].phase -eq 'accepted-no-changes') 'empty transfer preserves real source and no invented main commit'
 Plan $WorkerB 'b.txt' 'supplement failed work' 0 0;$old=$b;$oldHash=(Get-FileHash (Join-Path $WorkerB ".codex-runs/$old/task.md")).Hash
 $b=(W $WorkerB @('-CoordinatorRepo',$MainRepo,'-TaskId','b','-Command','rerun','-Id',$old,'-TaskFile',$task,'-Files','b.txt','-TestMode','-TestCli',$fake)).out.Trim();$s=WaitRun $WorkerB $b
 Assert ($s.taskId -eq 'b' -and $s.previous -eq $old -and (State $WorkerB $old).status -eq 'superseded' -and (Get-FileHash (Join-Path $WorkerB ".codex-runs/$old/task.md")).Hash -eq $oldHash) 'rerun preserves task and immutable previous history';Accept $WorkerB $b
 # Foreign index/worktree data is never discarded by integrate.
 Put (Join-Path $MainRepo 'c.txt') 'foreign staged fixture';[void](Git $MainRepo @('add','--','c.txt'));[void](W $MainRepo @('-Command','integrate','-TaskId','b','-Id',$b) -Fail);Assert ((Git $MainRepo @('diff','--cached','--name-only')) -eq 'c.txt' -and (Get-Content -Raw (Join-Path $MainRepo 'c.txt')) -eq 'foreign staged fixture') 'foreign staged bytes preserved'
 [void](Git $MainRepo @('restore','--staged','--','c.txt'));[void](Git $MainRepo @('restore','--','c.txt'));Put (Join-Path $MainRepo 'a.txt') 'foreign dirty fixture';[void](W $MainRepo @('-Command','integrate','-TaskId','b','-Id',$b) -Fail);Assert ((Get-Content -Raw (Join-Path $MainRepo 'a.txt')) -eq 'foreign dirty fixture') 'foreign unstaged bytes preserved';[void](Git $MainRepo @('restore','--','a.txt'))
 # Two simultaneous integrations race through one local owner; exactly one mutation wins.
 $one=BeginW $MainRepo @('-Command','integrate','-TaskId','b','-Id',$b);$two=BeginW $MainRepo @('-Command','integrate','-TaskId','b','-Id',$b);$results=@((Complete-NativeJob $one),(Complete-NativeJob $two));$wins=@($results|Where-Object {$_.code -eq 0});Assert ($wins.Count -eq 1) 'simultaneous integrate has exactly one successful owner';$ib=$wins[0].out.Trim();Accept $MainRepo $ib
 # Durable applying-before-pick cannot be reviewed as a false empty success.
 $beforeSource=Manual $WorkerC 'c.txt' 'before-pick source';Accept $WorkerC $beforeSource;$head=Git $MainRepo @('rev-parse','HEAD');Inject $beforeSource 'c' 'before-pick';$r=Registry;$fault=$r.owner.attemptId
 Assert ((Git $MainRepo @('rev-parse','HEAD')) -eq $head -and !(Git $MainRepo @('status','--porcelain'))) 'before-pick crash leaves main unchanged with durable intent'
 [void](W $MainRepo @('-Command','review','-Id',$fault,'-Evidence',$evidence) -Fail);[void](W $MainRepo @('-Command','recover','-TaskId','c','-Id',$fault) -Fail);Assert ((Registry).owner.attemptId -eq $fault) 'ambiguous applying remains owned; no false no-change acceptance'
 [void](W $MainRepo @('-Command','reject','-Id',$fault))
 # Failure after a real no-commit cherry-pick keeps the transferred bytes; recover never replays it.
 $afterSource=Manual $WorkerB 'c.txt' 'after-pick source';Accept $WorkerB $afterSource;Inject $afterSource 'b' 'after-pick';$fault=(Registry).owner.attemptId
 Assert ((Get-Content -Raw (Join-Path $MainRepo 'c.txt')) -eq 'after-pick source') 'after-pick crash preserves actual transferred bytes'
 [void](W $MainRepo @('-Command','recover','-TaskId','b','-Id',$fault));Assert ((State $MainRepo $fault).status -eq 'awaiting-review') 'after-pick recovery requires new main review';Accept $MainRepo $fault
 # Atomic slot race at limit=1: two independent launches cannot both reserve.
 [void](W $MainRepo @('-Command','configure','-MaxWorkers','1'));Plan $WorkerA 'a.txt' (Get-Content -Raw (Join-Path $WorkerA 'a.txt')) 10 0;Plan $WorkerB 'b.txt' (Get-Content -Raw (Join-Path $WorkerB 'b.txt')) 10 0
 $jobs=@((BeginW $WorkerA @('-CoordinatorRepo',$MainRepo,'-TaskId','a','-Command','run','-TaskFile',$task,'-Files','a.txt','-TestMode','-TestCli',$fake)),(BeginW $WorkerB @('-CoordinatorRepo',$MainRepo,'-TaskId','b','-Command','run','-TaskFile',$task,'-Files','b.txt','-TestMode','-TestCli',$fake)))
 $results=@((Complete-NativeJob $jobs[0]),(Complete-NativeJob $jobs[1]));$wins=@($results|Where-Object {$_.code -eq 0});Assert ($wins.Count -eq 1) 'simultaneous launch race reserves only one CPU slot'
 $id=$wins[0].out.Trim();$r=Registry;Assert (@($r.reservations.Values|Where-Object {$_.phase -ne 'released'}).Count -eq 1) 'common registry never exceeds configured capacity'
 $repo=$r.tasks[$r.reservations[$id].taskId].workerRepo;$done=WaitRun $repo $id;Accept $repo $id;[void](W $MainRepo @('-Command','configure','-MaxWorkers','2'))
 # Push succeeded but deployment failed: retry uses the same accepted commit and archive state.
 $p=(W $MainRepo @('-Command','publish','-CompleteItem') -Fail);$publication=Get-Content -Raw (Join-Path $MainRepo '.codex-runs/publication.json')|ConvertFrom-Json -AsHashtable
 Assert ($publication.pushed -and !$publication.deployed -and $publication.error) 'failure after push never claims deployment'
 $head=Git $MainRepo @('rev-parse','HEAD');$remote=Git $MainRepo @('ls-remote','origin','refs/heads/main');[void](W $MainRepo @('-Command','publish','-CompleteItem','-TestMode','-TestSkipDeployment'))
 Assert ((Git $MainRepo @('rev-parse','HEAD')) -eq $head -and (Git $MainRepo @('ls-remote','origin','refs/heads/main')) -eq $remote) 'retry after Pages failure reuses exact published commit'
 "PASS: $script:passed supplemental E2E assertions; fixtures retained."
}catch{Write-Error "FAILED after $script:passed assertions: $_`n$($_.ScriptStackTrace)" -ErrorAction Continue;exit 1}
