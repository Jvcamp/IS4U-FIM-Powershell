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
Add-TypeAccelerators -Assembly System.Xml.Linq -Class XAttribute
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
[XNamespace] $Ns = "http://schemas.microsoft.com/2006/11/ResourceManagement"
$RcdcSchema = New-Object System.Xml.Schema.XmlSchemaSet
$RcdcSchema.Add($Ns, (Join-Path $Dir ".\rcdc.xsd"))
$Script:AutoAppPoolRecycle = $false

Function Test-RcdcConfiguration {
<#
	.SYNOPSIS
	Test the validity of the rcdc configuration against the schema.

	.DESCRIPTION
	Test the validity of the rcdc configuration against the schema.
	
	.EXAMPLE
	Test-RcdcConfiguration -Rcdc <configurationData>
#>
	param(
		[Parameter(Mandatory=$True)]
		[String]
		$ConfigurationData
	)
	[xml] $rcdc = $ConfigurationData
	$rcdc.Schemas.Add($RcdcSchema)
	try {
		$rcdc.Validate($null)
		return $true
	} catch [System.Xml.Schema.XmlSchemaValidationException] {
		Write-Warning $_.Exception.Message
		return $false
	}
}

Function New-Rcdc {
<#
	.SYNOPSIS
	Create a new resource configuration display configuration.

	.DESCRIPTION
	Create a new resource configuration display configuration.
#>
	param(
		[Parameter(Mandatory=$True)]
		[String]
		$DisplayName,

		[Parameter(Mandatory=$True)]
		[String]
		$TargetObjectType,

		[Parameter(Mandatory=$True)]
		[String]
		$ConfigurationData,

		[Parameter(Mandatory=$false,parametersetname="AppliesToEdit")]
		[Switch]
		$AppliesToEdit,

		[Parameter(Mandatory=$false,parametersetname="AppliesToView")]
		[Switch]
		$AppliesToView,

		[Parameter(Mandatory=$false,parametersetname="AppliesToCreate")]
		[Switch]
		$AppliesToCreate
	)
	if(Test-RcdcConfiguration -ConfigurationData $ConfigurationData) {
		$changes = @()
		$changes += New-FimImportChange -Operation 'None' -AttributeName 'DisplayName' -AttributeValue $DisplayName
		$changes += New-FimImportChange -Operation 'None' -AttributeName 'TargetObjectType' -AttributeValue $TargetObjectType
		$changes += New-FimImportChange -Operation 'None' -AttributeName 'ConfigurationData' -AttributeValue $ConfigurationData
		switch($PsCmdlet.ParameterSetName){		
			"AppliesToCreate" {
			    $changes += New-FimImportChange -Operation 'None' -AttributeName 'AppliesToCreate' -AttributeValue $True
			    $changes += New-FimImportChange -Operation 'None' -AttributeName 'AppliesToEdit' -AttributeValue $False
			    $changes += New-FimImportChange -Operation 'None' -AttributeName 'AppliesToView' -AttributeValue $False}
		    "AppliesToEdit" {
			    $changes += New-FimImportChange -Operation 'None' -AttributeName 'AppliesToCreate' -AttributeValue $False
			    $changes += New-FimImportChange -Operation 'None' -AttributeName 'AppliesToEdit' -AttributeValue $True
			    $changes += New-FimImportChange -Operation 'None' -AttributeName 'AppliesToView' -AttributeValue $False}
		    "AppliesToView" {
			    $changes += New-FimImportChange -Operation 'None' -AttributeName 'AppliesToCreate' -AttributeValue $False
			    $changes += New-FimImportChange -Operation 'None' -AttributeName 'AppliesToEdit' -AttributeValue $False
			    $changes += New-FimImportChange -Operation 'None' -AttributeName 'AppliesToView' -AttributeValue $True}
		}
		New-FimImportObject -ObjectType ObjectVisualizationConfiguration -State Create -Changes $changes -ApplyNow
	} else {
		Write-Warning "Invalid RCDC configuration, RCDC not created" 
	}
}

