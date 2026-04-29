<#
.SYNOPSIS
Creates an Always On VPN Profile based on values stored in the registry.

.DESCRIPTION
This script uses values stored in the registry to build an AOVPN-Profile.
The profile is then used to create a new VPN connection.


.PARAMETER OutProfile
Writes the created profile to a specified file. If not set, no file is created. 

.PARAMETER OutProfileOnly
Prevents the new VPN connection from being created.
In this case, only the profile is written to the with '-OutProfile' specified file.



#>

[CmdletBinding(SupportsShouldProcess)]

Param (

    
   
    [Parameter(HelpMessage = 'Enter an OutFile-Path for the created Profile.')]
    [Alias("OP")]
    [string]$OutProfile,
    [Alias("OPO")]
    [switch]$OutProfileOnly


)

#Change directory to directory that the script was executed in
Set-Location $PSScriptRoot

#Declare Registry Paths for GPOs
$regpathdevicetunnel = "HKLM:\SOFTWARE\Policies\AovpnFromGPO\DeviceTunnel"
$regpathusertunnel = "HKLM:\SOFTWARE\Policies\AovpnFromGPO\AllUserConnection"


#Check if GPOs have been set 
$ConnectionTypes = @()
if (Test-Path $regpathdevicetunnel) {
    $ConnectionTypes += "Devicetunnel"
}
if (Test-Path $regpathusertunnel) {
    $ConnectionTypes += "Usertunnel"
}

#Check if script is running in correct context
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
If ($CurrentPrincipal.Identities.IsSystem -ne $True) {
    $NotRunningInSystemContext = $true
}




