# Introduction 
TRS App Service Environment Monitoring
Will update NSG based on values provided from API calls to the ASE


# Build and Test
1) Create an App Registration / Service Principal
	Create a Key =[AppKey]
	Get [ApplicationId] and Key for later use
	Permissions
		Read at the subscription
		Contributor at NSG RG
2) Get your [tenentId]
3) Get the [subscriptionId] where the App Service Environment (ase) is homed
4) Create RG for workspace and automation account
5) Create Workspace
	Get [WorkspaceId] and [WorkspaceKey]
6) Create Automation Account
	No to Create RunAsAccount
	Import Modules
		AzureRM.Profile
		AzureRm.Network
		AzureRm.Resources
7) Import the Runbooks
8) Publish the Runbooks (For Each)
	1) Navigate to
	2) Edit
	3) Publish
9) Create the Variables
	1) clientId => [ApplicationId]
	2) clientSecret => [AppKey]
	3) workspaceId => [WorkspaceId]
	4) workspaceKey => [WorkspaceKey]
	5) tenantId => [tenantId]
	6) subscriptionId => [subscriptionId]
	7) nsgName => [name of nsg to create or modify]
	8) nsgRgName => [Name of resource group that contains the nsg]
	9) location => the Azure location, eastus, canadacentral, canadaeast, etc
	10) hostingEnvironmentName => THe name of the ASE hosting environment
	11) hostingEnvironmentRG => The name of the Resource Group containing the hosting environment
10) Create Automation Schedules
	1) Nav to Runbook
	2) Schedule
	3) Link
	4) Create
		a. Name => UpdateNsgSchedule
		b. Recurring
		

# Contribute
TODO: Explain how other users and developers can contribute to make your code better. 

If you want to learn more about creating good readme files then refer the following [guidelines](https://www.visualstudio.com/en-us/docs/git/create-a-readme). You can also seek inspiration from the below readme files:
- [ASP.NET Core](https://github.com/aspnet/Home)
- [Visual Studio Code](https://github.com/Microsoft/vscode)
- [Chakra Core](https://github.com/Microsoft/ChakraCore)