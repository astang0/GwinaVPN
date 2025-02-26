<#
.SYNOPSIS
Creates an Always On VPN Profile based on values stored in the registry.

.DESCRIPTION
This script uses values stored in the registry to build an AOVPN-Profile.
The profile is then used to create a new VPN connection.
The script assumes that you use Richard Hicks' New-AovpnConnection.ps1 to create the VPN-Connection.
It also assumes that all necessary files are stored in the same directory. 

.PARAMETER Devicetunnel
Use if new connection is a Devicetunnel.

.PARAMETER AllUserConnection
Use if new connection is a AllUserConnection.

.PARAMETER ProfileName
Name of the connection.

.PARAMETER TranscriptLocation
Creates a transcript of last run in specified file.

.PARAMETER OutProfile
Writes the created profile to a specified file, otherwise it is written to .\Latest_[ConnectionType]_Profile.xml 

.PARAMETER OutProfileOnly
Prevents the new VPN connection from being created.
In this case, only the profile is written to the with '-OutProfile' specified file.



#>

[CmdletBinding(SupportsShouldProcess)]

Param (

    [Alias("AUC")]
    [switch]$AllUserConnection,
    [Alias("DT")]
    [switch]$DeviceTunnel,
    [Parameter(Mandatory = $true)]
    [string]$ProfileName,
    [Alias("TL")]
    [string]$TranscriptLocation,
    [Parameter(HelpMessage = 'Enter an OutFile-Path for the created Profile.')]
    [Alias("OP")]
    [string]$OutProfile,
    [Alias("OPO")]
    [switch]$OutProfileOnly


)


#Start logging if wanted
if ("" -ne $TranscriptLocation) {
    Start-Transcript -Path $TranscriptLocation -Force
}

#Check if a connection type was chosen
if ($AllUserConnection -and $DeviceTunnel) {
    Write-Error "Multiple connection types detected. Please choose either '-Devicetunnel' or '-AllUserConnection'."
    Exit 1
}
elseif (!$AllUserConnection -and !$DeviceTunnel) {
    Write-Error "No connection types detected. Please choose either '-Devicetunnel' or '-AllUserConnection'."
    Exit 1
}


#Check if script is running in correct context
if ($DeviceTunnel -or $AllUserConnection) {
    $CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    If ($CurrentPrincipal.Identities.IsSystem -ne $True) {
        Write-Warning "Script must run as System when using '-Devicetunnel' or '-AllUserConnection'."
        Stop-Transcript
        Exit 1
    }
}

#Change directory to directory that the script was executed in
Set-Location $PSScriptRoot

#Set default OutProfile-Path
if ($OutProfile -eq "") {
    if ($DeviceTunnel) {
        $OutProfile = ".\Latest_Devicetunnel_Profile.xml"
    }
    if ($AllUserConnection) {
        $OutProfile = ".\Latest_AllUserConnection_Profile.xml"
    }
    
}

