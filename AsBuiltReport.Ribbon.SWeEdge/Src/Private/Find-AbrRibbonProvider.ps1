function Get-AbrRibbonKnownProvider {
    <#
    .SYNOPSIS
        Returns the service providers whose published endpoints this module recognises.
    .DESCRIPTION
        Held in one place so the firewall section and the topology diagram identify a peer
        the same way. Suffix matching is anchored to a full domain label, so
        'notmicrosoft.com' cannot match '.microsoft.com'. Add a provider by adding an entry.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Get-AbrRibbonKnownProvider
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    [PSCustomObject]@{
        Name             = 'Microsoft Teams Direct Routing'
        Suffix           = @('.pstnhub.microsoft.com')
        Exact            = @('sip.pstnhub.microsoft.com', 'sip2.pstnhub.microsoft.com', 'sip3.pstnhub.microsoft.com')
        SignalingNetwork = '52.112.0.0/14, 52.122.0.0/15'
        Cidr             = @('52.112.0.0/14', '52.120.0.0/14')
        MediaNetwork     = '52.112.0.0/14, 52.122.0.0/15'
        MediaProtocol    = 'UDP'
        MediaPort        = '49152-53247'
        RelayPort        = '3478-3481'
        Reference        = 'Microsoft Direct Routing SBC connectivity requirements'
    }
}

function Find-AbrRibbonProvider {
    <#
    .SYNOPSIS
        Returns the known provider that a host name belongs to, if any.
    .DESCRIPTION
        An exact host name match or a full domain suffix match only. A host that is merely
        similar is deliberately not matched.
    .PARAMETER Address
        The host name or address of the peer.
    .PARAMETER Provider
        The provider list to search. Defaults to Get-AbrRibbonKnownProvider.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Find-AbrRibbonProvider -Address 'sip.pstnhub.microsoft.com'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [String] $Address,

        [PSObject[]] $Provider = @(Get-AbrRibbonKnownProvider)
    )

    if ([String]::IsNullOrWhiteSpace($Address)) {
        return
    }

    $Candidate = $Address.Trim().TrimEnd('.').ToLowerInvariant()

    $Ip = $null
    $IsIp = [System.Net.IPAddress]::TryParse($Candidate, [ref]$Ip) -and $Ip.AddressFamily -eq 'InterNetwork'

    foreach ($Entry in $Provider) {
        if ($Entry.Exact -contains $Candidate) {
            $Entry
            continue
        }

        if ($IsIp -and $Entry.PSObject.Properties['Cidr']) {
            $Value = [BitConverter]::ToUInt32([Byte[]]($Ip.GetAddressBytes()[3..0]), 0)
            $InRange = $false
            foreach ($Block in $Entry.Cidr) {
                $Base, $Bits = $Block -split '/'
                $BaseValue = [BitConverter]::ToUInt32([Byte[]](([System.Net.IPAddress]::Parse($Base)).GetAddressBytes()[3..0]), 0)
                $Mask = [UInt32]([Math]::Pow(2, 32) - [Math]::Pow(2, 32 - [Int]$Bits))
                if (($Value -band $Mask) -eq ($BaseValue -band $Mask)) { $InRange = $true; break }
            }
            if ($InRange) {
                $Entry
                continue
            }
        }

        foreach ($Suffix in $Entry.Suffix) {
            if ($Candidate.EndsWith($Suffix, [StringComparison]::Ordinal)) {
                $Entry
                break
            }
        }
    }
}
