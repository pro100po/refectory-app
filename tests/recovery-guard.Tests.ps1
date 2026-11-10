param([string]$TestRoot=(Join-Path ([IO.Path]::GetTempPath()) ('infra-recovery-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop';$passed=0
function Assert($ok,$message){if(!$ok){throw $message};$script:passed++}
$repo=Join-Path $TestRoot 'repo';[void][IO.Directory]::CreateDirectory($repo)
function Git([string[]]$a){$r=& git.exe -C $repo @a 2>&1;if($LASTEXITCODE){throw "git: $r"};$r}
function Put($path,$text){[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))}
function Refuse([scriptblock]$action,$pattern){$caught=$false;try{& $action}catch{$caught=$true;Assert ($_.ToString() -match $pattern) "Неожиданная ошибка: $_"};Assert $caught 'Команда должна отказать'}
[void](Git @('init','-b','main'));[void](Git @('config','user.name','Fixture'));[void](Git @('config','user.email','fixture@example.invalid'));Put (Join-Path $repo '.gitignore') "/.codex-runs/`n";Put (Join-Path $repo 'a.txt') 'baseline';[void](Git @('add','--','.gitignore','a.txt'));[void](Git @('commit','-m','baseline'))
$task=Join-Path $TestRoot 'task.md';$evidence=Join-Path $TestRoot 'evidence.md';$fake=Join-Path $TestRoot 'fake.ps1'
Put $task '# Read-only fake fixture';Put $evidence 'Ведущий проверил и завершил дерево процессов теста; подтверждена остановка его runner/adapter/native потомков.'
Put $fake '[Console]::In.ReadToEnd()|Out-Null;Start-Sleep -Seconds 180;exit 0'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Workflow.psm1') -Force
$id=Invoke-Workflow -Repo $repo -Command run -TaskFile $task -Files @('a.txt') -TestMode -TestCli $fake
$path=Join-Path $repo ".codex-runs/$id/state.json";$deadline=[datetime]::UtcNow.AddSeconds(20)
do{$s=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable;if($s.ContainsKey('cliPid')){break};Start-Sleep -Milliseconds 100}while([datetime]::UtcNow -lt $deadline)
Assert ($s.ContainsKey('cliPid')) 'Не стартовал реальный CLI adapter'
try {
 # Simulate an execution error recorded while its process remains alive.
 $s.status='failed';Put $path ($s|ConvertTo-Json -Depth 20)
 Refuse {Invoke-Workflow -Repo $repo -Command review -Id $id -Evidence $evidence} 'работает'
 Refuse {Invoke-Workflow -Repo $repo -Command reject -Id $id} 'работает'
 Assert ((Get-Content -LiteralPath $path -Raw|ConvertFrom-Json).status -eq 'failed') 'Отказ изменил состояние'
 $s.status='running';Put $path ($s|ConvertTo-Json -Depth 20)
 [void](& taskkill.exe /PID $s.pid /T /F 2>&1);Start-Sleep -Milliseconds 200
 Invoke-Workflow -Repo $repo -Command recover
 Assert ((Get-Content -LiteralPath $path -Raw|ConvertFrom-Json).status -eq 'interrupted') 'Ожидался interrupted'
 Refuse {Invoke-Workflow -Repo $repo -Command reject -Id $id} 'Evidence'
 Refuse {Invoke-Workflow -Repo $repo -Command rerun -Id $id -TaskFile $task -Files @('a.txt') -TestMode -TestCli $fake} 'Evidence'
 Assert (Test-Path -LiteralPath (Join-Path $repo '.codex-runs/active.json')) 'Отказ должен сохранить блокировку'
 Invoke-Workflow -Repo $repo -Command reject -Id $id -Evidence $evidence
 Assert (!(Test-Path -LiteralPath (Join-Path $repo '.codex-runs/active.json'))) 'Явное подтверждение должно освободить блокировку'
 Assert (Test-Path -LiteralPath (Join-Path $repo ".codex-runs/$id/recovery-evidence.md")) 'Подтверждение должно сохраниться'
 "PASS: $passed assertions; live review/reject refusal, interrupted evidence requirement, preserved lock, explicit cleanup."
}finally{if($s.pid){[void](& taskkill.exe /PID $s.pid /T /F 2>&1)}}
