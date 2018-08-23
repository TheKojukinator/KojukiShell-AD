# load the necessary assemblies
Add-Type -AssemblyName System.DirectoryServices.AccountManagement
Function Test-PSCredential {
    <#
    .SYNOPSIS
    Test PSCredential against local domain.

    .DESCRIPTION
    This function leverages [System.DirectoryServices.AccountManagement] to validate the provided PSCredential(s).

    .INPUTS
    PSCredential(s) can be provided via pipeline.

    .OUTPUTS
    [bool] $true if validation succeeds, otherwise $false.

    .EXAMPLE
    Get-Credential | Test-PSCredential
    True
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [PSCredential[]] $Credential
    )
    Process {
        try {
            $domain = (Get-ADDomain).NetBIOSName
            if (!$domain) {
                throw "Could not retrieve domain NetBIOSName"
            }
            return [System.DirectoryServices.AccountManagement.PrincipalContext]::new([System.DirectoryServices.AccountManagement.ContextType]::Domain, $domain).ValidateCredentials($Credential.GetNetworkCredential().UserName, $Credential.GetNetworkCredential().Password)
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
} # Test-PSCredential