<#--------------------Start Declaring Functions---------------------#>
<#--------------------Declare Function to build Profile.xml from registry settings---------------------#>
function BuildConfigfromGPO {
   
    [CmdletBinding()]
    param (
        [string]
        $path
    )
    
    $profileconf = Get-ItemProperty -Path $path

    ##Create XML-Document with Profile Base Structure
    $ProfileXML = [xml]@"
<VPNProfile>
    <AlwaysOn>true</AlwaysOn>
    <DeviceTunnel>false</DeviceTunnel>
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
    try {
        ##Set Settings in VPN-Profile-Node
        $VPNProfileNode = @("DNSSuffix", "DisableDisconnectbutton", "DisableAdvancedOptionsEditButton", "RegisterDNS")
        foreach ($Setting in $VPNProfileNode) {
            if ($NULL -ne $profileconf.$Setting) {
                $ProfileXML.VPNProfile.$Setting = $profileconf.$Setting
            }
        }

        ##Set Settings in NativeProfile-Node
        $NativeProfileNode = @("DisableClassBasedDefaultRoute")
        foreach ($Setting in $NativeProfileNode) {
            if ($NULL -ne $profileconf.$Setting) {
                $ProfileXML.VPNProfile.NativeProfile.$Setting = $profileconf.$Setting
            }
        }

        #Set Protocol type
        if ($DeviceTunnel) {
            $ProfileXML.VPNProfile.NativeProfile.NativeProtocolType = "IKEv2"
        }
        else {
            $ProfileXML.VPNProfile.NativeProfile.NativeProtocolType = "Automatic"
        }
        

        ##Set Devicetunnel flag if necessary
        if ($DeviceTunnel) {
            $ProfileXML.VPNProfile.DeviceTunnel = "true"
        }

        ##Adding Authentication Settings
        $AuthSettingsNode = $ProfileXML.CreateElement("Authentication")
        if ($DeviceTunnel) {
            $MachineMethodNode = $ProfileXML.CreateElement("MachineMethod")
            $MachineMethodNode.InnerText = "Certificate"
            $AuthSettingsNode.AppendChild($MachineMethodNode) | Out-Null
        }
        else {
            #Add User Method
            $UserMethodNode = $ProfileXML.CreateElement("UserMethod")
            $UserMethodNode.InnerText = "Eap"
            $AuthSettingsNode.AppendChild($UserMethodNode) | Out-Null

            #Add Machine Method
            $MachineMethodNode = $ProfileXML.CreateElement("MachineMethod")
            $MachineMethodNode.InnerText = "Eap"
            $AuthSettingsNode.AppendChild($MachineMethodNode) | Out-Null

            #Add Eap Node
            $EapNode = $ProfileXML.CreateElement("Eap")
            $EapConfigNode = $ProfileXML.CreateElement("Configuration")
        
            #Add Eap configuration
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
            
                    #Add Cryptography-Setting
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
            $SplitRoute = $Route -split "/"

            $RouteIPAddress = $SplitRoute[0]
            $RouteMask = $SplitRoute[1]

            if ($NULL -ne $SplitRoute[2]) {
                $RouteMetric = $SplitRoute[2]
            }
            else {
                $RouteMetric = 1
            }
    
            #Create New Route-Node
            $newroute = $ProfileXML.CreateElement("Route")
    
            #Add Address
            $addip = $ProfileXML.CreateElement("Address")
            $addip.InnerText = $RouteIPAddress
            $newroute.AppendChild($addip) | Out-Null

            #Add Mask
            $addmask = $ProfileXML.CreateElement("PrefixSize")
            $addmask.InnerText = $RouteMask
            $newroute.AppendChild($addmask) | Out-Null

            #Add Metric
            $addmetric = $ProfileXML.CreateElement("Metric")
            $addmetric.InnerText = $RouteMetric
            $newroute.AppendChild($addmetric) | Out-Null

            #Append new routes to Profile.xml
            $ProfileXML.VPNProfile.AppendChild($newroute) | Out-Null
            
            

        }

        Return $ProfileXML
    }
    catch {
        Write-Error "Something went wrong while building Profile $ProfileName." -ErrorAction Stop
    }
    
    
}

