# Group Policies for the Windows native VPN-Client 
## Synopsis

Easy Windows VPN management with **G**POs for the **Wi**ndows **na**tive **VPN** client (GwinaVPN)!

## Description

The native Windows VPN client provides sufficient capabilities for most Remote Access scenarios and even provides device level VPN capabilities in enterprise environments. To unlock the full range of features, Microsoft provides a single method of deployment: creating XML-based files containing the VPN settings and deploying these VPN profiles with a Powershell script.

This recommended procedure leaves open a lot of questions, for exampe:

- How do administrators centrally deploy the VPN connections?
- How can these connections be changed after they have been deployed?
- How do administrators remove VPN connections from clients?
- How can administrators safely change the VPN connection settings for clients that are currently connected remotely?
  
This project attempts to answer these questions by providing Windows VPN Client managability through Group Policy settings. 

P.S.: This project was created with Microsoft Always On VPN connections in mind so most of the current functionality is targeted towards that specific use case.

## Features
### Configuration
- All VPN settings are done via Group Policies
- Supports two connection types:
  - **Device Tunnel**: VPN connection at system boot (machine-level)
  - **All User Connection (AUC)**: VPN connection for all user logons (user-level)
- Per-User VPNs are NOT supported - only system wide user VPN connections can be configured
- One Device Tunnel and one AUC can be managed at a time by GwinaVPN

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
| Supported Authentication Methods      | Machine Certificate |   EAP-TLS|

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
  - `GwinaVPN_DT_LOG.txt` (Device Tunnel)
  - `GwinaVPN_AUC_LOG.txt` (All User Connection)
- Logs operations with timestamps and severity levels (Info, Error)
- Automatically trims logs to prevent excessive file growth
- Log file location, name and length customizable

## Requirements

- **PowerShell 5.1 or later**
- **Windows 10 1809 or later**
- **Execution Context**: Script **must run as SYSTEM** (not just Administrator)


## Quickstart
1. Drop the .admx and .adml file in the respective directories in your domains [Central Store for Group Polices](https://learn.microsoft.com/en-us/troubleshoot/windows-client/group-policy/create-and-manage-central-store).
   
2. Create a GPO, filter it to a newly created Active Directory Group and configure (at least) the mandatory settings under Computer Configuration/Administrative Templates/GwinaVPN/[Connection Type]. Mandatory settings are found in the root of the respective connection type settings tree.

![DT-Settings.png](https://github.com/astang0/GwinaVPN/blob/main/src/DT-Settings.png)


3. Create and share a directory that contains [Set-GwinaVPN.ps1](https://github.com/astang0/GwinaVPN/blob/main/Set-GwinaVPN.ps1).
   
4. Through a scheduling mechanism of your choice, do the following regularly (schedule depending on your needs):

    4.1 Sync the contents of the shared folder to a local directory on the devices that the VPN connection should be deployed on. 

    4.2 Run Set-GwinaVPN.ps1 from local folder with SYSTEM context.

5. Add users or computers to your AD group and wait until all settings have been synced.
   
6. Done. Now the Always On VPN Connection is regularly updated according to the settings that have been set through Group Policy.

7. If you want to remove a connection from a device, just remove the user/computer from the AD group. 
   <br/>The script will remove the connection if there are no settings configured in the GPO.


- Running the script without GPO configuration does nothing. 
- Start managing existing connections by reusing the name of the existing connection in the Group Policies
Alternatively use the same connection name to start managing the existing connection.



## Active Maintenance

This project currently includes all the functionality needed to deploy basic VPN profiles to Windows clients but does not yet include all available configuration options.

I will keep adding more features over time but if there is anything specific you would like to have included feel free to reach out.


