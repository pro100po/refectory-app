Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Utf8=[Text.UTF8Encoding]::new($false)
Import-Module (Join-Path $PSScriptRoot 'Monitor.psm1') -Force

function Write-Atomic($Path,$Value) {
 $tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
 [IO.File]::WriteAllText($tmp,($Value|ConvertTo-Json -Depth 30),$script:Utf8)
 $until=[datetime]::UtcNow.AddSeconds(3)
 while($true){try{[IO.File]::Move($tmp,$Path,$true);break}catch{if([datetime]::UtcNow -ge $until){if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp};throw};Start-Sleep -Milliseconds 25}}
}
function Read-Json($Path) {
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));$reader=[IO.StreamReader]::new($stream,$script:Utf8)
 try{$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable}finally{$reader.Dispose();$stream.Dispose()}
}
function Invoke-Native([string]$Exe,[string[]]$Arguments,[string]$Directory,[string]$InputText) {
 $p=[Diagnostics.Process]::new(); $si=[Diagnostics.ProcessStartInfo]::new()
 $si.FileName=$Exe; $si.WorkingDirectory=$Directory; $si.UseShellExecute=$false; $si.CreateNoWindow=$true
 $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true; $si.RedirectStandardInput=$true
 $si.StandardOutputEncoding=$script:Utf8; $si.StandardErrorEncoding=$script:Utf8;$si.StandardInputEncoding=$script:Utf8
 foreach($a in $Arguments){$si.ArgumentList.Add($a)}
 $p.StartInfo=$si; [void]$p.Start()
 $ot=$p.StandardOutput.ReadToEndAsync(); $et=$p.StandardError.ReadToEndAsync()
 if($InputText){$p.StandardInput.Write($InputText)}; $p.StandardInput.Close(); $p.WaitForExit()
 $r=@{Code=$p.ExitCode; Out=$ot.GetAwaiter().GetResult(); Err=$et.GetAwaiter().GetResult()}; $p.Dispose(); $r
}
function Git([string[]]$Arguments,[switch]$AllowFailure,[string]$InputText) {
 $r=Invoke-Native 'git' (@('-c','core.quotepath=false','-C',$script:Repo)+$Arguments) $script:Repo $InputText
 if($r.Code -ne 0 -and !$AllowFailure){throw "git $($Arguments[0]): $($r.Err.Trim()) $($r.Out.Trim()) [exit $($r.Code)]"}
 $r
}
function G([string[]]$Arguments) { (Git $Arguments).Out.TrimEnd("`r","`n") }
function Hash-Text([string]$Text) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:Utf8.GetBytes($Text))) }
function Event($State,[string]$Type,[string]$Details) {
 $entry=@{time=[datetime]::UtcNow.ToString('o');type=$Type;details=$Details}
 [IO.File]::AppendAllText((Join-Path $script:Runs "$($State.id)/events.jsonl"),(($entry|ConvertTo-Json -Compress)+"`n"),$script:Utf8)
 $State.lastEvent="$Type : $Details"; Save-State $State
}
function Save-State($State) { Write-Atomic (Join-Path $script:Runs "$($State.id)/state.json") $State }
function Load-State([string]$Id) {
 if($Id -notmatch '^\d{8}T\d{9}Z-[a-f0-9]{8}$'){throw 'Неверный ID запуска.'}
 $p=Join-Path $script:Runs "$Id/state.json"; if(!(Test-Path -LiteralPath $p)){throw 'Запуск не найден.'}; Read-Json $p
}
function Acquire-Operation {
 try { [IO.File]::Open((Join-Path $script:Runs 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
 catch { throw 'Другая команда инфраструктуры выполняется. Повторите после её завершения.' }
}
function Active { $p=Join-Path $script:Runs 'active.json'; if(Test-Path -LiteralPath $p){Read-Json $p} }
function Set-Active($State) { Write-Atomic (Join-Path $script:Runs 'active.json') @{id=$State.id;pid=$State.pid;processStarted=$State.processStarted} }
function Require-Owner($State) { $a=Active; if(!$a -or $a.id -ne $State.id){throw 'Запуск не владеет блокировкой репозитория.'} }
function Clear-Active($State) { Require-Owner $State; Remove-Item -LiteralPath (Join-Path $script:Runs 'active.json') }
function Assert-Free { $a=Active; if($a){throw "Репозиторий занят запуском $($a.id). Нужны проверка/приёмка, отклонение или recover."} }
function Get-Route([string]$Model,[string]$Effort,[switch]$AllowMax) {
 $map=@{luna='gpt-6-luna';terra='gpt-6.1-terra';sol='gpt-6.1-sol';astra='gpt-6-astra'}
 if($map.ContainsKey($Model)){$Model=$map[$Model]}
 $routes=@{'gpt-6-luna'=@('low');'gpt-6.1-terra'=@('medium');'gpt-6.1-sol'=@('medium','high','xhigh');'gpt-6-astra'=@('medium','high','xhigh')}
 if(!$routes.ContainsKey($Model)){throw "Неизвестная модель: $Model"}
 if($Effort -eq 'max' -and $AllowMax -and $Model -in @('gpt-6.1-sol','gpt-6-astra')){return @{model=$Model;effort=$Effort}}
 if($Effort -notin $routes[$Model]){throw "Недопустимый effort $Effort для $Model; max требует явного -AllowMax, ultra запрещён."}
 @{model=$Model;effort=$Effort}
}
function Safe-File([string]$Path) {
 if(!$Path -or [IO.Path]::IsPathRooted($Path) -or $Path -match '[\x00-\x1f:*?"<>|]' -or $Path -match '(^|[\\/])\.\.([\\/]|$)'){throw "Недопустимый относительный путь: $Path"}
 $norm=$Path.Replace('\','/'); if($norm -match '(^|/)\.(?:git|codex-runs)(/|$)' -or $norm -match '(^|/)\.(/|$)' -or $norm -match '/$'){throw "Служебный или неоднозначный путь: $Path"}
 $full=[IO.Path]::GetFullPath((Join-Path $script:Repo $norm))
 if(!$full.StartsWith($script:Repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Путь вне репозитория.'}
 $walk=$script:Repo
 foreach($part in $norm.Split('/')) {
  if($part.EndsWith('.') -or $part.EndsWith(' ')){throw 'Путь с конечной точкой/пробелом запрещён.'}
  $walk=Join-Path $walk $part
  if(Test-Path -LiteralPath $walk){$it=Get-Item -LiteralPath $walk -Force; if($it.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Символическая ссылка/reparse запрещена: $walk"}}
 }
 if((Test-Path -LiteralPath $full) -and (Get-Item -LiteralPath $full -Force).PSIsContainer){throw 'Нужны точные файлы, не папки.'}
 $norm
}
function Changed-Files {
 $a=@(); foreach($args in @(@('diff','--name-only','-z','HEAD'),@('ls-files','--others','--exclude-standard','-z'))){
  $out=(Git $args).Out; $a+=@($out.Split([char]0,[StringSplitOptions]::RemoveEmptyEntries))
 }; @($a|Sort-Object -Unique)
}
function Assert-Unstaged { if((G @('diff','--cached','--name-only')).Length){throw 'Индекс Git содержит staged изменения; сначала разберите их отдельно.'} }
function Assert-Clean { Assert-Unstaged; if(@(Changed-Files).Count){throw 'Рабочая папка содержит незавершённые изменения.'} }
function Assert-Scope($State,[switch]$AllowOwnStaged) {
 if((G @('rev-parse','HEAD')) -ne $State.baseline -or (G @('branch','--show-current')) -ne $State.branch){throw 'HEAD/ветка изменились после начала запуска.'}
 if(!$AllowOwnStaged){Assert-Unstaged}
 $changed=@(Changed-Files)
 foreach($p in $changed){$norm=Safe-File $p;if($norm -cnotin $State.files){throw "Правка вне задания: $norm"}}
 foreach($p in $State.files){[void](Safe-File $p)}
 $parts=@($State.baseline,$State.branch)
 foreach($p in $changed){$full=Join-Path $script:Repo $p;$v=if(Test-Path -LiteralPath $full){(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash}else{'DELETED'};$parts+="$p`0$v"}
 # Include Git metadata (mode changes included), as well as all untracked file bytes.
 $diff='';$untracked=@((Git @('ls-files','--others','--exclude-standard','-z')).Out.Split([char]0,[StringSplitOptions]::RemoveEmptyEntries))
 foreach($path in $changed){
  if($path -cin $untracked){$addition=Git @('diff','--no-index','--binary','--','NUL',$path) -AllowFailure;if($addition.Code -notin @(0,1)){throw "Не удалось сохранить diff нового файла: $path"};$diff+=$addition.Out}
  else{$diff+=(Git @('diff','--binary','HEAD','--',$path)).Out}
 }
 $parts+=$diff
 @{files=$changed;fingerprint=(Hash-Text ($parts -join "`n"));diff=$diff}
}
function New-State($TaskFile,$Files,$Route,[string]$Kind) {
 if(!$TaskFile -or !(Test-Path -LiteralPath $TaskFile -PathType Leaf)){throw 'Требуется явный существующий -TaskFile.'}
 if(!$Files -or !$Files.Count){throw 'Требуется список точных разрешённых файлов -Files.'}
 $list=@($Files|ForEach-Object {Safe-File $_}|Sort-Object -Unique)
 $id=[datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
 $dir=Join-Path $script:Runs $id;[void][IO.Directory]::CreateDirectory($dir)
 Copy-Item -LiteralPath $TaskFile -Destination (Join-Path $dir 'task.md')
 $s=@{id=$id;attemptId=$id;taskId=$script:TaskId;kind=$Kind;task=([IO.File]::ReadLines((Join-Path $dir 'task.md'))|Select-Object -First 1);taskHash=(Get-FileHash -LiteralPath (Join-Path $dir 'task.md')).Hash;files=$list;baseline=(G @('rev-parse','HEAD'));branch=(G @('branch','--show-current'));model=$Route.model;effort=$Route.effort;status='prepared';started=[datetime]::UtcNow.ToString('o');ended=$null;pid=$null;processStarted=$null;exitCode=$null;lastEvent='';review=$null;commit=$null;pushed=$false;deployed=$false;error=$null}
 foreach($name in @('stdout.jsonl','stderr.log','report.md','changes.diff')){[IO.File]::WriteAllText((Join-Path $dir $name),'',$script:Utf8)}
 Save-State $s; $s
}
function Process-Alive($State) {
 if(!$State.pid){return $false};if(!$State.processStarted){throw 'PID без StartTime: завершение не подтверждено.'}
 try {$p=Get-Process -Id $State.pid -ErrorAction Stop;return [Math]::Abs(($p.StartTime.ToUniversalTime()-([datetime]$State.processStarted).ToUniversalTime()).TotalMilliseconds) -lt 2}catch{
  # Tool sandboxes may hide normal-session PIDs. Absence from Get-Process is
  # not proof of death: CIM must confirm it, otherwise recovery fails closed.
  try{$native=Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $([int]$State.pid)" -ErrorAction Stop}catch{throw 'Нельзя подтвердить завершение процесса: нужен разрешённый доступ к обычной Windows-сессии. Повторите команду с таким доступом; не меняйте CLI sandbox.'}
  if(!$native){return $false}
  $created=$native.CreationDate.ToUniversalTime();$expected=([datetime]$State.processStarted).ToUniversalTime()
  return [Math]::Abs(($created-$expected).TotalMilliseconds) -lt 2
 }
}
function Assert-CLIStopped($State) {
 if($State.kind -ne 'cli'){return}
 if(Process-Alive $State){throw 'Runner ещё работает; проверка/отклонение пока запрещены.'}
 if($State.ContainsKey('cliPid') -and (Process-Alive @{pid=$State.cliPid;processStarted=$State.cliProcessStarted})){throw 'CLI adapter ещё работает; проверка/отклонение пока запрещены.'}
}
function Recovery-Evidence($State,$Evidence) {
 if($State.status -ne 'interrupted' -and !($State.ContainsKey('recoveryRequired') -and $State.recoveryRequired)){return}
 if(!$Evidence -or !(Test-Path -LiteralPath $Evidence -PathType Leaf)){throw 'После interrupted нужен явный -Evidence: ведущий проверяет/завершает дерево процессов и записывает результат. Правки и блокировка сохранены.'}
 $text=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $Evidence));if(!$text.Trim()){throw 'Подтверждение проверки дерева процессов пусто.'}
 [IO.File]::WriteAllText((Join-Path $script:Runs "$($State.id)/recovery-evidence.md"),$text,$script:Utf8)
 $State.recoveryEvidence=@{hash=(Hash-Text $text);time=[datetime]::UtcNow.ToString('o')};Event $State 'recovery-evidence' 'Ведущий представил явное подтверждение проверки дерева процессов'
}
function Start-Run($TaskFile,$Files,$Model,$Effort,$AllowMax,$TestMode,$TestCli,$Previous,$RecoveryEvidence) {
 if($Previous){
  if($Previous.kind -eq 'integration'){throw 'Интеграцию нельзя rerun: используйте recover/review/reject.'}
  if($Previous.status -in @('accepted','accepted-no-changes','superseded','starting','running')){throw 'Для rerun нужен завершённый непринятый запуск.'}
  if(Process-Alive $Previous){throw 'Прежний runner ещё работает.'}
  if($Previous.ContainsKey('cliPid') -and (Process-Alive @{pid=$Previous.cliPid;processStarted=$Previous.cliProcessStarted})){throw 'Прежний CLI ещё работает.'}
  $active=Active;if($active -and $active.id -ne $Previous.id){throw 'Репозиторий занят другим запуском.'}
  [void](Assert-Scope $Previous)
  $probe=@{baseline=$Previous.baseline;branch=$Previous.branch;files=@($Files|ForEach-Object {Safe-File $_})};[void](Assert-Scope $probe)
 }else{Assert-Free;Assert-Clean}
 $route=Get-Route $Model $Effort -AllowMax:$AllowMax
 if($TestCli -and !$TestMode){throw '-TestCli требует явного -TestMode.'}
 if($TestMode -and !$TestCli){throw 'В тестовом режиме нужен -TestCli.'}
 $cli=if($TestMode){(Resolve-Path -LiteralPath $TestCli).Path}else{(Get-Command codex -ErrorAction Stop).Source}
 if([IO.Path]::GetExtension($cli) -notin @('.exe','.cmd','.bat','.ps1')){throw 'Неподдерживаемый CLI endpoint.'}
 if([IO.Path]::GetExtension($cli) -in @('.cmd','.bat') -and ($script:Repo+$script:Runs+$cli) -match '[&|<>^%!"\r\n]'){throw 'cmd shim не допускает метасимволы в путях; используйте безопасный путь или exe.'}
 if($Previous){Recovery-Evidence $Previous $RecoveryEvidence}
 $s=New-State $TaskFile $Files $route 'cli';$s.cli=$cli;$s.testMode=[bool]$TestMode;$s.launchPhase='prepared';Save-State $s
 try{Reserve-Slot $s}catch{$s.status='invalid';$s.error="$_";Save-State $s;throw}
 $s.status='starting';if($Previous){$s.previous=$Previous.id;$Previous.status='superseded';Event $Previous 'superseded' "Повторный запуск $($s.id); правки сохранены"};Save-State $s;Set-Active $s
 $launchRequested=$false;$createdPid=$null
 try {
  # Encoded bootstrap contains only generated safe data, never shell text from the task.
  $data=@{module=$PSCommandPath;repo=$script:Repo;id=$s.id;stdout=(Join-Path $script:Runs "$($s.id)/runner.stdout.log");stderr=(Join-Path $script:Runs "$($s.id)/runner.stderr.log")}|ConvertTo-Json -Compress
  $encodedData=[Convert]::ToBase64String($script:Utf8.GetBytes($data))
  $code='$ErrorActionPreference=''Stop'';$d=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$encodedData+'''))|ConvertFrom-Json;try { & {Import-Module $d.module;Invoke-Worker -Repo $d.repo -Id $d.id} 1> $d.stdout 2> $d.stderr }catch{[IO.File]::AppendAllText($d.stderr,($_|Out-String),[Text.UTF8Encoding]::new($false));exit 1}'
  $enc=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
  # WMI creates a normal-user process outside the calling tool's process tree.
  # Start-Process alone is killed by some tool hosts when their command ends.
  # No RunAs/UAC, task scheduler, service install or sandbox bypass is involved.
  $startup=New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
  $pwsh=(Get-Command pwsh).Source
  $s.launchPhase='requested';Save-State $s;$launchRequested=$true
  $created=Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=('"'+$pwsh+'" -NoLogo -NoProfile -EncodedCommand '+$enc);CurrentDirectory=$script:Repo;ProcessStartupInformation=$startup}
  if($created.ReturnValue -ne 0 -or !$created.ProcessId){$launchRequested=$false;throw "Windows CIM launcher: ReturnValue=$($created.ReturnValue), PID=$($created.ProcessId). Нужен разрешённый доступ к обычной Windows-сессии; CLI sandbox не меняйте."}
  $createdPid=[int]$created.ProcessId
  $p=Get-Process -Id $createdPid -ErrorAction Stop
  $s.pid=$p.Id;$s.processStarted=$p.StartTime.ToUniversalTime().ToString('o');$s.launcher='Windows CIM (normal user, hidden)';Save-State $s;Set-Active $s
  Event $s 'started' "Отдельный runner PID $($s.pid), $($s.model)/$($s.effort)"
  [IO.File]::WriteAllText((Join-Path $script:Runs "$($s.id)/start.ready"),'ready',$script:Utf8);$s.id
 }catch{
  $s.error="$_"
  if($launchRequested){$s.status='starting';if($createdPid){$s.pid=$createdPid};Save-State $s;Set-Active $s;throw "Исход запуска не подтверждён; active и слот сохранены. $($s.error)"}
  $s.status='failed';$s.ended=[datetime]::UtcNow.ToString('o');Save-State $s;Clear-Active $s;Slot-LaunchFailed $s;throw
 }
}
function Init-Repo($Repo) {
 $script:Repo=Canonical-Directory $Repo
 $root=G @('rev-parse','--show-toplevel');if([IO.Path]::GetFullPath($root).TrimEnd('\','/') -ne $script:Repo){throw '-Repo должен указывать корень Git.'}
 if((Get-Item -LiteralPath $script:Repo -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Корень не должен быть reparse point.'}
 $script:Runs=Join-Path $script:Repo '.codex-runs'
 if(Test-Path -LiteralPath $script:Runs){if((Get-Item -LiteralPath $script:Runs -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '.codex-runs не должна быть ссылкой.'}}
 [void][IO.Directory]::CreateDirectory($script:Runs)
 if((Git @('check-ignore','-q','--','.codex-runs/probe') -AllowFailure).Code -ne 0){throw 'Сначала добавьте /.codex-runs/ в .gitignore. Запуск ничего не коммитит сам.'}
}
function Invoke-Worker([string]$Repo,[string]$Id) {
 Init-Repo $Repo
 Init-Coordination $null $null 'worker'
 $ready=Join-Path $script:Runs "$Id/start.ready";$deadline=[datetime]::UtcNow.AddSeconds(20)
 while(!(Test-Path -LiteralPath $ready)){if([datetime]::UtcNow -gt $deadline){throw 'Нет передачи владельца runner.'};Start-Sleep -Milliseconds 100}
 # Parent still holds operation.lock briefly after it signals ready. Retry the handoff,
 # then re-read state: never write stale starting state over the worker's progress.
 $lock=$null;$handoffUntil=[datetime]::UtcNow.AddSeconds(20)
 while(!$lock){try{$lock=Acquire-Operation}catch{if([datetime]::UtcNow -gt $handoffUntil){throw};Start-Sleep -Milliseconds 100}}
 try {$s=Load-State $Id;Require-Owner $s;if($s.pid -ne $PID){throw 'Неверный владелец runner.'};$s.status='running';Event $s 'running' 'codex exec запущен'}finally{$lock.Dispose()}
 try {
  $dir=Join-Path $script:Runs $Id
  $cliArgs=@('exec','--json','--output-last-message',(Join-Path $dir 'report.md'),'-m',$s.model,'-c',"model_reasoning_effort=$($s.effort)",'-s','workspace-write','-C',$script:Repo,'-')
  # Adapter is a fixed script. JSON args are data; task prose reaches CLI only via stdin.
  Write-Atomic (Join-Path $dir 'cli.json') @{cli=$s.cli;arguments=$cliArgs}
  $prompt="Ты отдельный исполнитель согласованного задания. Прочитай неизменяемый файл задания: $(Join-Path $dir 'task.md'). Следуй AGENTS.md и docs/EXECUTOR.md. Меняй только: $($s.files -join ', '). Не делай коммитов, push, checkout/reset и не запускай инфраструктурные команды. Верни отчёт с проверками и ограничениями."
  $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=(Get-Command pwsh).Source;$psi.WorkingDirectory=$script:Repo;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  foreach($a in @('-NoProfile','-File',(Join-Path $PSScriptRoot 'cli-adapter.ps1'),'-Config',(Join-Path $dir 'cli.json'))){$psi.ArgumentList.Add($a)}
  $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.RedirectStandardInput=$true;$psi.StandardOutputEncoding=$script:Utf8;$psi.StandardErrorEncoding=$script:Utf8;$psi.StandardInputEncoding=$script:Utf8
  $p=[Diagnostics.Process]::new();$p.StartInfo=$psi;[void]$p.Start();$s.cliPid=$p.Id;$s.cliProcessStarted=$p.StartTime.ToUniversalTime().ToString('o');Save-State $s
  $p.StandardInput.Write($prompt);$p.StandardInput.Close()
  $err=$p.StandardError.ReadToEndAsync()
  $writer=[IO.StreamWriter]::new((Join-Path $dir 'stdout.jsonl'),$false,$script:Utf8);$writer.AutoFlush=$true
  try {while($null -ne ($line=$p.StandardOutput.ReadLine())) {
   $writer.WriteLine($line)
   try {$j=$line|ConvertFrom-Json -AsHashtable;if($j.type){Event $s 'cli-event' ([string]$j.type)}}catch{Event $s 'cli-unparsed' 'Нестандартная строка stdout сохранена'}
  }}finally{$writer.Dispose()}
  $p.WaitForExit();$s.exitCode=$p.ExitCode;$p.Dispose();[IO.File]::WriteAllText((Join-Path $dir 'stderr.log'),$err.GetAwaiter().GetResult(),$script:Utf8)
  if((Get-FileHash -LiteralPath (Join-Path $dir 'task.md')).Hash -ne $s.taskHash){throw 'Исполнитель изменил копию задания.'}
  $scope=Assert-Scope $s;[IO.File]::WriteAllText((Join-Path $dir 'changes.diff'),$scope.diff,$script:Utf8)
  $s.status=if($s.exitCode -eq 0){'awaiting-review'}else{'failed'}
  if($s.exitCode -ne 0){$s.error="CLI exit $($s.exitCode)"}
 }catch{$s.status='failed';$s.error="$_"}finally{$s.ended=[datetime]::UtcNow.ToString('o');Event $s $s.status $(if($s.error){$s.error}else{'Исполнитель завершился; нужна проверка ведущего'})}
}
function Manual-Run($TaskFile,$Files,$Baseline) {
 Assert-Free;Assert-Unstaged
 if(!$Baseline -or (G @('rev-parse',"$Baseline^{commit}")) -ne (G @('rev-parse','HEAD'))){throw 'Ручная регистрация требует явного -Baseline, равного текущему HEAD.'}
 # Validate BEFORE writing an active lock; rollback registration on every failed validation.
 $route=@{model='manual';effort='manual'};$s=New-State $TaskFile $Files $route 'manual'
 try {$scope=Assert-Scope $s;if(!$scope.files.Count){throw 'Нет изменений для ручной регистрации.'};$s.status='awaiting-review';$s.ended=[datetime]::UtcNow.ToString('o');Set-Active $s;Event $s 'manual' 'Ручная работа зарегистрирована; CLI не запускался';$s.id}
 catch {$s.status='invalid';$s.error="$_";Save-State $s;throw}
}
function Review-Run($s,$Evidence) {
 Require-Owner $s;Assert-IntegrationOwner $s;Assert-NoUnmerged;if($s.kind -eq 'integration'){if($s.status -notin @('awaiting-review','reviewed','conflict')){throw 'Перенос не подтверждён; сначала адресный recover либо reject.'};Normalize-IntegrationIndex $s};if($s.status -in @('starting','running')){throw 'Исполнитель ещё работает.'}
 Assert-CLIStopped $s
 if(!$Evidence -or !(Test-Path -LiteralPath $Evidence -PathType Leaf)){throw 'Нужен -Evidence: файл с результатами проверок и решением ведущего.'}
 $text=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $Evidence));if(!$text.Trim()){throw 'Доказательства проверки пусты.'}
 $scope=Assert-Scope $s
 Recovery-Evidence $s $Evidence
 [IO.File]::WriteAllText((Join-Path $script:Runs "$($s.id)/changes.diff"),$scope.diff,$script:Utf8)
 [IO.File]::WriteAllText((Join-Path $script:Runs "$($s.id)/review.md"),$text,$script:Utf8)
 $s.review=@{fingerprint=$scope.fingerprint;evidenceHash=(Hash-Text $text);time=[datetime]::UtcNow.ToString('o')}
 $s.status='reviewed';Event $s 'reviewed' 'Проверка привязана к текущему отпечатку файлов';if($s.kind -eq 'integration'){Save-Integration $s 'reviewed'}
}
function Accept-Run($s,$Message) {
 Require-Owner $s;Assert-IntegrationOwner $s;Assert-NoUnmerged;if($s.status -ne 'reviewed' -or !$s.review){throw 'Сначала нужна review с доказательствами.'}
 if(!$Message -or !$Message.Trim()){throw 'Нужно явное сообщение коммита -Message.'}
 $scope=Assert-Scope $s;if($scope.fingerprint -ne $s.review.fingerprint){throw 'Файлы изменились после review; повторите проверку.'}
 $ev=[IO.File]::ReadAllText((Join-Path $script:Runs "$($s.id)/review.md"));if((Hash-Text $ev) -ne $s.review.evidenceHash){throw 'Доказательства проверки изменились.'}
 if(!$scope.files.Count){$s.status='accepted-no-changes';$s.error=$null;Event $s 'accepted-no-changes' 'Проверено: изменений нет, коммит не создавался';if($s.kind -eq 'integration'){Save-Integration $s 'accepted-no-changes'};Clear-Active $s;return}
 try {
  [void](Git (@('add','--')+$scope.files))
  # Detect races/foreign staged paths before commit. No broad reset on failure.
  $staged=@((G @('diff','--cached','--name-only')).Split("`n",[StringSplitOptions]::RemoveEmptyEntries));foreach($f in $staged){if($f.TrimEnd("`r") -cnotin $scope.files){throw 'В индексе появились чужие изменения.'}}
  if((G @('diff','--name-only')).Length){throw 'После git add возникли новые изменения; разберите индекс вручную.'}
  $after=Assert-Scope $s -AllowOwnStaged
  if($after.fingerprint -ne $s.review.fingerprint){throw 'Содержимое изменилось во время git add; коммит запрещён, повторите проверку после разбора индекса.'}
  if($s.kind -eq 'integration'){$s.acceptIntent=@{tree=(G @('write-tree'));baseline=$s.baseline;review=$s.review;time=[datetime]::UtcNow.ToString('o')};Save-State $s;Save-Integration $s 'committing'}
  [void](Git @('commit','-m',$Message));$s.commit=G @('rev-parse','HEAD');$s.acceptedTree=G @('rev-parse',"$($s.commit)^{tree}");$s.status='accepted';$s.error=$null
  $acceptedDetails=if($s.kind -eq 'integration'){"Интеграция принята: source $($s.sourceCommit) → main $($s.commit); push не выполнялся"}else{"Локальный коммит $($s.commit); push не выполнялся"};Event $s 'accepted' $acceptedDetails;if($s.kind -eq 'integration'){Save-Integration $s 'accepted'};Clear-Active $s
 }catch{$s.error="$_";Event $s 'accept-error' $s.error;throw}
}
function Get-Ledger {
 $items=@();foreach($f in Get-ChildItem -LiteralPath $script:Runs -Filter state.json -Recurse -File){$items+=Read-Json $f.FullName};$items
}
function Save-Publication($p){Write-Atomic (Join-Path $script:Runs 'publication.json') $p}
function Wait-Deployment($p,[int]$Timeout) {
 if($Timeout -lt 0 -or $Timeout -gt 3600){throw 'DeployTimeoutSeconds: 0..3600.'}
 $repoUrl=G @('remote','get-url','origin')
 if($repoUrl -notmatch '(?:github\.com[:/])([^/]+)/([^/]+?)(?:\.git)?$'){throw 'Origin не GitHub; проверка Pages недоступна.'}
 $slug="$($Matches[1])/$($Matches[2])";$deadline=[datetime]::UtcNow.AddSeconds($Timeout)
 do {
  $r=Invoke-Native 'gh' @('api',"repos/$slug/pages/builds?per_page=100") $script:Repo ''
  if($r.Code -ne 0){throw "Ошибка GitHub Pages API: $($r.Err)"}
  $builds=$r.Out|ConvertFrom-Json -AsHashtable
  $match=@($builds|Where-Object { $_.commit -eq $p.commit }|Sort-Object created_at -Descending)|Select-Object -First 1
  if($match -and $match.status -eq 'built'){$p.deployed=$true;$p.deployStatus='built';$p.deployChecked=[datetime]::UtcNow.ToString('o');Save-Publication $p;return}
  if($match -and $match.status -eq 'errored'){throw "Pages завершилась ошибкой для $($p.commit): $($match.error|ConvertTo-Json -Compress)"}
  if([datetime]::UtcNow -ge $deadline){throw "Время ожидания Pages истекло: подтверждения для $($p.commit) нет."}
  Start-Sleep -Seconds ([Math]::Min(5,[Math]::Max(1,[int]($deadline-[datetime]::UtcNow).TotalSeconds)))
 }while($true)
}
function New-Archive($p,$Message) {
 $stamp=[datetime]::UtcNow.ToString('yyyy-MM-dd_HHmmssfff')
 $archive="versions/$stamp.html";[void](Safe-File $archive);[void](Safe-File 'versions/list.txt');[void](Safe-File 'versions.html')
 if(Test-Path -LiteralPath (Join-Path $script:Repo $archive)){throw 'Коллизия имени архива.'}
 [void][IO.Directory]::CreateDirectory((Join-Path $script:Repo 'versions'))
 $html=[IO.File]::ReadAllText((Join-Path $script:Repo 'index.html'))
 # A new snapshot lives one directory deeper; preserve local font references only there.
 $html=$html -replace '(?<![\w/.-])(?:\./)?fonts/','../fonts/'
 [IO.File]::WriteAllText((Join-Path $script:Repo $archive),$html,$script:Utf8)
 $subject=$Message -replace '[\r\n\t]',' '
 [IO.File]::AppendAllText((Join-Path $script:Repo 'versions/list.txt'),"$stamp`t$subject`n",$script:Utf8)
 $rows=@();$lines=[IO.File]::ReadAllLines((Join-Path $script:Repo 'versions/list.txt'));[array]::Reverse($lines)
 foreach($line in $lines){if(!$line.Trim()){continue};$pair=$line.Split("`t",2);if($pair.Count -ne 2 -or $pair[0] -notmatch '^\d{4}-\d{2}-\d{2}_\d{4,9}$'){throw 'Неверная строка versions/list.txt; архив не будет опубликован.'};$safe=[Net.WebUtility]::HtmlEncode($pair[1]);$st=$pair[0];$rows+="<tr><td>$st</td><td>$safe</td><td><a href='versions/$st.html' target='_blank'>открыть</a></td></tr>"}
 $page='<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Кухня трапезной — история версий</title><style>body{max-width:1000px;margin:24px auto;padding:0 16px;background:white;color:#222;font:15px/1.5 system-ui}td{padding:8px;border-bottom:1px solid #ddd}td:first-child{white-space:nowrap}a{color:#295d92}</style></head><body><h1>Кухня трапезной — история версий</h1><p><a href="./">Текущая версия</a> · <a href="https://github.com/pro100po/refectory-app/blob/project-status/PROJECT_STATUS.md">Состояние проекта</a></p><table>'+($rows -join "`n")+'</table></body></html>'
 [IO.File]::WriteAllText((Join-Path $script:Repo 'versions.html'),$page,$script:Utf8)
 $p.archiveFiles=@($archive,'versions/list.txt','versions.html');$p.archiveHashes=@{};foreach($f in $p.archiveFiles){$p.archiveHashes[$f]=(Get-FileHash -LiteralPath (Join-Path $script:Repo $f)).Hash};$p.phase='archive-created';Save-Publication $p
}
function Publish-Item($Message,$CompleteItem,$TestMode,$TestSkipDeployment,$DeployTimeoutSeconds) {
 Assert-Free;if(!$CompleteItem){throw 'publish только для завершённого пункта: нужен -CompleteItem.'}
 if($TestSkipDeployment -and !$TestMode){throw 'Пропуск Pages разрешён только с -TestMode.'}
 if((G @('branch','--show-current')) -ne 'main'){throw 'Публиковать можно только main.'}
 $existingPub=Join-Path $script:Runs 'publication.json';$resume=if(Test-Path -LiteralPath $existingPub){Read-Json $existingPub}else{$null}
 if(!$resume -or $resume.phase -ne 'archive-created'){Assert-Unstaged}
 [void](Git @('fetch','origin','refs/heads/main:refs/remotes/origin/main'))
 $remote=G @('rev-parse','origin/main');$head=G @('rev-parse','HEAD')
 if((Git @('merge-base','--is-ancestor',$remote,$head) -AllowFailure).Code -ne 0){throw 'main расходится с GitHub; сначала разберите расхождение.'}
 $ledger=@(Get-Ledger);$known=@($ledger|Where-Object {$_.status -eq 'accepted'}|ForEach-Object {$_.commit})
 $pending=@((G @('rev-list','--reverse',"$remote..HEAD")).Split("`n",[StringSplitOptions]::RemoveEmptyEntries))
 $pubPath=Join-Path $script:Runs 'publication.json';$p=if(Test-Path -LiteralPath $pubPath){Read-Json $pubPath}else{$null}
 if($p -and $p.phase -in @('archive-created','archive-committed') -and !$p.pushed){
  if($head -ne $p.source -and $head -ne $p.commit){throw 'Незавершённая публикация относится к другому HEAD.'}
 }elseif(!$p -or $p.commit -ne $head){$p=@{source=$head;commit=$head;base=$remote;phase='prepared';archiveFiles=@();pushed=$false;deployed=$false;deployStatus='not-checked';error=$null};Save-Publication $p}
 foreach($c in $pending){if($c -notin $known -and !($p.phase -eq 'archive-committed' -and $c -eq $p.commit)){throw "Непроверенный локальный коммит $c — push запрещён."}
  if((G @('rev-list','--parents','-n','1',$c)).Split(' ').Count -ne 2){throw 'Публикация merge-коммитов не поддерживается.'}
 }
 if($p.phase -eq 'archive-created'){
  $actual=@(Changed-Files);if((($actual|Sort-Object) -join "`n") -cne (($p.archiveFiles|Sort-Object) -join "`n")){throw 'Незавершённый архив содержит посторонние изменения.'}
  foreach($f in $p.archiveFiles){[void](Safe-File $f);if((Get-FileHash -LiteralPath (Join-Path $script:Repo $f)).Hash -ne $p.archiveHashes[$f]){throw 'Созданный архив изменён после попытки публикации.'}}
 }else{Assert-Clean}
 try {
  if($p.phase -eq 'prepared' -and $pending.Count -and (G @('diff','--name-only',$remote,$head,'--','index.html'))){
   if(!$Message){throw 'Для истории версии нужен -Message.'};New-Archive $p $Message
  }
  if($p.phase -eq 'archive-created'){
   foreach($f in $p.archiveFiles){if((Get-FileHash -LiteralPath (Join-Path $script:Repo $f)).Hash -ne $p.archiveHashes[$f]){throw 'Архив изменён перед commit.'}}
   $staged=@((G @('diff','--cached','--name-only')).Split("`n",[StringSplitOptions]::RemoveEmptyEntries));foreach($f in $staged){if($f.TrimEnd("`r") -cnotin $p.archiveFiles){throw 'В индексе появились чужие файлы при публикации.'}}
   [void](Git (@('add','--')+$p.archiveFiles))
   $stagedAfter=@((G @('diff','--cached','--name-only')).Split("`n",[StringSplitOptions]::RemoveEmptyEntries));foreach($f in $stagedAfter){if($f.TrimEnd("`r") -cnotin $p.archiveFiles){throw 'После git add в индексе появились чужие файлы.'}}
   if((G @('rev-parse','HEAD')) -ne $p.source){throw 'HEAD изменился во время подготовки архива.'}
   foreach($f in $p.archiveFiles){if((Get-FileHash -LiteralPath (Join-Path $script:Repo $f)).Hash -ne $p.archiveHashes[$f]){throw 'Архив изменён во время git add.'}}
   if((G @('diff','--name-only')).Length){throw 'Файлы изменились во время подготовки архива к commit.'}
   [void](Git @('commit','-m',"История версии: $Message"));$p.commit=G @('rev-parse','HEAD');$p.phase='archive-committed';Save-Publication $p
  }
  if($remote -ne $p.commit){[void](Git @('push','origin',"$($p.commit):refs/heads/main"))}
  $p.pushed=$true;$p.phase='pushed';$p.error=$null;Save-Publication $p
  foreach($s in $ledger){if($s.commit -and ((Git @('merge-base','--is-ancestor',$s.commit,$p.commit) -AllowFailure).Code -eq 0)){$s.pushed=$true;Save-State $s}}
  if($TestSkipDeployment){$p.deployStatus='skipped-test';$p.deployed=$false;Save-Publication $p}
  elseif(!$p.deployed){Wait-Deployment $p $DeployTimeoutSeconds}
  if($p.deployed){foreach($s in $ledger){if($s.commit -and ((Git @('merge-base','--is-ancestor',$s.commit,$p.commit) -AllowFailure).Code -eq 0)){$s.deployed=$true;Save-State $s}}}
  $p|ConvertTo-Json -Depth 8
 }catch{$p.error="$_";Save-Publication $p;throw}
}
function Update-ProjectStatus($StatusFile) {
 Assert-Free;Assert-Clean
 if(!$StatusFile -or !(Test-Path -LiteralPath $StatusFile -PathType Leaf)){throw 'Нужен явный -StatusFile.'}
 $content=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $StatusFile));if(!$content.Trim()){throw 'Файл состояния пуст.'}
 $oldEnv=[Environment]::GetEnvironmentVariable('GIT_INDEX_FILE','Process');$tmp=Join-Path $script:Runs ('status-index-'+[guid]::NewGuid().ToString('N'));$source=Join-Path $script:Runs ('status-'+[guid]::NewGuid().ToString('N')+'.md')
 try {
  $ls=G @('ls-remote','--heads','origin','refs/heads/project-status');$parent=$null
  if($ls){[void](Git @('fetch','origin','refs/heads/project-status:refs/remotes/origin/project-status'));$parent=G @('rev-parse','refs/remotes/origin/project-status');if($parent -ne ($ls -split '\s+')[0]){throw 'Ветка состояния изменилась во время fetch; повторите.'}}
  $env:GIT_INDEX_FILE=$tmp
  # Orphan tree, deliberately only PROJECT_STATUS.md even if a bad old branch had extra files.
  [void](Git @('read-tree','--empty'));[IO.File]::WriteAllText($source,$content,$script:Utf8)
  $blob=G @('hash-object','-w','--no-filters',$source);[void](Git @('update-index','--add','--cacheinfo',"100644,$blob,PROJECT_STATUS.md"));$tree=G @('write-tree')
  if($parent -and (G @('rev-parse',"$parent^{tree}")) -eq $tree){return 'Состояние уже совпадает; новый коммит не нужен.'}
  $ca=@('commit-tree',$tree,'-m','Состояние проекта');if($parent){$ca+=@('-p',$parent)};$commit=G $ca
  # Normal push: concurrent remote update fails rather than overwriting it.
  [void](Git @('push','origin',"${commit}:refs/heads/project-status"))
  Write-Atomic (Join-Path $script:Runs 'status-publication.json') @{commit=$commit;time=[datetime]::UtcNow.ToString('o');url='https://github.com/pro100po/refectory-app/blob/project-status/PROJECT_STATUS.md'}
  'https://github.com/pro100po/refectory-app/blob/project-status/PROJECT_STATUS.md'
 }finally{if($null -eq $oldEnv){Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue}else{$env:GIT_INDEX_FILE=$oldEnv};foreach($f in @($tmp,$source)){if(Test-Path -LiteralPath $f){Remove-Item -LiteralPath $f}}}
}
function Canonical-Directory([string]$Path) {
 if(!$Path -or !(Test-Path -LiteralPath $Path -PathType Container)){throw 'Нужна существующая папка.'}
 $full=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd('\','/')
 $walk=$full
 while($walk){$item=Get-Item -LiteralPath $walk -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Reparse путь запрещён: $walk"};$next=Split-Path $walk -Parent;if($next -eq $walk){break};$walk=$next}
 $full
}
function Git-At([string]$Root,[string[]]$Arguments,[switch]$AllowFailure) {
 $r=Invoke-Native 'git' (@('-c','core.quotepath=false','-C',$Root)+$Arguments) $Root ''
 if($r.Code -ne 0 -and !$AllowFailure){throw "git $($Arguments[0]): $($r.Err) $($r.Out)"};$r
}
function Common-Dir([string]$Root){[IO.Path]::GetFullPath((Git-At $Root @('rev-parse','--path-format=absolute','--git-common-dir')).Out.Trim()).TrimEnd('\','/')}
function Coordinator-Path {Join-Path $script:CoordinatorRepo '.codex-runs/coordinator'}
function Registry-Path {Join-Path (Coordinator-Path) 'registry.json'}
function Coordinator-Gate {
 $dir=Coordinator-Path;[void][IO.Directory]::CreateDirectory($dir)
 if((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'coordinator не должен быть ссылкой.'}
 try{[IO.File]::Open((Join-Path $dir 'registry.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'Реестр координатора занят другой короткой операцией; повторите команду.'}
}
function Read-Registry {
 $r=Read-Json (Registry-Path)
 if(!$r -or $r.schemaVersion -ne 1 -or !$r.tasks -or !$r.reservations -or !$r.integrations){
  # Empty dictionaries are legitimate; distinguish absent keys from empty values.
  if(!$r -or $r.schemaVersion -ne 1 -or !$r.ContainsKey('tasks') -or !$r.ContainsKey('reservations') -or !$r.ContainsKey('integrations')){throw 'Реестр координатора повреждён; автоматическое восстановление пустым реестром запрещено.'}
 }
 if($r.coordinatorRepo -ne $script:CoordinatorRepo -or $r.commonDir -ne (Common-Dir $script:Repo)){throw 'Реестр принадлежит другой рабочей копии/Git common-dir.'};$r
}
function Save-Registry($r){Write-Atomic (Registry-Path) $r}
function Assert-Coordinator {
 if($script:WorkerBinding){throw 'Зарегистрированному worker запрещены интеграция, публикация и настройка координатора.'}
 if($script:Repo -ne $script:CoordinatorRepo -or (G @('branch','--show-current')) -ne 'main'){throw 'Команда разрешена только в канонической main координатора.'}
}
function Ensure-Registry {
 Assert-Coordinator
 $gate=Coordinator-Gate
 try{
  if(Test-Path -LiteralPath (Registry-Path)){[void](Read-Registry);return}
  $r=@{schemaVersion=1;coordinatorRepo=$script:Repo;commonDir=(Common-Dir $script:Repo);maxWorkers=2;tasks=@{};reservations=@{};integrations=@{};owner=$null;created=[datetime]::UtcNow.ToString('o')};Save-Registry $r
 }finally{$gate.Dispose()}
}
function Init-Coordination([string]$CoordinatorRepo,[string]$TaskId,[string]$Command) {
 $script:WorkerBinding=$null;$script:TaskId=$null;$script:CoordinatorRepo=$script:Repo
 $marker=Join-Path $script:Runs 'worker.json'
 if(Test-Path -LiteralPath $marker){
  $b=Read-Json $marker
  if(!$b -or !$b.taskId -or !$b.coordinatorRepo){throw 'Маркер worker повреждён; обход регистрации запрещён.'}
  $script:WorkerBinding=$b;$script:CoordinatorRepo=Canonical-Directory $b.coordinatorRepo;$script:TaskId=$b.taskId
  if($CoordinatorRepo -and (Canonical-Directory $CoordinatorRepo) -ne $script:CoordinatorRepo){throw 'CoordinatorRepo не совпадает с регистрацией worker.'}
  if($TaskId -and $TaskId -cne $b.taskId){throw 'TaskId не совпадает с регистрацией worker.'}
  if($Command -in @('run','rerun') -and (!$CoordinatorRepo -or !$TaskId)){throw 'Зарегистрированный worker требует явные -CoordinatorRepo и -TaskId при запуске.'}
  $r=Read-Registry;if(!$r.tasks.ContainsKey($b.taskId)){throw 'Worker отсутствует в реестре координатора.'};$t=$r.tasks[$b.taskId]
  if($t.workerRepo -ne $script:Repo -or $t.workerBranch -cne (G @('branch','--show-current')) -or $t.base -ne $b.base){throw 'Папка/ветка/base worker не совпадают с регистрацией.'}
 }elseif(($CoordinatorRepo -and (Canonical-Directory $CoordinatorRepo) -ne $script:Repo) -or ($TaskId -and $Command -in @('run','rerun','manual'))){throw 'Сначала зарегистрируйте эту рабочую копию командой register-worker.'}
 if(!$script:WorkerBinding -and $Command -eq 'record-stage' -and $TaskId){$r=Read-Registry;if(!$r.tasks.ContainsKey($TaskId)){throw 'TaskId этапа не зарегистрирован.'};$script:TaskId=$TaskId}
}
function Register-Worker([string]$TaskId,[string]$WorkerRepo,[string]$WorkerBranch) {
 Assert-Coordinator;Assert-Free
 if($TaskId -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$'){throw 'TaskId: 1–80 латинских букв, цифр, точек, дефисов или подчёркиваний.'}
 if(!$WorkerBranch -or $WorkerBranch -ieq 'main' -or (Git @('check-ref-format','--branch',$WorkerBranch) -AllowFailure).Code){throw 'Нужна отдельная допустимая не-main ветка.'}
 $worker=Canonical-Directory $WorkerRepo
 if($worker -eq $script:Repo -or (Common-Dir $worker) -ne (Common-Dir $script:Repo)){throw 'Нужен отдельный worktree с тем же Git common-dir.'}
 $top=(Git-At $worker @('rev-parse','--show-toplevel')).Out.Trim();if((Canonical-Directory $top) -ne $worker){throw 'WorkerRepo должен быть корнем Git worktree.'}
 $listed=(Git @('worktree','list','--porcelain','-z')).Out.Split([char]0,[StringSplitOptions]::RemoveEmptyEntries)
 if(!@($listed|Where-Object {$_ -like 'worktree *' -and (Canonical-Directory $_.Substring(9)) -eq $worker}).Count){throw 'WorkerRepo не зарегистрирован Git как worktree.'}
 if((Git-At $worker @('branch','--show-current')).Out.Trim() -cne $WorkerBranch){throw 'WorkerBranch не совпадает с фактической веткой worktree.'}
 $runs=Join-Path $worker '.codex-runs';$marker=Join-Path $runs 'worker.json'
 if(Test-Path -LiteralPath $runs){if((Get-Item -LiteralPath $runs -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Worker .codex-runs является ссылкой.'}}
 if((Git-At $worker @('check-ignore','-q','--','.codex-runs/probe') -AllowFailure).Code){throw 'Worker должен исключать /.codex-runs/ из Git.'}
 [void][IO.Directory]::CreateDirectory($runs)
 try{$workerLock=[IO.File]::Open((Join-Path $runs 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'Worker занят локальной командой регистрации/запуска.'}
 try{
 Ensure-Registry;$gate=Coordinator-Gate
 try{
  $r=Read-Registry
  if($r.tasks.ContainsKey($TaskId)){
   $old=$r.tasks[$TaskId];if($old.workerRepo -ne $worker -or $old.workerBranch -cne $WorkerBranch){throw 'Изменение привязки существующей задачи запрещено.'}
   if(Test-Path -LiteralPath $marker){$b=Read-Json $marker;if($b.taskId -cne $TaskId -or $b.coordinatorRepo -ne $script:Repo -or $b.base -ne $old.base){throw 'Маркер не совпадает с реестром.'}}else{if((Test-Path -LiteralPath (Join-Path $runs 'active.json')) -or (Git-At $worker @('status','--porcelain')).Out.Trim()){throw 'Для восстановления отсутствующего marker worker должен быть чистым и свободным.'}}
   Write-Atomic $marker @{taskId=$TaskId;coordinatorRepo=$script:Repo;workerRepo=$worker;workerBranch=$WorkerBranch;base=$old.base;phase='registered'}
   return "Задача $TaskId уже зарегистрирована."
  }
  foreach($t in $r.tasks.Values){if($t.workerRepo -eq $worker -or $t.workerBranch -ieq $WorkerBranch){throw 'Папка или ветка уже назначена другой задаче.'}}
  if($r.owner){throw 'Сначала завершите незавершённую интеграцию/публикацию.'}
  if(Test-Path -LiteralPath $marker){
   $pending=Read-Json $marker
   if($pending -isnot [Collections.IDictionary] -or !$pending.ContainsKey('phase') -or $pending.phase -ne 'registering' -or $pending.taskId -cne $TaskId -or $pending.coordinatorRepo -ne $script:Repo -or $pending.workerRepo -ne $worker -or $pending.workerBranch -cne $WorkerBranch -or $pending.base -ne (Git-At $worker @('rev-parse','HEAD')).Out.Trim()){throw 'Рабочая копия содержит другую/неоднозначную регистрацию.'}
  }
  if(Test-Path -LiteralPath (Join-Path $runs 'active.json')){throw 'В worker есть незавершённый локальный запуск.'}
  if((Git-At $worker @('status','--porcelain')).Out.Trim()){throw 'Перед регистрацией worker должен быть чистым.'}
  $base=(Git-At $worker @('rev-parse','HEAD')).Out.Trim();[void][IO.Directory]::CreateDirectory($runs)
  # Fail closed across process death: marker precedes registry. Only exact pending reentry may complete it.
  Write-Atomic $marker @{taskId=$TaskId;coordinatorRepo=$script:Repo;workerRepo=$worker;workerBranch=$WorkerBranch;base=$base;phase='registering'}
  $r.tasks[$TaskId]=@{taskId=$TaskId;workerRepo=$worker;workerBranch=$WorkerBranch;base=$base;registered=[datetime]::UtcNow.ToString('o');attempts=@()};Save-Registry $r
  Write-Atomic $marker @{taskId=$TaskId;coordinatorRepo=$script:Repo;workerRepo=$worker;workerBranch=$WorkerBranch;base=$base;phase='registered'};"Зарегистрирована задача $TaskId, ветка $WorkerBranch."
 }finally{$gate.Dispose()}
 }finally{$workerLock.Dispose()}
}
function Refresh-Reservations($r) {
 foreach($slot in $r.reservations.Values){
  if($slot.phase -eq 'released'){continue}
  try{$t=$r.tasks[$slot.taskId];$state=Read-Json (Join-Path $t.workerRepo ".codex-runs/$($slot.attemptId)/state.json");if($state -isnot [Collections.IDictionary] -or !$state.ContainsKey('status') -or !$state.ContainsKey('ended') -or !$state.ContainsKey('pid') -or !$state.ContainsKey('processStarted')){throw 'Неверная схема состояния'}}catch{$slot.error="Состояние недоступно, слот сохранён: $_";continue}
  if($state.status -in @('starting','running') -or !$state.ended){continue}
  if(!$state.pid){if($slot.phase -eq 'launch-failed'){$slot.phase='released';$slot.released=[datetime]::UtcNow.ToString('o')};continue}
  try{if(Process-Alive $state){continue};if($state.ContainsKey('cliPid') -and (Process-Alive @{pid=$state.cliPid;processStarted=$state.cliProcessStarted})){continue}}catch{$slot.error="Завершение не подтверждено: $_";continue}
  $slot.phase='released';$slot.released=[datetime]::UtcNow.ToString('o')
 }
}
function Reserve-Slot($s) {
 if(!$script:WorkerBinding){return}
 $gate=Coordinator-Gate
 try{
  $r=Read-Registry;Refresh-Reservations $r
  $busy=@($r.reservations.Values|Where-Object {$_.phase -ne 'released'})
  if($busy.Count -ge $r.maxWorkers){Save-Registry $r;throw "Предел $($r.maxWorkers) исполнителей занят: $(($busy|ForEach-Object {'{0}/{1}' -f $_.taskId,$_.attemptId}) -join ', ')."}
  $r.reservations[$s.id]=@{taskId=$script:TaskId;attemptId=$s.id;phase='reserved';launcherPid=$PID;launcherStarted=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');time=[datetime]::UtcNow.ToString('o')}
  $r.tasks[$script:TaskId].attempts=@($r.tasks[$script:TaskId].attempts)+$s.id;Save-Registry $r
 }finally{$gate.Dispose()}
}
function Slot-LaunchFailed($s) {
 if(!$script:WorkerBinding){return};$gate=Coordinator-Gate
 try{$r=Read-Registry;if($r.reservations.ContainsKey($s.id)){$r.reservations[$s.id].phase='launch-failed';Refresh-Reservations $r;Save-Registry $r}}finally{$gate.Dispose()}
}
function Configure-Workers([string]$MaxWorkers) {
 Assert-Coordinator;$limit=0
 if($MaxWorkers -notmatch '^[1-9][0-9]*$' -or ![int]::TryParse($MaxWorkers,[ref]$limit) -or $limit -lt 1){throw 'MaxWorkers должен быть положительным целым числом.'}
 Ensure-Registry;$gate=Coordinator-Gate
 try{$r=Read-Registry;Refresh-Reservations $r;$busy=@($r.reservations.Values|Where-Object {$_.phase -ne 'released'});if($limit -lt $busy.Count){throw 'Нельзя уменьшить предел ниже уже зарезервированных слотов.'};$r.maxWorkers=$limit;Save-Registry $r;"Предел исполнителей: $limit"}finally{$gate.Dispose()}
}
function Recover-OrphanSlot([string]$Id) {
 if(!$script:WorkerBinding -or !$Id){throw 'Нет активного запуска; для orphan reservation нужен зарегистрированный worker и явный -Id.'}
 $active=Active;if($active -and $active.id -ne $Id){throw 'Orphan recovery не владеет чужим active.'}
 $gate=Coordinator-Gate
 try{
  $r=Read-Registry;if(!$r.reservations.ContainsKey($Id) -or $r.reservations[$Id].taskId -cne $script:TaskId){throw 'Эта задача не владеет reservation.'}
  $slot=$r.reservations[$Id];$launcher=@{pid=$slot.launcherPid;processStarted=$slot.launcherStarted}
  if(Process-Alive $launcher){throw 'Launcher ещё работает; reservation сохранён.'}
  $s=Load-State $Id
  if(!$s.ContainsKey('launchPhase') -or $s.launchPhase -ne 'prepared' -or $s.pid){throw 'Нет доказательства отсутствия запуска процесса; reservation сохранён.'}
  $s.status='interrupted';$s.recoveryRequired=$true;$s.ended=[datetime]::UtcNow.ToString('o');Set-Active $s;Event $s 'interrupted' 'Launcher завершился до launch intent; слот освобождён, правки/история сохранены; нужен recovery evidence'
  $slot.phase='released';$slot.released=[datetime]::UtcNow.ToString('o');$slot.reason='launcher-dead-before-launch-intent';Save-Registry $r;$s.id
 }finally{$gate.Dispose()}
}
function Integration-Key([string]$TaskId,[string]$AttemptId){"$TaskId/$AttemptId"}
function Save-Integration($s,[string]$Phase) {
 $gate=Coordinator-Gate
 try{
  $r=Read-Registry;$key=Integration-Key $s.taskId $s.sourceAttemptId
  if(!$r.owner -or $r.owner.kind -ne 'integration' -or $r.owner.attemptId -ne $s.id){throw 'Нет владельца этой интеграции.'}
  $m=$r.integrations[$key];$m.phase=$Phase;$m.updated=[datetime]::UtcNow.ToString('o')
  if($s.review){$m.review=$s.review};if($s.ContainsKey('acceptIntent')){$m.acceptIntent=$s.acceptIntent}
  if($Phase -in @('accepted','accepted-no-changes')){$m.integratedAcceptedCommit=$s.commit;$m.accepted=[datetime]::UtcNow.ToString('o');$m.reason=if($s.commit){'fresh-main-review'}else{'Проверено текущее дерево main; перенос не содержит изменений'};$r.owner=$null}
  elseif($Phase -eq 'rejected'){$m.reason='Отклонено ведущим; изменения сохранены';$r.owner=$null}
  $report="# Интеграция $($s.taskId)`nПопытка: $($s.id)`nSource attempt: $($s.sourceAttemptId)`nSource commit: $($s.sourceCommit)`nMain baseline: $($s.baseline)`nIntegrated accepted commit: $($s.commit)`nPhase: $Phase`nReview: $($s.review|ConvertTo-Json -Compress)`n"
  [IO.File]::WriteAllText((Join-Path $script:Runs "$($s.id)/report.md"),$report,$script:Utf8)
  Save-Registry $r
 }finally{$gate.Dispose()}
}
function Assert-IntegrationOwner($s){
 if($s.kind -ne 'integration'){return};$r=Read-Registry
 if(!$r.owner -or $r.owner.kind -ne 'integration' -or $r.owner.attemptId -ne $s.id){throw 'Интеграция не владеет main.'}
}
function Assert-NoUnmerged {if((G @('diff','--name-only','--diff-filter=U')).Length){throw 'В индексе остались конфликты; разрешите только файлы задания и повторите fresh review.'}}
function Normalize-IntegrationIndex($s){
 Assert-IntegrationOwner $s;Assert-NoUnmerged
 $staged=@((G @('diff','--cached','--name-only','-z')).Split([char]0,[StringSplitOptions]::RemoveEmptyEntries))
 foreach($f in $staged){if($f -cnotin $s.files){throw "Чужой staged файл $f сохранён; review запрещён."}}
 if($staged.Count){[void](Git (@('restore','--staged','--')+$staged))}
 # Quit only cherry-pick metadata; never abort/reset or discard the resolved files.
 $ch=G @('rev-parse','--path-format=absolute','--git-path','CHERRY_PICK_HEAD');if(Test-Path -LiteralPath $ch){[void](Git @('cherry-pick','--quit'))}
}
function Integrate-Worker([string]$TaskId,[string]$Id) {
 Assert-Coordinator;Ensure-Registry
 if($TaskId -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$' -or $Id -notmatch '^\d{8}T\d{9}Z-[a-f0-9]{8}$'){throw 'Нужны безопасные -TaskId и source -Id.'}
 $gate=Coordinator-Gate
 try{
  $r=Read-Registry;$key=Integration-Key $TaskId $Id
  if($r.integrations.ContainsKey($key)){$known=$r.integrations[$key];if($known.phase -in @('accepted','accepted-no-changes')){return ($known|ConvertTo-Json -Depth 15)};throw "Источник уже имеет незавершённую/отклонённую интеграцию $($known.integrationAttemptId); используйте её recover/review."}
  if($r.owner){throw "Main занят владельцем $($r.owner.kind)/$($r.owner.attemptId)."}
  Assert-Free;Assert-Clean;Assert-NoUnmerged
  if(!$r.tasks.ContainsKey($TaskId)){throw 'Задача не зарегистрирована.'};$t=$r.tasks[$TaskId];$worker=Canonical-Directory $t.workerRepo
  if((Common-Dir $worker) -ne $r.commonDir -or (Git-At $worker @('branch','--show-current')).Out.Trim() -cne $t.workerBranch){throw 'Регистрация source больше не соответствует Git.'}
  $b=Read-Json (Join-Path $worker '.codex-runs/worker.json');if($b.taskId -cne $TaskId -or $b.coordinatorRepo -ne $script:Repo){throw 'Маркер source не соответствует координатору.'}
  $sourceDir=Join-Path $worker ".codex-runs/$Id";$source=Read-Json (Join-Path $sourceDir 'state.json')
  if(!$source -or $source.taskId -cne $TaskId -or $source.branch -cne $t.workerBranch -or $source.status -notin @('accepted','accepted-no-changes')){throw 'Источник должен быть принятым запуском этой задачи.'}
  Assert-CLIStopped $source
  if((Get-FileHash -LiteralPath (Join-Path $sourceDir 'task.md')).Hash -ne $source.taskHash){throw 'Исходное задание изменилось.'}
  $evidence=[IO.File]::ReadAllText((Join-Path $sourceDir 'review.md'));if((Hash-Text $evidence) -ne $source.review.evidenceHash){throw 'Source evidence изменились после приёмки.'}
  if($source.status -eq 'accepted'){
   if(!$source.commit -or $source.commit -notmatch '^[a-f0-9]{40,64}$'){throw 'Неизвестный source commit.'}
   if(!$source.ContainsKey('acceptedTree') -or (G @('rev-parse',"$($source.commit)^{tree}")) -ne $source.acceptedTree){throw 'Source tree не совпадает с принятым снимком.'}
   $parents=(G @('rev-list','--parents','-n','1',$source.commit)).Split(' ');if($parents.Count -ne 2 -or $parents[1] -ne $source.baseline){throw 'Интегрируется ровно один commit с родителем baseline; merge/пачка не поддержаны.'}
   if((Git-At $worker @('merge-base','--is-ancestor',$source.commit,$t.workerBranch) -AllowFailure).Code){throw 'Source commit больше не принадлежит worker ветке.'}
   $changed=@((G @('diff-tree','--no-commit-id','--name-only','-r','-z',$source.commit)).Split([char]0,[StringSplitOptions]::RemoveEmptyEntries));foreach($f in $changed){[void](Safe-File $f);if($f -cnotin $source.files){throw "Source commit за scope: $f"}}
  }elseif($source.commit){throw 'accepted-no-changes не должен содержать commit.'}
  $s=New-State (Join-Path $sourceDir 'task.md') $source.files @{model='integration';effort='fresh-review-required'} 'integration'
  $s.taskId=$TaskId;$s.attemptId=$s.id;$s.sourceAttemptId=$Id;$s.sourceCommit=$source.commit;$s.sourceBaseline=$source.baseline;$s.sourceReviewHash=$source.review.evidenceHash;$s.status='integrating';$s.ended=[datetime]::UtcNow.ToString('o');Save-State $s
  $r.owner=@{kind='integration';taskId=$TaskId;attemptId=$s.id;pid=$PID;processStarted=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');time=[datetime]::UtcNow.ToString('o')}
  $r.integrations[$key]=@{taskId=$TaskId;sourceAttemptId=$Id;sourceCommit=$source.commit;sourceBaseline=$source.baseline;sourceReviewHash=$source.review.evidenceHash;integrationAttemptId=$s.id;mainBaseline=$s.baseline;files=$s.files;phase='intent';integratedAcceptedCommit=$null;review=$null;created=[datetime]::UtcNow.ToString('o');pushed=$false;deployed=$false};Save-Registry $r;Set-Active $s
 }finally{$gate.Dispose()}
 # Durable intent exists before the first Git mutation. Other workers use their own checkout.
 Save-Integration $s 'applying'
 if($s.sourceCommit){$pick=Git @('cherry-pick','--no-commit',$s.sourceCommit) -AllowFailure}else{$pick=@{Code=0;Out='';Err=''}}
 if($pick.Code -ne 0){$s.status='conflict';$s.error=$pick.Err+$pick.Out;Event $s 'integration-conflict' "Перенос сохранён, нужны разбор конфликтов и fresh review: $($s.error)";Save-Integration $s 'conflict';$s.id;return}
 Normalize-IntegrationIndex $s;$scope=Assert-Scope $s;$s.transferFingerprint=$scope.fingerprint;$s.status='awaiting-review';Event $s 'integrated' "Source $($s.sourceCommit) перенесён на main $($s.baseline); нужна новая проверка";Save-Integration $s 'awaiting-review';$s.id
}
function Recover-Integration([string]$TaskId,[string]$Id) {
 Assert-Coordinator;$r=Read-Registry;$owner=$r.owner
 if(!$owner -or $owner.kind -ne 'integration'){throw 'Нет незавершённой интеграции.'}
 if(($TaskId -and $TaskId -cne $owner.taskId) -or ($Id -and $Id -ne $owner.attemptId)){throw 'recover адресован другой интеграции.'}
 if(Process-Alive $owner){throw 'Команда владельца интеграции ещё работает.'}
 $s=Load-State $owner.attemptId;$m=$r.integrations[(Integration-Key $s.taskId $s.sourceAttemptId)]
 $a=Active;if(!$a){Set-Active $s}elseif($a.id -ne $s.id){throw 'Main active принадлежит другому запуску.'}
 $head=G @('rev-parse','HEAD')
 if($s.status -in @('accepted','accepted-no-changes')){Save-Integration $s $s.status;Clear-Active $s;return 'Принятая связь восстановлена без нового коммита.'}
 if($head -ne $s.baseline){
  if(!$s.ContainsKey('acceptIntent')){throw 'HEAD изменился без accept intent: сохранена неоднозначность, автоматическая приёмка запрещена.'}
  $parents=(G @('rev-list','--parents','-n','1',$head)).Split(' ')
  $ev=[IO.File]::ReadAllText((Join-Path $script:Runs "$($s.id)/review.md"))
  if($parents.Count -ne 2 -or $parents[1] -ne $s.baseline -or (G @('rev-parse',"$head^{tree}")) -ne $s.acceptIntent.tree -or (Hash-Text $ev) -ne $s.review.evidenceHash){throw 'Коммит не совпал с intent/tree/evidence; владелец и файлы сохранены.'}
  $files=@((G @('diff-tree','--no-commit-id','--name-only','-r','-z',$head)).Split([char]0,[StringSplitOptions]::RemoveEmptyEntries));foreach($file in $files){if($file -cnotin $s.files){throw 'Recovered commit выходит за scope.'}}
  Assert-Clean;$s.commit=$head;$s.status='accepted';Event $s 'accepted' "Восстановлен точный принятый commit $head";Save-Integration $s 'accepted';Clear-Active $s;return 'Mapping восстановлена без второго commit.'
 }
 if($m.phase -eq 'intent'){
  Assert-Clean;throw 'Сбой до применения: intent сохранён. Явно reject (без потери данных), повтор не применяет cherry-pick вслепую.'
 }
 Assert-NoUnmerged
 # Once applying has begun, only inspect the saved tree. Never replay cherry-pick.
 Normalize-IntegrationIndex $s;$scope=Assert-Scope $s
 if($m.phase -eq 'applying' -and !$scope.files.Count -and $s.sourceCommit){throw 'Нет доказательства завершения применения source: пустое дерево после applying неоднозначно; owner сохранён, нужен явный разбор/reject.'}
 $s.transferFingerprint=$scope.fingerprint;$s.status='awaiting-review';$s.review=$null;Event $s 'recovered' 'Перенос сохранён после сбоя; требуется fresh review';Save-Integration $s 'awaiting-review';$s.id
}
function Begin-Publication {
 Assert-Coordinator;Ensure-Registry;$gate=Coordinator-Gate
 try{
  $r=Read-Registry
  if($r.owner){
   if($r.owner.kind -ne 'publication'){throw 'Публикация запрещена до приёмки/отклонения интеграции.'}
   if(Process-Alive $r.owner){throw 'Другой владелец публикации ещё работает.'}
  }
  $r.owner=@{kind='publication';attemptId='publication';pid=$PID;processStarted=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');time=[datetime]::UtcNow.ToString('o')};Save-Registry $r
 }finally{$gate.Dispose()}
}
function Complete-Publication {
 $gate=Coordinator-Gate
 try{$r=Read-Registry;if(!$r.owner -or $r.owner.kind -ne 'publication' -or $r.owner.pid -ne $PID){throw 'Владелец публикации изменился.'};$r.owner=$null;Save-Registry $r}finally{$gate.Dispose()}
}
function Sync-PublicationMappings {
 if(!(Test-Path -LiteralPath (Registry-Path))){return};$p=Read-Json (Join-Path $script:Runs 'publication.json');$gate=Coordinator-Gate
 try{
  $r=Read-Registry
  foreach($m in $r.integrations.Values){if($m.phase -ne 'accepted' -or !$m.integratedAcceptedCommit){continue}
   if((Git @('merge-base','--is-ancestor',$m.integratedAcceptedCommit,$p.commit) -AllowFailure).Code -eq 0){$m.pushed=$p.pushed;$m.deployed=$p.deployed;$m.publicationCommit=$p.commit}
  };Save-Registry $r
 }finally{$gate.Dispose()}
}

function Read-SharedText([string]$Path) {
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));$reader=[IO.StreamReader]::new($stream,$script:Utf8)
 try{$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}
}
function Monitor-ObservationError([string]$Root,[string]$TaskId,[string]$AttemptId,[string]$Details,[string]$Log) {
 $id=Hash-Text "$Root/$TaskId/$AttemptId/$Details/$Log"
 if(!(Get-Variable -Name MonitorErrorTimes -Scope Script -ErrorAction SilentlyContinue)){$script:MonitorErrorTimes=@{}}
 if(!$script:MonitorErrorTimes.ContainsKey($id)){$script:MonitorErrorTimes[$id]=[datetime]::UtcNow.ToString('o')}
 $brief=if($Details.Length -gt 420){$Details.Substring(0,420)+'…'}else{$Details}
 @{time=$script:MonitorErrorTimes[$id];type='error';details="$brief; полный журнал: $Log";root=$Root;taskId=$TaskId;attemptId=$AttemptId;eventId=$id}
}
function Read-MonitorSnapshot {
 $roots=@(@{root=$script:Repo;taskId=$null;mapping=$null});$runs=@();$events=@();$stages=@();$pubs=@()
 $registryFile=Join-Path $script:Runs 'coordinator/registry.json'
 if(Test-Path -LiteralPath $registryFile){
  try{$registry=Read-Json $registryFile;foreach($t in $registry.tasks.Values){$roots+=@{root=$t.workerRepo;taskId=$t.taskId;mapping=$registry.integrations}}}
  catch{$events+=Monitor-ObservationError $script:Repo 'coordinator' 'registry' "Ошибка реестра: $_" $registryFile}
 }
 foreach($entry in $roots){
  $root=$entry.root;$local=Join-Path $root '.codex-runs'
  try{
   if(!(Test-Path -LiteralPath $root)){throw "Рабочая копия отсутствует: $root"}
   if(!(Test-Path -LiteralPath $local)){continue}
   foreach($dir in Get-ChildItem -LiteralPath $local -Directory|Where-Object {$_.Name -match '^\d{8}T\d{9}Z-[a-f0-9]{8}$'}){
    try{
     $file=Join-Path $dir.FullName 'state.json';if(!(Test-Path -LiteralPath $file)){throw 'Отсутствует state.json'};$s=Read-Json $file;if(!$s){throw 'Пустой state.json'}
     $s.root=$root;$s.taskId=if($s.ContainsKey('taskId')){$s.taskId}else{$entry.taskId};$s.attemptId=$s.id
     if($entry.mapping){$key=Integration-Key $entry.taskId $s.id;if($entry.mapping.ContainsKey($key)){$m=$entry.mapping[$key];$s.sourceCommit=$m.sourceCommit;$s.integratedAcceptedCommit=$m.integratedAcceptedCommit;$s.mainBaseline=$m.mainBaseline;$s.integrationStatus=$m.phase;$s.pushed=$m.pushed;$s.deployed=$m.deployed}}
     $runs+=$s
     $log=Join-Path $dir.FullName 'events.jsonl';if(Test-Path -LiteralPath $log){
      $raw=Read-SharedText $log;$lines=$raw.Split("`n");for($i=0;$i -lt $lines.Length-1;$i++){if(!$lines[$i].Trim()){continue};try{$e=$lines[$i]|ConvertFrom-Json -AsHashtable;$e.root=$root;$e.taskId=$s.taskId;$e.attemptId=$s.id;$e.lineIndex=$i;if($e.type -match 'error|failed|conflict|interrupted' -and $e.details.Length -gt 600){$e.details=$e.details.Substring(0,420)+"…; полный журнал: $log"};$events+=$e}catch{$events+=Monitor-ObservationError $root $s.taskId $s.id "Ошибка строки $i JSONL: $_" $log}}
     }
    }catch{$events+=Monitor-ObservationError $root $entry.taskId $dir.Name "Ошибка задачи $($entry.taskId)/$($dir.Name): $_" $file}
   }
   $stagePath=Join-Path $local 'stages.jsonl';if(Test-Path -LiteralPath $stagePath){$raw=Read-SharedText $stagePath;$lines=$raw.Split("`n");for($i=0;$i -lt $lines.Length-1;$i++){if(!$lines[$i].Trim()){continue};try{$e=$lines[$i]|ConvertFrom-Json -AsHashtable;$e.root=$root;if(!$e.ContainsKey('taskId')){$e.taskId=$entry.taskId};if(!$e.ContainsKey('attemptId')){$e.attemptId='stages'};$e.lineIndex=$i;$stages+=$e}catch{$events+=Monitor-ObservationError $root $entry.taskId 'stages' "Ошибка строки $i JSONL: $_" $stagePath}}}
   $pubPath=Join-Path $local 'publication.json';if(Test-Path -LiteralPath $pubPath){$p=Read-Json $pubPath;$p.root=$root;$p.taskId=if($entry.taskId){$entry.taskId}else{'publication'};$p.attemptId='publication';$p.time=(Get-Item -LiteralPath $pubPath).LastWriteTimeUtc.ToString('o');$pubs+=$p}
  }catch{$events+=Monitor-ObservationError $root $entry.taskId 'registry' "Ошибка задачи $($entry.taskId): $_" $local}
 }
 @{Runs=$runs;Events=$events;Stages=$stages;Publications=$pubs;Roots=@($roots|ForEach-Object {$_.root})}
}
function Show-Monitor([datetime]$Now=[datetime]::UtcNow) {
 $snapshot=Read-MonitorSnapshot
 Format-WorkflowMonitorSummary -Runs $snapshot.Runs -Stages $snapshot.Stages -Publications $snapshot.Publications -Now $Now
 $records=@(Get-WorkflowMonitorRecords -Runs $snapshot.Runs -Events $snapshot.Events -Stages $snapshot.Stages -Publications $snapshot.Publications)
 $cursor=New-WorkflowMonitorCursor
 Write-WorkflowMonitorRecords -Records @(Select-WorkflowMonitorNewRecords -Records $records -Cursor $cursor -InitialSkipFallback)
}
function Watch-Monitor {
 if(-not ('CodexMonitorChangesV2' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Collections.Generic;
public sealed class CodexMonitorChangesV2 : IDisposable {
 readonly Dictionary<string,FileSystemWatcher> watchers = new Dictionary<string,FileSystemWatcher>(StringComparer.OrdinalIgnoreCase);
 readonly AutoResetEvent changed = new AutoResetEvent(false);
 readonly object gate = new object(); bool disposed;
 public void Add(string path) {
  if(!Directory.Exists(path) || watchers.ContainsKey(path)) return;
  var watcher = new FileSystemWatcher(path) { IncludeSubdirectories=true, NotifyFilter=NotifyFilters.FileName|NotifyFilters.DirectoryName|NotifyFilters.LastWrite|NotifyFilters.Size,InternalBufferSize=65536 };
  watcher.Changed+=Wake;watcher.Created+=Wake;watcher.Deleted+=Wake;watcher.Renamed+=Wake;watcher.Error+=Overflow;
  watchers.Add(path,watcher);watcher.EnableRaisingEvents=true;
 }
 void Wake(object sender,FileSystemEventArgs args){Signal();}
 void Overflow(object sender,ErrorEventArgs args){Signal();}
 void Signal(){lock(gate){if(!disposed)changed.Set();}}
 public bool Wait(int milliseconds){return changed.WaitOne(milliseconds);}
 public void Dispose(){lock(gate){disposed=true;}foreach(var watcher in watchers.Values)watcher.Dispose();changed.Dispose();}
}
'@
 }
 $changes=[CodexMonitorChangesV2]::new();$cursor=New-WorkflowMonitorCursor;$initial=$true
 try{
  $changes.Add($script:Runs)
  while($true){
   # Arm new worker roots before rereading: writes during initial snapshot stay signalled.
   $snapshot=Read-MonitorSnapshot;foreach($root in $snapshot.Roots){$local=Join-Path $root '.codex-runs';if(Test-Path -LiteralPath $local){$changes.Add($local)}};$snapshot=Read-MonitorSnapshot
   if($initial){"Монитор Codex";Format-WorkflowMonitorSummary -Runs $snapshot.Runs -Stages $snapshot.Stages -Publications $snapshot.Publications;$initial=$false}
   $records=@(Get-WorkflowMonitorRecords -Runs $snapshot.Runs -Events $snapshot.Events -Stages $snapshot.Stages -Publications $snapshot.Publications)
   Write-WorkflowMonitorRecords -Records @(Select-WorkflowMonitorNewRecords -Records $records -Cursor $cursor -InitialSkipFallback)
   while(!$changes.Wait(1000)){}
   $burst=[Diagnostics.Stopwatch]::StartNew();while($changes.Wait(150) -and $burst.ElapsedMilliseconds -lt 750){}
  }
 }finally{$changes.Dispose()}
}

function Invoke-Workflow {
 [CmdletBinding()]param([string]$Command='status',[string]$Repo,[string]$CoordinatorRepo,[string]$TaskId,[string]$WorkerRepo,[string]$WorkerBranch,[string]$MaxWorkers='2',[string]$Id,[string]$TaskFile,[string[]]$Files,[string]$Model='sol',[string]$Effort='medium',[switch]$AllowMax,[string]$Evidence,[string]$Message,[string]$Baseline,[string]$StatusFile,[string]$Stage,[string]$StageAction='start',[switch]$Once,[switch]$CompleteItem,[int]$DeployTimeoutSeconds=300,[switch]$TestMode,[string]$TestCli,[switch]$TestSkipDeployment)
 if(!$Repo){$Repo=Split-Path $PSScriptRoot -Parent};Init-Repo $Repo;Init-Coordination $CoordinatorRepo $TaskId $Command
 if($Command -in @('status','monitor')){if($Command -eq 'status' -or $Once){"Монитор Codex";Show-Monitor}else{Watch-Monitor};return}
 # Lock order for every mutating command is local operation.lock, then short coordinator registry.lock.
 # A worker runner holds neither coordinator gate nor local operation.lock while executing CLI.
 $lock=Acquire-Operation
 try {
  Init-Coordination $CoordinatorRepo $TaskId $Command
  switch($Command){
   'register-worker' {Register-Worker $TaskId $WorkerRepo $WorkerBranch}
   'configure' {Configure-Workers $MaxWorkers}
   'integrate' {Integrate-Worker $TaskId $Id}
   'run' {Start-Run $TaskFile $Files $Model $Effort $AllowMax $TestMode $TestCli $null $null}
   'rerun' {Start-Run $TaskFile $Files $Model $Effort $AllowMax $TestMode $TestCli (Load-State $Id) $Evidence}
   'manual' {Manual-Run $TaskFile $Files $Baseline}
   'review' {Review-Run (Load-State $Id) $Evidence}
   'accept-step' {Accept-Run (Load-State $Id) $Message}
   'reject' {
    $s=Load-State $Id;Require-Owner $s;Assert-IntegrationOwner $s;Assert-CLIStopped $s
    if($s.status -in @('starting','running')){throw 'Сначала дождитесь исполнителя или recover.'}
    if($s.kind -eq 'integration'){$scope=Assert-Scope $s -AllowOwnStaged}
    Recovery-Evidence $s $Evidence;$s.status='rejected';Event $s 'rejected' 'Правки сохранены; автоматического отката нет'
    if($s.kind -eq 'integration'){Save-Integration $s 'rejected'};Clear-Active $s
   }
   'recover' {
    if((Test-Path -LiteralPath (Registry-Path)) -and !$script:WorkerBinding){$r=Read-Registry;if($r.owner -and $r.owner.kind -eq 'integration'){Recover-Integration $TaskId $Id;break};if($r.owner -and $r.owner.kind -eq 'publication'){if(Process-Alive $r.owner){throw 'Публикация ещё работает.'};throw 'Публикация сохранена; повторите publish для продолжения того же commit/archive.'}}
    $a=Active;if(!$a){Recover-OrphanSlot $Id;break};if($Id -and $a.id -ne $Id){throw 'recover адресован другому запуску.'};$s=Load-State $a.id
    if(!$s.pid -and $s.status -in @('starting','running') -and $s.ContainsKey('launchPhase') -and $s.launchPhase -eq 'prepared'){Recover-OrphanSlot $s.id;break}
    if(!$s.pid -and $s.status -in @('starting','running')){throw 'PID ещё не зарегистрирован: завершение не подтверждено. Требуется проверка запуска в обычной Windows-сессии.'}
    if($s.kind -eq 'integration' -and $s.status -in @('accepted','accepted-no-changes')){$r=Read-Registry;$m=$r.integrations[(Integration-Key $s.taskId $s.sourceAttemptId)];$expected=if($s.commit){$s.commit}else{$s.baseline};if(!$r.owner -and $m.phase -eq $s.status -and $m.integratedAcceptedCommit -eq $s.commit -and (G @('rev-parse','HEAD')) -eq $expected){Assert-Clean;Clear-Active $s;'Принятая mapping подтверждена, active освобождён.';break}}
    if(Process-Alive $s){throw 'Runner ещё работает.'}
    if($s.ContainsKey('cliPid') -and (Process-Alive @{pid=$s.cliPid;processStarted=$s.cliProcessStarted})){throw 'CLI процесс ещё работает; сначала дождитесь его/остановите явно.'}
    if($s.status -in @('starting','running')){$s.status='interrupted';$s.recoveryRequired=$true;$s.ended=[datetime]::UtcNow.ToString('o');Event $s 'interrupted' 'Runner завершился без подтверждённого результата; правки и блокировка сохранены'}else{'Запуск уже завершён; нужна review или reject.'}
    if($script:WorkerBinding){$gate=Coordinator-Gate;try{$r=Read-Registry;Refresh-Reservations $r;Save-Registry $r}finally{$gate.Dispose()}}
   }
   'publish' {Begin-Publication;try{Publish-Item $Message $CompleteItem $TestMode $TestSkipDeployment $DeployTimeoutSeconds;Sync-PublicationMappings;Complete-Publication}catch{if(Test-Path -LiteralPath (Join-Path $script:Runs 'publication.json')){Sync-PublicationMappings};throw}}
   'update-status' {if($script:WorkerBinding){throw 'Worker не публикует состояние проекта.'};Update-ProjectStatus $StatusFile}
   'record-stage' {if(!$Stage -or !$Message){throw 'Нужны -Stage и -Message.'};$route=Get-Route $Model $Effort -AllowMax:$AllowMax;$e=@{time=[datetime]::UtcNow.ToString('o');taskId=$script:TaskId;attemptId=$Id;stage=$Stage;action=$StageAction;model=$route.model;effort=$route.effort;details=$Message};[IO.File]::AppendAllText((Join-Path $script:Runs 'stages.jsonl'),(($e|ConvertTo-Json -Compress)+"`n"),$script:Utf8)}
   default {throw 'Неизвестная команда.'}
  }
 }finally{$lock.Dispose()}
}
Export-ModuleMember -Function Invoke-Workflow,Invoke-Worker