Function Update-Rcdc {
<#
	.SYNOPSIS
	Update a resource configuration display configuration.

	.DESCRIPTION
	Update a resource configuration display configuration.
	
	.PARAMETER DisplayName
	The name of the RCDC in the FIM portal
	
	.PARAMETER ConfigurationData
	String consisting of xml configuration of the RCDC
#>
	param(
		[Parameter(Mandatory=$True)]
		[String]
		$DisplayName,

		[Parameter(Mandatory=$True)]
		[String]
		$ConfigurationData
	)
	if(Test-RcdcConfiguration -ConfigurationData $ConfigurationData) {
		$anchor = @{'DisplayName' = $DisplayName}
		$changes = @{"ConfigurationData" = $ConfigurationData}
		New-FimImportObject -ObjectType ObjectVisualizationConfiguration -State Put -Anchor $anchor -Changes $changes -ApplyNow
		if($Script:AutoAppPoolRecycle){
			Write-Host "Automated AppPool recycle is: " -NoNewline
			Write-Host "enabled" -ForegroundColor Green
			Restart-ApplicationPool -Site $(Find-FIMPortalSite)
		}else{
			Write-Host "Automated AppPool recycle is: " -NoNewline
			Write-Host "disabled" -NoNewline -ForegroundColor Yellow
			Write-Host ", recycle appPool manually or run 'Enable-AutoAppPoolRecycle'"
		}
	} else {
		Write-Warning "Invalid RCDC configuration, RCDC not updated"
	}
}

Function Remove-Rcdc {
<#
	.SYNOPSIS
	Remove a resource configuration display configuration.

	.DESCRIPTION
	Remove a resource configuration display configuration.

	.EXAMPLE
	Remove-Rcdc -DisplayName "Configuration for user editing"
#>
	param(
		[Parameter(Mandatory=$True)]
		[String]
		$DisplayName
	)
	Remove-FimObject -AnchorName DisplayName -AnchorValue $DisplayName -ObjectType ObjectVisualizationConfiguration
}

Function Read-RcdcFromFile {
	<#
	.SYNOPSIS
	Reads and validates an RCDC from an .xml file
	.DESCRIPTION
	Reads the RCDC from an .xml file and validates the file against the XML schema. Returns a string which can be used as $ConfigurationData
	.EXAMPLE
	Read-RcdcFromFile -FilePath ".\user_edit.xmll"
	.PARAMETER FilePath
	Specifies the full path to the saved RCDC configuration. Example: ".\user_edit.xml"
#>
	param(
		[Parameter(Mandatory=$True)]
		[String]
		$FilePath
	)
	[String] $ConfigurationData = Get-Content -Path $FilePath
	if(Test-RcdcConfiguration -ConfigurationData $ConfigurationData) {
		return $ConfigurationData
	} else {
		Write-Warning -Message "Read XML $FilePath is not valid"
	}
}