<#--------------------Start Declaring Functions---------------------#>
<#--------------------Declare Function to build Profile.xml from registry settings---------------------#>
function Build-ConfigfromGPO {
   
    [CmdletBinding()]
    param (
        [string]$path,
        [bool]$DeviceTunnel
    )
    
    $profileconf = Get-ItemProperty -Path $path

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
        if ($NULL -ne $profileconf.$Setting) {
            $ProfileXML.VPNProfile.$Setting = $profileconf.$Setting
        }
    }

    # Set Settings in NativeProfile-Node
    $NativeProfileNode = @("DisableClassBasedDefaultRoute")
    foreach ($Setting in $NativeProfileNode) {
        if ($NULL -ne $profileconf.$Setting) {
            $ProfileXML.VPNProfile.NativeProfile.$Setting = $profileconf.$Setting
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
        foreach ($line in $profileconf.EapConfig) {
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
            if ($NULL -ne $profileconf.$Setting) {
            
                # Add Cryptography-Setting
                $addcryptosetting = $ProfileXML.CreateElement($Setting)
                $addcryptosetting.InnerText = $profileconf.$Setting
                $CryptoSuiteNode.AppendChild($addcryptosetting) | Out-Null

            
            }
        }
        #Append IPsec-Cryptography to NativeProfile Node in Profile.xml
        $ProfileXML.VPNProfile.NativeProfile.AppendChild($CryptoSuiteNode) | Out-Null
    }
        
        
        
    ##Add DisableClassBasedDefaultRoute Setting
    $DisableClassBasedDefaultRouteNode = $ProfileXML.CreateElement("DisableClassBasedDefaultRoute")
    if ($NULL -ne $profileconf.DisableClassBasedDefaultRoute) {
        $DisableClassBasedDefaultRouteNode.InnerText = $profileconf.DisableClassBasedDefaultRoute
    }
    else {
        $DisableClassBasedDefaultRouteNode.InnerText = "true"
    }
    $ProfileXML.VPNProfile.NativeProfile.AppendChild($DisableClassBasedDefaultRouteNode) | Out-Null
        
        

    
    ##Trusted Network Detection is not in VPNProfile-Node-Loop because it needs additional formatting
    foreach ($Entry in $profileconf.TrustedNetworkDetection) {
        $TrustedNetworks = "$TrustedNetworks,$Entry"  
    }
    $ProfileXML.VPNProfile.TrustedNetworkDetection = $TrustedNetworks.Substring(1)

    #Servers setting must be configured seperately because of special formatting
    $value = $profileconf.Servers
    $ProfileXML.VPNProfile.NativeProfile.Servers = "$value;$value"
    
    #Each Route is added as separate Node with multiple child nodes
    foreach ($Route in $profileconf.Routes) {
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
    if ($NULL -ne $profileconf.TrafficFiltersXML) {

        #Join each line to string then split string into traffic filter xml elements
        $TrafficFiltersXMLString = $profileconf.TrafficFiltersXml -join "`n"
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
    if ($NULL -ne $profileconf.DomainNameInformation) {
        foreach ($Entry in $profileconf.DomainNameInformation) {
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

<#--------------------Declare Function to check if mandatory settings have been set---------------------#>
function Test-AovpnConfiguration {

    [CmdletBinding()]
    param (
        [string]$path,
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
        try {
            Get-ItemPropertyValue -Path $path -Name $Setting | Out-Null
        }
        catch {
            Write-Error "ERROR: Setting '$Setting' must be configured." -ErrorAction Continue
            $settingsmissing++
        }   
    }
    
    if ($NULL -ne $settingsmissing) {
        Write-Error "ERROR: $settingsmissing mandatory settings have not been configured for connection type $Connectiontype. Please check GPO settings."
        Stop-Transcript
        Continue main
    }
    
}

<#--------------------Declare Function to format XML-Document to readable string---------------------#>
function Format-XML ([xml]$xml, $indent = 3, $format = "Indented") {
    $StringWriter = New-Object System.IO.StringWriter
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter
    $xmlWriter.Formatting = $format
    $xmlWriter.Indentation = $Indent
    $xml.WriteContentTo($XmlWriter)
    $XmlWriter.Flush()
    $StringWriter.Flush()
    Write-Output $StringWriter.ToString()
}

<#-------------------Declare function to deploy the VPN connection-----------------------------------#>
function Add-AovpnConnection {

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

        $session.CreateInstance($namespaceName, $newInstance)
        $Message = "Created $ProfileName profile."
        Write-Host "LOG: $Message"
    }
    catch [Exception] {
        $Message = "Unable to create $ProfileName profile: $_"
        Write-Host "LOG: $Message"
        Stop-Transcript
        Continue Main
    }
    $Message = "Complete."
    Write-Host "LOG: $Message"
}

function Remove-AovpnConnection {
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
        Write-Host "LOG: No connection of this type found."
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
        Write-Error "ERROR: A connection with the current connection type already exists and could not be removed. Instance ID: $CurrentConnectionName. Aborting deployment."
        Stop-Transcript
        Continue main
    }
   
    $ProfileNameEscaped = $CurrentConnectionName
    $ProfileName = $ProfileNameEscaped.Replace("%20"," ") 
    Write-Host "LOG: Successfully removed connection $ProfileName. Starting Registry-Cleanup..."
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

    Write-Host "LOG: Registry-Cleanup finished. Removal of connection $ProfileName is complete."

}

<#--------------------End Declaring Functions---------------------#>


:main foreach ($ConnectionType in $ConnectionTypes) {


    #Set Registry-Path that contains the values that were set through GPO and Key that contains current config
    if ($ConnectionType -like "Devicetunnel") {
        $targetconfregpath = $regpathdevicetunnel
        $TranscriptLocation = ".\AOVPN_DT_LOG.txt"
        $IsDevicetunnel = $true
    }
    elseif ($ConnectionType -like "Usertunnel") {
        $targetconfregpath = $regpathusertunnel
        $TranscriptLocation = ".\AOVPN_AUC_LOG.txt"
        $IsDevicetunnel = $false
    }

    Start-Transcript -Path $TranscriptLocation -Force

    if ($NotRunningInSystemContext) {
        Write-Warning "Script must be run as System."
        Stop-Transcript
        Exit 1
    }

    #Check if connection with same connection type exists
    $namespaceName = "root\cimv2\mdm\dmmap"
    $className = "MDM_VPNv2_01"
    if($IsDevicetunnel){
        $CurrentConnection = Get-CimInstance -Namespace $namespaceName -ClassName $className | Where-Object DeviceTunnel -eq "True" -ErrorAction SilentlyContinue
    }
    else{
        $CurrentConnection = Get-CimInstance -Namespace $namespaceName -ClassName $className | Where-Object DeviceTunnel -ne "True" -ErrorAction SilentlyContinue
    }
    

    #Get properties of the Registry keys
    $currentconfregpath = "$targetconfregpath\Current"
    $targetproperties = Get-Item -Path $targetconfregpath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property | Sort-Object 
    $currentproperties = Get-Item -Path $currentconfregpath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property | Sort-Object


    ## If no settings are configured, remove connection
    if ($NULL -eq $targetproperties) {
        Write-Host "LOG: No settings were configured. Removing any connection with type $ConnectionType..."

        if($CurrentConnection){
            Remove-AovpnConnection -IsDevicetunnel $IsDevicetunnel
        }

        #Remove properties from 'Current' key 
        foreach ($property in $currentproperties) {
            Remove-ItemProperty -Path $currentconfregpath -Name $Property
        }
        Stop-Transcript
        Continue main
    }
    

    #Check mandatory settings
    Write-Host "LOG: Running check for mandatory Settings..."
    Test-AovpnConfiguration -path $targetconfregpath -DeviceTunnel $IsDevicetunnel
    $TargetProfileName = (Get-ItemPropertyValue -Path $targetconfregpath -Name ProfileName -ErrorAction SilentlyContinue)
    Write-Host "LOG: Check successful. Comparing target and current profile..."
   
    


    # vvvvvvvvvvvvv Compare current to target config vvvvvvvvvvvvvvvvvv #

    #Check if Registry path for current configuration exists
    $currentconfregpathexists = Test-Path $currentconfregpath

    #If it does not exist, create 'Current' Reg-Key 
    if (!$currentconfregpathexists) {
        New-Item -Path $currentconfregpath -Force
        
    }
    #If it does exist, check if there is already a VPN-Profile with the same name as the new one
    else {
    
        #If there is connection with same conenction type and the 'Current'-Subkey is populated
        if ($null -ne $CurrentConnection) {
            
            #Compare current configuration to target configuration 
            try {
                $match = Compare-Object -ReferenceObject $targetproperties -DifferenceObject $currentproperties -ErrorAction SilentlyContinue
            }
            catch {
                Write-Host "LOG: No current configuration found. Skipping configuration comparison..."
                $match = 1
            }
            
            #If there are identical properties set in both keys, compare the property values
            if ($null -eq $match) {
                $configdifferences = 0
    
                foreach ($Property in $targetproperties) {
                    
                    $targetvalue = (Get-ItemProperty -Path $targetconfregpath).$Property
                    $currentvalue = (Get-ItemProperty -Path $currentconfregpath).$Property
                   
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
                    Write-Host "LOG: Configurations are identical. No changes will be made to the VPN-Connection $ProfileName."
                    Stop-Transcript
                    Continue main
                }
                else{
                    Write-Host "LOG: Configuration changes detected."
                }
                
            }

    
        } 
    }

    ## Build Profile
    try {
        Write-Host "LOG: Building configuration..."
        $ProfileXML = Build-ConfigfromGPO -Path $targetconfregpath -DeviceTunnel $IsDevicetunnel
        
    
    }
    catch {
        Write-Error $_.Exception.InnerException.Message -ErrorAction Continue
        Stop-Transcript
        Continue main
    }


    $ProfileFormatted = Format-XML $ProfileXML.OuterXml

    # If there were configuration differences, remove outdated connection with ProfileName
    if (($null -ne $match) -or ($configdifferences -gt 0)) {

        Write-Host "LOG: Removing currently configured $Connectiontype..."
        Remove-AovpnConnection -IsDevicetunnel $IsDevicetunnel
    }

    #Remove properties from 'Current' key 
    foreach ($property in $currentproperties) {
        Remove-ItemProperty -Path $currentconfregpath -Name $Property
    }

    #Create VPN-Connection from Profile.xml
    Write-Host "LOG: Creating new connection..."

    try {
   
        Add-AovpnConnection -ProfileName $TargetProfileName
    
    }
    catch {
        Write-Error $_.Exception.InnerException.Message -ErrorAction Continue
        Stop-Transcript
        Continue main
    }


    #Then copy values from 'target' to 'current'
    foreach ($Property in $targetproperties) {
        Copy-ItemProperty -Path $targetconfregpath -Destination $currentconfregpath -Name $Property
    }

    Stop-Transcript
    Continue main


}

