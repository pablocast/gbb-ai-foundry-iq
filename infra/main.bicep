// ===============================================
// IQ Series — Foundry IQ Infrastructure
// Creates: Azure AI Search, Azure OpenAI (with model deployments),
//          AI Services (Foundry) with Foundry Project,
//          AI Search connection, Azure Blob Storage,
//          and RBAC role assignments
// ===============================================

@secure()
@description('Principal ID of the deployment identity to grant permissions to. If not set, permissions will be granted to the deployment user, which may cause issues for CI/CD deployments.')
param principalId string

@description('Resource name prefix')
param resourcePrefix string = 'foundryiq'

@description('Azure region — must support agentic retrieval (see https://learn.microsoft.com/azure/search/search-region-support)')
param location string 

@description('AI Search SKU')
@allowed(['basic', 'standard', 'standard2', 'standard3'])
param searchServiceSku string = 'standard'


@description('AI Services SKU')
@allowed(['S0'])
param aiServicesSku string = 'S0'

@description('Embedding model name')
@allowed(['text-embedding-3-large'])
param embeddingModelName string 

@description('Embedding model version')
param embeddingModelVersion string 

@description('Embedding model capacity (1K TPM per unit)')
@minValue(1)
@maxValue(200)
param embeddingModelCapacity int

@description('Chat model name')
param chatModelName string 

@description('Chat model version')
param chatModelVersion string 

@description('Chat model capacity (1K TPM per unit)')
@minValue(1)
@maxValue(200)
param chatModelCapacity int 

@description('Agentic chat model name')
param agenticChatModelName string 

@description('Agentic chat model version')
param agenticChatModelVersion string 

@description('Agentic chat model capacity (1K TPM per unit)')
@minValue(1)
@maxValue(200)
param agenticChatModelCapacity int 

// -----------------------------------------------
// Variables
// -----------------------------------------------

var uniqueSuffix = uniqueString(resourceGroup().id)

var names = {
  search: '${resourcePrefix}-search-${uniqueSuffix}'
  openAi: '${resourcePrefix}-openai-${uniqueSuffix}'
  aiServices: '${resourcePrefix}-ai-${uniqueSuffix}'
  project: '${resourcePrefix}-project'
  searchConnection: 'iq-series-search-connection'
  storage: take('${toLower(resourcePrefix)}st${uniqueSuffix}', 24)
  blobContainer: 'product-manuals'
  embeddingDeployment: embeddingModelName
  chatDeployment: chatModelName
  agenticChatDeployment: agenticChatModelName
}

// -----------------------------------------------
// RBAC role definition IDs
// -----------------------------------------------

var roles = {
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  searchIndexDataReader: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
  cognitiveServicesUser: 'a97b65f3-24c7-4388-baec-2e87135dc908'
  cognitiveServicesContributor: '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68'
  cognitiveServicesOpenAIUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  storageBlobDataReader: 'b441f262-bc79-4517-9f6f-13482bfb26c5'
}

// ===============================================
// AZURE AI SEARCH
// ===============================================

resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: names.search
  location: location
  sku: {
    name: searchServiceSku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    disableLocalAuth: false
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    semanticSearch: 'standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
}


// ===============================================
// AI SERVICES (FOUNDRY)
// ===============================================

resource aiServices 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: names.aiServices
  location: location
  sku: {
    name: aiServicesSku
  }
  kind: 'AIServices'
  properties: {
    customSubDomainName: names.aiServices
    allowProjectManagement: true
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ===============================================
// FOUNDRY PROJECT
// ===============================================

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: aiServices
  name: names.project
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'IQ Series Foundry Project'
    description: 'Project for running the IQ Series cookbooks'
  }
}

// ===============================================
// AI SEARCH CONNECTION (Project → AI Search)
// ===============================================

resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: names.searchConnection
  properties: {
    category: 'CognitiveSearch'
    authType: 'AAD'
    target: 'https://${searchService.name}.search.windows.net'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchService.id
    }
  }
}

// ===============================================
// AZURE BLOB STORAGE (for Episode 2 — Blob Knowledge Source)
// ===============================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: names.storage
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: names.blobContainer
  properties: {
    publicAccess: 'None'
  }
}

// ===============================================
// MODEL DEPLOYMENTS (AI Services / Foundry)
// Deployed on the AI Services account so they
// appear in the Foundry project portal
// ===============================================

resource aiServicesEmbeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: aiServices
  name: names.embeddingDeployment
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: embeddingModelCapacity
  }
}

resource aiServicesChatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: aiServices
  name: names.chatDeployment
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'GlobalStandard'
    capacity: chatModelCapacity
  }
  dependsOn: [
    aiServicesEmbeddingDeployment
  ]
}

resource agenticRetrievalChatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: aiServices
  name: names.agenticChatDeployment
  properties: {
    model: {
      format: 'OpenAI'
      name: agenticChatModelName
      version: agenticChatModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'GlobalStandard'
    capacity: agenticChatModelCapacity
  }
  dependsOn: [
    aiServicesEmbeddingDeployment
    aiServicesChatDeployment
  ]
}

// ===============================================
// SERVICE PRINCIPAL ROLE ASSIGNMENTS
// (AI Search managed identity → OpenAI & AI Services)
// ===============================================

resource searchToOpenAI_CogServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, searchService.name, roles.cognitiveServicesOpenAIUser)
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
  }
}

resource searchToAIServices_CogServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, searchService.name, roles.cognitiveServicesUser)
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesUser)
  }
}

// Foundry Project managed identity -> Search Index Data Contributor
resource projectToSearch_SearchIndexContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, searchService.name, project.id, roles.searchIndexDataContributor)
  scope: searchService
  properties: {
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
  }
}

