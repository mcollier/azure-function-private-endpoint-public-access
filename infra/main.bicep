targetScope = 'subscription'

@minLength(1)
@maxLength(17)
@description('Prefix for all resources, i.e. {name}storage')
param name string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('The username to use for the virtual machine.')
@secure()
param vmAdminUserName string

@description('The password to use for the virtual machine.')
@secure()
param vmAdminPassword string

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${name}rg'
  location: location
}

module resources 'resources.bicep' = {
  name: '${name}res'
  scope: resourceGroup
  params: {
    name: name
    location: location
    adminUserName: vmAdminUserName
    adminPassword: vmAdminPassword
  }
}
