@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo GPT vypolnyaet zadanie iz TASK.md... podozhdite.
codex exec -s workspace-write "Execute the task described in TASK.md. Follow the rules in AGENTS.md strictly." > codex-log.txt 2>&1
git diff > review.diff
echo.
echo Gotovo. Napishite Claude v chate: gotovo
pause
