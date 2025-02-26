# Always on VPN From GPO
## How it works
The values of the settings found in the provided administrative template are stored in the Windows Registry. The provided script then uses the stored values to create a formatted Always on VPN profile (.xml), which is then used to (re-)deploy a VPN connection.

Before creating a profile, the script validates that all mandatory settings have been set. This prevents administrators from pushing out invalid VPN profiles.

After creating the profile, the script by default uses Richard Hicks' [New-AovpnConnection.ps1](https://github.com/richardhicks/aovpn/blob/master/New-AovpnConnection.ps1) to create a VPN connection from the Profile.xml. I recommend that you use his script since it removes a few Registry artifacts of older connections before deploying a new one. If you decide against it, however, you´ll have to edit the provided script to use your own VPN creation script instead. It is assumed that the scripts are located in the same directory.

A copy of the latest Profile.xml is stored in the same location the script is in by default.

## Quickstart
1. Drop the .admx and .adml file in the respective directories in your domains [Central Store for Group Polices](https://learn.microsoft.com/en-us/troubleshoot/windows-client/group-policy/create-and-manage-central-store).
   
2. Create a GPO, filter it to a newly created Active Directory Group and configure (at least) the mandatory settings under Computer Configuration/Administrative Templates/Always On VPN From GPO/[Connection Type]:

![DT-Settings.png](https://github.com/astang0/AovpnFromGPO/blob/main/src/DT-Settings.png)


3. Create and share a directory that contains both [Set-AovpnFromGPO.ps1](https://github.com/astang0/AovpnFromGPO/blob/main/Set-AovpnFromGPO.ps1) and [New-AovpnConnection.ps1](https://github.com/richardhicks/aovpn/blob/master/New-AovpnConnection.ps1).
4. Through a scheduling mechanism of your choice do the following regularly (schedule depending on your needs):

    3.1 Sync the contents of the shared folder to a local directory on the devices that AOVPN should be deployed on.

    3.2 Run Set-AovpnFromGPO.ps1 in SYSTEM context with params of your choice.

5. Add users or computers to your AD group.
   
6. Done.

7. If you want to remove a connection from a device, just remove the user/computer from the AD group. 
   <br/>The script will remove the connection if there are no settings configured in the GPO.

For more information refer to the wiki.

## Parameters
#### ```-ProfileName```
Sets the name of the profile. You should only use one name per connection type throughout your organization to avoid unwanted side effects. For device tunnels you could use 'Devicetunnel' and for the user tunnel you could use '[Insert your company name] VPN', for example.

#### ```-Devicetunnel``` (Alias: ```-DT```)
Use if you want to deploy an Always on VPN Devicetunnel. Requires Windows 10/11 Enterprise or Education.

#### ```-AllUserConnection``` (Alias: ```-AUC```)
Use if you want to deploy an Always on VPN Usertunnel. This will deploy the connection for all users of a device.

#### ```-TranscriptLocation``` (Alias: ```-TL```)
Writes the output of the scripts latest run to a specified file. Useful for troubleshooting purposes.

#### ```-OutProfile``` (Alias: ```-OP```)
Use if you want to specify the output location and file name of the created Profile.xml, otherwise it will be saved to the scripts root directory.

#### ```-OutProfileOnly``` (Alias: ```-OPO```)
Use if you only want the script to create the Profile.xml and NOT create an AOVPN connection from it.


## Supported Features
| Feature                               |Devicetunnel   |Usertunnel |
| :---                                  |    :----:     |   :---:   |
| VPN-Protocols                         |IKEv2/IPsec    |    SSTP      |
| Set Custom Cryptography Settings      |     ✅        |    ❌      |
| Define Custom VPN-Server              | ✅            |   ✅      |
| Define Custom IP Routes               | ✅            |   ✅      |
| Define Custom DNS-Suffix when connected|     ✅        |    ✅      |
| Define Trusted Networks               | ✅            |   ✅      |
| Enable DNS-Registration               | ✅            |   ✅      |
| Show/Hide Advanced Options Edit Button| ✅            |   ✅      |
| Show/Hide Disconnect Button           | ✅            |   ✅      |
| Show/Hide Devicetunnel in UI          |       ✅      |    —       |
| Allow Class Based Default Route       |     ❌        |    ❌      |
| Define Custom VPN-Server              | ✅            |   ✅      |
|Authentication Methods                 | Machine Certificate |   EAP|

