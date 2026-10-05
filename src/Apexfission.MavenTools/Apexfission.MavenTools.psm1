# Import definitions only. Native tools are checked when commands are invoked.
$publicCommands = @(
    'New-MavenSigningKey', 'Get-MavenSigningKey', 'Publish-MavenPublicKey',
    'Save-MavenCredentials', 'Set-MavenGitHubEnvironment', 'Test-MavenToolsDependency'
)
foreach ($commandName in $publicCommands) {
    . (Join-Path $PSScriptRoot "Public/$commandName.ps1")
}
Export-ModuleMember -Function $publicCommands
