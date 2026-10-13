targetScope = 'subscription'

@minLength(1)
@maxLength(32)
param environmentName string
param location string
@minLength(36)
@maxLength(36)
param postgresAdminObjectId string
@minLength(1)
param postgresAdminUsername string
@description('One explicitly approved public IPv4 address for local development and SQL bootstrap.')
param developerIpv4 string
@description('Optional second individually approved public IPv4 address; never a range.')
param developerIpv4Secondary string = ''
@description('Explicit acknowledgement of the cross-subscription Azure-services firewall exception.')
param allowAzureServices bool = false
param applicationImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param springDatasourceUrl string = ''
param springDatasourceUsername string = ''
param springProfile string = 'azure'

var token = uniqueString(subscription().subscriptionId, environmentName, location)
var tags = {
  'azd-env-name': environmentName
  prototype: 'springboot-postgresql'
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-spring-${token}'
  location: location
  tags: tags
}

module resources 'resources.bicep' = {
  name: 'spring-resources-${token}'
  scope: resourceGroup
  params: {
    location: location
    token: token
    tags: tags
    postgresAdminObjectId: postgresAdminObjectId
    postgresAdminUsername: postgresAdminUsername
    developerIpv4: developerIpv4
    developerIpv4Secondary: developerIpv4Secondary
    allowAzureServices: allowAzureServices
    applicationImage: applicationImage
    springDatasourceUrl: springDatasourceUrl
    springDatasourceUsername: springDatasourceUsername
    springProfile: springProfile
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_CONTAINER_APP_NAME string = resources.outputs.containerAppName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = resources.outputs.registryEndpoint
output AZURE_CONTAINER_REGISTRY_NAME string = resources.outputs.registryName
output AZURE_CLIENT_ID string = resources.outputs.managedIdentityClientId
output AZURE_TENANT_ID string = tenant().tenantId
output POSTGRES_HOST string = resources.outputs.postgresHost
output POSTGRES_PORT string = '5432'
output POSTGRES_DATABASE string = 'notes'
output POSTGRES_USERNAME string = postgresAdminUsername
output POSTGRES_ADMIN_OBJECT_ID string = postgresAdminObjectId
output POSTGRES_MANAGED_IDENTITY_USERNAME string = resources.outputs.managedIdentityUsername
output POSTGRES_MANAGED_IDENTITY_OBJECT_ID string = resources.outputs.managedIdentityObjectId
output SERVICE_API_ENDPOINT_URL string = resources.outputs.endpoint
