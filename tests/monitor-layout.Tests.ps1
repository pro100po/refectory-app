param([string]$Module=(Join-Path $PSScriptRoot '../scripts/Monitor.psm1'))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module $Module -Force
function Assert($Condition,$Message){if(!$Condition){throw $Message};"PASS: $Message"}
function Event($Task,$Attempt,$Root,$Index,$Message,$Type='running'){
 @{root=$Root;taskId=$Task;attemptId=$Attempt;lineIndex=$Index;time='2026-11-10T09:00:00Z';type=$Type;details=$Message}
}
$longText=('Проверка русского текста, пути C:\Работа\кухня и Unicode 漢字 👩‍💻 é. '*60).Trim()
$events=@((Event 'кухня' 'attempt-1' 'C:\one' 0 'Исполнитель запущен' 'starting'),(Event 'кухня' 'attempt-1' 'C:\one' 1 $longText),(Event 'кухня' 'attempt-1' 'C:\two' 0 'Вторая рабочая копия' 'running'),(Event 'кухня' 'attempt-2' 'C:\one' 0 'Повторный запуск' 'starting'))
$stages=@(
 @{root='C:\one';taskId='кухня';attemptId='attempt-1';lineIndex=0;time='2026-11-10T09:01:00Z';stage='Проверка';action='start';model='gpt-6.1-sol';effort='high';details='Первая проверка'},
 @{root='C:\one';taskId='кухня';attemptId='attempt-2';lineIndex=1;time='2026-11-10T09:01:00Z';stage='Проверка';action='end';model='gpt-6.1-sol';effort='medium';details='Другая попытка завершена'}
)
$records=@(Get-WorkflowMonitorRecords -Events $events -Stages $stages)
Assert ($records.Count -eq 6) 'task + attempt + root + stage stay distinct'
Assert (@($records.Id|Sort-Object -Unique).Count -eq 6) 'record identity never mixes separate roots and attempts'
Assert ($records[0].Message -eq 'Исполнитель запущен' -and $records[1].Message -eq $longText) 'equal timestamps preserve source order'
$line=Format-WorkflowMonitorRecord $records[1]
Assert ($line.Contains($longText)) 'long Unicode event text remains complete for normal terminal wrapping'
Assert ($line -match '^\d{2}:\d{2}:\d{2} \[кухня\] ') 'plain log has local time and short task label'
$realIds=@(Get-WorkflowMonitorRecords -Events @((Event 'кухня' '20261110T090000000Z-12345678' 'a' 0 'Первая попытка'),(Event 'кухня' '20261110T090000000Z-abcdef12' 'a' 0 'Вторая попытка')))
$realLines=@($realIds|Format-WorkflowMonitorRecord)
Assert ($realLines[0].Contains('[Задача 12345678]') -and $realLines[1].Contains('[Задача abcdef12]')) 'real timestamp attempt IDs display distinct GUID suffixes'
foreach($width in @(40,80,120)){
 # Terminals wrap the same ordinary line; the formatter never creates columns.
 $rendered=($records|Format-WorkflowMonitorRecord|Out-String -Width $width)
 Assert ($rendered.Contains($longText)) "plain output preserves full event text at width $width"
 Assert ($rendered -notmatch '\x1b|\x08|─|┌|└') "no ANSI, cursor control, or card layout at width $width"
}
$cursor=New-WorkflowMonitorCursor
$first=@(Select-WorkflowMonitorNewRecords -Records $records -Cursor $cursor -InitialLimit 2)
Assert ($first.Count -eq 2 -and $cursor.Seen.Count -eq 6) 'startup emits bounded tail and remembers older events'
Assert (@(Select-WorkflowMonitorNewRecords -Records $records -Cursor $cursor).Count -eq 0) 'unchanged state emits nothing'
$next=@(Get-WorkflowMonitorRecords -Events @($events+(Event 'кухня' 'attempt-1' 'C:\one' 2 'Правка принята' 'accepted')) -Stages $stages)
$added=@(Select-WorkflowMonitorNewRecords -Records $next -Cursor $cursor)
Assert ($added.Count -eq 1 -and $added[0].Message -eq 'Правка принята') 'only newly appended event is emitted'
Assert (@(Select-WorkflowMonitorNewRecords -Records $records -Cursor $cursor).Count -eq 0) 'deleting or rescanning a log never replays old events'
$replacement=@(Get-WorkflowMonitorRecords -Events @((Event 'кухня' 'attempt-1' 'C:\one' 1 'Заменённое событие с тем же offset')))
Assert (@(Select-WorkflowMonitorNewRecords -Records $replacement -Cursor $cursor).Count -eq 1) 'atomic replacement with new content at existing offset remains visible'
$zero=New-WorkflowMonitorCursor
Assert (@(Select-WorkflowMonitorNewRecords -Records $records -Cursor $zero -InitialLimit 0).Count -eq 0 -and $zero.Seen.Count -eq 6) 'zero startup tail still establishes cursor'
$levels=@(Get-WorkflowMonitorRecords -Events @((Event 'x' 'a' 'r' 0 'Запуск' 'starting'),(Event 'x' 'a' 'r' 1 'Принят' 'accepted'),(Event 'x' 'a' 'r' 2 'Ожидание' 'awaiting-review'),(Event 'x' 'a' 'r' 3 'Ошибка' 'failed'),(Event 'x' 'a' 'r' 4 'Журнал' 'note')))
Assert (($levels.Level -join ',') -eq 'info,success,warning,error,service') 'native color levels cover start, success, waiting, failure and service'
$plain=@(Write-WorkflowMonitorRecords -Records $levels -Plain)
Assert ($plain.Count -eq 5 -and ($plain -join "`n") -notmatch '\x1b') 'redirected/plain mode contains ordinary strings without color escapes'
$unsafe=Event '👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻👩‍💻' 'a' 'r' 0 "a`e[31mred`e[0m`r`n b`t c`0 d"
$safe=Format-WorkflowMonitorRecord @(Get-WorkflowMonitorRecords -Events @($unsafe))[0]
Assert ($safe -notmatch '[\x00-\x1f\x7f-\x9f]' -and $safe.EndsWith('ared b c d')) 'terminal controls are stripped and multiline details become a readable single event'
Assert ($safe.Contains('…') -and $safe -notmatch '\uFFFD') 'short Unicode identity uses text elements and remains valid'
$runs=@()
foreach($n in 1..7){$runs+=@{id="done-$n";taskId="done-$n";task="Завершённая $n";status='accepted';model='gpt-6.1-sol';effort='medium';started='2026-11-10T08:00:00Z';ended='2026-11-10T09:00:00Z';commit='abcdef';pushed=$false;deployed=$false}}
foreach($n in 1..2){$runs+=@{id="active-$n";taskId="active-$n";task="Активная $n";status='running';model='gpt-6.1-sol';effort='high';started='2026-11-10T08:00:00Z'}}
$summary=@(Format-WorkflowMonitorSummary -Runs $runs -Now ([datetime]'2026-11-10T10:00:00Z') -CompletedLimit 2)
$text=$summary -join "`n"
Assert ($text.Contains('Активных задач: 2.') -and !$text.Contains('Ещё завершённых задач:')) 'startup summary bounds completed history and counts all tasks'
Assert ((($text.IndexOf('Активная 1') -lt $text.IndexOf('Завершённая')) -and ($text.IndexOf('Активная 2') -lt $text.IndexOf('Завершённая')))) 'active tasks appear before completed tasks'
Assert ($text.Contains('длительность: 2ч 0м 0с') -and $text.Contains('длительность: 1ч 0м 0с')) 'snapshot durations use supplied event time and fixed completed end'
Assert (($summary -join "`n") -eq ((Format-WorkflowMonitorSummary -Runs $runs -Now ([datetime]'2026-11-10T10:00:00Z') -CompletedLimit 2) -join "`n")) 'same snapshot time produces stable summary without ticking'
$before=$events|ConvertTo-Json -Depth 10 -Compress
$null=Get-WorkflowMonitorRecords -Events $events
Assert (($events|ConvertTo-Json -Depth 10 -Compress) -ceq $before) 'formatting never mutates journal observations'
$publications=@(@{root='a';commit='abc';pushed=$true;deployed=$false;deployStatus='pending'},@{root='b';commit='abc';pushed=$true;deployed=$true;deployStatus='built'},@{root='c';commit='abc';error='доступ запрещён'})
$p=@(Get-WorkflowMonitorRecords -Publications $publications)
Assert (($p.Type -join ',') -eq 'pushed,deployed,error') 'push, deployment and publication errors are distinct events'
$defaultSummary=Format-WorkflowMonitorSummary -Runs $runs -Publications $publications
Assert (($defaultSummary -join "`n") -notmatch 'Завершённая' -and ($defaultSummary -join "`n").Contains('Последняя публикация. Ошибка публикации: доступ запрещён')) 'default startup shows active tasks and last publication without completed history'
$state=@{root='C:\one';taskId='кухня';attemptId='attempt-1';status='running';started='2026-11-10T09:00:00Z';lastEvent='starting : Исполнитель запущен';error=$null;commit=$null;pushed=$false;deployed=$false}
$stateOnly=@(Get-WorkflowMonitorRecords -Runs @($state))
Assert ($stateOnly.Count -eq 1 -and $stateOnly[0].Message.Contains('Исполнитель запущен')) 'state-only observations produce a semantic fallback event'
$dedup=New-WorkflowMonitorCursor
$null=Select-WorkflowMonitorNewRecords -Records $stateOnly -Cursor $dedup
$complete=@(Get-WorkflowMonitorRecords -Runs @($state) -Events @($events[0]))
Assert ($complete.Count -eq 1 -and $complete[0].Type -eq 'starting') 'matching raw event replaces fallback in snapshot'
Assert (@(Select-WorkflowMonitorNewRecords -Records $complete -Cursor $dedup).Count -eq 0) 'late complete journal line does not repeat previously shown fallback'
$reverse=New-WorkflowMonitorCursor
$null=Select-WorkflowMonitorNewRecords -Records $complete -Cursor $reverse
Assert (@(Select-WorkflowMonitorNewRecords -Records $stateOnly -Cursor $reverse).Count -eq 0) 'temporary journal read omission does not repeat fallback after raw event'
$state.status='failed';$state.error='Ошибка запуска'
$changed=@(Get-WorkflowMonitorRecords -Runs @($state))
Assert (@(Select-WorkflowMonitorNewRecords -Records $changed -Cursor $dedup).Count -eq 1) 'semantic state changes produce one new fallback'
$sha='c8aa97742c99ef8237e54f6b151bb339a452fbc6'
$run=@{root='r';taskId='20261110T152055490Z-945ac728';attemptId='20261110T152055490Z-945ac728';title='Параллельные задачи';status='running'}
$short=@(Get-WorkflowMonitorRecords -Runs @($run) -Events @((Event $run.taskId $run.attemptId 'r' 0 "Сохранено $sha" 'accepted'),(Event $run.taskId $run.attemptId 'r' 1 'turn.completed' 'cli-event'),(Event $run.taskId $run.attemptId 'r' 2 'Проверка привязана к текущему отпечатку файлов' 'reviewed'),(Event $run.taskId $run.attemptId 'r' 3 'Критическая ошибка запуска' 'failed')) -Publications @(@{root='r';commit=$sha;phase='prepared'},@{root='r';commit=$sha;pushed=$true;deployStatus='not-checked'}))
$c=New-WorkflowMonitorCursor;$visible=@(Select-WorkflowMonitorNewRecords -Records $short -Cursor $c -InitialLimit 100);$render=@($visible|Format-WorkflowMonitorRecord) -join "`n"
$rawTitle=@{root='r';taskId='20261110T152055490Z-945ac728';attemptId='20261110T152055490Z-945ac728';title='20261110T152055490Z-945ac728';status='running'}
Assert ((Format-WorkflowMonitorRecord @(Get-WorkflowMonitorRecords -Runs @($rawTitle))[0]).Contains('[Задача 945ac728]')) 'technical timestamp title uses short task label'
Assert ($render.Contains('[Параллельные задачи]') -and $render.Contains('[Публикация]')) 'semantic task and publication labels'
Assert ($render -notmatch $sha -and $render.Contains('c8aa977') -and $render -notmatch '20261110T152055490') 'full hashes and timestamp IDs stay out of display'
Assert ($render -notmatch 'turn.completed|отпечатк' -and $render.Contains('Критическая ошибка запуска')) 'technical chatter is hidden and critical error remains'
Assert ($render.Contains('Подготовка публикации') -and $render.Contains('проверка сайта ожидается')) 'publication statuses are readable'
Assert (@(Select-WorkflowMonitorNewRecords -Records $short -Cursor $c).Count -eq 0) 'filtered records do not disturb deduplication'
'ALL MONITOR LOG LAYOUT TESTS PASSED'
