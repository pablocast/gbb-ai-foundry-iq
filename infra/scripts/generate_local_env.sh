#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
parameters_path="$repo_root/infra/main.parameters.json"
dot_env_path="$repo_root/.env"

if ! command -v azd >/dev/null 2>&1; then
	echo "The 'azd' CLI is required to generate $dot_env_path. Install Azure Developer CLI and run 'azd provision' first." >&2
	exit 1
fi

if ! azd env get-values --cwd "$repo_root" --no-prompt >/dev/null 2>&1; then
	echo "No active azd environment is selected for $repo_root. Run 'azd env select' or 'azd provision' first." >&2
	exit 1
fi

python_bin=""
if command -v python3 >/dev/null 2>&1; then
	python_bin="python3"
elif command -v python >/dev/null 2>&1; then
	python_bin="python"
fi

get_azd_value() {
	local default_value="$1"
	shift

	local key
	local value
	for key in "$@"; do
		[[ -z "$key" ]] && continue
		if value="$(azd env get-value "$key" --cwd "$repo_root" --no-prompt 2>/dev/null)" && [[ -n "$value" ]]; then
			printf '%s\n' "$value"
			return 0
		fi
	done

	printf '%s\n' "$default_value"
}

get_parameter_value() {
	local name="$1"
	local default_value="${2:-}"

	if [[ -n "$python_bin" && -f "$parameters_path" ]]; then
		local value
		value="$($python_bin - "$parameters_path" "$name" <<'PY'
import json
import sys

path, name = sys.argv[1], sys.argv[2]
try:
		with open(path, encoding='utf-8') as handle:
				document = json.load(handle)
		value = ((document.get('parameters') or {}).get(name) or {}).get('value')
		if value is not None:
				print(value)
except Exception:
		pass
PY
)" || true

		if [[ -n "$value" ]]; then
			printf '%s\n' "$value"
			return 0
		fi
	fi

	printf '%s\n' "$default_value"
}

get_host_prefix() {
	local uri="$1"
	uri="${uri#*://}"
	uri="${uri%%/*}"
	printf '%s\n' "${uri%%.*}"
}

search_endpoint="$(get_azd_value "" SEARCH_ENDPOINT searchEndpoint)"
openai_endpoint="$(get_azd_value "" AOAI_ENDPOINT openAiEndpoint)"
foundry_project_endpoint="$(get_azd_value "" FOUNDRY_PROJECT_ENDPOINT foundryProjectEndpoint)"
embedding_model="$(get_azd_value "$(get_parameter_value embeddingModelName text-embedding-3-large)" AOAI_EMBEDDING_MODEL embeddingModel embeddingModelName)"
embedding_deployment="$(get_azd_value "text-embedding-3-large" AOAI_EMBEDDING_DEPLOYMENT embeddingDeploymentName)"
chat_model="$(get_azd_value "$(get_parameter_value chatModelName gpt-5.4)" AOAI_GPT_MODEL chatModel chatModelName)"
chat_deployment="$(get_azd_value "gpt-4o-mini" AOAI_GPT_DEPLOYMENT FOUNDRY_MODEL_DEPLOYMENT_NAME chatDeploymentName)"
search_connection_name="$(get_azd_value "iq-series-search-connection" AZURE_AI_SEARCH_CONNECTION_NAME searchConnectionName)"
agentic_chat_model="$(get_azd_value "$(get_parameter_value agenticChatModelName gpt-4.1)" AOAI_AGENTIC_GPT_MODEL agenticChatModel agenticChatModelName)"
agentic_chat_deployment="$(get_azd_value "agentic-chat" AOAI_AGENTIC_GPT_DEPLOYMENT agenticChatDeploymentName)"
subscription_id="$(get_azd_value "" AZURE_SUBSCRIPTION_ID AZURE_SUBSCRIPTION)"
resource_group="$(get_azd_value "" AZURE_RESOURCE_GROUP RESOURCE_GROUP_NAME)"
ai_services_name="$(get_azd_value "" AI_SERVICES_NAME aiServicesName)"
foundry_project_name="$(get_azd_value "" FOUNDRY_PROJECT_NAME foundryProjectName)"
foundry_project_resource_id="$(get_azd_value "" FOUNDRY_PROJECT_RESOURCE_ID foundryProjectResourceId)"
user_assigned_identity_resource_id="$(get_azd_value "" USER_ASSIGNED_IDENTITY_RESOURCE_ID userAssignedIdentityResourceId)"
storage_resource_id="$(get_azd_value "" STORAGE_RESOURCE_ID storageResourceId)"

if [[ -z "$ai_services_name" && -n "$foundry_project_endpoint" ]]; then
	ai_services_name="$(get_host_prefix "$foundry_project_endpoint")"
fi

if [[ -z "$foundry_project_name" && -n "$foundry_project_endpoint" ]]; then
	foundry_project_name="${foundry_project_endpoint%/}"
	foundry_project_name="${foundry_project_name##*/}"
fi

if [[ -z "$foundry_project_resource_id" && -n "$subscription_id" && -n "$resource_group" && -n "$ai_services_name" && -n "$foundry_project_name" ]]; then
	foundry_project_resource_id="/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.CognitiveServices/accounts/$ai_services_name/projects/$foundry_project_name"
fi

missing=()
[[ -z "$search_endpoint" ]] && missing+=("SEARCH_ENDPOINT/searchEndpoint")
[[ -z "$openai_endpoint" ]] && missing+=("AOAI_ENDPOINT/openAiEndpoint")
[[ -z "$foundry_project_endpoint" ]] && missing+=("FOUNDRY_PROJECT_ENDPOINT/foundryProjectEndpoint")
[[ -z "$foundry_project_resource_id" ]] && missing+=("FOUNDRY_PROJECT_RESOURCE_ID/foundryProjectResourceId")

if (( ${#missing[@]} > 0 )); then
	printf 'Missing required azd environment values: %s\n' "${missing[*]}" >&2
	echo "Run 'azd provision' or 'azd env refresh' first." >&2
	exit 1
fi

cat > "$dot_env_path" <<EOF
SEARCH_ENDPOINT=$search_endpoint
AOAI_ENDPOINT=$openai_endpoint
AOAI_EMBEDDING_MODEL=$embedding_model
AOAI_EMBEDDING_DEPLOYMENT=$embedding_deployment
AOAI_GPT_MODEL=$chat_model
AOAI_GPT_DEPLOYMENT=$chat_deployment
FOUNDRY_PROJECT_ENDPOINT=$foundry_project_endpoint
FOUNDRY_MODEL_DEPLOYMENT_NAME=$chat_deployment
AZURE_AI_SEARCH_CONNECTION_NAME=$search_connection_name
FOUNDRY_PROJECT_RESOURCE_ID=$foundry_project_resource_id
AOAI_AGENTIC_GPT_MODEL=$agentic_chat_model
AOAI_AGENTIC_GPT_DEPLOYMENT=$agentic_chat_deployment
USER_ASSIGNED_IDENTITY_RESOURCE_ID=$user_assigned_identity_resource_id
STORAGE_RESOURCE_ID=$storage_resource_id
EOF

printf 'Wrote %s\n' "$dot_env_path"
