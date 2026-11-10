param([string]$Module=(Join-Path $PSScriptRoot '../scripts/Workflow.psm1'))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Module=(Resolve-Path -LiteralPath $Module).Path
$utf8=[Text.UTF8Encoding]::new($false)
$root=Join-Path ([IO.Path]::GetTempPath()) ('monitor-events-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$process=$null
function Assert($condition,$message){if(!$condition){throw $message};"PASS: $message"}
function Read-Shared($path){
 $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));$reader=[IO.StreamReader]::new($stream)
 try{$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}
}
function Frames {if(Test-Path -LiteralPath $output){return @([regex]::Matches((Read-Shared $output),'Монитор Codex · UTC')).Count};return 0}
function Await-Frames($expected){
 $deadline=[datetime]::UtcNow.AddSeconds(12)
 while((Frames) -lt $expected -and [datetime]::UtcNow -lt $deadline){
  if($process.HasExited){throw "Monitor exited: $((Read-Shared $errors))"};Start-Sleep -Milliseconds 50
 }
 if((Frames) -ne $expected){throw "frame count $expected (actual $(Frames)); stdout=$(Read-Shared $output); stderr=$(Read-Shared $errors)"};Assert $true "frame count $expected"
}
function Stable($expected,$milliseconds=700){Start-Sleep -Milliseconds $milliseconds;Assert ((Frames) -eq $expected) "no redraw ($milliseconds ms, $expected frames)"}
function Write-State($path,$event){
 $state=@{id=(Split-Path (Split-Path $path) -Leaf);kind='cli';task='Test';model='sol';effort='medium';status='running';started='2026-11-10T09:00:00Z';ended=$null;commit=$null;pushed=$false;deployed=$false;lastEvent=$event;error=$null}
 [IO.File]::WriteAllText($path,($state|ConvertTo-Json),$utf8)
}
try {
 $repo=Join-Path $root 'repo';[void][IO.Directory]::CreateDirectory($repo)
 & git init --quiet $repo;if($LASTEXITCODE){throw 'git init failed'}
 [IO.File]::WriteAllText((Join-Path $repo '.gitignore'),"/.codex-runs/`n",$utf8)
 $runs=Join-Path $repo '.codex-runs';[void][IO.Directory]::CreateDirectory($runs)
 $output=Join-Path $root 'stdout.txt';$errors=Join-Path $root 'stderr.txt'
 $runner=Join-Path $root 'runner.ps1'
 [IO.File]::WriteAllText($runner,'param($Module,$Repo,[switch]$Once)'+"`n"+'$ErrorActionPreference="Stop";[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);Import-Module $Module -Force;Invoke-Workflow -Command monitor -Repo $Repo -Once:$Once',$utf8)
 $exe=(Get-Process -Id $PID).Path
 $process=Start-Process $exe -ArgumentList @('-NoProfile','-File',('"'+$runner+'"'),'-Module',('"'+$Module+'"'),'-Repo',('"'+$repo+'"')) -RedirectStandardOutput $output -RedirectStandardError $errors -PassThru -WindowStyle Hidden
 Await-Frames 1
 Stable 1 2600
 # Unrelated logs, temp files and directories may wake the watcher, but cannot redraw.
 [void][IO.Directory]::CreateDirectory((Join-Path $runs 'logs'))
 [IO.File]::WriteAllText((Join-Path $runs 'logs/stdout.log'),'noise',$utf8)
 [IO.File]::WriteAllText((Join-Path $runs 'state.json.tmp'),'{}',$utf8)
 Stable 1
 # New run atomically published after its directory was created.
 $run=Join-Path $runs '20261110T090000000Z-12345678';[void][IO.Directory]::CreateDirectory($run)
 $state=Join-Path $run 'state.json';$temp=Join-Path $run 'new.tmp'
 Write-State $temp 'created';[IO.File]::Move($temp,$state)
 Await-Frames 2
 [IO.File]::WriteAllText($state,[IO.File]::ReadAllText($state),$utf8)
 (Get-Item -LiteralPath $state).LastWriteTimeUtc=[datetime]::UtcNow
 Stable 2 2400
 # A JSON field not displayed by Show-Monitor also does not change the screen.
 $data=Get-Content -Raw $state|ConvertFrom-Json -AsHashtable;$data['internalOnly']='not displayed'
 [IO.File]::WriteAllText($state,($data|ConvertTo-Json),$utf8)
 Stable 2
 Write-State $state 'changed';Await-Frames 3
 Write-State $temp 'atomic replacement';[IO.File]::Move($temp,$state,$true);Await-Frames 4
 # Several closely spaced updates should produce just one final frame.
 foreach($i in 1..5){Write-State $state "burst $i";Start-Sleep -Milliseconds 20}
 Await-Frames 5;Stable 5
 Assert ((Read-Shared $output).Contains('burst 5')) 'burst displays the final data'
 $stage=Join-Path $runs 'stages.jsonl'
 $entry=@{time='2026-11-10T09:00:00Z';stage='Check';action='start';model='sol';effort='medium';details='Started'}
 [IO.File]::WriteAllText($stage,(($entry|ConvertTo-Json -Compress)+"`n"),$utf8);Await-Frames 6
 Remove-Item -LiteralPath $stage;Await-Frames 7
 $pub=Join-Path $runs 'publication.json';$publication=@{commit='abcdef';pushed=$true;deployed=$true;deployStatus='success';error=$null}
 [IO.File]::WriteAllText($pub,($publication|ConvertTo-Json),$utf8);Await-Frames 8
 Remove-Item -LiteralPath $pub;Await-Frames 9
 # Rename/removal of an entire directory must also rescan the recursive ledger.
 $hidden=Join-Path $root 'hidden';[IO.Directory]::Move($run,$hidden);Await-Frames 10
 [IO.Directory]::Move($hidden,$run);Await-Frames 11
 Remove-Item -LiteralPath $state;Await-Frames 12;Stable 12
 Assert ((Read-Shared $errors).Length -eq 0) 'continuous monitor has no stderr'
 $process.Kill();$process.WaitForExit();$process.Dispose();$process=$null
 $once=Start-Process $exe -ArgumentList @('-NoProfile','-File',('"'+$runner+'"'),'-Module',('"'+$Module+'"'),'-Repo',('"'+$repo+'"'),'-Once') -RedirectStandardOutput $output -RedirectStandardError $errors -PassThru -WindowStyle Hidden
 try{Assert ($once.WaitForExit(12000)) '-Once exits';Assert ($once.ExitCode -eq 0) '-Once exit code';Assert ((Frames) -eq 1) '-Once emits one snapshot'}finally{if(!$once.HasExited){$once.Kill()};$once.Dispose()}
 'ALL MONITOR EVENT TESTS PASSED'
}finally{
 if($process){if(!$process.HasExited){$process.Kill();$process.WaitForExit()};$process.Dispose()}
 # Only this test-owned, explicitly resolved temporary directory is removed.
 $resolved=[IO.Path]::GetFullPath($root)
 if($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'monitor-events-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
