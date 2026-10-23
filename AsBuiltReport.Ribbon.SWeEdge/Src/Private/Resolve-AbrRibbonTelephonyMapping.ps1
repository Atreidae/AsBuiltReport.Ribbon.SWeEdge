function Resolve-AbrRibbonTelephonyMapping {
    <#
    .SYNOPSIS
        Resolves the telephony mapping tables of a Ribbon SBC.
    .DESCRIPTION
        Covers cause code reroute tables, message translation tables, the SIP to Q.850 and
        Q.850 to SIP mappings, and tone tables.

        A reroute table stores its trigger causes in CauseCodes as a base64 byte sequence,
        one byte per Q.850 cause, rather than the two byte sequences used elsewhere.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with RerouteTable, MessageTranslation,
        SipToQ850, Q850ToSip and ToneTable.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonTelephonyMapping -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml

    # Q.850 causes seen in reroute tables. The full range is defined in the standard, only the
    # ones that occur in practice are named here and anything else is shown as its number.
    $CauseName = @{
        '1' = 'Unallocated Number'; '2' = 'No Route To Transit Network'; '3' = 'No Route To Destination'
        '4' = 'Send Special Information Tone'; '5' = 'Misdialed Trunk Prefix'; '6' = 'Channel Unacceptable'
        '8' = 'Preemption'; '16' = 'Normal Call Clearing'; '17' = 'User Busy'; '18' = 'No User Responding'
        '19' = 'No Answer from User'; '20' = 'Subscriber Absent'; '21' = 'Call Rejected'; '22' = 'Number Changed'
        '25' = 'Exchange Routing Error'; '26' = 'Non-selected User Clearing'; '27' = 'Destination Out of Order'
        '28' = 'Invalid Number Format'; '29' = 'Facility Rejected'; '31' = 'Normal, Unspecified'
        '34' = 'No Circuit/Channel Available'; '38' = 'Network Out of Order'; '41' = 'Temporary Failure'
        '42' = 'Switching Equipment Congestion'; '43' = 'Access Information Discarded'
        '44' = 'Requested Circuit/Channel Not Available'; '47' = 'Resource Unavailable, Unspecified'
        '50' = 'Requested Facility Not Subscribed'; '57' = 'Bearer Capability Not Authorized'
        '58' = 'Bearer Capability Not Available'; '63' = 'Service or Option Not Available'
        '65' = 'Bearer Capability Not Implemented'; '79' = 'Service or Option Not Implemented'
        '88' = 'Incompatible Destination'; '95' = 'Invalid Message, Unspecified'
        '96' = 'Mandatory Information Element is Missing'; '97' = 'Message Type Not Implemented'
        '102' = 'Recovery on Timer Expiry'; '111' = 'Protocol Error, Unspecified'
        '127' = 'Interworking, Unspecified'
    }

    $RerouteTable = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='TelephonyMappingTables']/Token[@name='RerouteTable']/ID") | ConvertFrom-AbrRibbonIeNode)) {

        # One byte per cause, not the two byte form used by ordering sequences.
        $Cause = @(ConvertFrom-AbrRibbonSequence -EncodedSequence $Row.CauseCodes -ByteCount 1)

        [PSCustomObject]@{
            ID          = $Row.ID
            Description = $Row.Description
            State       = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            CauseCode   = $Cause
            CauseName   = @(
                foreach ($Code in $Cause) {
                    if ($CauseName.ContainsKey([String]$Code)) {
                        '{0} ({1})' -f $Code, $CauseName[[String]$Code]
                    } else {
                        [String]$Code
                    }
                }
            )
        }
    }

    # Names a Q.850 cause where the standard defines one, otherwise returns the bare number.
    # Never invents a name for a cause that is not in the table.
    $NameCause = {
        param([String] $Code)

        if ([String]::IsNullOrWhiteSpace($Code)) {
            ''
        } elseif ($CauseName.ContainsKey($Code)) {
            '{0} ({1})' -f $Code, $CauseName[$Code]
        } else {
            $Code
        }
    }

    # Enumerations used by the message translation tables. These are the values the WebUI
    # presents for each field. Anything outside the set is passed through as its raw number
    # rather than being mapped to the nearest match.
    $MsgType = @{ '0' = 'Progress (183)'; '1' = 'Alerting (180)'; '2' = 'Connect (200 OK)'; '3' = 'Proceeding' }
    $IeType = @{ '0' = 'Progress Indicator'; '1' = "Don't Care"; '2' = 'Facility' }
    $SendMessage = @{ '0' = 'Yes'; '1' = 'No'; '2' = 'No on Subsequent'; '3' = 'No on Cut Through' }
    $CutThrough = @{ '0' = 'Yes on Early Media'; '1' = 'Yes'; '2' = 'No' }
    $EarlyMedia = @{ '0' = 'Any'; '1' = 'Negotiated'; '2' = 'Not Negotiated' }
    $ToneType = @{
        '1' = 'Ringback'; '2' = 'Dial'; '3' = 'Busy'; '4' = 'Congestion'
        '5' = 'Call Waiting'; '6' = 'Disconnect'; '7' = 'Confirmation'
    }

    $FromEnum = {
        param([Hashtable] $Map, [String] $Value)

        if ([String]::IsNullOrWhiteSpace($Value)) { '' }
        elseif ($Map.ContainsKey($Value)) { $Map[$Value] }
        else { $Value }
    }

    # Each of these tables is a container row holding one or more child entry rows. The
    # container carries the description shown in the WebUI, the children carry the mapping.
    $MessageTranslation = foreach ($Node in @($Xml.Configuration.SelectNodes("Token[@name='TelephonyMappingTables']/Token[@name='MsgTranslationTable']/ID"))) {

        $Table = $Node | ConvertFrom-AbrRibbonIeNode

        $Entry = foreach ($Child in @($Node.SelectNodes('ID') | ConvertFrom-AbrRibbonIeNode)) {
            [PSCustomObject]@{
                ID               = $Child.ID
                Description      = $Child.Description
                State            = if ($Child.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                InMessage        = & $FromEnum $MsgType $Child.InMsgType
                InIeType         = & $FromEnum $IeType $Child.InIEType
                OutMessage       = & $FromEnum $MsgType $Child.OutMsgType
                OutIeType        = & $FromEnum $IeType $Child.OutIEType
                SendMessage      = & $FromEnum $SendMessage $Child.SendMessage
                MediaCutThrough  = & $FromEnum $CutThrough $Child.MediaCutthroughType
                EarlyMediaStatus = & $FromEnum $EarlyMedia $Child.EarlyMediaStatus

                # The progress indicator fields have no published enumeration, so the raw
                # values are carried through rather than being given invented labels.
                PiPresent        = $Child.InPIPresent
                PiSelection      = $Child.InPISelection
                PiValue          = $Child.InPiValue
            }
        }

        [PSCustomObject]@{
            ID          = $Table.ID
            Description = $Table.Description
            State       = if ($Table.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            Entry       = @($Entry)
        }
    }

    # SipToQ850 and Q850ToSip are the same shape, they differ only in the direction the
    # mapping is applied and in the class name of the child rows.
    $CauseMap = {
        param([String] $TokenName)

        foreach ($Node in @($Xml.Configuration.SelectNodes("Token[@name='TelephonyMappingTables']/Token[@name='$TokenName']/ID"))) {

            $Table = $Node | ConvertFrom-AbrRibbonIeNode

            $Entry = foreach ($Child in @($Node.SelectNodes('ID') | ConvertFrom-AbrRibbonIeNode)) {
                [PSCustomObject]@{
                    ID        = $Child.ID
                    State     = if ($Child.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                    Sip       = $Child.SIP
                    Q850      = $Child.Q850
                    Q850Named = & $NameCause ([String]$Child.Q850)
                }
            }

            [PSCustomObject]@{
                ID          = $Table.ID
                Description = $Table.Description
                State       = if ($Table.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                Entry       = @($Entry)
            }
        }
    }

    $ToneTable = foreach ($Node in @($Xml.Configuration.SelectNodes("Token[@name='ToneTables']/ID"))) {

        $Table = $Node | ConvertFrom-AbrRibbonIeNode

        # Profile is an automatic variable, so the tone rows use a qualified name.
        $ToneProfile = foreach ($Child in @($Node.SelectNodes('ID') | ConvertFrom-AbrRibbonIeNode)) {

            # A second frequency or cadence of zero means the tone does not use it.
            $Frequency = @($Child.Frequency1, $Child.Frequency2 | Where-Object { $_ -and $_ -ne '0' })
            $Amplitude = @($Child.Amplitude1, $Child.Amplitude2 | Where-Object { $_ -and $_ -ne '0' })

            [PSCustomObject]@{
                ID          = $Child.ID
                State       = if ($Child.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                ToneType    = & $FromEnum $ToneType $Child.ToneProfileType
                Frequency   = @($Frequency)
                Amplitude   = @($Amplitude)
                CadenceOn   = $Child.CadenceOn
                CadenceOff  = $Child.CadenceOff
                Cadence2On  = $Child.Cadence2On
                Cadence2Off = $Child.Cadence2Off
            }
        }

        [PSCustomObject]@{
            ID          = $Table.ID
            Description = $Table.Description
            State       = if ($Table.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            Profile     = @($ToneProfile)
        }
    }

    [PSCustomObject]@{
        RerouteTable       = @($RerouteTable)
        MessageTranslation = @($MessageTranslation)
        SipToQ850          = @(& $CauseMap 'SipToQ850')
        Q850ToSip          = @(& $CauseMap 'Q850ToSip')
        ToneTable          = @($ToneTable)
    }
}