Function Add-ElementToRcdc {
<#
	.SYNOPSIS
	Add an element to the RCDC configuration.

	.DESCRIPTION
	Add an element to the RCDC configuration.
	
	.PARAMETER DisplayName
	The name of the RCDC in the FIM portal
	
	.PARAMETER GroupingName
	The name of the grouping in which the element will be added. This will show in the FIM Portal as a new tab. If the name does not equal an existing FIM grouping a new grouping will be created with the name specified.
	
	.PARAMETER RcdcElement
	The XML-element to add to the RCDC

	.PARAMETER BeforeElement
	Specifies the name of the "my:Control" element in front of which the new element will be added. If this parameter is not specified, the new element will be added at the end of the grouping.
	
	.EXAMPLE
	Add-ElementToRcdc -DisplayName "Configuration for user editing" -GroupingName "Basic" -RcdcElement <Element>
#>
	param(
		[Parameter(Mandatory=$True)] 
		[String]
		$DisplayName,
		
		[Parameter(Mandatory=$True)]
		[String]
		$GroupingName,
		
		[Parameter(Mandatory=$True)]
		[XElement]
		$RcdcElement,
		
		[Parameter(Mandatory=$False)]
		[String]
		$GroupingCaption = "Caption",
		
		[Parameter(Mandatory=$False)]
		[String]
		$BeforeElement
	)
	$rcdc = Get-FimObject -Attribute DisplayName -Value $DisplayName -ObjectType ObjectVisualizationConfiguration
	$date = [datetime]::now.ToString("yyyy-MM-dd_HHmmss")
	$filename = "$pwd/$date" + "_" + $DisplayName + "_before.xml"
	Write-Output $rcdc.ConfigurationData | Out-File $filename -Encoding UTF8

	$xDoc = [XDocument]::Load($filename)
	$panel = [XElement] $xDoc.Root.Element($Ns + "Panel")
	$grouping = [XElement] ($panel.Elements($Ns + "Grouping") | Where { $_.Attribute($Ns + "Name").Value -eq $GroupingName } | Select -index 0)
	$control = [XElement] ($grouping.Elements($Ns + "Control")| Where { $_.Attribute($Ns + "Name").Value -eq $BeforeElement } | Select -index 0)
	
	if($grouping -eq $null) {
		$grouping = New-Object XElement ($ns + "Grouping")
		$grouping.Add((New-Object XAttribute ($ns + "Name"), $GroupingName))
		$grouping.Add((New-Object XAttribute ($ns + "Caption"), $GroupingCaption))
		$grouping.Add((New-Object XAttribute ($ns + "Enabled"), $true))
		$grouping.Add((New-Object XAttribute ($ns + "Visible"), $true))
		$grouping.Add($RcdcElement)
		$summary = [XElement] ($panel.Elements($Ns + "Grouping") | Where { $_.Attribute($Ns + "IsSummary") -ne $null -and $_.Attribute($Ns + "IsSummary").Value -eq "true" } | Select -index 0)
		if($summary -eq $null) {
			$panel.Add($grouping)
		} else {
			$summary.AddBeforeSelf($grouping)
		}
	} else {
		if($BeforeElement){
			$control.AddBeforeSelf($RcdcElement)
		}else{
			$grouping.Add($RcdcElement)
		}
	}
	
	$filename = "$pwd/$date" + "_" + $DisplayName + "_after.xml"
	$xDoc.Save($filename)
	if(Test-RcdcConfiguration -ConfigurationData $xDoc.ToString()) {
		Update-Rcdc -DisplayName $DisplayName -ConfigurationData $xDoc.ToString()
	} else {
		Write-Warning "Invalid RCDC configuration, Element not added to RCDC"
	}
}

Function Remove-ElementFromRcdc {
<#
	.SYNOPSIS
	Removes an element from the RCDC configuration.
	.DESCRIPTION
	Removes an element from the RCDC configuration.
	.EXAMPLE
	Remove-ElementFromRcdc -DisplayName "Configuration for user editing" -ControlName "Domain"
	.PARAMETER DisplayName
	The name of the RCDC in the FIM portal
	.PARAMETER ControlName
	The name of the "my:Control" element in the RCDC. If the Control Element can not be found the remove operation will be aborted.
#>
	param(
		[Parameter(Mandatory=$True)]
		[String]
		$DisplayName,
		[Parameter(Mandatory=$True)]
		[String]
		$ControlName
	)
	$rcdc = Get-FimObject -Attribute DisplayName -Value $DisplayName -ObjectType ObjectVisualizationConfiguration
	$date = [datetime]::now.ToString("yyyy-MM-dd_HHmmss")
	$filename = "$pwd/$date" + "_" + $DisplayName + "_before.xml"
	Write-Output $rcdc.ConfigurationData | Out-File $filename -Encoding UTF8
	$xDoc = [XDocument]::Load($filename)
	$panel = [XElement] $xDoc.Root.Element($Ns + "Panel")
	$control = [XElement] ($panel.Descendants($Ns + "Control")| Where { $_.Attribute($Ns + "Name").Value -eq $ControlName } | Select -index 0)
	if($control) {
		$control.Remove()
	} else {
		Write-Warning "Control '$ControlName' not found, operation aborted"
		Remove-Item $filename
		return
	}
	$filename = "$pwd/$date" + "_" + $DisplayName + "_after.xml"
	$xDoc.Save($filename)
	if(Test-RcdcConfiguration -ConfigurationData $xDoc.ToString()) {			if(Test-RcdcConfiguration -ConfigurationData $xDoc.ToString()) {
		Update-Rcdc -DisplayName $DisplayName -ConfigurationData $xDoc.ToString()				Update-Rcdc -DisplayName $DisplayName -ConfigurationData $xDoc.ToString()
	} else {			} else {
		Write-Warning "Invalid RCDC configuration, Element not added to RCDC"				Write-Warning "Invalid RCDC configuration not uploaded"
	}			}
}		

