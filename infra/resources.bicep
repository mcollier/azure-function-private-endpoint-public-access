@minLength(1)
@maxLength(17)
@description('Prefix for all resources, i.e. {name}storage')
param name string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('The username to use for the virtual machine.')
@secure()
param adminUserName string

@description('The password to use for the virtual machine.')
@secure()
param adminPassword string

var aadLoginExtensionName = 'AADLoginForWindows'

resource storageAccountFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-02-01' = {
  name: '${storageAccount.name}/default/${name}share'
}

// -- Virtual Network -- //

resource privateEndpoingNsg 'Microsoft.Network/networkSecurityGroups@2021-08-01' = {
  name: '${name}pensg'
  location: location
}

resource vmNsg 'Microsoft.Network/networkSecurityGroups@2021-08-01' = {
  name: '${name}vmnsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow_RDP_Inbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 200
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: '${name}vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.2.0.0/16'
      ]
    }
    subnets: [
      {
        name: '${name}pesubnet'
        properties: {
          addressPrefix: '10.2.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: privateEndpoingNsg.id
          }
        }
      }
      {
        name: '${name}vmsubnet'
        properties: {
          addressPrefix: '10.2.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: vmNsg.id
          }
        }
      }
    ]
  }

  resource privateEndpointSubnet 'subnets' existing = {
    name: '${name}pesubnet'
  }

  resource vmSubnet 'subnets' existing = {
    name: '${name}vmsubnet'
  }
}

resource functionPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'Global'

  resource link 'virtualNetworkLinks' = {
    name: '${name}dnsvnetlink'
    location: 'Global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
}

resource functionPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-08-01' = {
  name: '${name}functionprivateendpoint'
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: ''
        properties: {
          privateLinkServiceId: functionApp.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }

  resource dnsZoneGroup 'privateDnsZoneGroups' = {
    name: '${name}privateDnsZoneGroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: functionPrivateDnsZone.id
          }
        }
      ]
    }
  }
}

// --  Virtual Machine -- //

resource windowsVmSchedule 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${windowsVM.name}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '1900'
    }
    timeZoneId: 'UTC'
    notificationSettings: {
      status: 'Disabled'
    }
    targetResourceId: windowsVM.id
  }
}

resource windowsVM 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: '${name}vm'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D4ds_v5'
    }
    licenseType: 'Windows_Client'
    osProfile: {
      computerName: 'myvm'
      adminUsername: adminUserName
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          enableHotpatching: false
          patchMode: 'AutomaticByOS'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'Windows-10'
        sku: '20h2-pro-g2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }

  resource ex 'extensions' = {
    name: aadLoginExtensionName
    location: location
    properties: {
      publisher: 'Microsoft.Azure.ActiveDirectory'
      autoUpgradeMinorVersion: true
      type: aadLoginExtensionName
      typeHandlerVersion: '1.0'
    }
  }
}

resource vmPip 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${name}vmpip'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: '${name}nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig'
        properties: {
          subnet: {
            id: vnet::vmSubnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: vmPip.id
            properties: {
              deleteOption: 'Delete'
            }
          }
        }
      }
    ]
  }
}

// -- Function App -- //

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: '${name}loganalyticsworkspace'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: '${name}applicationinsights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: '${name}storage'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {}
}

resource functionPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: '${name}plan'
  location: location
  kind: 'elastic'
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    size: 'EP1'
  }
  properties: {
    maximumElasticWorkerCount: 10
    reserved: false
  }
}

resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: '${name}functionapp'
  location: location
  kind: 'functionapp'
  properties: {
    httpsOnly: true
    serverFarmId: functionPlan.id
    reserved: false
    siteConfig: {
      // publicNetworkAccess: 'Enabled'
      vnetRouteAllEnabled: false
      functionsRuntimeScaleMonitoringEnabled: false
      linuxFxVersion: json('null')
      appSettings: [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: '${name}share'
        }
      ]
    }
  }

  resource config 'config' = {
    name: 'web'
    properties: {
      publicNetworkAccess: 'Enabled'
    }
  }
}
