Function Get-GPOLinked {
    <#
    .SYNOPSIS
        Get list of linked group policy objects.
    .DESCRIPTION
        This function returns a list of linked group policy objects under the specified OU, recursively. Unfortunately, it's not very fast due to how this information is made available, so it is advised to start as deep in to the AD tree as possible.
    .PARAMETER FilterGPO
        Filter to use when looking for GPOs. Default is '*'.
    .PARAMETER FilterOU
        Filter to use when looking for OUs. Default is '*'.
    .PARAMETER SearchBase
        Distinguished Name OU path to search under.

        Refer to SearchBase help from Get-ADOrganizationalUnit for more details.
    .PARAMETER Unique
        Filters the results to show only the top-most discovered links. By default all GPO links under SearchBase are returned.
    .OUTPUTS
        [PSCustomObject]@{
            DisplayName
            GUID
            DomainName
            Owner
            GpoStatus
            Description
            CreationTime
            ModificationTime
            UserVersion
            ComputerVersion
            WmiFilter
            OU
            SysVol
        }
    .EXAMPLE
        Get-GPOLinked -FilterGPO "*Some GPO*" -FilterOU "*SubContainerA*" -SearchBase "OU=Container,DC=sub,DC=domain,DC=com"
        DisplayName GUID                                 OU
        ----------- ----                                 --
        Some GPO 1  79FCEDE7-5127-4319-BC44-74710BB315F7 OU=SubContainerA,OU=Container,DC=sub,DC=domain,DC=com
        Some GPO 2  2D83C5B3-1E47-4BB0-84DD-4CD0BD78001A OU=SubContainerA,OU=Container,DC=sub,DC=domain,DC=com
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $FilterGPO = '*',
        [ValidateNotNullOrEmpty()]
        [string] $FilterOU = '*',
        [string] $SearchBase,
        [switch] $Unique
    )
    process {
        try {
            # build the Get-ADOrganizationalUnit expression piecemeal as a string, since it may not use all the parameters
            $exp = "Get-ADOrganizationalUnit"
            if ($SearchBase) { $exp += " -SearchBase `"$SearchBase`"" }
            $exp += " -Filter 'Name -like `"$FilterOU`"'"
            # setup an array to hold the constructed objects with results
            $results = @()
            # call the expression and parse the OUs we got
            foreach ($ou in Invoke-Expression $exp) {
                # process any linked GPOs
                foreach ($link in $ou.LinkedGroupPolicyObjects) {
                    # isolate the GPO GUID via RegEx
                    $guid = ([regex]::Match($link, "{(.*)}")).Groups[1].Value
                    # valid GUIDs are 36 characters long
                    if ($guid.Length -eq 36) {
                        # null out $obj to start fresh
                        $obj = $null
                        # try to retrieve the GPO object, and construct the new custom object
                        try {
                            # when retrieving the GPO, filter it
                            $gpo = Get-GPO -Guid $guid | Where-Object DisplayName -Like "$FilterGPO"
                            # only construct custom object if we got a GPO back
                            if ($gpo) {
                                $obj = [PSCustomObject]@{
                                    DisplayName      = $gpo.DisplayName
                                    GUID             = $guid
                                    DomainName       = $gpo.DomainName
                                    Owner            = $gpo.Owner
                                    GpoStatus        = $gpo.GpoStatus
                                    Description      = $gpo.Description
                                    CreationTime     = $gpo.CreationTime
                                    ModificationTime = $gpo.ModificationTime
                                    UserVersion      = $gpo.User
                                    ComputerVersion  = $gpo.Computer
                                    WmiFilter        = $gpo.WmiFilter
                                    OU               = $ou.DistinguishedName
                                    SysVol           = "\\$($gpo.DomainName)\sysvol\$($gpo.DomainName)\Policies\{$guid}"
                                }
                            }
                        } catch {
                            Write-Warning "Can't read [$guid] linked in [$($ou.DistinguishedName)]"
                        }
                        if ($obj) {
                            # configure DefaultDisplayPropertySet for the custom object we made
                            [string[]]$defaultProperties = "DisplayName", "GUID", "OU"
                            $defaultPropertySet = New-Object System.Management.Automation.PSPropertySet DefaultDisplayPropertySet, $defaultProperties
                            $defaultMembers = [System.Management.Automation.PSMemberInfo[]]$defaultPropertySet
                            Add-Member -InputObject $obj -MemberType MemberSet -Name PSStandardMembers -Value $defaultMembers
                            # append the object to the results array
                            $results += $obj
                        }
                    }
                }
            }
            # if we are interested in Unique objects on the pipeline, filter them...
            if ($Unique) {
                <#
                    Many of the GPOs are likely linked in several OUs. If looking for Unique items,
                    the user is probably interested in the top-most link. So, we're going to sort by the
                    OU length and then the OU string, then group by GUID, and only output the first item
                    of the group. Then resort for final display.
                #>
                $results | Sort-Object @{e = { $PSItem.OU.Length }}, OU | Group-Object GUID | ForEach-Object { $PSItem.Group | Select-Object -First 1 } | Sort-Object DisplayName, OU
            } else {
                # otherwise, put all of them on the pipeline, sort by OU length, OU, then by name.
                $results | Sort-Object DisplayName, OU
            }
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
} # Get-GPLinked
