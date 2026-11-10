param([Parameter(Mandatory)][string]$Config)
$ErrorActionPreference='Stop'
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Text.UTF8Encoding]::new($false)
$c=Get-Content -LiteralPath $Config -Raw -Encoding utf8|ConvertFrom-Json
$argv=@($c.arguments)
if([IO.Path]::GetExtension($c.cli) -in @('.cmd','.bat')){
 foreach($a in @($c.cli)+$argv){if($a -match '[&|<>^%!"\r\n]'){throw 'cmd метасимволы в CLI аргументах запрещены.'}}
}
# PowerShell's native pipeline forwards UTF8 stdin explicitly. PS1 test endpoints
# execute in a child process too, rather than inheriting this adapter's consumed stream.
$prompt=[Console]::In.ReadToEnd()
if([IO.Path]::GetExtension($c.cli) -eq '.ps1'){
 $prompt | & (Get-Command pwsh).Source -NoProfile -File $c.cli @argv
}else{$prompt | & $c.cli @argv}
if($null -ne $LASTEXITCODE){exit $LASTEXITCODE}
if(!$?){exit 1}
