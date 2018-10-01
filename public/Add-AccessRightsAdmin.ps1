Function Add-AccessRightsAdmin {
    <#
    .SYNOPSIS
        Todo
    .DESCRIPTION
        Todo
    .EXAMPLE
        Add-AccessRightsAdmin "exa" "it-tss-138m"
    .EXAMPLE
        Add-AccessRightsAdmin "TSS-WM-Role-AutomationAdmin" "it-tss-529m"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)]
        [ValidateScript( {
                # identity needs to be an existing AD User or Group
                @("user", "group") -contains (Get-ADObject -Filter "sAMAccountName -eq `"$PSItem`"").ObjectClass
            })]
        [string] $Identity,
        [Parameter(Position = 1, Mandatory)]
        [ValidateScript( {
                # computer needs to be an existing AD Computer
                @("computer") -contains (Get-ADObject -Filter "sAMAccountName -eq `"$PSItem$`"").ObjectClass
            })]
        [string] $Computer,
        [PSCredential] $Credential
    )
    process {
        try {
            [System.DirectoryServices.AccountManagement]::
            # determine the domain netbios name for use in "domain\identity" strings
            $domain = (Get-ADDomain).NetBIOSName
            if (!$domain) {
                throw "Could not retrieve domain NetBIOSName"
            }
            # recast Identity as ADObject and get it, along with properties sAMAccountName, objectSid
            [Microsoft.ActiveDirectory.Management.ADObject]$Identity = Get-ADObject -Filter "sAMAccountName -eq `"$Identity`"" -Properties sAMAccountName, objectSid
            # recast Computer as ADObject and get it, along with properties sAMAccountName, objectSid
            [Microsoft.ActiveDirectory.Management.ADObject]$Computer = Get-ADObject -Filter "sAMAccountName -eq `"$Computer`"" -Properties sAMAccountName, objectSid
            #region XML
            # process the xml
            $file = "\\ad.ufl.edu\tss\Store\WorkstationManagement\Scripts\PowerShell\exa_dev\_test\{E1B8BDCA-0628-4119-8A01-7F238B01ED5E}\Machine\Preferences\Groups\Groups.xml"
            [xml]$xml = Get-Content $file
            #region Group
            $newGroup = $xml.CreateElement("Group")
            $newGroup.Attributes.Append($xml.CreateAttribute("clsid")) *> $null
            $newGroup.Attributes.Append($xml.CreateAttribute("name")) *> $null
            $newGroup.Attributes.Append($xml.CreateAttribute("image")) *> $null
            $newGroup.Attributes.Append($xml.CreateAttribute("changed")) *> $null
            $newGroup.Attributes.Append($xml.CreateAttribute("uid")) *> $null
            $newGroup.Attributes.Append($xml.CreateAttribute("userContext")) *> $null
            $newGroup.Attributes.Append($xml.CreateAttribute("removePolicy")) *> $null
            $newGroup.clsid = "{6D4A79E4-529C-4481-ABD0-F5BD7EA93BA7}"
            $newGroup.name = "Administrators (built-in)"
            $newGroup.image = "2"
            $newGroup.changed = "$(Get-Date -f "yyyy-MM-dd HH:mm:ss")"
            $newGroup.uid = "{$([guid]::NewGuid().ToString().ToUpper())}"
            $newGroup.userContext = "0"
            $newGroup.removePolicy = "0"
            #region Properties
            $newProperties = $xml.CreateElement("Properties")
            $newProperties.Attributes.Append($xml.CreateAttribute("action")) *> $null
            $newProperties.Attributes.Append($xml.CreateAttribute("newName")) *> $null
            $newProperties.Attributes.Append($xml.CreateAttribute("description")) *> $null
            $newProperties.Attributes.Append($xml.CreateAttribute("deleteAllUsers")) *> $null
            $newProperties.Attributes.Append($xml.CreateAttribute("deleteAllGroups")) *> $null
            $newProperties.Attributes.Append($xml.CreateAttribute("removeAccounts")) *> $null
            $newProperties.Attributes.Append($xml.CreateAttribute("groupSid")) *> $null
            $newProperties.Attributes.Append($xml.CreateAttribute("groupName")) *> $null
            $newProperties.action = "U"
            $newProperties.newName = ""
            $newProperties.description = "$($Identity.SamAccountName) on $($Computer.Name)"
            $newProperties.deleteAllUsers = "0"
            $newProperties.deleteAllGroups = "0"
            $newProperties.removeAccounts = "0"
            $newProperties.groupSid = "S-1-5-32-544"
            $newProperties.groupName = "Administrators (built-in)"
            #region Members
            $newMembers = $xml.CreateElement("Members")
            #region Member
            $newMember = $xml.CreateElement("Member")
            $newMember.Attributes.Append($xml.CreateAttribute("name")) *> $null
            $newMember.Attributes.Append($xml.CreateAttribute("action")) *> $null
            $newMember.Attributes.Append($xml.CreateAttribute("sid")) *> $null
            $newMember.name = "$domain\$($Identity.SamAccountName)"
            $newMember.action = "ADD"
            $newMember.sid = "$($Identity.objectSid)"
            $newMembers.AppendChild($newMember) *> $null
            #endregion Member
            $newProperties.AppendChild($newMembers) *> $null
            #endregion Members
            $newGroup.AppendChild($newProperties) *> $null
            #endregion Properties
            #region Filters
            $newFilters = $xml.CreateElement("Filters")
            #region FilterComputer
            $newFilterComputer = $xml.CreateElement("FilterComputer")
            $newFilterComputer.Attributes.Append($xml.CreateAttribute("bool")) *> $null
            $newFilterComputer.Attributes.Append($xml.CreateAttribute("not")) *> $null
            $newFilterComputer.Attributes.Append($xml.CreateAttribute("type")) *> $null
            $newFilterComputer.Attributes.Append($xml.CreateAttribute("name")) *> $null
            $newFilterComputer.bool = "AND"
            $newFilterComputer.not = "0"
            $newFilterComputer.type = "NETBIOS"
            $newFilterComputer.name = "$($Computer.Name)"
            $newFilters.AppendChild($newFilterComputer) *> $null
            #endregion FilterComputer
            $newGroup.AppendChild($newFilters) *> $null
            #endregion Filters
            $xml.DocumentElement.AppendChild($newGroup) *> $null
            #endregion Group
            # the following facilitates saving the XML with proper encoding and "pretty" formatting
            $xmlSettings = New-Object System.Xml.XmlWriterSettings
            $xmlSettings.Encoding = [System.Text.Encoding]::ASCII
            $xmlSettings.Indent = $true
            $xmlWriter = [System.XML.XmlWriter]::Create($file, $xmlSettings)
            $xml.Save($xmlWriter)
            $xmlWriter.Flush()
            $xmlWriter.Close()
            #endregion XML
        } catch {
            if (!$PSitem.InvocationInfo.MyCommand) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        (New-Object "$($PSItem.Exception.GetType().FullName)" (
                                "$($PSCmdlet.MyInvocation.MyCommand.Name) : $($PSItem.Exception.Message)`n`nStackTrace:`n$($PSItem.ScriptStackTrace)`n"
                            )),
                        $PSItem.FullyQualifiedErrorId,
                        $PSItem.CategoryInfo.Category,
                        $PSItem.TargetObject
                    )
                )
            } else { $PSCmdlet.ThrowTerminatingError($PSitem) }
        }
    }
} # Add-AccessRightsAdmin

#Add-AccessRightsAdmin "exa" "it-tss-138m"
#Add-AccessRightsAdmin "TSS-WM-Role-AutomationAdmin" "it-tss-529m"
