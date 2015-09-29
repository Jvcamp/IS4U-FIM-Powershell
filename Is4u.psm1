<#
Copyright (C) 2015 by IS4U (info@is4u.be)

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

Function Add-TypeAccelerators
{
<#
.SYNOPSIS
Add type accelerators for an assembly. Add a class name from this assembly to check
if the accelerators already exist.

.DESCRIPTION
Add type accelerators for an assembly. Add a class name from this assembly to check
if the accelerators already exist.

.EXAMPLE
Add-TypeAccelerators -AssemblyName System.Xml.Linq -Class XElement
#>
	param(
		[Parameter(Mandatory=$True)]
		[String]
		$AssemblyName,
		
		[Parameter(Mandatory=$True)]
		[String]
		$Class
	)
	$typeAccelerators = [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")
	$existingAccelerators = $typeAccelerators::get
	if(! $existingAccelerators.ContainsKey($Class)){
		$assembly = [Reflection.Assembly]::LoadWithPartialName($AssemblyName)
		$assembly.GetTypes() | ? { $_.IsPublic } | % {
			$typeAccelerators::Add( $_.Name, $_.FullName )
		}
	}
}