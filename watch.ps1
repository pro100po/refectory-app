[CmdletBinding()]
param(
 [ValidateSet('status','monitor','run','rerun','manual','review','accept-step','reject','recover','publish','update-status','record-stage')][string]$Command='status',
 [string]$Repo=$PSScriptRoot, [string]$Id, [string]$TaskFile, [string[]]$Files,
 [string]$Model='sol', [string]$Effort='medium', [switch]$AllowMax,
 [string]$Evidence, [string]$Message, [string]$Baseline, [string]$StatusFile,
 [string]$Stage, [ValidateSet('start','end')][string]$StageAction='start',
 [switch]$Once, [switch]$CompleteItem, [int]$DeployTimeoutSeconds=300,
 [switch]$TestMode, [string]$TestCli, [switch]$TestSkipDeployment
)
$ErrorActionPreference='Stop'
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Text.UTF8Encoding]::new($false)
Import-Module (Join-Path $PSScriptRoot 'scripts/Workflow.psm1') -Force
try { Invoke-Workflow @PSBoundParameters } catch { Write-Error $_ -ErrorAction Continue; exit 1 }
