<#
Copyright (C) 2016 by IS4U (info@is4u.be)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation version 3.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

A full copy of the GNU General Public License can be found 
here: http://opensource.org/licenses/gpl-3.0.
#>
Set-StrictMode -Version Latest

Function Start-Is4uFimSchedule {
<#
	.SYNOPSIS
	Starts the on demand schedule of the IS4U FIM Scheduler.

	.DESCRIPTION
	Starts the on demand schedule of the IS4U FIM Scheduler.

	.EXAMPLE
	Start-Is4uFimSchedule
#>
	[System.Reflection.Assembly]::Load("System.ServiceProcess, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a") | Out-Null
	$is4uScheduler = New-Object System.ServiceProcess.ServiceController
	$is4uScheduler.Name = "IS4UFIMScheduler"
	if($is4uScheduler.Status -eq "Running") {
		$is4uScheduler.ExecuteCommand(234)
	} else {
		Write-Host $is4uScheduler.DisplayName "is not running"
	}
}

function Find-FIMPortalSite{
<#
	.SYNOPSIS
	Lists all available IIS sites ands lets you choose which one is the FIM Portal site. Subsequent runs will remeber your choice unless the -ResetSite switch is specified.

	.DESCRIPTION
	Lists all available IIS sites ands lets you choose which one is the FIM Portal site. Subsequent runs will remeber your choice unless the -ResetSite parameter is set to true. Your choice is saved as '$Script:FIMPortalSiteName' (script scope).

	.PARAMETER ResetSite
	Defaults to $false. If set to $true a previously specified choice of FIM Portal site will be discarded and you will be forced to choose again.

	.EXAMPLE1
	Find-FIMPortalSite -ResetSite
#>
	param(
		[Parameter(Mandatory=$false)]
		[switch]
		$ResetSite
	)
	if($(Test-Path variable:script:FIMPortalSiteName) -and !$ResetSite){
		return $Script:FIMPortalSiteName
	}else{
	    if(!$(Test-RunAsAdmin)) {
		    Write-Warning "Elevated permissions are required"
	    } else {
		    # Load IIS module:
			if($(Get-Module |select -expand Name) -notcontains "WebAdministration"){
	            Import-Module WebAdministration
			}
			$Sites = Get-WebSite | Select -Expand Name
			Write-Host ""
			Write-Host "Found Sites:"
			Write-Host "============"
			do{
				[int]$chosen = 0
				[int]$choice = 1
				foreach($site in $Sites){
				Write-Host "($choice)  " -NoNewline
				Write-Host "$site"
				$choice++
				}
				Write-Host ""
			try{
			$chosen = Read-Host "Specify the FIM Portal Site (enter the number)"
			}catch{
				if($_.Exception.gettype().fullName -eq "System.Management.Automation.ArgumentTransformationMetadataException"){
					Write-Host "You did not enter a number" -ForegroundColor Red
				}else{
					Throw $_.Exception
				}
			}
			}While($chosen -ge $choice -or $chosen -lt 1)
			$Script:FIMPortalSiteName = $Sites[$chosen-1]
			return $Script:FIMPortalSiteName
		}
	}
}

