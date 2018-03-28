# Introduction 
TODO: Give a short introduction of your project. Let this section explain the objectives or the motivation behind this project. 

# Getting Started
TODO: Guide users through getting your code up and running on their own system. In this section you can talk about:
1.	Installation process
2.	Software dependencies
3.	Latest releases
4.	API references

# Build and Test
Create an App Registration / Service Principal
	Create a Key =[AppKey]
	Get [ApplicationId] and Key for later use
	Permissions
		Read at the subscription
		Contributor at NSG RG
Get your [tenentId]
Get the [subscriptionId] where the App Service Environment (ase) is homed
Create RG for workspace and automation account
Create Workspace
	Get [WorkspaceId] and [WorkspaceKey]
	a997e25a-6eaf-4400-86fc-1ee923e22ca6
	euSWTIDtR0eHggCbs2X5rshzZI5r1c6LjKlRiR0Am4cIKa4yDffUpWBXtl78vqqAaW3AfupDDt3SjaDzsF/WDQ==
Create Automation Account
	No to Create RunAsAccount
Import the Runbooks
Publish the Runbooks (For Each)
	1) Navigate to
	2) Edit
	3) Publish
Create the Variables
	1) clientId => [ApplicationId]
	2) clientSecret => [AppKey]
	3) workspaceId => [WorkspaceId]
	4) workspaceKey => [WorkspaceKey]
	5) tenantId => [tenantId]
	6) subscriptionId => [subscriptionId]
1. Create Automation Schedules
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