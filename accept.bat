@echo off
chcp 65001 >nul
echo Проверка: pwsh -NoProfile -File "%~dp0watch.ps1" -Command review -Id ^<ID^> -Evidence ^<файл проверки^>
echo Сохранение: pwsh -NoProfile -File "%~dp0watch.ps1" -Command accept-step -Id ^<ID^> -Message ^<сообщение^>
echo Публикация завершённого пункта выполняется отдельно командой publish -CompleteItem.
