param([string]$TestRoot=(Join-Path ([IO.Path]::GetTempPath()) ('infra-diff-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$repo=Join-Path $TestRoot 'repo';[void][IO.Directory]::CreateDirectory($repo)
function Git([string[]]$Arguments){$out=& git.exe -C $repo @Arguments 2>&1;if($LASTEXITCODE -ne 0){throw "git: $out"};($out -join "`n")}
function Put($File,$Text){[IO.File]::WriteAllText((Join-Path $repo $File),$Text,[Text.UTF8Encoding]::new($false))}
[void](Git @('init','-b','main'));[void](Git @('config','user.name','Fixture'));[void](Git @('config','user.email','fixture@example.invalid'));[void](Git @('config','core.autocrlf','false'))
Put '.gitignore' "/.codex-runs/`n";Put 'middle.txt' 'baseline';[void](Git @('add','--','.gitignore','middle.txt'));[void](Git @('commit','-m','baseline'))
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Workflow.psm1') -Force
$task=Join-Path $TestRoot 'task.md';$evidence=Join-Path $TestRoot 'evidence.md';[IO.File]::WriteAllText($task,'# Ручная миграция');[IO.File]::WriteAllText($evidence,'Проверены три файла; принять.')
Put 'AAA.txt' 'Новый первый';Put 'middle.txt' 'Существующий изменён';Put 'zzz.txt' 'Новый последний'
$id=Invoke-Workflow -Repo $repo -Command manual -TaskFile $task -Files @('AAA.txt','middle.txt','zzz.txt') -Baseline (Git @('rev-parse','HEAD'))
Invoke-Workflow -Repo $repo -Command review -Id $id -Evidence $evidence
$diff=[IO.File]::ReadAllText((Join-Path $repo ".codex-runs/$id/changes.diff"))
if(!$diff.Contains('Новый первый') -or !$diff.Contains('Новый последний') -or !$diff.Contains('Существующий изменён')){throw 'Новые/существующие файлы отсутствуют в сохранённом diff.'}
Invoke-Workflow -Repo $repo -Command accept-step -Id $id -Message 'Ручная миграция трёх файлов'
$s=Get-Content -LiteralPath (Join-Path $repo ".codex-runs/$id/state.json") -Raw|ConvertFrom-Json
if($s.status -ne 'accepted' -or !$s.commit){throw 'Миграция не принята.'}
$files=(Git @('diff-tree','--no-commit-id','--name-only','-r','HEAD')).Split("`n")
if(($files -join ',') -ne 'AAA.txt,middle.txt,zzz.txt'){throw 'Неверный состав коммита.'}
'PASS: 3 assertions; new+tracked files diff, stable post-stage fingerprint, scoped manual commit.'