Function Get-DefaultRcdc {
<#
	.SYNOPSIS
	Get default create RCDC configuration.

	.DESCRIPTION
	Get default create RCDC configuration.

	.EXAMPLE
	Get-DefaultRcdc -Caption "Create Department" -Xml defaultCreate.xml
#>
	param(
		[Parameter(Mandatory=$True)] 
		[String]
		$Caption,
		
		[Parameter(Mandatory=$False)]
		[String]
		$Xml,
		
		[Switch]
		$Create,
		
		[Switch]
		$Edit,

		[Switch]
		$View
	)
	if($Xml) {
		$rcdc = [XDocument]::Load((Join-Path $pwd $Xml))
	} elseif($Create) {
		$rcdc = [XDocument]::Load((Join-Path $Dir ".\defaultCreateRcdc.xml"))
	} elseif($Edit) {
		$rcdc = [XDocument]::Load((Join-Path $Dir ".\defaultEditRcdc.xml"))
	} elseif($View) {
		$rcdc = [XDocument]::Load((Join-Path $Dir ".\defaultViewRcdc.xml"))
	}
	$rcdc.Root.Element($Ns + "Panel").Element($Ns+"Grouping").Element($Ns + "Control").Attribute($Ns+"Caption").Value = $Caption
	return $rcdc
}

Function Get-RcdcIdentityPicker {
<#
	.SYNOPSIS
	Create an XElement configuration for an RCDC Identity Picker.

	.DESCRIPTION
	Create an XElement configuration for an RCDC Identity Picker.
	
	.PARAMETER AttributeName
	The Name of the FIM portal attribute the RCDC element should bind to.

	.PARAMETER ControlElementName
	The name of the 'my:Control' element in the RCDC, which can configured to be different then the FIM portal attribute name. If this parameter is not specified, the 'AttributeName' paramater will be used as name for the controlelement.
	
	.EXAMPLE
	Get-RcdcIdentityPicker -AttributeName DepartmentReference -ObjectType Person
#>
	param(
		[Parameter(Mandatory=$True)] 
		[String]
		$AttributeName,
		
		[Parameter(Mandatory=$False)]
		[String]
		$ControlElementName = $AttributeName,

		[Parameter(Mandatory=$True)] 
		[String]
		$ObjectType,
		
		[Parameter(Mandatory=$False)] 
		[String]
		$Mode = "SingleResult",
		
		[Parameter(Mandatory=$False)] 
		[String]
		$ColumnsToDisplay = "DisplayName, Description",
		
		[Parameter(Mandatory=$False)] 
		[String]
		$AttributesToSearch = "DisplayName, Description",

		[Parameter(Mandatory=$False)] 
		[String]
		$ListViewTitle = "ListViewTitle",

		[Parameter(Mandatory=$False)] 
		[String]
		$PreviewTitle = "PreviewTitle",

		[Parameter(Mandatory=$False)] 
		[String]
		$MainSearchScreenText = "MainSearchScreenText"
	)
	$element = New-Object XElement ($Ns + "Control")
	$element.Add((New-Object XAttribute ($Ns+"Name"), $ControlElementName))
	$element.Add((New-Object XAttribute ($Ns+"TypeName"), "UocIdentityPicker"))
	$element.Add((New-Object XAttribute ($Ns+"Caption"), "{Binding Source=schema, Path=$AttributeName.DisplayName}"))
	$element.Add((New-Object XAttribute ($Ns+"Description"), "{Binding Source=schema, Path=$AttributeName.Description}"))
	$element.Add((New-Object XAttribute ($Ns+"RightsLevel"), "{Binding Source=rights, Path=$AttributeName}"))

	$properties = New-Object XElement ($Ns + "Properties")
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "Required"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), "{Binding Source=schema, Path=$AttributeName.Required}"))
	$properties.Add($property)

	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "Mode"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), $Mode))
	$properties.Add($property)

	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "ObjectTypes"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), $ObjectType))
	$properties.Add($property)

	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "AttributesToSearch"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), $AttributesToSearch))
	$properties.Add($property)
	
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "ColumnsToDisplay"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), $ColumnsToDisplay))
	$properties.Add($property)

	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "UsageKeywords"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), $ObjectType))
	$properties.Add($property)

	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "ResultObjectType"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), $ObjectType))
	$properties.Add($property)

	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "Value"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), "{Binding Source=object, Path=$AttributeName, Mode=TwoWay}"))
	$properties.Add($property)

	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "ListViewTitle"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), $ListViewTitle))
	$properties.Add($property)

	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "PreviewTitle"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), $PreviewTitle))
	$properties.Add($property)

	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns+"Name"), "MainSearchScreenText"))
	$property.Add((New-Object XAttribute ($Ns+"Value"), $MainSearchScreenText))
	$properties.Add($property)

	$element.Add($properties)
	return $element
}

