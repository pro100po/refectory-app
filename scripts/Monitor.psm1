Set-StrictMode -Version Latest

# The monitor only formats observations. It never changes a run or its journals.
function Read-MonitorField($Value,[string[]]$Names,$Default='') {
 foreach($name in $Names){
  if($null -eq $Value){continue}
  if($Value -is [Collections.IDictionary]){if($Value.Contains($name) -and $null -ne $Value[$name] -and "$($Value[$name])" -ne ''){return $Value[$name]}}
  elseif($Value.PSObject.Properties[$name] -and $null -ne $Value.$name -and "$($Value.$name)" -ne ''){return $Value.$name}
 }
 return $Default
}
function ConvertTo-MonitorLine([string]$Text) {
 # Keep full readable text, but never replay terminal escape/control commands.
 $Text=$Text -replace '\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)','' -replace '\x1b\[[0-?]*[ -/]*[@-~]',''
 return ($Text -replace '[\x00-\x20\x7f-\x9f]+',' ').Trim()
}
function Limit-MonitorLabel([string]$Text,[int]$Length) {
 $Text=ConvertTo-MonitorLine $Text
 $parts=[Globalization.StringInfo]::ParseCombiningCharacters($Text)
 if($parts.Count -le $Length){return $Text}
 return $Text.Substring(0,$parts[$Length-1])+'…'
}
function Get-MonitorIdentity($Value) {
 $task="$(Read-MonitorField $Value @('taskId','taskKey'))"
 $attempt="$(Read-MonitorField $Value @('attemptId','runId','id'))"
 $root="$(Read-MonitorField $Value @('root','taskRoot','repo'))"
 if(!$task){$task=$attempt};if(!$task){$task='проект'}
 @{root=$root;task=$task;attempt=$attempt}
}
function Get-MonitorHash([object[]]$Parts) {
 $text=ConvertTo-Json -InputObject @($Parts) -Compress -Depth 10
 [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text)))
}
function Get-MonitorLevel([string]$Type,[string]$Action='') {
 if($Type -match '(?i)error|failed|rejected|invalid|conflict|interrupted'){return 'error'}
 if($Type -match '(?i)await|waiting|warning|superseded|recover|pending'){return 'warning'}
 if($Type -match '(?i)accepted|success|completed|deployed|pushed|integrated|reviewed' -or $Action -eq 'end'){return 'success'}
 if($Type -match '(?i)start|running|prepared|info' -or $Action -eq 'start'){return 'info'}
 return 'service'
}
function Get-MonitorStatus([string]$Status) {
 $labels=@{prepared='Подготовлен';starting='Запуск';running='Исполнитель работает';'awaiting-review'='Ожидает проверки';reviewed='Проверен';accepted='Принят и сохранён';'accepted-no-changes'='Принят без правок';failed='Ошибка';interrupted='Прерван';rejected='Отклонён, правки сохранены';superseded='Заменён новым запуском';invalid='Регистрация отклонена';integrated='Включён в основную версию'}
 if($labels.ContainsKey($Status)){return $labels[$Status]};return $Status
}
function Get-MonitorTime($Value) {
 $result=[datetimeoffset]::MinValue
 if([datetimeoffset]::TryParse("$Value",[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$result)){return $result}
 return [datetimeoffset]::MinValue
}

function Get-WorkflowMonitorRecords {
 [CmdletBinding()]param([object[]]$Runs=@(),[object[]]$Events=@(),[object[]]$Stages=@(),[object[]]$Publications=@())
 $records=[Collections.Generic.List[object]]::new();$sequence=0
 $states=@(foreach($run in $Runs){
  $scope=Get-MonitorIdentity $run
  $status="$(Read-MonitorField $run @('status'))";$last="$(Read-MonitorField $run @('lastEvent'))"
  $errorText="$(Read-MonitorField $run @('error'))";$commit="$(Read-MonitorField $run @('commit'))"
  $pushed=Read-MonitorField $run @('pushed') $false;$deployed=Read-MonitorField $run @('deployed') $false
  $key=Get-MonitorHash @('state',$scope.root,$scope.task,$scope.attempt,$status,$last,$errorText,$commit,$pushed,$deployed)
  @{Run=$run;Scope=$scope;Status=$status;Last=$last;Error=$errorText;Commit=$commit;Pushed=$pushed;Deployed=$deployed;Id=$key;Matched=$false}
 })
 foreach($source in @(@{kind='event';items=$Events},@{kind='stage';items=$Stages},@{kind='publication';items=$Publications})){
  foreach($entry in $source.items){
   if($null -eq $entry){continue}
   $identity=Get-MonitorIdentity $entry
   $time="$(Read-MonitorField $entry @('time','updated','deployChecked'))"
   $type="$(Read-MonitorField $entry @('type','status') $source.kind)"
   $action="$(Read-MonitorField $entry @('action'))"
   $stage="$(Read-MonitorField $entry @('stage'))"
   $message="$(Read-MonitorField $entry @('details','message','lastEvent'))"
   $title=''
   foreach($state in $states){if($state.Scope.root -ceq $identity.root -and $state.Scope.task -ceq $identity.task -and $state.Scope.attempt -ceq $identity.attempt){$title="$(Read-MonitorField $state.Run @('title','task'))";break}}
   $aliases=@()
   if($source.kind -eq 'event'){
    foreach($state in $states){
     if($state.Scope.root -ceq $identity.root -and $state.Scope.task -ceq $identity.task -and $state.Scope.attempt -ceq $identity.attempt -and $state.Last -and $state.Last -ceq "$type : $message"){$state.Matched=$true;$aliases+=$state.Id}
    }
   }
   if($source.kind -eq 'stage'){
    $verb=if($action -eq 'start'){'Начат этап'}elseif($action -eq 'end'){'Завершён этап'}else{'Этап'}
    $model="$(Read-MonitorField $entry @('model'))";$effort="$(Read-MonitorField $entry @('effort'))"
    $route=if($model -and $action -ne 'end'){" ($model / $effort)"}else{''}
    $message="${verb}: $stage$route. $message"
   }elseif($source.kind -eq 'publication'){
    $errorText="$(Read-MonitorField $entry @('error'))"
    $commit="$(Read-MonitorField $entry @('commit'))"
    $pushed=[bool](Read-MonitorField $entry @('pushed') $false);$deployed=[bool](Read-MonitorField $entry @('deployed') $false)
    $type=if($errorText){'error'}elseif($deployed){'deployed'}elseif($pushed){'pushed'}else{'publication'}
    $message=if($errorText){"Ошибка публикации: $errorText"}elseif($deployed){"Сайт обновлён. Коммит $commit"}elseif($pushed){"Отправлено на GitHub. Коммит $commit. Развёртывание: $(Read-MonitorField $entry @('deployStatus') 'не подтверждено')"}else{"Публикация: $(Read-MonitorField $entry @('phase') 'подготовка'). Коммит $commit"}
   }elseif(!$message){$message=Get-MonitorStatus $type}
   $explicitId=Read-MonitorField $entry @('eventId')
   $eventKey=Read-MonitorField $entry @('eventId','lineIndex')
   # Keep a stable line/event discriminator AND its content: atomic replacement
   # can legitimately change an already observed offset without appending.
   $eventKey=Get-MonitorHash @($eventKey,$(if("$explicitId" -eq ''){$time}else{''}),$type,$action,$stage,$message)
   # Publication state may change without a timestamp; content is its version.
   if($source.kind -eq 'publication'){$eventKey=Get-MonitorHash @($message,(Read-MonitorField $entry @('phase')),(Read-MonitorField $entry @('commit')),(Read-MonitorField $entry @('pushed') $false),(Read-MonitorField $entry @('deployed') $false),(Read-MonitorField $entry @('deployStatus')),(Read-MonitorField $entry @('error')))}
   $key=Get-MonitorHash @($source.kind,$identity.root,$identity.task,$identity.attempt,$stage,$eventKey)
   $records.Add([pscustomobject]@{Id=$key;Aliases=@($aliases);IsFallback=$false;Time=$time;SortTime=(Get-MonitorTime $time);Sequence=$sequence;Root=$identity.root;Task=$identity.task;Attempt=$identity.attempt;Title=$title;Source=$source.kind;Stage=$stage;Type=$type;Message=(ConvertTo-MonitorLine $message);Level=(Get-MonitorLevel $type $action)});$sequence++
  }
 }
 foreach($state in $states){
  if($state.Matched){continue}
  $time="$(Read-MonitorField $state.Run @('updated','lastEventTime','ended','started'))"
  $details=if($state.Last){$state.Last}else{Get-MonitorStatus $state.Status}
  $message="Состояние: $details"
  if($state.Error){$message+=". Ошибка: $($state.Error)"}
  if($state.Commit){$message+=". Сохранено: $($state.Commit)"}
  if($state.Pushed){$message+='. Отправлено на GitHub'}
  if($state.Deployed){$message+='. Сайт обновлён'}
  $records.Add([pscustomobject]@{Id=$state.Id;Aliases=@();IsFallback=$true;Time=$time;SortTime=(Get-MonitorTime $time);Sequence=$sequence;Root=$state.Scope.root;Task=$state.Scope.task;Attempt=$state.Scope.attempt;Title=(Read-MonitorField $state.Run @('title','task'));Source='state';Stage='';Type=$state.Status;Message=(ConvertTo-MonitorLine $message);Level=(Get-MonitorLevel $state.Status)});$sequence++
 }
 $records | Sort-Object SortTime,Sequence
}

function New-WorkflowMonitorCursor {
 [pscustomobject]@{Initialized=$false;Seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)}
}
function Select-WorkflowMonitorNewRecords {
 [CmdletBinding()]param([object[]]$Records=@(),[Parameter(Mandatory)]$Cursor,[ValidateRange(0,10000)][int]$InitialLimit=12,[switch]$InitialSkipFallback)
 $fresh=[Collections.Generic.List[object]]::new()
 foreach($record in @($Records|Sort-Object SortTime,Sequence)){
  $ids=@([string]$record.Id)+@(Read-MonitorField $record @('Aliases') @())
  $seen=$false;foreach($id in $ids){if($Cursor.Seen.Contains([string]$id)){$seen=$true}}
  foreach($id in $ids){[void]$Cursor.Seen.Add([string]$id)}
  $type="$(Read-MonitorField $record @('Type'))"; $message="$(Read-MonitorField $record @('Message'))"
  $noise=(($type -in @('cli-event','cli-unparsed')) -and $message -notmatch '(?i)error|fail|ошиб|сбой') -or ($type -eq 'reviewed' -and $message -match '(?i)отпечатк')
  if(!$seen -and !$noise){$fresh.Add($record)}
 }
 if(!$Cursor.Initialized){$Cursor.Initialized=$true;if($InitialLimit -gt 0){$fresh|Where-Object {!$InitialSkipFallback -or !(Read-MonitorField $_ @('IsFallback') $false)}|Select-Object -Last $InitialLimit};return}
 $fresh
}
function Format-WorkflowMonitorRecord {
 [CmdletBinding()]param([Parameter(Mandatory,ValueFromPipeline)]$Record)
 process {
  $time=Get-MonitorTime $Record.Time
  $stamp=if($time -eq [datetimeoffset]::MinValue){'--:--:--'}else{$time.ToLocalTime().ToString('HH:mm:ss')}
  $source="$(Read-MonitorField $Record @('Source'))"
  $title="$(Read-MonitorField $Record @('Title'))"
  if($title -match '^\d{8}T\d{9}Z-[a-fA-F0-9]{8}$'){$title=''}else{$title=$title -replace '^#+\s+',''}
  $attempt="$(Read-MonitorField $Record @('Attempt'))"
  $task="$(Read-MonitorField $Record @('Task'))"
  $label=if($source -eq 'publication'){'Публикация'}elseif($source -eq 'stage'){'Этап'}elseif($title){Limit-MonitorLabel $title 50}elseif($attempt -match '([a-fA-F0-9]{8})$'){"Задача $($Matches[1])"}elseif($task -match '([a-fA-F0-9]{8})$'){"Задача $($Matches[1])"}else{Limit-MonitorLabel $task 18}
  $message=ConvertTo-MonitorLine $Record.Message
  if($source -eq 'state' -and $message -match '^Состояние: (cli-event|cli-unparsed|reviewed) : '){$message=$message -replace '^Состояние: (cli-event|cli-unparsed|reviewed) : [^.]*',('Состояние: '+(Get-MonitorStatus "$(Read-MonitorField $Record @('Type'))"))}
  $message=[regex]::Replace($message,'(?<![a-fA-F0-9])[a-fA-F0-9]{40}(?![a-fA-F0-9])',{param($m) $m.Value.Substring(0,7)})
  if($source -eq 'publication'){$message=$message -replace 'Публикация: prepared','Подготовка публикации' -replace 'Развёртывание: not-checked','проверка сайта ожидается' -replace 'Развёртывание: pending','проверка сайта ожидается'}
  "$stamp [$label] $message"
 }
}
function Write-WorkflowMonitorRecords {
 [CmdletBinding()]param([object[]]$Records=@(),[switch]$Plain)
 $colors=@{info='Cyan';success='Green';warning='Yellow';error='Red';service='Gray'}
 foreach($record in $Records){
  $line=Format-WorkflowMonitorRecord $record
  if($Plain -or [Console]::IsOutputRedirected){Write-Output $line}
  else{$color=if($colors.ContainsKey("$($record.Level)")){$colors["$($record.Level)"]}else{'Gray'};Write-Host $line -ForegroundColor $color}
 }
}
function Format-WorkflowMonitorSummary {
 [CmdletBinding()]param([object[]]$Runs=@(),[object[]]$Stages=@(),[object[]]$Publications=@(),[datetime]$Now=[datetime]::UtcNow,[ValidateRange(0,100)][int]$CompletedLimit=0)
 $terminal=@('accepted','accepted-no-changes','rejected','failed','interrupted','superseded','invalid','integrated')
 $ordered=@($Runs|Sort-Object {Get-MonitorTime (Read-MonitorField $_ @('started'))} -Descending)
 $active=@($ordered|Where-Object {(Read-MonitorField $_ @('status')) -notin $terminal})
 $complete=@($ordered|Where-Object {(Read-MonitorField $_ @('status')) -in $terminal})
 $stamp=$Now.ToLocalTime().ToString('HH:mm:ss')
 "$stamp [монитор] Активных задач: $($active.Count)."
 foreach($run in @($active)+@($complete|Select-Object -First $CompletedLimit)){
  $identity=Get-MonitorIdentity $run
  $start=Get-MonitorTime (Read-MonitorField $run @('started'))
  $end=Get-MonitorTime (Read-MonitorField $run @('ended'))
  if($end -eq [datetimeoffset]::MinValue){$end=[datetimeoffset]$Now.ToUniversalTime()}
  $duration=if($start -ne [datetimeoffset]::MinValue){[Math]::Max(0,[int]($end-$start).TotalSeconds)}else{0}
  $elapsed=[timespan]::FromSeconds($duration)
  $clock=if($start -eq [datetimeoffset]::MinValue){'не указано'}else{$start.ToLocalTime().ToString('MM-dd HH:mm:ss')}
  $title=ConvertTo-MonitorLine "$(Read-MonitorField $run @('title','task'))"
  $route="$(Read-MonitorField $run @('model') 'модель не указана') / $(Read-MonitorField $run @('effort') 'уровень не указан')"
  $status=Get-MonitorStatus "$(Read-MonitorField $run @('status') 'не указан')"
  $record=[pscustomobject]@{Time=$Now.ToString('o');Task=$identity.task;Attempt=$identity.attempt;Title=$title;Source='state';Message="$status. $route. Начало: $clock; длительность: $([int]$elapsed.TotalHours)ч $($elapsed.Minutes)м $($elapsed.Seconds)с."}
  Format-WorkflowMonitorRecord $record
  $integration="$(Read-MonitorField $run @('integrationStatus'))"
  $commit="$(Read-MonitorField $run @('commit'))"
  if($commit -or $integration){$record.Message="Сохранение: $(if($commit){$commit}else{'нет коммита'}); включение: $(if($integration){$integration}else{'не зарегистрировано'}); GitHub: $(if(Read-MonitorField $run @('pushed') $false){'отправлено'}else{'не отправлено'}); сайт: $(if(Read-MonitorField $run @('deployed') $false){'обновлён'}else{'не подтверждён'}).";Format-WorkflowMonitorRecord $record}
 }
 if($Publications.Count){
  $lastPublication=@($Publications|Sort-Object {Get-MonitorTime (Read-MonitorField $_ @('time','deployChecked','updated'))}|Select-Object -Last 1)
  foreach($record in @(Get-WorkflowMonitorRecords -Publications $lastPublication)){$record.Time=$Now.ToString('o');$record.Message='Последняя публикация. '+$record.Message;Format-WorkflowMonitorRecord $record}
 }
 if(!$Runs.Count -and !$Stages.Count -and !$Publications.Count){"$stamp [монитор] Запусков пока нет. Исполнение и публикация не запускались."}
}
Export-ModuleMember -Function Get-WorkflowMonitorRecords,New-WorkflowMonitorCursor,Select-WorkflowMonitorNewRecords,Format-WorkflowMonitorRecord,Write-WorkflowMonitorRecords,Format-WorkflowMonitorSummary
