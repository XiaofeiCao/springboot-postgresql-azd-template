param location string
@minLength(13)
@maxLength(13)
param token string
param tags object
param postgresAdminObjectId string
param postgresAdminUsername string
param developerIpv4 string
param developerIpv4Secondary string
param allowAzureServices bool
param applicationImage string
param springDatasourceUrl string
param springDatasourceUsername string
param springProfile string

var postgresDatabase = 'notes'

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-notes-${token}'
  location: location
  tags: tags
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'acr${token}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, appIdentity.id, 'AcrPull')
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: 'pg-notes-${token}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
      tenantId: tenant().tenantId
    }
    storage: {
      storageSizeGB: 32
      autoGrow: 'Disabled'
      type: 'Premium_LRS'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: { mode: 'Disabled' }
    network: { publicNetworkAccess: 'Enabled' }
  }
}

resource postgresAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = {
  parent: postgres
  name: postgresAdminObjectId
  properties: {
    principalName: postgresAdminUsername
    principalType: 'User'
    tenantId: tenant().tenantId
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgres
  name: postgresDatabase
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource developerFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgres
  name: 'ApprovedDeveloper'
  properties: {
    startIpAddress: developerIpv4
    endIpAddress: developerIpv4
  }
}

resource secondaryDeveloperFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = if (!empty(developerIpv4Secondary)) {
  parent: postgres
  name: 'ApprovedDeveloperSecondary'
  properties: {
    startIpAddress: developerIpv4Secondary
    endIpAddress: developerIpv4Secondary
  }
}

// 0.0.0.0 is the special Azure-services exception, NOT a subscription-scoped rule.
resource azureServicesFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = if (allowAzureServices) {
  parent: postgres
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-notes-${token}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: json('0.1') }
  }
}

resource containerEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-notes-${token}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

module containerApp 'api.bicep' = {
  name: 'notes-app'
  params: {
    environmentName: tags['azd-env-name']
    location: location
    applicationImage: applicationImage
    postgresHost: postgres.properties.fullyQualifiedDomainName
    springDatasourceUrl: springDatasourceUrl
    springDatasourceUsername: springDatasourceUsername
    springProfile: springProfile
  }
  // The app module refers to existing resources; order their initial creation explicitly.
  dependsOn: [acrPull, containerEnvironment]
}

output containerAppName string = containerApp.outputs.AZURE_CONTAINER_APP_NAME
output registryEndpoint string = registry.properties.loginServer
output registryName string = registry.name
output managedIdentityClientId string = appIdentity.properties.clientId
output managedIdentityObjectId string = appIdentity.properties.principalId
output managedIdentityUsername string = appIdentity.name
output postgresHost string = postgres.properties.fullyQualifiedDomainName
output endpoint string = containerApp.outputs.SERVICE_API_ENDPOINT_URL