Function Get-RcdcTextBox {
<#
	.SYNOPSIS
	Create an XElement configuration for an RCDC Text Box.

	.DESCRIPTION
	Create an XElement configuration for an RCDC Text Box.
	
	.PARAMETER AttributeName
	The Name of the FIM portal attribute the RCDC element should bind to.

	.PARAMETER ControlElementName
	The name of the 'my:Control' element in the RCDC, which can configured to be different then the FIM portal attribute name. If this parameter is not specified, the 'AttributeName' paramater will be used as name for the controlelement.
	
	.EXAMPLE
	Get-RcdcTextBox -AttributeName VisaCardNumber -ControlElementName uniqueNameVisa
#>
	param(
		[Parameter(Mandatory=$True)] 
		[String]
		$AttributeName
	)
	$element = New-Object XElement ($Ns + "Control")
	$element.Add((New-Object XAttribute ($Ns + "Name"), $ControlElementName))
	$element.Add((New-Object XAttribute ($Ns + "TypeName"), "UocTextBox"))
	$element.Add((New-Object XAttribute ($Ns + "Caption"), "{Binding Source=schema, Path=$AttributeName.DisplayName}"))
	$element.Add((New-Object XAttribute ($Ns + "Description"), "{Binding Source=schema, Path=$AttributeName.Description}"))
	$element.Add((New-Object XAttribute ($Ns + "RightsLevel"), "{Binding Source=rights, Path=$AttributeName}"))
	
	$properties = New-Object XElement ($Ns + "Properties")
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "ReadOnly"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "false"))
	$properties.Add($property)
	
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "Required"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "{Binding Source=schema, Path=$AttributeName.Required}"))
	$properties.Add($property)
	
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "Text"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "{Binding Source=object, Path=$AttributeName, Mode=TwoWay}"))
	$properties.Add($property)
	
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "MaxLength"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "400"))
	$properties.Add($property)	
	
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "RegularExpression"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "{Binding Source=schema, Path=$AttributeName.StringRegex}"))
	$properties.Add($property)
	
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "Hint"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "{Binding Source=schema, Path=$AttributeName.Hint}"))
	$properties.Add($property)

	$element.Add($properties)
	return $element
}

