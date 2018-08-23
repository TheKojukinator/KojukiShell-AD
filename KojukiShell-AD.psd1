@{
    ModuleVersion     = '0.1'
    Author            = 'Stephen Kojoukhine'
    Copyright         = '(c) 2018 Stephen Kojoukhine. All rights reserved.'
    GUID              = 'aeb859f4-1a88-4c32-a079-f0696f8867e2'
    PowerShellVersion = '5.1'
    RequiredModules   = @('ActiveDirectory')
    NestedModules     = @(
        '.\functions\Add-AccessRightsAdmin.ps1',
        '.\functions\Get-ADNestedMembership.ps1',
        '.\functions\Get-GPOLinked.ps1',
        '.\functions\Test-PSCredential.ps1'
    )
    FunctionsToExport = @('*')
}
