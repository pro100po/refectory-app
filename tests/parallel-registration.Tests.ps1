param([Parameter(Mandatory)][string]$MainRepo,[Parameter(Mandatory)][string]$WorkerRepo,[string]$TaskId='d')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$src=Split-Path $PSScriptRoot -Parent;$watch=Join-Path $src 'watch.ps1';$module=Join-Path $src 'scripts/Workflow.psm1';$utf8=[Text.UTF8Encoding]::new($false);$passed=0
function Assert($ok,$msg){if(!$ok){throw $msg};$script:passed++;"PASS: $msg"}
function Native([string[]]$argv){$si=[Diagnostics.ProcessStartInfo]::new();$si.FileName=(Get-Command pwsh).Source;$si.WorkingDirectory=$MainRepo;$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true;foreach($a in $argv){$si.ArgumentList.Add($a)};$p=[Diagnostics.Process]::new();$p.StartInfo=$si;[void]$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();$p.WaitForExit();$r=@{code=$p.ExitCode;out=$o.GetAwaiter().GetResult();err=$e.GetAwaiter().GetResult()};$p.Dispose();$r}
$artifacts=Join-Path $MainRepo '.codex-runs/parallel-tests';$injection=Join-Path $artifacts 'registration-fault.ps1'
$text=@'
param($Module,$Main,$Worker,$Task)
$ErrorActionPreference='Stop';Import-Module $Module -Force;$m=Get-Module Workflow
& $m {
 param($Main,$Worker,$Task)
 Init-Repo $Main;Init-Coordination $null $null 'register-worker';$lock=Acquire-Operation
 try{function script:Save-Registry($r){throw 'Injected registry save failure after durable pending marker'};Register-Worker $Task $Worker (Git-At $Worker @('branch','--show-current')).Out.Trim()}finally{$lock.Dispose()}
} $Main $Worker $Task
'@
[IO.File]::WriteAllText($injection,$text,$utf8)
$r=Native @('-NoProfile','-File',$injection,'-Module',$module,'-Main',$MainRepo,'-Worker',$WorkerRepo,'-Task',$TaskId);Assert ($r.code -ne 0) 'injected failure interrupts registration after marker'
$marker=Join-Path $WorkerRepo '.codex-runs/worker.json';$b=Get-Content -Raw $marker|ConvertFrom-Json -AsHashtable;$registryPath=Join-Path $MainRepo '.codex-runs/coordinator/registry.json';$registry=Get-Content -Raw $registryPath|ConvertFrom-Json -AsHashtable
Assert ($b.phase -eq 'registering' -and !$registry.tasks.ContainsKey($TaskId)) 'pending marker survives without incomplete registry binding'
$r=Native @('-NoProfile','-File',$watch,'-Repo',$WorkerRepo,'-Command','run','-TaskFile',(Join-Path $artifacts 'task.md'),'-Files','a.txt','-TestMode','-TestCli',(Join-Path $artifacts 'fake-cli.ps1'));Assert ($r.code -ne 0 -and !(Test-Path (Join-Path $WorkerRepo '.codex-runs/active.json'))) 'legacy run cannot bypass pending registration'
$branch=(& git -C $WorkerRepo branch --show-current).Trim();if($LASTEXITCODE){throw 'branch query failed'}
$r=Native @('-NoProfile','-File',$watch,'-Repo',$MainRepo,'-Command','register-worker','-TaskId','different-task','-WorkerRepo',$WorkerRepo,'-WorkerBranch',$branch);Assert ($r.code -ne 0) 'pending binding cannot be reassigned'
$r=Native @('-NoProfile','-File',$watch,'-Repo',$MainRepo,'-Command','register-worker','-TaskId',$TaskId,'-WorkerRepo',$WorkerRepo,'-WorkerBranch',$branch);Assert ($r.code -eq 0) "exact pending reentry completes safely: $($r.err)"
$b2=Get-Content -Raw $marker|ConvertFrom-Json -AsHashtable;$registry=Get-Content -Raw $registryPath|ConvertFrom-Json -AsHashtable;Assert ($b2.phase -eq 'registered' -and $b2.base -eq $b.base -and $registry.tasks[$TaskId].base -eq $b.base) 'registered marker and registry preserve the original base'
$r=Native @('-NoProfile','-File',$watch,'-Repo',$MainRepo,'-Command','register-worker','-TaskId',$TaskId,'-WorkerRepo',$WorkerRepo,'-WorkerBranch',$branch);Assert ($r.code -eq 0) 'identical registration remains idempotent'
"PASS: $passed registration crash assertions."
