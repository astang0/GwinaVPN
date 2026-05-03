#Requires -Version 5.1

<#
.SYNOPSIS
Creates a Microsoft Always On VPN Profile based on values stored in the registry.

.DESCRIPTION
This script uses values stored in the registry to build an MS-AOVPN-Profile.
The profile is then used to create a new VPN connection.

#>

[CmdletBinding(SupportsShouldProcess)]

Param (
    #
)

#Change directory to directory that the script was executed in
Set-Location $PSScriptRoot

#Set-Variables for log file.
$LogfileDT = ".\AOVPN_DT_LOG.txt"
$LogfileAUC = ".\AOVPN_AUC_LOG.txt"
$MaxLogLength = 1000

#Fetch Registry Settings for both User and Device Tunnel
$RegistrySettings = Get-ChildItem -Path "HKLM:\SOFTWARE\Policies\AovpnFromGPO\" -Recurse -ErrorAction SilentlyContinue


#Check if script is running in correct context
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
If ($CurrentPrincipal.Identities.IsSystem -ne $True) {
    $NotRunningInSystemContext = $true
}

function Write-Log {
    <#
    .SYNOPSIS
    Writes a message to the log file and console.

    .DESCRIPTION
    This function writes a message to the log file and console with a timestamp and log level.

    .PARAMETER Message
    The message to write to the log.

    .PARAMETER Level
    The log level of the message.
    #>

    param(
        [string]$Message, 
        [string]$Level = 'Info'  
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Write-Host $LogEntry
    Add-Content -Path $Logfile -Value $LogEntry
}

function Build-ConfigfromGPO {
    <#
    .SYNOPSIS
    Builds a VPN profile from registry settings.

    .DESCRIPTION
    This function creates a VPN profile XML structure based on values stored in the registry.

    .PARAMETER TargetPropertyValues
    An array of property values from the registry.

    .PARAMETER DeviceTunnel
    A boolean indicating whether the tunnel is a device tunnel.
    #>

    [CmdletBinding()]
    param (
        [Object[]]$TargetPropertyValues,
        [bool]$DeviceTunnel
    )

    ##Create XML-Document with Profile Base Structure
    $ProfileXML = [xml]@"
<VPNProfile>
    <AlwaysOn>true</AlwaysOn>
    <DeviceTunnel>true</DeviceTunnel>
    <DnsSuffix></DnsSuffix>
    <TrustedNetworkDetection></TrustedNetworkDetection>
    <DisableAdvancedOptionsEditButton>true</DisableAdvancedOptionsEditButton>
    <DisableDisconnectButton>true</DisableDisconnectButton>
    <NativeProfile>
        <Servers></Servers>
        <RoutingPolicyType>SplitTunnel</RoutingPolicyType>
        <NativeProtocolType></NativeProtocolType>
    </NativeProfile>
    <RegisterDNS>true</RegisterDNS>
</VPNProfile>
"@
    
    # Set Settings in VPN-Profile-Node
    $VPNProfileNode = @("DNSSuffix", "DisableDisconnectbutton", "DisableAdvancedOptionsEditButton", "RegisterDNS")
    foreach ($Setting in $VPNProfileNode) {
        if ($NULL -ne $TargetPropertyValues.$Setting) {
            $ProfileXML.VPNProfile.$Setting = $TargetPropertyValues.$Setting
        }
    }

    # Set Settings in NativeProfile-Node
    $NativeProfileNode = @("DisableClassBasedDefaultRoute")
    foreach ($Setting in $NativeProfileNode) {
        if ($NULL -ne $TargetPropertyValues.$Setting) {
            $ProfileXML.VPNProfile.NativeProfile.$Setting = $TargetPropertyValues.$Setting
        }
    }

    # Set Protocol type
    if ($DeviceTunnel) {
        $ProfileXML.VPNProfile.NativeProfile.NativeProtocolType = "IKEv2"
    }
    else {
        $ProfileXML.VPNProfile.NativeProfile.NativeProtocolType = "Automatic"
    }
        

    # Remove Devicetunnel flag if necessary
    if (!$DeviceTunnel) {
        $DTnode = $ProfileXML.VPNProfile.SelectSingleNode("DeviceTunnel")
        $ProfileXML.VPNProfile.RemoveChild($DTnode) | out-null
    }

    # Adding Authentication Settings
    $AuthSettingsNode = $ProfileXML.CreateElement("Authentication")
    if ($DeviceTunnel) {
        $MachineMethodNode = $ProfileXML.CreateElement("MachineMethod")
        $MachineMethodNode.InnerText = "Certificate"
        $AuthSettingsNode.AppendChild($MachineMethodNode) | Out-Null
    }
    else {
        # Add User Method
        $UserMethodNode = $ProfileXML.CreateElement("UserMethod")
        $UserMethodNode.InnerText = "Eap"
        $AuthSettingsNode.AppendChild($UserMethodNode) | Out-Null

        # Add Machine Method
        $MachineMethodNode = $ProfileXML.CreateElement("MachineMethod")
        $MachineMethodNode.InnerText = "Eap"
        $AuthSettingsNode.AppendChild($MachineMethodNode) | Out-Null

        # Add Eap Node
        $EapNode = $ProfileXML.CreateElement("Eap")
        $EapConfigNode = $ProfileXML.CreateElement("Configuration")
        
        # Add Eap configuration
        foreach ($line in $TargetPropertyValues.EapConfig) {
            $EapConfigString = $EapConfigString + $line
        }
        $EapConfigNode.InnerXml = $EapConfigString

            
        $EapNode.AppendChild($EapConfigNode) | Out-Null
        $AuthSettingsNode.AppendChild($EapNode) | Out-Null

    }
    $ProfileXML.VPNProfile.NativeProfile.AppendChild($AuthSettingsNode) | Out-Null
        
    ##Adding IPsec Cryptography Settings
    if ($DeviceTunnel) {
        $cryptographysettings = @("AuthenticationTransformConstants", "CipherTransformConstants", "EncryptionMethod", "PfsGroup", "DHGroup",
            "IntegrityCheckMethod")
        #Create New Cryptography-Node
        $CryptoSuiteNode = $ProfileXML.CreateElement("CryptographySuite")
        foreach ($Setting in $cryptographysettings) {
            if ($NULL -ne $TargetPropertyValues.$Setting) {
            
                # Add Cryptography-Setting
                $addcryptosetting = $ProfileXML.CreateElement($Setting)
                $addcryptosetting.InnerText = $TargetPropertyValues.$Setting
                $CryptoSuiteNode.AppendChild($addcryptosetting) | Out-Null

            
            }
        }
        #Append IPsec-Cryptography to NativeProfile Node in Profile.xml
        $ProfileXML.VPNProfile.NativeProfile.AppendChild($CryptoSuiteNode) | Out-Null
    }
        
        
        
    ##Add DisableClassBasedDefaultRoute Setting
    $DisableClassBasedDefaultRouteNode = $ProfileXML.CreateElement("DisableClassBasedDefaultRoute")
    if ($NULL -ne $TargetPropertyValues.DisableClassBasedDefaultRoute) {
        $DisableClassBasedDefaultRouteNode.InnerText = $TargetPropertyValues.DisableClassBasedDefaultRoute
    }
    else {
        $DisableClassBasedDefaultRouteNode.InnerText = "true"
    }
    $ProfileXML.VPNProfile.NativeProfile.AppendChild($DisableClassBasedDefaultRouteNode) | Out-Null
        
        

    
    ##Trusted Network Detection is not in VPNProfile-Node-Loop because it needs additional formatting
    foreach ($Entry in $TargetPropertyValues.TrustedNetworkDetection) {
        $TrustedNetworks = "$TrustedNetworks,$Entry"  
    }
    $ProfileXML.VPNProfile.TrustedNetworkDetection = $TrustedNetworks.Substring(1)

    #Servers setting must be configured seperately because of special formatting
    $value = $TargetPropertyValues.Servers
    $ProfileXML.VPNProfile.NativeProfile.Servers = "$value;$value"
    
    #Each Route is added as separate Node with multiple child nodes
    foreach ($Route in $TargetPropertyValues.Routes) {
        $Route = $Route.Replace(" ","")
        $SplitRoute = $Route -split ";"

        $RouteIPAddress = $SplitRoute[0]
        $RouteMask = $SplitRoute[1]

        if ($NULL -ne $SplitRoute[2]) {
            $RouteMetric = $SplitRoute[2]
        }
        else {
            $RouteMetric = 1
        }
    
        # Create New Route-Node
        $newroute = $ProfileXML.CreateElement("Route")
    
        # Add Address
        $addip = $ProfileXML.CreateElement("Address")
        $addip.InnerText = $RouteIPAddress
        $newroute.AppendChild($addip) | Out-Null

        # Add Mask
        $addmask = $ProfileXML.CreateElement("PrefixSize")
        $addmask.InnerText = $RouteMask
        $newroute.AppendChild($addmask) | Out-Null

        # Add Metric
        $addmetric = $ProfileXML.CreateElement("Metric")
        $addmetric.InnerText = $RouteMetric
        $newroute.AppendChild($addmetric) | Out-Null

        # Append new routes to Profile.xml
        $ProfileXML.VPNProfile.AppendChild($newroute) | Out-Null
            
            

    }

    #Add Traffic Filters
    if ($NULL -ne $TargetPropertyValues.TrafficFiltersXML) {

        #Join each line to string then split string into traffic filter xml elements
        $TrafficFiltersXMLString = $TargetPropertyValues.TrafficFiltersXml -join "`n"
        $TrafficFiltersXMLSplit = $TrafficFiltersXMLString -split "(?<=</TrafficFilter>)" | Select-Object -SkipLast 1

        #Create new XML Element for each traffic filter node and then append that node to Profile.xml
        foreach ($Entry in $TrafficFiltersXMLSplit) {
            $NewTrafficFiltersXMLDoc = New-Object System.Xml.XmlDocument
            $NewTrafficFiltersXMLDoc.LoadXml($Entry)
            $NewTrafficFiltersXMLElement = $NewTrafficFiltersXMLDoc.DocumentElement

            $NewTrafficFiltersXML = $ProfileXML.CreateElement("TrafficFilter")
            $NewTrafficFiltersXML.InnerXml = $NewTrafficFiltersXMLElement.InnerXml
            $ProfileXML.VPNProfile.AppendChild($NewTrafficFiltersXML) | Out-Null
        }
    }
        

    #Each DNS-Server entry is added as separate Node with multiple child nodes
    if ($NULL -ne $TargetPropertyValues.DomainNameInformation) {
        foreach ($Entry in $TargetPropertyValues.DomainNameInformation) {
            $SplitEntry = $Entry -split ";"
    
            $DomainName = $SplitEntry[0]
            $DnsServers = $SplitEntry[1]
    
        
            #Create Domain Name Information Node
            $newdni = $ProfileXML.CreateElement("DomainNameInformation")
        
            #Add Domain Name
            $addDomain = $ProfileXML.CreateElement("DomainName")
            $addDomain.InnerText = $DomainName
            $newdni.AppendChild($addDomain) | Out-Null
    
            #Add DnsServer if configured
            if ($NULL -ne $DnsServers) {
                $addDnsServers = $ProfileXML.CreateElement("DnsServers")
                $addDnsServers.InnerText = $DnsServers
                $newdni.AppendChild($addDnsServers) | Out-Null
            }
    
            #Append new Dni to Profile.xml
            $ProfileXML.VPNProfile.AppendChild($newdni) | Out-Null
                
                
    
        }
    }

    Return $ProfileXML
    
    
    
}


function Test-AovpnConfiguration {
    <#
    .SYNOPSIS
    Function to check if mandatory settings have been set

    .DESCRIPTION
    This function verifies that all mandatory settings for the VPN configuration are properly configured.
    
    .PARAMETER TargetPropertyValues
    An array of property values from the registry.

    .PARAMETER DeviceTunnel
    A boolean indicating whether the tunnel is a device tunnel.
    #>
    [CmdletBinding()]
    param (
        [Object[]]$TargetPropertyValues,
        [bool]$DeviceTunnel
    )
    
    $mandatorysettings = @("Routes", "TrustedNetworkDetection", "Servers", "DnsSuffix", "ProfileName")
    
    if ($DeviceTunnel) {
        $mandatorysettings = $mandatorysettings + @("AuthenticationTransformConstants", "CipherTransformConstants", "EncryptionMethod", "IntegrityCheckMethod", 
            "PfsGroup")
    }
    else {
        $mandatorysettings = $mandatorysettings + @("EapConfig")
    }

    #Check if mandatory settings have been configured
    foreach ($Setting in $mandatorysettings) {
        if($NULL -eq $TargetPropertyValues.$Setting) {
            $MissingSettings += $Setting
        }
    }
    $MissingSettings
    if ($MissingSettings) {
        $ErrorMessage = "Mandatory settings missing: $($MissingSettings -join ', ')"
        #Write-Log -Message $ErrorMessage -Level 'Error'
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    Write-Log -Message "Check successful. All mandatory settings are configured." -Level 'Info'
    
}

function Format-XML ([xml]$xml, $indent = 3, $format = "Indented") {

    <#
    .SYNOPSIS
    Function to format XML-Document to readable string
    .DESCRIPTION
    This function takes an XML document and formats it to a readable string with specified indentation and formatting.
    .PARAMETER xml
    The XML document to be formatted.
    .PARAMETER indent
    The number of spaces to use for indentation. 
    .PARAMETER format
    The formatting style to use. 
    #>
    $StringWriter = New-Object System.IO.StringWriter
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter
    $xmlWriter.Formatting = $format
    $xmlWriter.Indentation = $Indent
    $xml.WriteContentTo($XmlWriter)
    $XmlWriter.Flush()
    $StringWriter.Flush()
    Write-Output $StringWriter.ToString()
}

function Compare-AovpnConfiguration {
    <#
    .SYNOPSIS
    Function to compare VPN configurations

    .DESCRIPTION
    This function compares the current VPN configuration with the target configuration.

    .PARAMETER OptionalParameters
    Optional parameters for the function.
    #>
    
    param (
        [Object[]]$TargetPropertyValues,
        [Object[]]$CurrentPropertyValues,
        [string[]]$TargetRegPropertyNames,
        [string[]]$CurrentRegPropertyNames
    )


    #Compare current configuration to target configuration 
    try {
        $match = Compare-Object -ReferenceObject $TargetRegPropertyNames -DifferenceObject $CurrentRegPropertyNames -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "LOG: No current configuration found. Skipping configuration comparison..."
        $match = 1
    }
    
    #If there are identical properties set in both keys, compare the property values
    if ($null -eq $match) {
        $configdifferences = 0

        foreach ($Property in $TargetRegPropertyNames) {
            
            $targetvalue = $TargetPropertyValues.$Property
            $currentvalue = $CurrentPropertyValues.$Property
            
            #If the property values are arrays, compare content of arrays
            if ($targetvalue -is [array]) {
                if ($targetvalue.length -gt $currentvalue.length) {
                    $length = $targetvalue.Length
                }
                else {
                    $length = $currentvalue.Length
                }

                for ($j = 0; $j -lt $length; $j++) {
                    if (!($targetvalue[$j] -ceq $currentvalue[$j])) {
                        $configdifferences++
                        Break
                    }
                }
            }
            #Else compare property values directly
            elseif (!($targetvalue -ceq $currentvalue)) {
                $configdifferences++
                Break
            }
                
        }
    
        # If there are no differences between the target and the currently configured settings, exit script
        if ($configdifferences -eq 0) {
            Write-Log -Message "Configurations are identical. No changes will be made to the VPN-Profile." -Level 'Info'
            Continue main
        }
        else{
            Write-Log -Message "Configuration changes detected." -Level 'Info'
        }
        
    }

    if (($null -ne $match) -or ($configdifferences -gt 0)) {
        $ConfigurationDifferencesExist = $true
    }

    Return $ConfigurationDifferencesExist
}

function Set-AovpnConnection {
    <#
    .SYNOPSIS
    Function to add a new VPN connection

    .DESCRIPTION
    This function creates a new VPN connection with the specified profile name.

    .PARAMETER ProfileName
    The name of the profile to be created.
    #>

    param(
        [string]$ProfileName
    )

    $ProfileNameEscaped = $ProfileName -replace ' ', '%20'

    $ProfileToDeploy = @("$($ProfileFormatted)")
    $ProfileToDeploy = $ProfileToDeploy -replace '<', '&lt;'
    $ProfileToDeploy = $ProfileToDeploy -replace '>', '&gt;'
    $ProfileToDeploy = $ProfileToDeploy -replace '"', '&quot;'

    $nodeCSPURI = './Vendor/MSFT/VPNv2'
    $namespaceName = "root\cimv2\mdm\dmmap"
    $className = "MDM_VPNv2_01"

    $session = New-CimSession

    try {
        $newInstance = New-Object Microsoft.Management.Infrastructure.CimInstance $className, $namespaceName
        $property = [Microsoft.Management.Infrastructure.CimProperty]::Create("ParentID", "$nodeCSPURI", 'String', 'Key')
        $newInstance.CimInstanceProperties.Add($property)
        $property = [Microsoft.Management.Infrastructure.CimProperty]::Create("InstanceID", "$ProfileNameEscaped", 'String', 'Key')
        $newInstance.CimInstanceProperties.Add($property)
        $property = [Microsoft.Management.Infrastructure.CimProperty]::Create("ProfileXML", "$ProfileToDeploy", 'String', 'Property')
        $newInstance.CimInstanceProperties.Add($property)

        $session.CreateInstance($namespaceName, $newInstance) | Out-Null
        $Message = "Successfully (re)deployed $ProfileName profile."
        Write-Log -Message $Message -Level 'Info'
    }
    catch [Exception] {
        $Message = "Unable to create $ProfileName profile: $_"
        throw $Message
        Continue Main
    }
}

function Remove-AovpnConnection {
    <#
    .SYNOPSIS
    Function to remove a VPN connection
    .DESCRIPTION
    This function removes an existing VPN connection with the specified profile name and cleans up registry artifacts.
    .PARAMETER ProfileName
    The name of the profile to be removed.
    #>
    param(
        [bool]$IsDevicetunnel
    )

    $namespaceName = "root\cimv2\mdm\dmmap"
    $className = "MDM_VPNv2_01"

    #Get Cim Instance for the connection
    if($IsDevicetunnel){
        $CurrentConnection = Get-CimInstance -Namespace $namespaceName -ClassName $className | Where-Object DeviceTunnel -eq "True" -ErrorAction SilentlyContinue
    }
    else{
        $CurrentConnection = Get-CimInstance -Namespace $namespaceName -ClassName $className | Where-Object DeviceTunnel -ne "True" -ErrorAction SilentlyContinue
    }

    #If nothing was found, return
    if(!$CurrentConnection){
        Write-Log "No connection of this type found." -Level 'Info' 
        Return
    }

    #Else extract name, delete and check if gone
    $CurrentConnectionName= $CurrentConnection.InstanceID
    Remove-CimInstance -CimInstance $CurrentConnection
    if($IsDevicetunnel){
        $CurrentConnection = Get-CimInstance -Namespace $namespaceName -ClassName $className | Where-Object DeviceTunnel -eq "True" -ErrorAction SilentlyContinue
    }
    else{
        $CurrentConnection = Get-CimInstance -Namespace $namespaceName -ClassName $className | Where-Object DeviceTunnel -ne "True" -ErrorAction SilentlyContinue
    }

    #At this point there should be no connection with same connectiontype configured so check if for some reason a connection still exists
    if ($NULL -ne ($CurrentConnection)) {
        Write-Log -Message "A connection with the current connection type already exists and could not be removed. Instance ID: $CurrentConnectionName. Aborting deployment." -Level 'Error'
        Continue main
    }
   
    $ProfileNameEscaped = $CurrentConnectionName
    $ProfileName = $ProfileNameEscaped.Replace("%20"," ") 
    Write-Log "Successfully removed connection $ProfileName. Starting Registry-Cleanup..." -Level 'Info' 
    #Clean-Up by Richard Hicks

    # Registry clean-up
    Write-Verbose "Cleaning up registry artifacts for VPN connection ""$ProfileName""..."

    # Remove registry artifacts from ERM\Tracked
    Write-Verbose "Searching ERM\Tracked for profile ""$ProfileNameEscaped""..."

    $BasePath = "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked"
    $Tracked = Get-ChildItem -Path $BasePath

    ForEach ($Item in $Tracked) {

        Write-Verbose "Processing $(Convert-Path $Item.PsPath)..."
        $Key = Get-ChildItem $Item.PsPath -Recurse | Where-Object { $_ | Get-ItemProperty -Include "Path*" }
        $PathCount = ($Key.Property -Match "Path\d+").Count
        Write-Verbose "Found a total of $PathCount ERM\Tracked entries."

        # There may be more than 1 matching key
        ForEach ($K in $Key) {

            $Path = $K.Property | Where-Object { $_ -Match "Path\d+" }
            $Count = $Path.Count
            Write-Verbose "Found $Count entries under $($K.Name)."

            ForEach ($P in $Path) {

                Write-Verbose "Testing $P..."
                $Value = $K.GetValue($P)

                If ($Value -Match "$($ProfileNameEscaped)$") {

                    Write-Verbose "Removing $Value under $($K.Name)..."
                    $K | Remove-ItemProperty -Name $P

                    # Decrement count
                    $Count--

                }

            } # ForEach $P in $Path

            #  // Update count
            Write-Verbose "Setting count to $Count..."
            $K | Set-ItemProperty -Name Count -Value $Count

        } # ForEach $K in $Key

    } # ForEach $Item in $Tracked

    # Remove registry artifacts from NetworkList\Profiles
    $Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles\'
    Write-Verbose "Searching $Path for VPN profile ""$ProfileName""..."
    $Key = Get-Childitem -Path $Path | Where-Object { (Get-ItemPropertyValue $_.PsPath -Name Description) -eq $ProfileName }

    If ($Key) {

        Write-Verbose "Removing $($Key.Name)..."
        $Key | Remove-Item

    }

    Else {

        Write-Verbose "No profiles found matching ""$ProfileName"" in the network list."

    }

    # Remove registry artifacts from RasMan\Config
    $Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\RasMan\Config\'
    $Name = 'AutoTriggerDisabledProfilesList'

    Write-Verbose "Searching $Name under $Path for VPN profile ""$ProfileName""..."

    Try {

        # Get the current registry values as an array of strings
        [string[]]$Current = Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop

    }

    Catch {

        Write-Verbose "$Name does not exist under $Path. No action required."

    }

    If ($Current) {

        # Create ordered hashtable
        $List = [Ordered]@{}
        $Current | ForEach-Object { $List.Add("$($_.ToLower())", $_) }

        # Search hashtable for matching VPN profile and remove if present
        If ($List.Contains($ProfileName)) {

            Write-Verbose "Profile found in AutoTriggerDisabledProfilesList. Removing entry..."
            $List.Remove($ProfileName)
            Write-Verbose "Updating the registry..."
            Set-ItemProperty -Path $Path -Name $Name -Value $List.Values

        }

    }

    Else {

        Write-Verbose "No profiles found matching ""$ProfileName"" in the AutoTriggerDisabledProfilesList registry key."

    }

    # Remove registry artifacts from RasMan\DeviceTunnel
    If ($DeviceTunnel) {

        Write-Verbose 'Searching for entries in RasMan\DeviceTunnel...'
        $Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\RasMan\DeviceTunnel\'

        If (Test-Path -Path $Path) {

            Write-Verbose 'RasMan\DeviceTunnel found. Removing registry key...'
            $Path = Get-Item -Path $Path
            Remove-Item -Path $Path.PsPath -Recurse -Force

        }

        Else {

            Write-Verbose 'RasMan\DeviceTunnel not found. No action required.'

        }

    }

    Write-Log "Registry-Cleanup finished. Removal of connection $ProfileName is complete." -Level 'Info' 

}




:main foreach ($ConnectionTypeSettings in ($RegistrySettings | where Name -Notlike "*Current")) {

    try {
        #Determine connection type and set variables accordingly
        if ($ConnectionTypeSettings.Name -like "*Devicetunnel") {
            $ConnectionTypeDisplayName = "DeviceTunnel"
            $script:Logfile = $LogfileDT
            $IsDevicetunnel = $true
        }
        elseif ($ConnectionTypeSettings.Name -like "*AllUserConnection") {
            $ConnectionTypeDisplayName = "AllUserConnection"
            $script:Logfile = $LogfileAUC
            $IsDevicetunnel = $false
        }


        if ($NotRunningInSystemContext) {
            throw "Script must be run as System."
        }

        Write-Log -Message "Starting processing for $ConnectionTypeDisplayName connection..." -Level 'Info'
        #Set variables for current and target configuration
        $RegistryPath = $ConnectionTypeSettings.PSPath
        $ConnectionTypeSettingsCurrent = $RegistrySettings | where Name -like ($ConnectionTypeSettings.Name + "*Current")

        $TargetRegPropertyNames =  $ConnectionTypeSettings | Select-Object -ExpandProperty Property -ErrorAction SilentlyContinue | Sort-Object
        $CurrentRegPropertyNames = $ConnectionTypeSettingsCurrent | Select-Object -ExpandProperty Property -ErrorAction SilentlyContinue | Sort-Object

        $TargetPropertyValues = $ConnectionTypeSettings | Get-ItemProperty -ErrorAction SilentlyContinue
        $CurrentPropertyValues = $ConnectionTypeSettingsCurrent | Get-ItemProperty -ErrorAction SilentlyContinue

        $TargetProfileName = $TargetPropertyValues.ProfileName


        #Check if connection with same connection type exists
        $namespaceName = "root\cimv2\mdm\dmmap"
        $className = "MDM_VPNv2_01"
        if($IsDevicetunnel){
            $CurrentConnection = Get-CimInstance -Namespace $namespaceName -ClassName $className | Where-Object DeviceTunnel -eq "True" -ErrorAction SilentlyContinue
        }
        else{
            $CurrentConnection = Get-CimInstance -Namespace $namespaceName -ClassName $className | Where-Object DeviceTunnel -ne "True" -ErrorAction SilentlyContinue
        }
        

        ## If no settings are configured, remove connection
        if ($NULL -eq $TargetRegPropertyNames) {
            Write-Log -Message "No settings were configured. Removing any connection with type $ConnectionTypeDisplayName..." -Level 'Info' 

            if($CurrentConnection){
                Remove-AovpnConnection -IsDevicetunnel $IsDevicetunnel
            }
            Remove-Item -Path "$RegistryPath\Current" -ErrorAction SilentlyContinue
            Continue Main
        }
        

        # Check mandatory settings
        Write-Log -Message "Running check for mandatory Settings..." -Level 'Info' 
        Test-AovpnConfiguration -TargetPropertyValues $TargetPropertyValues -DeviceTunnel $IsDevicetunnel
        
        # If it does not exist, create 'Current' Reg-Key 
        if (!$ConnectionTypeSettingsCurrent) {
            New-Item -Path ($RegistryPath+"\Current") -Force
            
        }
        #If it does exist, check if there is already a VPN-Profile with the same name as the new one
        else {
            #If there is connection with same connection type, run configuration comparison
            if ($null -ne $CurrentConnection) {
                $ConfigurationDifferencesExist = Compare-AovpnConfiguration -TargetPropertyValues $TargetPropertyValues -CurrentPropertyValues $CurrentPropertyValues -TargetRegPropertyNames $TargetRegPropertyNames -CurrentRegPropertyNames $CurrentRegPropertyNames
            } 
        }

        # Build Profile
        Write-Log -Message "Building configuration..." -Level 'Info' 
        $ProfileXML = Build-ConfigfromGPO -TargetPropertyValues $TargetPropertyValues -DeviceTunnel $IsDevicetunnel
        $ProfileFormatted = Format-XML $ProfileXML.OuterXml

        # If there were configuration differences, remove outdated connection with ProfileName
        if ($ConfigurationDifferencesExist) {
            Write-Log -Message "Removing currently configured $ConnectionTypeDisplayName..." -Level 'Info' 
            Remove-AovpnConnection -IsDevicetunnel $IsDevicetunnel
        }

        #Remove properties from 'Current' key 
        foreach ($property in $CurrentRegPropertyNames) {
            Remove-ItemProperty -Path "$RegistryPath\Current" -Name $Property
        }

        #Create VPN-Connection from Profile.xml
        Write-Log -Message "Creating new connection..." -Level 'Info' 
        Set-AovpnConnection -ProfileName $TargetProfileName

        #Then copy values from 'target' to 'current'
        foreach ($Property in $TargetRegPropertyNames) {
            Copy-ItemProperty -Path $RegistryPath -Destination "$RegistryPath\Current" -Name $Property
        }
    }
    catch {
        Write-Log -Message "Error in $ConnectionTypeDisplayName processing: $($_.Exception.Message)" -Level 'Error' 
    }
    finally{
        Write-Log -Message "Finished processing $ConnectionTypeDisplayName connection." -Level 'Info' 

        #Trim log file to max length
        $LogfileContent = Get-Content -Path $Logfile
        if ($LogfileContent.Length -gt $MaxLogLength) {
            $LogfileContent = $LogfileContent | Select-Object -Last $MaxLogLength
            Set-Content -Path $Logfile -Value $LogfileContent
        }
        
    }

}


