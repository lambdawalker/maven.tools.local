function Test-MavenToolsDependency {
    <#
    .SYNOPSIS
    Report whether the native programs used by Maven Tools are available.
    .DESCRIPTION
    Checks PATH without executing programs, installing software or prompting.
    GPG is used by the key and credential commands. GitHub environment setup also
    requires gpg-connect-agent and gh. Unavailable tools are returned as data.
    .EXAMPLE
    Test-MavenToolsDependency
    .OUTPUTS
    PSCustomObject with Name, Available and Path properties.
    #>
    [CmdletBinding()]
    param()
    foreach ($name in @('gpg', 'gpg-connect-agent', 'gh')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $path = $null
        if ($null -ne $command) { $path = $command.Source }
        [pscustomobject]@{ Name = $name; Available = ($null -ne $command); Path = $path }
    }
}
