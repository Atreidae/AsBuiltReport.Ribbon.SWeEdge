function Resolve-AbrRibbonUnreferencedObject {
    <#
    .SYNOPSIS
        Finds configuration objects that nothing in the configuration refers to.
    .DESCRIPTION
        Ribbon configurations accumulate tables that were built, superseded and never removed.
        The WebUI gives no way to see this: nothing lists the referrers of a table, so an
        unused table looks exactly like a used one.

        Every element that can hold a reference is collected by name from anywhere in the
        configuration, rather than by walking the places references are expected to appear.
        That matters because references turn up in unobvious spots: a SIP server table can be
        held by a call admission control profile, and a TLS profile by the QoE configuration.
        Walking only signaling groups and route entries would report both as orphans.

        An object referenced only by a disabled referrer is reported separately rather than as
        unreferenced. It is still wired in, and re-enabling one route entry brings it back into
        play, so calling it an orphan would be wrong.

        Reporting a false orphan is worse than not checking at all, because it invites somebody
        to delete a table that is in use. Object types are only listed here once every field
        that can reference them has been found in a real configuration.
    .PARAMETER Config
        The configuration object returned by Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Config
    )

    $Xml = $Config.RawXml

    # Type, where the objects are defined, and every element name that can point at one. The
    # element names were taken from a real configuration rather than assumed; anything added
    # here should be found the same way.
    $Definition = @(
        [PSCustomObject]@{
            Type     = 'TransformationTable'
            Path     = "Token[@name='Transformation']/ID"
            Referrer = @('TransformationTable')
        }
        [PSCustomObject]@{
            Type     = 'TranslationTable'
            Path     = "Token[@name='Translation']/ID"
            Referrer = @('TranslationTable')
        }
        [PSCustomObject]@{
            Type     = 'RoutingTable'
            Path     = "Token[@name='CallRouting']/Token[@name='RoutingTable']/ID"
            Referrer = @('RouteTableID', 'ReRouteTable')
        }
        [PSCustomObject]@{
            Type     = 'MessageRuleTable'
            Path     = "Token[@name='SIP']/Token[@name='SIPSPRMessageRules']/ID"
            Referrer = @('IngressSPRMessageTableList', 'EgressSPRMessageTableList')
        }
        [PSCustomObject]@{
            Type     = 'MediaList'
            Path     = "Token[@name='Media']/Token[@name='MediaListProfiles']/ID"
            Referrer = @('MediaConfigID')
        }
        [PSCustomObject]@{
            Type     = 'SipProfile'
            Path     = "Token[@name='SIP']/Token[@name='Profile']/ID"
            Referrer = @('ProfileID')
        }
        [PSCustomObject]@{
            Type     = 'SipServerTable'
            Path     = "Token[@name='SIP']/Token[@name='SIPServers']/ID"
            # Call admission control profiles hold a server cluster too, which is easy to miss.
            Referrer = @('ServerClusterId', 'SkypeEdgeServerClusterId')
        }
        [PSCustomObject]@{
            Type     = 'TlsProfile'
            Path     = "Token[@name='Security']/Token[@name='TLSProfile']/ID"
            # Signaling group listen port slots, individual SIP servers, the global listen port
            # list and QoE reporting all reference these.
            Referrer = @('TLSProfileID', 'TLSProfileID_1', 'TLSProfileID_2', 'TLSProfileID_3',
                'TLSProfileID_4', 'TLSProfileID_5', 'TLSProfileID_6', 'HQGTLSProfileID')
        }
        [PSCustomObject]@{
            Type     = 'ToneTable'
            Path     = "Token[@name='ToneTables']/ID"
            Referrer = @('ToneTableID', 'ToneTableNumber')
        }
        [PSCustomObject]@{
            Type     = 'ActionSet'
            Path     = "Token[@name='ActionSets']/ID"
            Referrer = @('ActionSetTableID', 'ActionsetTableNumber')
        }
    )

    foreach ($Entry in $Definition) {

        $Referenced = [System.Collections.Generic.HashSet[String]]::new()
        $ReferencedLive = [System.Collections.Generic.HashSet[String]]::new()

        foreach ($Field in $Entry.Referrer) {
            foreach ($Node in $Xml.SelectNodes("//*[local-name()='$Field']")) {

                $Owner = $Node.ParentNode

                # A deny route still carries a transformation identifier, but the SBC never
                # applies it, so it does not count as a reference.
                if ($Entry.Type -eq 'TransformationTable') {
                    $Destination = $Owner.SelectSingleNode('DestinationType')
                    if ($null -ne $Destination -and [String]$Destination.InnerText -eq '2') { continue }
                }

                # A drained signaling group holds its references but carries no calls, so only
                # a fully enabled owner counts as a live referrer.
                $State = $Owner.SelectSingleNode('customAdminState')
                if ($null -eq $State) { $State = $Owner.SelectSingleNode('Enabled') }
                $Live = ($null -eq $State) -or ([String]$State.InnerText -eq '1')

                # Some of these fields hold several identifiers separated by commas.
                foreach ($Id in @(([String]$Node.InnerText) -split ',')) {
                    $Key = $Id.Trim()
                    if ([String]::IsNullOrWhiteSpace($Key) -or $Key -eq '0') { continue }

                    $null = $Referenced.Add($Key)
                    if ($Live) { $null = $ReferencedLive.Add($Key) }
                }
            }
        }

        foreach ($Row in @($Xml.Configuration.SelectNodes($Entry.Path) | ConvertFrom-AbrRibbonIeNode)) {

            $Id = [String]$Row.ID

            # Identifier 0 is the "none selected" placeholder rather than a real object.
            if ([String]::IsNullOrWhiteSpace($Id) -or $Id -eq '0') { continue }

            $Status = if (-not $Referenced.Contains($Id)) { 'Unreferenced' }
            elseif (-not $ReferencedLive.Contains($Id)) { 'DisabledReferrer' }
            else { continue }

            [PSCustomObject]@{
                Type   = $Entry.Type
                ID     = $Id
                Name   = if ([String]::IsNullOrWhiteSpace([String]$Row.Description)) { '(unnamed)' } else { ([String]$Row.Description).Trim() }
                Status = $Status
            }
        }
    }
}
