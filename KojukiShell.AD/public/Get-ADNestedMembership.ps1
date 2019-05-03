Function Get-ADNestedMembership {
    <#
    .SYNOPSIS
        Generate membership structure for AD object(s).
    .DESCRIPTION
        This function parses an AD object's Member attribute down the chain, or MemberOf up the chain, and generates a human readable table.

        The following columns are included in the table:
            Index           : Line numbers for readability, and to reference from Status messages.
            MembershipTree  : Tree-style view of the membership structure.
            Status          : Shows duplicate and looping information, along with relevant Index number.
            MembershipPath  : Absolute-path view of the membership structure.

        When using DontFormat parameter, the returned objects include the sAMAccountName of the root Identity, helpful if parsing many items from the pipeline.
    .PARAMETER Identity
        Identity(y/ies) of the AD object(s) to process. Must match sAMAccountName AD attribute.
    .PARAMETER Action
        Select whether to process Member or MemberOf. Defaults to Member if omitted.
    .PARAMETER DontFormat
        Output unformatted objects instead of a table.
    .INPUTS
        Identit(y/ies) can be provided via pipeline.
    .OUTPUTS
        [String] containing the full table, or
        [PSCustomObject] for each membership item, when using DontFormat parameter.
    .EXAMPLE
        Get-ADNestedMembership "SomeUser"
    .EXAMPLE
        Get-ADNestedMembership "SomeUser" -Action MemberOf
    .EXAMPLE
        "SomeUser", "SomeComputer", "SomeGroup" | Get-ADNestedMembership | Out-File "Member.txt" -Encoding utf8
    .EXAMPLE
        "SomeUser", "SomeComputer", "SomeGroup" | Get-ADNestedMembership -DontFormat | Export-Csv "Member.csv" -Encoding utf8 -NoTypeInformation
    .EXAMPLE
        "SomeUser", "SomeComputer", "SomeGroup" | Get-ADNestedMembership -Action MemberOf -DontFormat | Export-Csv "MemberOf.csv" -Encoding utf8 -NoTypeInformation
    #>
    [CmdletBinding()]
    [OutputType([String], [PSCustomObject])]
    param(
        [Parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [ValidateScript( {
                # identity needs to be an existing AD User, Group, or Computer object
                @("user", "group", "computer") -contains (Get-ADObject -Filter "sAMAccountName -eq `"$PSItem`" -or sAMAccountName -eq `"$PSItem$`"").ObjectClass
            })]
        [string] $Identity,
        [Parameter(Position = 1)]
        [ValidateSet("Member", "MemberOf")]
        [string] $Action = "Member",
        [switch] $DontFormat
    )
    begin {
        # define Get-Data to do the grunt-work so we can have recursion and support formatting the output objects at the end
        Function Get-Data {
            [CmdletBinding()]
            [OutputType([PSCustomObject])]
            param(
                [Parameter(Position = 0, Mandatory)]
                [Microsoft.ActiveDirectory.Management.ADObject] $Identity,
                [Parameter(Position = 1)]
                [ValidateSet("Member", "MemberOf")]
                [string] $Action,
                [System.Collections.ArrayList] $HistoryFull = @(),
                [PSCustomObject[]] $HistoryChain = @(),
                [int] $Depth = 0
            )
            process {
                try {
                    # generate the output object
                    $objOut = [PSCustomObject][Ordered]@{
                        # keep track of the root object's sAMAccountName, will be useful if processing multiple items from the pipeline and not formatting the output
                        sAMAccountName = $(if (Test-Property $HistoryChain "sAMAccountName") { @($HistoryChain.sAMAccountName)[0] } else { $Identity.sAMAccountName })
                        Index          = $HistoryFull.Count
                        # pad the Identity name based on Depth
                        MembershipTree = $(if ($Depth) { "    " + "|   " * ($Depth - 1) }) + $Identity.Name
                        # assign appropriate Status and Details for looping and duplicate states
                        Status         = $(if (Test-Property $HistoryChain "DistinguishedName") {
                                if ($HistoryChain.DistinguishedName -contains $Identity.DistinguishedName) {
                                    "Looping @ $($HistoryFull.DistinguishedName.IndexOf($Identity.DistinguishedName))"
                                } elseif ($HistoryFull.DistinguishedName -contains $Identity.DistinguishedName) {
                                    "Duplicate @ $($HistoryFull.DistinguishedName.IndexOf($Identity.DistinguishedName))"
                                } else { $null }
                            }
                        )
                        # generate membership path from the current HistoryChain names (if any) and Identity name (cast to arrays just in case we have single items)
                        MembershipPath = $(@(if (Test-Property $HistoryChain "sAMAccountName") {$HistoryChain.sAMAccountName}) + @($Identity.sAMAccountName)) -join "\"
                        CanonicalName  = $Identity.CanonicalName
                    }
                    # configure DefaultDisplayPropertySet for the custom object we made
                    [string[]]$defaultProperties = "Index", "MembershipTree", "Status", "MembershipPath"
                    $defaultPropertySet = New-Object System.Management.Automation.PSPropertySet DefaultDisplayPropertySet, $defaultProperties
                    $defaultMembers = [System.Management.Automation.PSMemberInfo[]]$defaultPropertySet
                    Add-Member -InputObject $objOut -MemberType MemberSet -Name PSStandardMembers -Value $defaultMembers
                    <#
                        When piping an Array in to a cmdlet parameter it gets scoped differently than piping to ForEach-Object and using the cmdlet inside the scriptblock. Mainly, the former will treat the Array like a static variable, and appending values at any function recursion level will continuously add items to the Array. However, in the latter case of ForEach-Object, the Array inside the scriptblock will only inherit the members from the parent function call during recursion.

                        Alternatively, an ArrayList behaves like a static variable in both the pipeline and the ForEach-Object scriptblock.

                        Knowing this, we are able to take advantage of both containers for their respective feature.

                        The ArrayList $HistoryFull will be a complete history of accumulated objects from ALL function calls, while the Array $HistoryChain will only contain the objects accumulated from the callstack leading directly to it.

                        HistoryChain is useful when looking for looping, because we have only the direct parent tree.

                        HistoryFull is useful when looking for duplicates, because we have the entire history (so far) to compare against. It's important to note that in the current implementation we look only for the first instance of the duplicate, and use its path in the Details field of the output object.
                    #>
                    # generate the history object from Identity details and membership path
                    $objHist = [PSCustomObject][Ordered]@{
                        sAMAccountName    = $Identity.sAMAccountName
                        Name              = $Identity.Name
                        DistinguishedName = $Identity.DistinguishedName
                    }
                    # append histories, ArrayList returns the new object index so pipe it to null
                    $HistoryFull.Add($objHist) *> $null
                    $HistoryChain += $objHist
                    # put the output object on the pipeline
                    $objOut
                    # if the object is looping or duplicate, return from the function so we don't continue recursing
                    if ($objOut.Status -match "Looping*|Duplicate*") { return }
                    # recurse if $Action isn't empty, make sure to get sAMAccountName, CanonicalName, and $Action from Get-ADObject
                    $Identity.$Action | Get-ADObject -Properties sAMAccountName, CanonicalName, $Action | Sort-Object Name | ForEach-Object {
                        Get-Data -Identity $PSItem -Action $Action -HistoryFull $HistoryFull -HistoryChain $HistoryChain -Depth ($Depth + 1)
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
        } # Get-Data
    }
    process {
        try {
            # recast Identity as ADObject and get it, along with properties sAMAccountName, CanonicalName, and $Action
            # the -or "$Itentity$" is to match computer objects, since they have a '$' at the end of their sAMAccountName
            [Microsoft.ActiveDirectory.Management.ADObject]$Identity = Get-ADObject -Filter "sAMAccountName -eq `"$Identity`" -or sAMAccountName -eq `"$Identity$`"" -Properties sAMAccountName, CanonicalName, $Action
            if ($DontFormat) {
                # if we don't want to format, just get the objects on the pipeline
                Get-Data -Identity $Identity -Action $Action
            } else {
                # get the output from Get-Data, format it as a table, and then convert it to string with plenty of width
                $output = Get-Data -Identity $Identity -Action $Action | Format-Table -AutoSize | Out-String -Width 4096
                # split the output to separate lines, remove empty lines, and trim spaces from ends of lines
                $output = $output -split "`r`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $PSItem.TrimEnd() }
                # join all the lines with CRLF, add an empty line at the end, and put the output on the pipeline
                ($output -join "`r`n") + "`r`n"
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
} # Get-ADNestedMembership
