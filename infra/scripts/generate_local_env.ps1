$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..\..')).Path
$parametersPath = Join-Path $repoRoot 'infra\main.parameters.json'
$dotEnvPath = Join-Path $repoRoot '.env'

if (-not (Get-Command azd -ErrorAction SilentlyContinue)) {
	throw "The 'azd' CLI is required to generate $dotEnvPath. Install Azure Developer CLI and run 'azd provision' first."
}

$null = & azd env get-values --cwd $repoRoot --no-prompt 2>$null
if ($LASTEXITCODE -ne 0) {
	throw "No active azd environment is selected for $repoRoot. Run 'azd env select' or 'azd provision' first."
}

$parameters = $null
if (Test-Path $parametersPath) {
	$parameters = Get-Content -Raw -Path $parametersPath | ConvertFrom-Json
}

function Get-AzdValue {
	param(
		[string[]]$Keys,
		[string]$Default = ''
	)

	foreach ($key in $Keys) {
		if ([string]::IsNullOrWhiteSpace($key)) {
			continue
		}

		$value = & azd env get-value $key --cwd $repoRoot --no-prompt 2>$null
		if ($LASTEXITCODE -ne 0) {
			continue
		}

		$trimmed = ([string]$value).Trim()
		if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
			return $trimmed
		}
	}

	return $Default
}

function Get-ParameterValue {
	param(
		[string]$Name,
		[string]$Default = ''
	)

	if ($parameters -and $parameters.parameters.PSObject.Properties.Name -contains $Name) {
		$value = $parameters.parameters.$Name.value
		if ($null -ne $value) {
			$stringValue = ([string]$value).Trim()
			if (-not [string]::IsNullOrWhiteSpace($stringValue)) {
				return $stringValue
			}
		}
	}

	return $Default
}

function Get-HostPrefix {
	param([string]$Uri)

	if ([string]::IsNullOrWhiteSpace($Uri)) {
		return ''
	}

	try {
		return ([uri]$Uri).Host.Split('.')[0]
	}
	catch {
		return ''
	}
}

$searchEndpoint = Get-AzdValue @('SEARCH_ENDPOINT', 'searchEndpoint')
$openAiEndpoint = Get-AzdValue @('AOAI_ENDPOINT', 'openAiEndpoint')
$foundryProjectEndpoint = Get-AzdValue @('FOUNDRY_PROJECT_ENDPOINT', 'foundryProjectEndpoint')
$embeddingModel = Get-AzdValue @('AOAI_EMBEDDING_MODEL', 'embeddingModel', 'embeddingModelName') (Get-ParameterValue 'embeddingModelName' 'text-embedding-3-large')
$embeddingDeployment = Get-AzdValue @('AOAI_EMBEDDING_DEPLOYMENT', 'embeddingDeploymentName') 'text-embedding-3-large'
$chatModel = Get-AzdValue @('AOAI_GPT_MODEL', 'chatModel', 'chatModelName') (Get-ParameterValue 'chatModelName' 'gpt-5.4')
$chatDeployment = Get-AzdValue @('AOAI_GPT_DEPLOYMENT', 'FOUNDRY_MODEL_DEPLOYMENT_NAME', 'chatDeploymentName') 'gpt-4o-mini'
$searchConnectionName = Get-AzdValue @('AZURE_AI_SEARCH_CONNECTION_NAME', 'searchConnectionName') 'iq-series-search-connection'
$agenticChatModel = Get-AzdValue @('AOAI_AGENTIC_GPT_MODEL', 'agenticChatModel', 'agenticChatModelName') (Get-ParameterValue 'agenticChatModelName' 'gpt-4.1')
$agenticChatDeployment = Get-AzdValue @('AOAI_AGENTIC_GPT_DEPLOYMENT', 'agenticChatDeploymentName') 'agentic-chat'
$subscriptionId = Get-AzdValue @('AZURE_SUBSCRIPTION_ID', 'AZURE_SUBSCRIPTION')
$resourceGroup = Get-AzdValue @('AZURE_RESOURCE_GROUP', 'RESOURCE_GROUP_NAME')
$aiServicesName = Get-AzdValue @('AI_SERVICES_NAME', 'aiServicesName')
$foundryProjectName = Get-AzdValue @('FOUNDRY_PROJECT_NAME', 'foundryProjectName')
$foundryProjectResourceId = Get-AzdValue @('FOUNDRY_PROJECT_RESOURCE_ID', 'foundryProjectResourceId')
$userAssignedIdentityResourceId = Get-AzdValue @('USER_ASSIGNED_IDENTITY_RESOURCE_ID', 'userAssignedIdentityResourceId')
$storageResourceId = Get-AzdValue @('STORAGE_RESOURCE_ID', 'storageResourceId')

