# Always on VPN From GPO
## Synopsis

Manage Microsoft Always on VPN connections with Group Policies! 

## Description

The native Windows VPN client provides sufficient capabilities for most Remote Access scenarios and even provides device level VPN capabilities in enterprise environments. To unlock the full range of features, Microsoft provides a single method of deployment: creating XML-based files containing the VPN settings and deploying these VPN profiles with a Powershell script.

This recommended procedure leaves open a lot of questions, for exampe:

- How do administrators centrally deploy the VPN connections?
- How can these connections be changed after they have been deployed?
- How do administrators remove VPN connections from clients?
- How can administrators safely change the VPN connection settings for clients that are currently connected remotely?
  
This project attempts to answer these questions by providing easy Microsoft Always on VPN managability through Group Policy settings. 

## Features
### Configuration
- All VPN settings are done via Group Policies
- Supports two connection types:
  - **Device Tunnel**: VPN connection at system boot (machine-level)
  - **All User Connection (AUC)**: VPN connection for all user logons (user-level)
- Per-User VPNs are NOT supported - only system wide user VPN connections can be configured
- One Device Tunnel and one AUC can be managed at a time by AovpnFromGPO

### Profile Building
- Constructs XML-based VPN profiles based on GPO settings and creates a connection from the profile all within the script
- Overview over supported settings:
  
| Setting                               |Devicetunnel   |Usertunnel |
| :---                                  |    :----:     |   :---:   |
| Supported VPN-Protocols               |IKEv2/IPsec    |    SSTP      |
| Set Custom Cryptography Settings      |     ✅        |    ❌      |
| Define Custom Connection Name         | ✅            |   ✅      |
| Define Custom VPN-Server              | ✅            |   ✅      |
| Define Custom Domain Name Resolution Policies| ✅     |   ✅      |
| Define Custom IP Routes               | ✅            |   ✅      |
| Define Custom DNS-Suffix when connected|     ✅        |    ✅      |
| Define Trusted Networks               | ✅            |   ✅      |
| Define XML-based Traffic Filters      | ✅            |   ✅      |
| Enable DNS-Registration               | ✅            |   ✅      |
| Show/Hide Advanced Options Edit Button| ✅            |   ✅      |
| Show/Hide Disconnect Button           | ✅            |   ✅      |
| Show/Hide Devicetunnel in UI          |       ✅      |    —       |
| Allow Class Based Default Route       |     ❌        |    ❌      |
| Supported Authentication Methods      | Machine Certificate |   EAP|

### Connection Management
- Creates new VPN connections using the MDM_VPNv2 WMI class
- Checks all mandatory settings have been configured
- Detects and compares existing configurations
- Updates connections when configuration changes are detected
- Removes old connections before deploying new ones
- Performs comprehensive registry cleanup when removing connections
- Attempts failback in the event of failed connection (re)deployments

### Logging
- Creates separate log files for each connection type in same directory the script is run from:
  - `AOVPN_DT_LOG.txt` (Device Tunnel)
  - `AOVPN_AUC_LOG.txt` (All User Connection)
- Logs operations with timestamps and severity levels (Info, Error)
- Automatically trims logs to prevent excessive file growth
- Log file location, name and length customizable

## Requirements

- **PowerShell 5.1 or later**
- **Windows 10 1809 or later**
- **Execution Context**: Script **must run as SYSTEM** (not just Administrator)


