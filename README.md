### Build an end-to-end agentic retrieval solution using Azure AI Search

Learn how to create an intelligent, MCP-enabled solution that integrates Azure AI Search with Foundry Agent Service for agentic retrieval. You can use this architecture for conversational applications that require complex reasoning over large knowledge domains, such as customer support or technical troubleshooting.


## 📋 Prerequisites

- **Azure Subscription** with permissions to create resources and assign roles
- **Azure CLI** installed and configured ([Install guide](https://learn.microsoft.com/cli/azure/install-azure-cli))
- **Python 3.10+** installed
- A region that supports [agentic retrieval](https://learn.microsoft.com/azure/search/search-region-support) (default: `eastus2`)

## What Gets Deployed

| Resource | Purpose |
|----------|---------|
| **Azure AI Search** (Standard) | Vector search, semantic ranking, agentic retrieval |
| **Azure OpenAI** | `text-embedding-3-large` + `gpt-4.1` + `gpt-5.4` model deployments |
| **Azure AI Services** | Foundry resource with project management enabled |
| **Foundry Project** | Project for running the IQ Series cookbooks |
| **AI Search Connection** | Connects the Foundry project to your AI Search service |
| **RBAC Role Assignments** | Proper permissions for your user + service-to-service access |

## Using Existing Resources (Skip Infra Deployment)

If your Azure AI Search, AI Services/Foundry project, storage, and model deployments already exist, you can skip infrastructure deployment and run the notebooks directly.

### 1) Configure environment variables

Set these values in your local `.env`:

- `SEARCH_ENDPOINT`
- `AOAI_ENDPOINT`
- `FOUNDRY_PROJECT_ENDPOINT`
- `FOUNDRY_PROJECT_RESOURCE_ID`
- `AOAI_EMBEDDING_MODEL`
- `AOAI_EMBEDDING_DEPLOYMENT`
- `AOAI_GPT_MODEL`
- `AOAI_GPT_DEPLOYMENT`
- `AOAI_AGENTIC_GPT_MODEL`
- `AOAI_AGENTIC_GPT_DEPLOYMENT`
- `STORAGE_RESOURCE_ID` (or `STORAGE_RESOURCE_ID_MANUALS` and `STORAGE_RESOURCE_ID_CATALOG` for notebook 2)

Use the `AOAI_` prefix for these variables (for example, `AOAI_AGENTIC_GPT_DEPLOYMENT`).

### 2) Verify access and role assignments

Before running notebooks, confirm these permissions are in place:

- Your deployment user/service principal can manage Search indexes and indexers.
- Foundry project managed identity has `Search Index Data Contributor` on the Search service.
- Search service managed identity has `Storage Blob Data Reader` and `Storage Blob Data Contributor` on Storage, plus `Cognitive Services OpenAI User` and `Cognitive Services User` on model resources used for embeddings.

### 3) Choose the notebook path based on what already exists

- Run `1 -> 2 -> 3 -> 4` if you want to recreate/refresh the full pipeline.
- Run `3 -> 4` if indexes and indexed data already exist.
- Run `4` only if knowledge sources and knowledge base already exist.

When running notebook 4 against existing resources, make sure `base_name` matches your existing knowledge base name.

## Notebook Usage (Run In Order)

The core workflow uses the four numbered notebooks in this order:

- [1.create_search_index.ipynb](1.create_search_index.ipynb)
- [2.create_indexer_and_index.ipynb](2.create_indexer_and_index.ipynb)
- [3.create_ks_kb.ipynb](3.create_ks_kb.ipynb)
- [4.create_agent_with_foundry_iq.ipynb](4.create_agent_with_foundry_iq.ipynb)

### 1) [1.create_search_index.ipynb](1.create_search_index.ipynb)

Purpose:

- Creates the two Azure AI Search indexes used by the solution:
	- `product-manuals` for chunked manual content
	- `product-catalog` for structured product JSON
- Configures vector search and semantic ranking for both indexes.

How to use:

- Run all cells top-to-bottom once your `.env` values are available.
- Confirm both success messages are printed for manuals and catalog indexes.

### 2) [2.create_indexer_and_index.ipynb](2.create_indexer_and_index.ipynb)

Purpose:

- Creates blob data sources for manuals and catalog containers.
- Creates skillsets:
	- Manuals: split + embeddings + index projection
	- Catalog: embeddings for `ProductVector`
- Creates indexers for both indexes.
- Includes a page normalization step for manuals chunk documents.

How to use:

- Run sections `2.1`, `2.2`, and `2.3` to provision data sources, skillsets, and indexers.
- Run section `2.4` after a manuals indexer run to normalize `page` values.

### 3) [3.create_ks_kb.ipynb](3.create_ks_kb.ipynb)

Purpose:

- Creates knowledge sources for:
	- `product-manuals`
	- `product-catalog`
- Creates a unified knowledge base named `product-info`.

How to use:

- Run all cells after notebooks 1 and 2 are complete.
- Confirm both knowledge sources and the knowledge base are created successfully.

### 4) [4.create_agent_with_foundry_iq.ipynb](4.create_agent_with_foundry_iq.ipynb)

Purpose:

- Creates a Foundry project connection to the knowledge base MCP endpoint.
- Creates the Foundry prompt agent with `knowledge_base_retrieve` as the allowed tool.
- Sends a user prompt to the agent.
- Renders answers with citations and extracts structured references.

How to use:

- Run all cells top-to-bottom.
- Use the chat cell to ask your question (for example, by setting `user_question`).
- The next cell demonstrates programmatic reference extraction.

### Citation Usage In Notebook 4

This repo includes helper utilities in `utils.py` so notebook responses can be shown with a clean references section.

Usage 1 (human-readable output):

```python
import importlib
import utils

importlib.reload(utils)

formatted_response = utils.format_response_with_references(response)
print(formatted_response)
```

Expected output shape:

```text
Response: <assistant answer without inline citation tokens>

---

**References**:
- [<reference label>](<message_idx>:<search_idx>)
- ...
```

Usage 2 (structured output):

```python
import importlib
import utils

importlib.reload(utils)

parsed = utils.extract_references(response)
print(parsed["response_text"])
print(parsed["references"])
```

`extract_references` returns:

- `response_text`: assistant answer text with inline `【message_idx:search_idx†source_name】` markers removed.
- `references`: list of entries with:
	- `message_idx`
	- `search_idx`
	- `source_name`
	- `label`
	- `document` (parsed MCP payload when available)

Notes:

- Run the chat cell first so `response` exists.
- `utils.py` uses `model_dump()` when available (Pydantic v2 compatible).