if ([string]::IsNullOrWhiteSpace($aiServicesName)) {
	$aiServicesName = Get-HostPrefix $foundryProjectEndpoint
}

if ([string]::IsNullOrWhiteSpace($foundryProjectName) -and -not [string]::IsNullOrWhiteSpace($foundryProjectEndpoint)) {
	$foundryProjectName = ($foundryProjectEndpoint.TrimEnd('/') -split '/')[-1]
}

if (
	[string]::IsNullOrWhiteSpace($foundryProjectResourceId) -and
	-not [string]::IsNullOrWhiteSpace($subscriptionId) -and
	-not [string]::IsNullOrWhiteSpace($resourceGroup) -and
	-not [string]::IsNullOrWhiteSpace($aiServicesName) -and
	-not [string]::IsNullOrWhiteSpace($foundryProjectName)
) {
	$foundryProjectResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$aiServicesName/projects/$foundryProjectName"
}

$missing = @()
if ([string]::IsNullOrWhiteSpace($searchEndpoint)) { $missing += 'SEARCH_ENDPOINT/searchEndpoint' }
if ([string]::IsNullOrWhiteSpace($openAiEndpoint)) { $missing += 'AOAI_ENDPOINT/openAiEndpoint' }
if ([string]::IsNullOrWhiteSpace($foundryProjectEndpoint)) { $missing += 'FOUNDRY_PROJECT_ENDPOINT/foundryProjectEndpoint' }
if ([string]::IsNullOrWhiteSpace($foundryProjectResourceId)) { $missing += 'FOUNDRY_PROJECT_RESOURCE_ID/foundryProjectResourceId' }

if ($missing.Count -gt 0) {
	throw "Missing required azd environment values: $($missing -join ', '). Run 'azd provision' or 'azd env refresh' first."
}

$envLines = @(
	"SEARCH_ENDPOINT=$searchEndpoint"
	"AOAI_ENDPOINT=$openAiEndpoint"
	"AOAI_EMBEDDING_MODEL=$embeddingModel"
	"AOAI_EMBEDDING_DEPLOYMENT=$embeddingDeployment"
	"AOAI_GPT_MODEL=$chatModel"
	"AOAI_GPT_DEPLOYMENT=$chatDeployment"
	"FOUNDRY_PROJECT_ENDPOINT=$foundryProjectEndpoint"
	"FOUNDRY_MODEL_DEPLOYMENT_NAME=$chatDeployment"
	"AZURE_AI_SEARCH_CONNECTION_NAME=$searchConnectionName"
	"FOUNDRY_PROJECT_RESOURCE_ID=$foundryProjectResourceId"
	"AOAI_AGENTIC_GPT_MODEL=$agenticChatModel"
	"AOAI_AGENTIC_GPT_DEPLOYMENT=$agenticChatDeployment"
	"USER_ASSIGNED_IDENTITY_RESOURCE_ID=$userAssignedIdentityResourceId"
	"STORAGE_RESOURCE_ID=$storageResourceId"
)

Set-Content -Path $dotEnvPath -Value (($envLines -join [Environment]::NewLine) + [Environment]::NewLine) -Encoding utf8NoBOM
Write-Host "Wrote $dotEnvPath"