## Quickstart
1. Drop the .admx and .adml file in the respective directories in your domains [Central Store for Group Polices](https://learn.microsoft.com/en-us/troubleshoot/windows-client/group-policy/create-and-manage-central-store).
   
2. Create a GPO, filter it to a newly created Active Directory Group and configure (at least) the mandatory settings under Computer Configuration/Administrative Templates/Always On VPN From GPO/[Connection Type]:

![DT-Settings.png](https://github.com/astang0/AovpnFromGPO/blob/main/src/DT-Settings.png)


3. Create and share a directory that contains [Set-AovpnFromGPO.ps1](https://github.com/astang0/AovpnFromGPO/blob/main/Set-AovpnFromGPO.ps1).
4. Through a scheduling mechanism of your choice do the following regularly (schedule depending on your needs):

    4.1 Sync the contents of the shared folder to a local directory on the devices that AOVPN should be deployed on. (Optional, but is recommended)

    4.2 Run Set-AovpnFromGPO.ps1 from local or shared folder in SYSTEM context.

5. Add users or computers to your AD group and wait until all settings have been synced.
   
6. Done. Now the Always On VPN Connection is regularly updated according to the settings that have been set through Group Policy.

7. If you want to remove a connection from a device, just remove the user/computer from the AD group. 
   <br/>The script will remove the connection if there are no settings configured in the GPO.


- Running the script without GPO configuration does nothing. 
- Start managing existing connections by reusing the name of the existing connection in the Group Policies
Alternatively use the same connection name to start managing the existing connection.

## Considerations

###  Critical!!!

1. **Script Must Run as SYSTEM**
   - The script checks if it's running in SYSTEM context
   - Will fail if run as a regular Administrator
   - Use PsExec, scheduled tasks or other mechanisms ensure SYSTEM execution

2. **Destructive Updates**
   - When configuration changes are detected, **existing AovpnFromGPO-managed VPN connections are removed and recreated**
   - Any VPN-related registry artifacts are cleaned up during this process

3. **Connection Type Filtering**
   - The script distinguishes connections by the conncection type
   - Only one Device Tunnel and one All User connection can exist per configuration
   - Existing connections are replaced, not merged

###  Important!

4. **Error Recovery**
   - If VPN connection creation fails, the script attempts to revert to the previous configuration
   - If no previous configuration exists, the original error is thrown

5. **Registry Cleanup**
   - When removing connections, the script cleans up registry artifacts 
   - May affect manually created VPN profiles with the same name

6. **Multi-String Registry Values**
   - Properties like `Routes` and `TrustedNetworkDetection` are multi-string values
   - Each item should be on a separate line in the registry editor

7. **Protocol Selection**
   - Device Tunnel always uses **IKEv2**
   - All User Connection uses **Automatic** protocol selection, which means SSTP with IKEv2 as fallback protocol
   - Cannot currently not be customized

8. **Split Tunnel Routing**
   - Script always uses **SplitTunnel** routing policy
   - All traffic is NOT forced through the VPN

### Notable Behaviors

9. **Configuration Comparison**
   - If target configuration matches current configuration exactly, no changes are made
   - Comparison is **case-sensitive** for string values
   - If changes are detected, a full redeployment occurs

10. **Log File Management**
    - Log files are created in the script's working directory
    - Default maximum log size is 1000 lines; older entries are removed automatically -> can be adjusted in beginning of script
    - Device Tunnel and AUC have separate log files
    - Custom log file location, name and length can be configured in the starting section of the script

11. **Missing Configuration**
    - If all registry settings are removed, any existing VPN connection is deleted
    - Registry cleanup still occurs
    - No new connection is created

12. **EAP Configuration**
    - EAP configuration must be provided as XML in the registry
    - The XML is inserted directly into the VPN profile
    - Malformed XML will cause profile creation to fail

13. **Always On**
    - Script currently always deploys connections as "Always On" (hence the projects' name...), meaning the VPN client will automatically start the VPN connection anytime an untrusted network is detected 

## Security Considerations

- Script requires SYSTEM context; use secure scheduled task configuration
- Registry may contain sensitive VPN configuration (same would apply when working with XML-based configuration files)
- EAP certificates should be properly secured on the system


## Further Developement

This project currently includes all the functionality needed to deploy basic VPN profiles to Windows clients but does not yet include all available configuration options.

If there is anything you would like to have included feel free to reach out.