// ===============================================
// USER ROLE ASSIGNMENTS
// ===============================================

// Search Service Contributor
resource userRole_searchContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, searchService.name, principalId, roles.searchServiceContributor)
  scope: searchService
  properties: {
    principalId: principalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchServiceContributor)
  }
}

// Search Index Data Reader
resource userRole_searchIndexReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, searchService.name, principalId, roles.searchIndexDataReader)
  scope: searchService
  properties: {
    principalId: principalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataReader)
  }
}

// Search Index Data Contributor
resource userRole_searchIndexContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, searchService.name, principalId, roles.searchIndexDataContributor)
  scope: searchService
  properties: {
    principalId: principalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
  }
}

// Cognitive Services Contributor (AI Services / Foundry)
resource userRole_aiServicesContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, aiServices.name, principalId, roles.cognitiveServicesContributor)
  scope: aiServices
  properties: {
    principalId: principalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesContributor)
  }
}

// Storage Blob Data Contributor (for Episode 2 — upload docs to blob)
resource userRole_storageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, storageAccount.name, principalId, roles.storageBlobDataContributor)
  scope: storageAccount
  properties: {
    principalId: principalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
  }
}

resource storageRoleSearchService 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(resourceGroup().id, storageAccount.name, searchService.id, roles.storageBlobDataContributor)
  properties: {
    principalId: searchService.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalType: 'ServicePrincipal'
  }
}

resource storageReaderRoleSearchService 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(resourceGroup().id, storageAccount.name, searchService.id, roles.storageBlobDataReader)
  properties: {
    principalId: searchService.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataReader)
    principalType: 'ServicePrincipal'
  }
}


// ===============================================
// DATA SEEDING (Deployment Script)
// Creates search index, uploads sample data,
// knowledge source, and knowledge base so the
// MCP endpoint is ready to use immediately
// ===============================================

@description('Seed sample data and create knowledge base during deployment')
param seedData bool = true

resource seedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (seedData) {
  name: '${resourcePrefix}-seed-${uniqueSuffix}'
  location: location
}

// Grant the seed identity Search Service Contributor on the search service
resource seedRole_searchContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (seedData) {
  name: guid(resourceGroup().id, searchService.name, 'seed', roles.searchServiceContributor)
  scope: searchService
  properties: {
    principalId: seedData ? seedIdentity.properties.principalId : ''
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchServiceContributor)
  }
}

// Grant the seed identity Search Index Data Contributor on the search service
resource seedRole_searchIndexContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (seedData) {
  name: guid(resourceGroup().id, searchService.name, 'seed', roles.searchIndexDataContributor)
  scope: searchService
  properties: {
    principalId: seedData ? seedIdentity.properties.principalId : ''
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
  }
}

// Grant the seed identity Cognitive Services User on the Foundry service
// (required for knowledge base model validation)
resource seedRole_cogServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (seedData) {
  name: guid(resourceGroup().id, aiServices.name, 'seed', roles.cognitiveServicesUser)
  scope: aiServices
  properties: {
    principalId: seedData ? seedIdentity.properties.principalId : ''
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesUser)
  }
}

// ===============================================
// OUTPUTS
// ===============================================

@description('AI Search endpoint')
output searchEndpoint string = 'https://${searchService.name}.search.windows.net'

@description('AI Search admin API key')
output searchApiKey string = searchService.listAdminKeys().primaryKey

@description('AI Services endpoint')
output aiServicesEndpoint string = aiServices.properties.endpoint

@description('Azure OpenAI endpoint (same as AI Services endpoint, included for clarity)')
output openAiEndpoint string = 'https://${names.aiServices}.openai.azure.com/'

@description('AI Services name')
output aiServicesName string = aiServices.name

@description('Embedding deployment name')
output embeddingDeploymentName string = aiServicesEmbeddingDeployment.name

@description('Chat deployment name')
output chatDeploymentName string = aiServicesChatDeployment.name

@description('Search service name')
output searchServiceName string = searchService.name

@description('Foundry project endpoint')
output foundryProjectEndpoint string = 'https://${names.aiServices}.services.ai.azure.com/api/projects/${project.name}'

@description('Foundry project name')
output foundryProjectName string = project.name

@description('Foundry project resource ID')
output foundryProjectResourceId string = project.id

@description('AI Search connection name (use in .env)')
output searchConnectionName string = searchConnection.name

@description('Embedding model name')
output embeddingModel string = embeddingModelName

@description('Chat model name')
output chatModel string = chatModelName

@description('Agentic chat deployment name')
output agenticChatDeploymentName string = agenticRetrievalChatDeployment.name

@description('Agentic chat model name')
output agenticChatModel string = agenticChatModelName

@description('Blob Storage connection string (use as BLOB_CONNECTION_STRING in .env)')
output blobConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Blob container name (use as BLOB_CONTAINER_NAME in .env)')
output blobContainerName string = blobContainer.name

@description('User-assigned identity resource ID used by seed/indexing operations')
output userAssignedIdentityResourceId string = seedData ? seedIdentity.id : ''

@description('Storage resource connection string format for indexer data sources')
output storageResourceId string = 'ResourceId=${storageAccount.id}'

@description('Resource location')
output resourceLocation string = location

@description('Knowledge base name (for MCP endpoint)')
output knowledgeBaseName string = 'earth-knowledge-base'

@description('MCP endpoint URL (connect agents to the knowledge base)')
output mcpEndpoint string = 'https://${searchService.name}.search.windows.net/knowledgebases/earth-knowledge-base/mcp'
