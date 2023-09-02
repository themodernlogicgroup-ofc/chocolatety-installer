#requires -Modules cChoco
## 1. REQUIREMENTS ##
### Here are the requirements necessary to ensure this is successful.

### a. Internal/Private Cloud Repository Set Up ###
#### You'll need an internal/private cloud repository you can use. These are
####  generally really quick to set up and there are quite a few options.
####  Chocolatey Software recommends Nexus, Artifactory Pro, or ProGet as they
####  are repository servers and will give you the ability to manage multiple
####  repositories and types from one server installation.

### b. Download Chocolatey Package and Put on Internal Repository ###
#### You need to have downloaded the Chocolatey package as well.
####  Please see https://chocolatey.org/install#organization

### c. Other Requirements ###
#### i. Requires chocolatey\cChoco DSC module to be installed on the machine compiling the DSC manifest
#### NOTE: This will need to be installed before running the DSC portion of this script
if (-not (Get-Module cChoco -ListAvailable)) {
    $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    if (($PSGallery = Get-PSRepository -Name PSGallery).InstallationPolicy -ne "Trusted") {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
    Install-Module -Name cChoco
    if ($PSGallery.InstallationPolicy -ne "Trusted") {
        Set-PSRepository -Name PSGallery -InstallationPolicy $PSGallery.InstallationPolicy
    }
}

#### ii. Requires a hosted copy of the install.ps1 script
##### This should be available to download without authentication.
##### The original script can be found here: https://community.chocolatey.org/install.ps1

Configuration ChocolateyConfig {
## 2. TOP LEVEL VARIABLES ##
    param(
### a. Your internal repository url (the main one). ###
####  Should be similar to what you see when you browse
#### to https://community.chocolatey.org/api/v2/
        $NugetRepositoryUrl      = "https://github.com/themodernlogicgroup-ofc/chocolatety-installer",

### b. Chocolatey nupkg download url ###
#### This url should result in an immediate download when you navigate to it in
#### a web browser
        $ChocolateyNupkgUrl      = "https://github.com/themodernlogicgroup-ofc/chocolatety-installer/package/chocolatey.2.2.2.nupkg",

### c. Internal Repository Credential ###
#### If required, add the repository access credential here
#        $NugetRepositoryCredential = [PSCredential]::new(
#            "username",
#            ("password" | ConvertTo-SecureString -AsPlainText -Force)
#        ),

### d. Install.ps1 URL
#### The path to the hosted install script:
        $ChocolateyInstallPs1Url = "https://community.chocolatey.org/install.ps1"

### e. Chocolatey Central Management (CCM) ###
#### If using CCM to manage Chocolatey, add the following:
#### i. Endpoint URL for CCM
#        $ChocolateyCentralManagementUrl = "https://chocolatey-central-management:24020/ChocolateyManagementService",

#### ii. If using a Client Salt, add it here
#        $ChocolateyCentralManagementClientSalt = "clientsalt",

#### iii. If using a Service Salt, add it here
#        $ChocolateyCentralManagementServiceSalt = "servicesalt"
    )
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName cChoco

    Node 'localhost' {
## 3. ENSURE CHOCOLATEY IS INSTALLED ##
### Ensure Chocolatey is installed from your internal repository
        Environment chocoDownloadUrl {
            Name  = "chocolateyDownloadUrl"
            Value = $ChocolateyNupkgUrl
        }

        cChocoInstaller installChocolatey {
            DependsOn = "[Environment]chocoDownloadUrl"
            InstallDir = Join-Path $env:ProgramData "chocolatey"
            ChocoInstallScriptUrl = $ChocolateyInstallPs1Url
        }

## 4. CONFIGURE CHOCOLATEY BASELINE ##
### a. FIPS Feature ###
#### If you need FIPS compliance - make this the first thing you configure
#### before you do any additional configuration or package installations
#        cChocoFeature featureFipsCompliance {
#            FeatureName = "useFipsCompliantChecksums"
#        }

### b. Apply Recommended Configuration ###

#### Move cache location so Chocolatey is very deterministic about
#### cleaning up temporary data and the location is secured to admins
        cChocoConfig cacheLocation {
            DependsOn  = "[cChocoInstaller]installChocolatey"
            ConfigName = "cacheLocation"
            Value      = "C:\ProgramData\chocolatey\cache"
        }

#### Increase timeout to at least 4 hours
        cChocoConfig commandExecutionTimeoutSeconds {
            DependsOn  = "[cChocoInstaller]installChocolatey"
            ConfigName = "commandExecutionTimeoutSeconds"
            Value      = 14400
        }

#### Turn off download progress when running choco through integrations
        cChocoFeature showDownloadProgress {
            DependsOn   = "[cChocoInstaller]installChocolatey"
            FeatureName = "showDownloadProgress"
            Ensure      = "Absent"
        }

### c. Sources ###
#### Remove the default community package repository source
        cChocoSource removeCommunityRepository {
            DependsOn  = "[cChocoInstaller]installChocolatey"
            Name       = "chocolatey"
            Ensure     = "Absent"
        }

#### Add internal default sources
#### You could have multiple sources here, so we will provide an example
#### of one using the remote repo variable here.
#### NOTE: This EXAMPLE may require changes
        cChocoSource addInternalSource {
            DependsOn  = "[cChocoInstaller]installChocolatey"
            Name        = "ChocolateyInternal"
            Source      = $NugetRepositoryUrl
            Credentials = $NugetRepositoryCredential
            Priority    = 1
        }

### b. Keep Chocolatey Up To Date ###
#### Keep chocolatey up to date based on your internal source
#### You control the upgrades based on when you push an updated version
####  to your internal repository.
#### Note the source here is to the OData feed, similar to what you see
####  when you browse to https://community.chocolatey.org/api/v2/
        cChocoPackageInstaller updateChocolatey {
            DependsOn   = "[cChocoSource]addInternalSource", "[cChocoSource]removeCommunityRepository"
            Name        = "chocolatey"
            AutoUpgrade = $true
        }