Function Get-FimStatus {
<#
	.SYNOPSIS
	Get the status of the FIM Windows Services

	.DESCRIPTION
	Displays the status of the different FIM and BHold Windows Services

	.EXAMPLE
	Get-FimStatus
#>
	$services = @("FIMSynchronizationService", "FIMService", "SPTimerV4", "W3SVC", "B1Service", "AttestationService", "IS4UFIMScheduler")
	$oricolor = $Host.UI.RawUI.ForegroundColor
	foreach($service in $services) {
		$s = Get-Service -Name $service -ErrorAction SilentlyContinue
		if(!$s) {
			Write-Warning "Service $service not present on this host"
		} else {
			$s | Format-Table -Property @{label = 'Status'; Expression = { if( $_.Status -ne "Running") `
			{$Host.UI.RawUI.ForegroundColor = "red"; $_.Status } else `
			{$Host.UI.RawUI.ForegroundColor = $oricolor; $_.Status }} ; Width = 8}, `
			@{label = 'Name'; Width = 26; Expression = {$_.Name}}, DisplayName
		}
	}
	$Host.UI.RawUI.ForegroundColor = $oricolor
}

Function Get-Sid {
<#
	.SYNOPSIS
	Get the security identifier (SID) for the given user.

	.DESCRIPTION
	Get the security identifier (SID) for the given user.

	.EXAMPLE
	Get-Sid Domain\username
#>
	param(
		[Parameter(Mandatory=$True)]
		[String]
		$DSIdentity
	)
	$ID = New-Object System.Security.Principal.NTAccount($DSIdentity)
	return $ID.Translate([System.Security.Principal.SecurityIdentifier]).toString()
}

Function Set-DcomPermission {
<#
	.SYNOPSIS
	Sets the Dcom permissions required for FIM SSPR.

	.DESCRIPTION
	Sets the Dcom permissions required for FIM SSPR.
	Written by Brad Turner (bturner@ensynch.com)
	Blog: http://www.identitychaos.com
	Inspired by Karl Mitschke's post:
	http://unlockpowershell.wordpress.com/2009/11/20/script-remote-dcom-wmi-access-for-a-domain-user/

	.EXAMPLE
	Set-DcomPermission -Principal "DOMAIN\FIM PasswordSet" -Computers ('fimsyncprimary', 'fimsyncstandby')
#>
	param( 
		[Parameter(Mandatory=$True)]
		[String]
		$Principal,

		[Parameter(Mandatory=$True)]
		[Array]
		$Computers
	)
	Write-Host "Set-FIM-DCOM - Updates DCOM Permissions for FIM Password Reset"
	Write-Host "`tWritten by Brad Turner (bturner@ensynch.com)"
	Write-Host "`tBlog: http://www.identitychaos.com"

	$sid = Get-Sid $Principal

	#MachineLaunchRestriction - Local Launch, Remote Launch, Local Activation, Remote Activation
	$DCOMSDDLMachineLaunchRestriction = "A;;CCDCLCSWRP;;;$sid"
	#MachineAccessRestriction - Local Access, Remote Access
	$DCOMSDDLMachineAccessRestriction = "A;;CCDCLC;;;$sid"
	#DefaultLaunchPermission - Local Launch, Remote Launch, Local Activation, Remote Activation
	$DCOMSDDLDefaultLaunchPermission = "A;;CCDCLCSWRP;;;$sid"
	#DefaultAccessPermision - Local Access, Remote Access
	$DCOMSDDLDefaultAccessPermision = "A;;CCDCLC;;;$sid"
	#PartialMatch
	$DCOMSDDLPartialMatch = "A;;\w+;;;$sid"

	foreach ($strcomputer in $computers) {
		Write-Host "`nWorking on $strcomputer with principal $Principal ($sid):"
		# Get the respective binary values of the DCOM registry entries
		$Reg = [WMIClass]"\\$strcomputer\root\default:StdRegProv"
		$DCOMMachineLaunchRestriction = $Reg.GetBinaryValue(2147483650,"software\microsoft\ole","MachineLaunchRestriction").uValue
		$DCOMMachineAccessRestriction = $Reg.GetBinaryValue(2147483650,"software\microsoft\ole","MachineAccessRestriction").uValue
		$DCOMDefaultLaunchPermission = $Reg.GetBinaryValue(2147483650,"software\microsoft\ole","DefaultLaunchPermission").uValue
		$DCOMDefaultAccessPermission = $Reg.GetBinaryValue(2147483650,"software\microsoft\ole","DefaultAccessPermission").uValue

		# Convert the current permissions to SDDL
		Write-Host "`tConverting current permissions to SDDL format..."
		$converter = new-object system.management.ManagementClass Win32_SecurityDescriptorHelper
		$CurrentDCOMSDDLMachineLaunchRestriction = $converter.BinarySDToSDDL($DCOMMachineLaunchRestriction)
		$CurrentDCOMSDDLMachineAccessRestriction = $converter.BinarySDToSDDL($DCOMMachineAccessRestriction)
		$CurrentDCOMSDDLDefaultLaunchPermission = $converter.BinarySDToSDDL($DCOMDefaultLaunchPermission)
		$CurrentDCOMSDDLDefaultAccessPermission = $converter.BinarySDToSDDL($DCOMDefaultAccessPermission)

		# Build the new permissions
		Write-Host "`tBuilding the new permissions..."
		if (($CurrentDCOMSDDLMachineLaunchRestriction.SDDL -match $DCOMSDDLPartialMatch) -and ($CurrentDCOMSDDLMachineLaunchRestriction.SDDL -notmatch $DCOMSDDLMachineLaunchRestriction)) {
			$NewDCOMSDDLMachineLaunchRestriction = $CurrentDCOMSDDLMachineLaunchRestriction.SDDL -replace $DCOMSDDLPartialMatch, $DCOMSDDLMachineLaunchRestriction
		} else {
			$NewDCOMSDDLMachineLaunchRestriction = $CurrentDCOMSDDLMachineLaunchRestriction.SDDL += "(" + $DCOMSDDLMachineLaunchRestriction + ")"
		}
  
		if (($CurrentDCOMSDDLMachineAccessRestriction.SDDL -match $DCOMSDDLPartialMatch) -and ($CurrentDCOMSDDLMachineAccessRestriction.SDDL -notmatch $DCOMSDDLMachineAccessRestriction)) {
			$NewDCOMSDDLMachineAccessRestriction = $CurrentDCOMSDDLMachineAccessRestriction.SDDL -replace $DCOMSDDLPartialMatch, $DCOMSDDLMachineLaunchRestriction
		} else {
			$NewDCOMSDDLMachineAccessRestriction = $CurrentDCOMSDDLMachineAccessRestriction.SDDL += "(" + $DCOMSDDLMachineAccessRestriction + ")"
		}

		if (($CurrentDCOMSDDLDefaultLaunchPermission.SDDL -match $DCOMSDDLPartialMatch) -and ($CurrentDCOMSDDLDefaultLaunchPermission.SDDL -notmatch $DCOMSDDLDefaultLaunchPermission)) {
			$NewDCOMSDDLDefaultLaunchPermission = $CurrentDCOMSDDLDefaultLaunchPermission.SDDL -replace $DCOMSDDLPartialMatch, $DCOMSDDLDefaultLaunchPermission
		} else {
			$NewDCOMSDDLDefaultLaunchPermission = $CurrentDCOMSDDLDefaultLaunchPermission.SDDL += "(" + $DCOMSDDLDefaultLaunchPermission + ")"
		}

		if (($CurrentDCOMSDDLDefaultAccessPermission.SDDL -match $DCOMSDDLPartialMatch) -and ($CurrentDCOMSDDLDefaultAccessPermission.SDDL -notmatch $DCOMSDDLDefaultAccessPermision)) {
			$NewDCOMSDDLDefaultAccessPermission = $CurrentDCOMSDDLDefaultAccessPermission.SDDL -replace $DCOMSDDLPartialMatch, $DCOMSDDLDefaultAccessPermision
		} else {
			$NewDCOMSDDLDefaultAccessPermission = $CurrentDCOMSDDLDefaultAccessPermission.SDDL += "(" + $DCOMSDDLDefaultAccessPermision + ")"
		}

		# Convert SDDL back to Binary
		Write-Host "`tConverting SDDL back into binary form..."
		$DCOMbinarySDMachineLaunchRestriction = $converter.SDDLToBinarySD($NewDCOMSDDLMachineLaunchRestriction)
		$DCOMconvertedPermissionsMachineLaunchRestriction = ,$DCOMbinarySDMachineLaunchRestriction.BinarySD

		$DCOMbinarySDMachineAccessRestriction = $converter.SDDLToBinarySD($NewDCOMSDDLMachineAccessRestriction)
		$DCOMconvertedPermissionsMachineAccessRestriction = ,$DCOMbinarySDMachineAccessRestriction.BinarySD

		$DCOMbinarySDDefaultLaunchPermission = $converter.SDDLToBinarySD($NewDCOMSDDLDefaultLaunchPermission)
		$DCOMconvertedPermissionDefaultLaunchPermission = ,$DCOMbinarySDDefaultLaunchPermission.BinarySD

		$DCOMbinarySDDefaultAccessPermission = $converter.SDDLToBinarySD($NewDCOMSDDLDefaultAccessPermission)
		$DCOMconvertedPermissionsDefaultAccessPermission = ,$DCOMbinarySDDefaultAccessPermission.BinarySD

		# Apply the changes
		Write-Host "`tApplying changes..."
		if ($CurrentDCOMSDDLMachineLaunchRestriction.SDDL -match $DCOMSDDLMachineLaunchRestriction) {
			Write-Host "`t`tCurrent MachineLaunchRestriction matches desired value."
		} else {
			$result = $Reg.SetBinaryValue(2147483650,"software\microsoft\ole","MachineLaunchRestriction", $DCOMbinarySDMachineLaunchRestriction.binarySD)
			if($result.ReturnValue='0') {Write-Host "  Applied MachineLaunchRestricition complete."}
		}

		if ($CurrentDCOMSDDLMachineAccessRestriction.SDDL -match $DCOMSDDLMachineAccessRestriction) {
			Write-Host "`t`tCurrent MachineAccessRestriction matches desired value."
		} else {
			$result = $Reg.SetBinaryValue(2147483650,"software\microsoft\ole","MachineAccessRestriction", $DCOMbinarySDMachineAccessRestriction.binarySD)
			if($result.ReturnValue='0') {Write-Host "  Applied MachineAccessRestricition complete."}
		}

		if ($CurrentDCOMSDDLDefaultLaunchPermission.SDDL -match $DCOMSDDLDefaultLaunchPermission) {
			Write-Host "`t`tCurrent DefaultLaunchPermission matches desired value."
		} else {
			$result = $Reg.SetBinaryValue(2147483650,"software\microsoft\ole","DefaultLaunchPermission", $DCOMbinarySDDefaultLaunchPermission.binarySD)
			if($result.ReturnValue='0') {Write-Host "  Applied DefaultLaunchPermission complete."}
		}

		if ($CurrentDCOMSDDLDefaultAccessPermission.SDDL -match $DCOMSDDLDefaultAccessPermision) {
			Write-Host "`t`tCurrent DefaultAccessPermission matches desired value."
		} else {
			$result = $Reg.SetBinaryValue(2147483650,"software\microsoft\ole","DefaultAccessPermission", $DCOMbinarySDDefaultAccessPermission.binarySD)
			if($result.ReturnValue='0') {Write-Host "  Applied DefaultAccessPermission complete."}
		}
	}
	trap 
	{ 
		$exMessage = $_.Exception.Message
		if($exMessage.StartsWith("L:")) {
			Write-Host "`n" $exMessage.substring(2) "`n" -foregroundcolor white -backgroundcolor darkblue
		} else {
			Write-Host "`nError: " $exMessage "`n" -foregroundcolor white -backgroundcolor darkred
		}
	}
}

Function Set-WmiPermission {
<#
	.SYNOPSIS
	Sets the WMI permissions required for FIM SSPR.

	.DESCRIPTION
	Sets the WMI permissions required for FIM SSPR.
	Written by Brad Turner (bturner@ensynch.com)
	Blog: http://www.identitychaos.com
	Inspired by Karl Mitschke's post:
	http://unlockpowershell.wordpress.com/2009/11/20/script-remote-dcom-wmi-access-for-a-domain-user/

	.EXAMPLE
	Set-WmiPermission -Principal "DOMAIN\FIM PasswordSet" -Computers ('fimsyncprimary', 'fimsyncstandby')
#>
	param( 
		[Parameter(Mandatory=$True)]
		[String]
		$Principal,

		[Parameter(Mandatory=$True)]
		[Array]
		$Computers
	)
	Write-Host "Set-FIM-WMI - Updates WMI Permissions for FIM Password Reset"
	Write-Host "`tWritten by Brad Turner (bturner@ensynch.com)"
	Write-Host "`tBlog: http://www.identitychaos.com"

	$sid = Get-Sid $Principal

	#WMI Permission - Enable Account, Remote Enable for This namespace and subnamespaces 
	$WMISDDL = "A;CI;CCWP;;;$sid" 

	#PartialMatch
	$WMISDDLPartialMatch = "A;\w*;\w+;;;$sid"

	foreach ($strcomputer in $computers) {
		Write-Host "`nWorking on $strcomputer..."
		$security = Get-WmiObject -ComputerName $strcomputer -Namespace root/cimv2 -Class __SystemSecurity
		$binarySD = @($null)
		$result = $security.PsBase.InvokeMethod("GetSD",$binarySD)

		# Convert the current permissions to SDDL 
		Write-Host "`tConverting current permissions to SDDL format..."
		$converter = New-Object system.management.ManagementClass Win32_SecurityDescriptorHelper
		$CurrentWMISDDL = $converter.BinarySDToSDDL($binarySD[0])

		# Build the new permissions 
		Write-Host "`tBuilding the new permissions..."
		if (($CurrentWMISDDL.SDDL -match $WMISDDLPartialMatch) -and ($CurrentWMISDDL.SDDL -notmatch $WMISDDL)) {
			$NewWMISDDL = $CurrentWMISDDL.SDDL -replace $WMISDDLPartialMatch, $WMISDDL
		} else {
			$NewWMISDDL = $CurrentWMISDDL.SDDL += "(" + $WMISDDL + ")"
		}

		# Convert SDDL back to Binary 
		Write-Host `t"Converting SDDL back into binary form..."
		$WMIbinarySD = $converter.SDDLToBinarySD($NewWMISDDL)
		$WMIconvertedPermissions = ,$WMIbinarySD.BinarySD
 
		# Apply the changes
		Write-Host "`tApplying changes..."
		if ($CurrentWMISDDL.SDDL -match $WMISDDL) {
			Write-Host "`t`tCurrent WMI Permissions matches desired value."
		} else {
			$result = $security.PsBase.InvokeMethod("SetSD",$WMIconvertedPermissions) 
			if($result='0') {Write-Host "`t`tApplied WMI Security complete."}
		}
	}
}

Function Restart-ApplicationPool {
<#
	.SYNOPSIS
	Restarts the application pool of the specified site.

	.DESCRIPTION
	Restarts the application pool of the specified  site.

	.PARAMETER Site
	Specifies the site name. The module looks up the application pool based on the site name. If you pass '$(Find-FIMPortalSite)' as site name you can select a site as the FIM portal site. 

	.EXAMPLE1
	Restart-MimAppPool -Site "MIM Portal"

	.EXAMPLE2
	Restart-ApplicationPool -Site $(Find-FIMPortalSite)
#>
	param( 
		[Parameter(Mandatory=$False)]
		[String]
		$Site = "MIM Portal"
	)
	if(!$(Test-RunAsAdmin)) {
		Write-Warning "Elevated permissions are required"
	} else {
		# Load IIS module:
		if($(Get-Module |select -expand Name) -notcontains "WebAdministration"){
	    Import-Module WebAdministration
		}
		# Get pool name by the site name:
		$pool = (Get-Item "IIS:\Sites\$Site" | Select-Object applicationPool).applicationPool
		# Recycle the application pool:
		Restart-WebAppPool $pool

		$event = Get-EventLog -LogName System -Source WAS -Newest 1 |select message,timewritten
		if($($event.Message.split("'")[1]) -eq $Site){
			Write-Host "$($event.TimeWritten) - Application pool recycle initiated for site '$Site'" -ForegroundColor Green
		}
	}
}

Function Test-RunAsAdmin{
<#
	.SYNOPSIS
	Test if the user is a local administrator.

	.DESCRIPTION
	Test if the user is a local administrator.
#>
$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
return $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

Function Get-SyncGroupMembers{
	<#
	.SYNOPSIS
	Finds the MIM Sync Administrative Security groups, and the members which are part of those groups.

	.DESCRIPTION
	Finds the MIM Sync Administrative Security groups, and the members which are part of those groups. By default this function looks for groups with 'MIM' in their name. This can be changed by specifying the -filter parameter.

	.PARAMETER filter
	Specify this parameter to use a custom filter to lookup the MIM Sync Administrative Security groups. This is implemented as "name -like '*$filter*'".

	.EXAMPLE1
	Get-SyncGroupMembers -filter "FIM"
#>
	param(
		[Parameter(Mandatory = $false)]
		[String]
		$filter = "mim"
	)
	write-host "Get-AdGroup -filter 'name -like  *$filter*'"
	foreach($groupname in $(Get-AdGroup -filter "name -like  '*$filter*'" |select -expand name)){
		write-host "$groupname : "
		foreach( $useraccount in (Get-AdGroupMember $groupname | select -expand name)){
			Write-host "`t`t $useraccount" 
		}
		write-host "`n"
	}
}