<#--------------------Declare Function to check if mandatory settings have been set---------------------#>
function CheckMandatorySettings {

    [CmdletBinding()]
    param (
        [string]
        $path
    )
    
    $mandatorysettings = @("Routes", "TrustedNetworkDetection", "Servers", "DnsSuffix")
    
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
            Write-Error "Setting '$Setting' must be configured." -ErrorAction Continue
            $settingsmissing++
        }   
    }
   
    #If any mandatory settings are unconfigured, exit
    if ($NULL -ne $settingsmissing) {
        Write-Error "$settingsmissing mandatory setting(s) have not been configured. Please check group policies." -ErrorAction Stop
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

<#--------------------End Declaring Functions---------------------#>



#Set Registry-Path that contains the values that were set through GPO and Key that contains current config
if ($DeviceTunnel) {
    $desiredconfregpath = "HKLM:\SOFTWARE\Policies\AovpnFromGPO\DeviceTunnel"
}
elseif ($AllUserConnection) {
    $desiredconfregpath = "HKLM:\SOFTWARE\Policies\AovpnFromGPO\AllUserConnection"
}

$currentconfregpath = "$desiredconfregpath\Current"

#Get properties of the Registry keys
$desiredproperties = Get-Item -Path $desiredconfregpath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property | Sort-Object 
$currentproperties = Get-Item -Path $currentconfregpath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property | Sort-Object


## If no settings are configured, remove tunnel with ProfileName
if ($NULL -eq $desiredproperties) {
    Write-Host "No settings were configured. Checking if profile with name $ProfileName exists..."
    $Connection = Get-VpnConnection -AllUserConnection -Name $ProfileName -ErrorAction SilentlyContinue

    if($null -ne $Connection){
        
        Write-Host 
        if ($Connection.Connectionstatus -eq "Connected") {
            Write-Host "Disconnecting VPN-Connection $ProfileName..."
            rasdial.exe $ProfileName /disconnect
        }
    
        Write-Host "Removing Profile $ProfileName..."
        Remove-VpnConnection -Name $ProfileName -AllUserConnection -Force

        foreach ($property in $currentproperties) {
            Remove-ItemProperty -Path $currentconfregpath -Name $Property
        }
        
        
    }
    else{
        Write-Host "Profile $ProfileName does not exist. Exiting..."
    }
    Stop-Transcript
    Exit 0
}

    
Write-Host "Running check for mandatory Settings..."
CheckMandatorySettings -path $desiredconfregpath
Write-Host "Check successful. Comparing desired and current profile..."


# vvvvvvvvvvvvv Compare current to desired config vvvvvvvvvvvvvvvvvv #

#Check if Registry path for current configuration exists
$currentconfregpathexists = Test-Path $currentconfregpath

#If it does not exist, create 'Current' Reg-Key 
if (!$currentconfregpathexists) {
    New-Item -Path $currentconfregpath -Force
}
#If it does exist, check if there is already a VPN-Profile with the same name as the new one
else {
    
    $Connection = Get-VpnConnection -AllUserConnection -Name $ProfileName -ErrorAction SilentlyContinue
    
    #If there is connection with same name and the 'Current'-Subkey is populated
    if ($null -ne $Connection) {

        #Compare current configuration to desired configuration 
        try {
            $match = Compare-Object -ReferenceObject $desiredproperties -DifferenceObject $currentproperties
        }
        catch {
            Write-Host "No current configuration found. Skipping configuration comparison..."
            $match = 1
        }
    
        #If there are identical properties set in both keys, compare the property values
        if ($null -eq $match) {
    
            $configdifferences = 0
    
            foreach ($Property in $desiredproperties) {
                    
                $desiredvalue = (Get-ItemProperty -Path $desiredconfregpath).$Property
                $currentvalue = (Get-ItemProperty -Path $currentconfregpath).$Property
                   
                #If the property values are arrays, compare content of arrays
                if ($desiredvalue -is [array]) {
                    if ($desiredvalue.length -gt $currentvalue.length) {
                        $length = $desiredvalue.Length
                    }
                    else {
                        $length = $currentvalue.Length
                    }

                    for ($j = 0; $j -lt $length; $j++) {
                        if (!($desiredvalue[$j] -ceq $currentvalue[$j])) {
                            $configdifferences++
                            Break
                        }
                    }
                }
                #Else compare property values directly
                elseif (!($desiredvalue -ceq $currentvalue)) {
                    $configdifferences++
                    Break
                }
                    
                     
            }
    
            # If there are no differences between the desired and the currently configured settings, exit script
            if ($configdifferences -eq 0) {
                Write-Host "Configurations are identical. No changes will be made to the VPN-Connection $ProfileName."
                Exit 0
            }
                
        }

    
    } 
}

## Build Profile
$ProfileXML = BuildConfigfromGPO -Path $desiredconfregpath
$ProfileFormatted = Format-XML $ProfileXML.OuterXml
    
#Write profile to specified OutProfile-Path if wanted, else use default Path
try {
        
    $ProfileFormatted | Out-File $OutProfile 
    Write-Host "Created Profile.xml in Path $OutProfile"

    #Stop if OutProfileOnly is set
    if ($OutProfileOnly) {
        Exit 0
    }
}
catch {
    Write-Error "Profile $ProfileName could not be created in Path $OutProfile." -ErrorAction Stop
}

# If there were configuration differences, remove outdated connection with ProfileName
if (($null -ne $match) -or ($configdifferences -gt 0)) {
    if ($Connection.Connectionstatus -eq "Connected") {
        Write-Host "Disconnecting VPN-Connection $ProfileName..."
        rasdial.exe $ProfileName /disconnect
    }

    Write-Host "Removing Profile $ProfileName..."
    Remove-VpnConnection -Name $ProfileName -AllUserConnection -Force
    
}

#At this point there should be no connection with ProfileName configured so check if for some reason a connection still exists
if($NULL -ne (Get-VpnConnection $ProfileName -AllUserConnection -ErrorAction SilentlyContinue)){
    Write-Error "Profile $ProfileName already exists and could not be removed. Aborting script."
    Exit 1
}

#Create VPN-Connection from Profile.xml
Write-Host "Creating new connection..."

try {
    if ($AllUserConnection) {
        .\New-AovpnConnection -xmlFilePath $OutProfile -ProfileName $ProfileName -AllUserConnection
    }
    else{
        .\New-AovpnConnection -xmlFilePath $OutProfile -ProfileName $ProfileName -Devicetunnel
    }
    
}
catch {
    Write-Error $_.Exception.InnerException.Message -ErrorAction Continue
    Stop-Transcript
    Exit 1
}



#Remove properties from 'Current' key 
foreach ($property in $currentproperties) {
    Remove-ItemProperty -Path $currentconfregpath -Name $Property
}

#Then copy values from 'desired' to 'current'
foreach ($Property in $desiredproperties) {
    Copy-ItemProperty -Path $desiredconfregpath -Destination $currentconfregpath -Name $Property
}

Stop-Transcript




