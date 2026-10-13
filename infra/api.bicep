param environmentName string
param location string
param applicationImage string
param postgresHost string
param springDatasourceUrl string
param springDatasourceUsername string
param springProfile string

var token = uniqueString(subscription().subscriptionId, environmentName, location)
var isBootstrap = applicationImage == 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'id-notes-${token}'
}
resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: 'acr${token}'
}
resource containerEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: 'cae-notes-${token}'
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-notes-${token}'
  location: location
  tags: {
    'azd-env-name': environmentName
    'azd-service-name': 'api'
    prototype: 'springboot-postgresql'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${appIdentity.id}': {} }
  }
  properties: {
    managedEnvironmentId: containerEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        allowInsecure: false
        targetPort: isBootstrap ? 80 : 8080
        transport: 'http'
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: appIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: applicationImage
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: concat([
            { name: 'AZURE_CLIENT_ID', value: appIdentity.properties.clientId }
            { name: 'POSTGRES_HOST', value: postgresHost }
            { name: 'POSTGRES_PORT', value: '5432' }
            { name: 'POSTGRES_DATABASE', value: 'notes' }
            { name: 'POSTGRES_USERNAME', value: appIdentity.name }
            { name: 'POSTGRES_MANAGED_IDENTITY_ENABLED', value: 'true' }
            { name: 'POSTGRES_SSL_ROOT_CERT', value: '/etc/ssl/certs/ca-certificates.crt' }
            { name: 'AZURE_TENANT_ID', value: tenant().tenantId }
            { name: 'SPRING_PROFILES_ACTIVE', value: springProfile }
          ], isBootstrap ? [] : [
            { name: 'SPRING_DATASOURCE_URL', value: springDatasourceUrl }
            { name: 'SPRING_DATASOURCE_USERNAME', value: springDatasourceUsername }
          ])
          probes: isBootstrap ? [] : [
            {
              type: 'Startup'
              tcpSocket: { port: 8080 }
              periodSeconds: 5
              failureThreshold: 60
            }
            {
              type: 'Liveness'
              httpGet: { path: '/actuator/health/liveness', port: 8080 }
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: { path: '/actuator/health/readiness', port: 8080 }
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
        rules: [
          {
            name: 'http'
            http: { metadata: { concurrentRequests: '10' } }
          }
        ]
      }
    }
  }
}

output AZURE_CONTAINER_APP_NAME string = containerApp.name
output SERVICE_API_ENDPOINT_URL string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
