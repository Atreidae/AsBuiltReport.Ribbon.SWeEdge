function Resolve-AbrRibbonTopology {
    <#
    .SYNOPSIS
        Resolves the trunk topology of an appliance: its interfaces, signalling groups and the
        far ends those groups talk to.
    .DESCRIPTION
        Assembles data the other resolvers already hold into the shape a diagram needs. No new
        configuration is parsed here.

        Each signalling group is placed on the interface that carries its signalling. Its far
        ends come from two places: the servers in the SIP server table it references, and its
        federated host list. A far end that matches a known provider is reported under the
        provider's name, so many hosts of one provider collapse into one far end.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .PARAMETER Name
        Display name of the appliance. Defaults to the platform type when not supplied.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonTopology -Config $Config -Name 'sbc01'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config,

        [String] $Name
    )

    $Provider = @(Get-AbrRibbonKnownProvider)
    $Sip = Resolve-AbrRibbonSipConfiguration -Config $Config

    $ServerTable = @{}
    foreach ($Table in @($Sip.ServerTable)) {
        if (-not [String]::IsNullOrWhiteSpace($Table.Description)) {
            $ServerTable[[String]$Table.Description] = $Table
        }
    }

    $Group = foreach ($Signaling in @(Resolve-AbrRibbonSignalingGroup -Config $Config)) {

        $FarEnd = [System.Collections.Generic.List[PSObject]]::new()
        $Seen = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::OrdinalIgnoreCase)

        $AddFarEnd = {
            param([String] $HostName, [String] $Port, [String] $Protocol, [String] $Source, [String] $State)

            $Match = @(Find-AbrRibbonProvider -Address $HostName -Provider $Provider) | Select-Object -First 1

            # A provider is one far end however many of its hosts are configured, and the
            # transport is part of the identity because a trunk to the same provider on TLS
            # and on UDP are different links.
            if ($Match) {
                $Key = 'provider|{0}|{1}' -f $Match.Name, $Protocol
                $Label = $Match.Name
            } else {
                $Key = 'host|{0}|{1}|{2}' -f $HostName, $Port, $Protocol
                $Label = if ($Port) { '{0}:{1}' -f $HostName, $Port } else { $HostName }
            }

            if ($Seen.Add($Key)) {
                $FarEnd.Add([PSCustomObject]@{
                        Key      = $Key
                        Label    = $Label
                        Host     = $HostName
                        Port     = $Port
                        Protocol = $Protocol
                        Provider = if ($Match) { $Match.Name } else { '' }
                        Source   = $Source
                        State    = $State
                    })
            }
        }

        if ($Signaling.Type -eq 'SIP') {
            $Table = if ($Signaling.SipServerName -and $ServerTable.ContainsKey([String]$Signaling.SipServerName)) {
                $ServerTable[[String]$Signaling.SipServerName]
            }

            foreach ($Server in @($Table.Server)) {
                if ([String]::IsNullOrWhiteSpace($Server.Host)) {
                    continue
                }

                & $AddFarEnd $Server.Host ([String]$Server.Port) $Server.Protocol 'ServerTable' $Server.State
            }

            # Federated entries restrict who may signal to the group. They carry no port of
            # their own, so the transport shown is the one the group listens on.
            $ListenProtocol = @($Signaling.ListenPort | ForEach-Object { $_.Protocol } | Select-Object -Unique) -join '/'

            foreach ($Entry in @($Signaling.FederatedHost)) {
                if ([String]::IsNullOrWhiteSpace($Entry)) {
                    continue
                }

                $HostName = ($Entry -split '\s*/\s*')[0].Trim()

                # An unspecified address is the wildcard entry, which restricts nothing.
                if ($HostName -in @('0.0.0.0', '::', '')) {
                    continue
                }

                # The same peer is routinely in both the server table and the federated list.
                # The server table entry carries the port, so it is the one kept.
                if (@($FarEnd | Where-Object { $_.Host -eq $HostName }).Count) {
                    continue
                }

                & $AddFarEnd $HostName '' $ListenProtocol 'Federated' 'Enabled'
            }
        } elseif ($Signaling.Port) {
            # ISDN and CAS groups terminate on a physical telephony port rather than a peer.
            $Key = 'port|{0}' -f $Signaling.Port
            $null = $Seen.Add($Key)
            $FarEnd.Add([PSCustomObject]@{
                    Key      = $Key
                    Label    = [String]$Signaling.Port
                    Host     = ''
                    Port     = ''
                    Protocol = $Signaling.Type
                    Provider = ''
                    Source   = 'Port'
                    State    = 'Enabled'
                })
        }

        [PSCustomObject]@{
            ID        = $Signaling.ID
            Name      = if ([String]::IsNullOrWhiteSpace($Signaling.Description)) { 'Signaling group {0}' -f $Signaling.ID } else { [String]$Signaling.Description }
            Type      = $Signaling.Type
            State     = $Signaling.State
            Interface = $Signaling.SignalingInterface
            Listen    = @($Signaling.ListenPort | ForEach-Object { '{0} {1}' -f $_.Protocol, $_.Port })
            FarEnd    = @($FarEnd)
        }
    }

    [PSCustomObject]@{
        Name         = if ([String]::IsNullOrWhiteSpace($Name)) { [String]$Config.PlatformType } else { $Name }
        PlatformType = [String]$Config.PlatformType
        Release      = [String]$Config.SystemRelease
        Interface    = @($Group | ForEach-Object { $_.Interface } | Select-Object -Unique)
        Group        = @($Group)
    }
}
