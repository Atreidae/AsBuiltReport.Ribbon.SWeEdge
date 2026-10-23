function Resolve-AbrRibbonSipConfiguration {
    <#
    .SYNOPSIS
        Resolves the SIP server tables, servers and profiles of a Ribbon SBC.
    .DESCRIPTION
        A SIP server table holds one or more servers. The order the SBC tries them is held in
        the table's base64 Sequence field, so it is decoded rather than relying on the order
        the rows appear in the document.

        Remote authorization credentials are referenced by identifier. Table names are
        resolved, but no credential material is returned.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with ServerTable, SipProfile, Registrar
        and CredentialTable.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonSipConfiguration -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml
    $ProtocolName = @{ '1' = 'UDP'; '2' = 'TCP'; '4' = 'TLS' }

    $TlsLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='Security']/Token[@name='TLSProfile']/ID") | ConvertFrom-AbrRibbonIeNode)
    $CredentialLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='SIP']/Token[@name='SIPCredentialsTables']/ID") | ConvertFrom-AbrRibbonIeNode)
    $RegistrationLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='SIP']/Token[@name='SIPRegistrationTables']/ID") | ConvertFrom-AbrRibbonIeNode)

    $ServerTable = foreach ($TableNode in @($Xml.Configuration.SelectNodes("Token[@name='SIP']/Token[@name='SIPServers']/ID"))) {

        $Table = ConvertFrom-AbrRibbonIeNode -Node $TableNode
        if (-not $Table) {
            continue
        }

        $ServerRow = @($TableNode.SelectNodes('ID') | ConvertFrom-AbrRibbonIeNode)
        $Order = ConvertFrom-AbrRibbonSequence -EncodedSequence $Table.Sequence -ByteCount 2

        $Server = foreach ($Row in @(Get-AbrRibbonOrderedRow -Row $ServerRow -Order $Order)) {
            [PSCustomObject]@{
                ExecutionOrder = $Row.ExecutionOrder
                ID             = $Row.ID
                Host           = $Row.Host
                Port           = $Row.Port
                Protocol       = if ($ProtocolName.ContainsKey([String]$Row.Protocol)) { $ProtocolName[[String]$Row.Protocol] } else { "Unknown ($($Row.Protocol))" }
                State          = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                Priority       = $Row.Priority
                Weight         = $Row.Weight
                Monitor        = if ($Row.Monitor -eq '1') { 'Enabled' } else { 'Disabled' }
                KeepAlive      = $Row.KeepAliveFrequency
                # Names only. No credential material is carried through.
                RemoteAuth     = Resolve-AbrRibbonReference -Id ([String]$Row.RemoteAuthorizationTableID) -Lookup $CredentialLookup
                Registrant     = Resolve-AbrRibbonReference -Id ([String]$Row.ContactRegistrantTableID) -Lookup $RegistrationLookup
                TlsProfile     = Resolve-AbrRibbonReference -Id ([String]$Row.TLSProfileID) -Lookup $TlsLookup
            }
        }

        # Servers in one table normally share a TLS profile. A server pointing at a different
        # one is usually a mistake, and because it is often a low priority failover target it
        # can sit unnoticed until the primaries are down.
        $TlsInUse = @($Server | Where-Object { $_.Protocol -eq 'TLS' } | Select-Object -ExpandProperty TlsProfile -Unique)

        [PSCustomObject]@{
            ID                  = $Table.ID
            Description         = $Table.Description
            State               = if ($Table.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            Server              = @($Server)
            TlsProfileConsistent = @($TlsInUse).Count -le 1
            TlsProfileInUse     = $TlsInUse
        }
    }

    $SipProfile = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='SIP']/Token[@name='Profile']/ID") | ConvertFrom-AbrRibbonIeNode)) {
        [PSCustomObject]@{
            ID              = $Row.ID
            Description     = $Row.Description
            State           = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            UserAgent       = $Row.UserAgentHeader
            StaticHost      = $Row.StaticHost
            SessionTimer    = if ($Row.SessionTimer -eq '1') { 'Enabled' } else { 'Disabled' }
            SessionExpires  = $Row.SessionTimerExp
            SessionMinSe    = $Row.SessionTimerMin
            TimerT1         = $Row.TimerT1
            TimerT2         = $Row.TimerT2
            FromHeader      = $Row.FQDNinFromHeader
            ContactHeader   = $Row.FQDNinContactHeader
        }
    }

    $Registrar = @($Xml.Configuration.SelectNodes("Token[@name='SIP']/Token[@name='SIPRegistrars']/ID") | ConvertFrom-AbrRibbonIeNode)

    [PSCustomObject]@{
        ServerTable     = @($ServerTable)
        SipProfile      = @($SipProfile)
        Registrar       = @($Registrar)
        CredentialTable = @($Xml.Configuration.SelectNodes("Token[@name='SIP']/Token[@name='SIPCredentialsTables']/ID") | ConvertFrom-AbrRibbonIeNode)
    }
}