Function Get-RcdcCheckBox {
<#
	.SYNOPSIS
	Create an XElement configuration for an RCDC Check Box.

	.DESCRIPTION
	Create an XElement configuration for an RCDC Check Box.

	.PARAMETER AttributeName
	The Name of the FIM portal attribute the RCDC element should bind to.

	.PARAMETER ControlElementName
	The name of the 'my:Control' element in the RCDC, which can configured to be different then the FIM portal attribute name. If this parameter is not specified, the 'AttributeName' paramater will be used as name for the controlelement.
	
	.PARAMETER ReadOnly
	Defines if the checkbox is readonly. This value defaults to "false"
	
	.EXAMPLE
	Get-RcdcCheckBox -AttributeName IsAwesome
#>
	param(
		[Parameter(Mandatory=$True)] 
		[String]
		$AttributeName,

		[Parameter(Mandatory=$False)]
		[String]
		$ControlElementName = $AttributeName,
		
		[Parameter(Mandatory=$False)]
		[String]
		$ReadOnly = "False"
	)
	$element = New-Object XElement ($Ns + "Control")
	$element.Add((New-Object XAttribute ($Ns + "Name"), $ControlElementName))
	$element.Add((New-Object XAttribute ($Ns + "TypeName"), "UocCheckBox"))
	$element.Add((New-Object XAttribute ($Ns + "Caption"), "{Binding Source=schema, Path=$AttributeName.DisplayName}"))
	$element.Add((New-Object XAttribute ($Ns + "Description"), "{Binding Source=schema, Path=$AttributeName.Description}"))
	$element.Add((New-Object XAttribute ($Ns + "RightsLevel"), "{Binding Source=rights, Path=$AttributeName}"))
	
	$properties = New-Object XElement ($Ns + "Properties")
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "ReadOnly"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "false"))
	$properties.Add($property)
	
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "Required"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "{Binding Source=schema, Path=$AttributeName.Required}"))
	$properties.Add($property)
	
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "Checked"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "{Binding Source=object, Path=$AttributeName, Mode=TwoWay}"))
	$properties.Add($property)
	
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "Hint"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "{Binding Source=schema, Path=$AttributeName.Hint}"))
	$properties.Add($property)

	$element.Add($properties)
	return $element
}

Function Get-RcdcLabel {
<#
	.SYNOPSIS
	Create an XElement configuration for an RCDC Label.
	.DESCRIPTION
	Create an XElement configuration for an RCDC Label.
	.EXAMPLE
	Get-RcdcLabel -AttributeName LastLogonTimestamp
#>
	param(
		[Parameter(Mandatory=$True)]
		[String]
		$AttributeName,
		
		[Parameter(Mandatory=$False)]
		[String]
		$ControlElementName = $AttributeName
	)
	$element = New-Object XElement ($Ns + "Control")
	$element.Add((New-Object XAttribute ($Ns + "Name"), $ControlElementName))
	$element.Add((New-Object XAttribute ($Ns + "TypeName"), "UocLabel"))
	$element.Add((New-Object XAttribute ($Ns + "Caption"), "{Binding Source=schema, Path=$AttributeName.DisplayName}"))
	$element.Add((New-Object XAttribute ($Ns + "Description"), "{Binding Source=schema, Path=$AttributeName.Description}"))
	$element.Add((New-Object XAttribute ($Ns + "RightsLevel"), "{Binding Source=rights, Path=$AttributeName}"))
	$properties = New-Object XElement ($Ns + "Properties")
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "Required"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "{Binding Source=schema, Path=$AttributeName.Required}"))
	$properties.Add($property)
	$property = New-Object XElement ($Ns + "Property")
	$property.Add((New-Object XAttribute ($Ns + "Name"), "Text"))
	$property.Add((New-Object XAttribute ($Ns + "Value"), "{Binding Source=object, Path=$AttributeName, Mode=TwoWay}"))
	$properties.Add($property)
	$element.Add($properties)
	return $element
}	

Function Enable-AutoAppPoolRecycle{
	if(Test-IsUserAdmin){
		$Script:AutoAppPoolRecycle = $true
	}else{
		Write-Warning "Elevated permissions are required"
	}
}	

Function Disable-AutoAppPoolRecycle{
	$Script:AutoAppPoolRecycle = $false
}
