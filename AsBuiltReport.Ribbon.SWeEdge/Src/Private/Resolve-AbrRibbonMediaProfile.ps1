function Resolve-AbrRibbonMediaProfile {
    <#
    .SYNOPSIS
        Resolves the media profiles of a Ribbon SBC and links media lists to their codecs.
    .DESCRIPTION
        Media lists reference voice and fax codec profiles through a base64 encoded sequence
        held in VoiceFaxProfileID. The order of that sequence is the codec preference order,
        so it is preserved rather than sorted.

        Crypto profiles are referenced by identifier and are resolved to their descriptions.
        Key material and key lifetimes are never returned.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with VoiceCodecProfile, FaxCodecProfile,
        CryptoProfile and MediaList collections.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonMediaProfile -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml

    $VoiceCodecProfile = @($Xml.Configuration.SelectNodes("Token[@name='Media']/Token[@name='VoiceProfiles']/ID") | ConvertFrom-AbrRibbonIeNode)
    $FaxCodecProfile = @($Xml.Configuration.SelectNodes("Token[@name='Media']/Token[@name='FaxProfiles']/ID") | ConvertFrom-AbrRibbonIeNode)
    $CryptoProfile = @($Xml.Configuration.SelectNodes("Token[@name='Media']/Token[@name='MediaCryptoProfiles']/ID") | ConvertFrom-AbrRibbonIeNode)
    $DtlsProfile = @($Xml.Configuration.SelectNodes("Token[@name='Media']/Token[@name='DTLSProfiles']/ID") | ConvertFrom-AbrRibbonIeNode)

    # Voice and fax profiles share one identifier space, because a media list references both
    # through the same sequence field.
    $CodecLookup = @{}
    foreach ($Codec in @($VoiceCodecProfile) + @($FaxCodecProfile)) {
        $CodecLookup[[String]$Codec.ID] = [String]$Codec.Description
    }

    $CryptoLookup = Get-AbrRibbonIdLookup -Row $CryptoProfile
    $DtlsLookup = Get-AbrRibbonIdLookup -Row $DtlsProfile

    $MediaList = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='Media']/Token[@name='MediaListProfiles']/ID") | ConvertFrom-AbrRibbonIeNode)) {

        # Sequence order is codec preference order and must not be re-sorted.
        $CodecIds = @(ConvertFrom-AbrRibbonSequence -EncodedSequence $Row.VoiceFaxProfileID -ByteCount 2)
        $CodecNames = foreach ($CodecId in $CodecIds) {
            Resolve-AbrRibbonReference -Id ([String]$CodecId) -Lookup $CodecLookup
        }

        $Row | Add-Member -NotePropertyName 'CodecIds' -NotePropertyValue $CodecIds -Force
        $Row | Add-Member -NotePropertyName 'CodecNames' -NotePropertyValue @($CodecNames) -Force
        $Row | Add-Member -NotePropertyName 'CryptoProfileName' -NotePropertyValue (Resolve-AbrRibbonReference -Id ([String]$Row.CryptoProfileID) -Lookup $CryptoLookup) -Force
        $Row | Add-Member -NotePropertyName 'DtlsProfileName' -NotePropertyValue (Resolve-AbrRibbonReference -Id ([String]$Row.DtlsProfileID) -Lookup $DtlsLookup) -Force

        $Row
    }

    [PSCustomObject]@{
        VoiceCodecProfile = @($VoiceCodecProfile)
        FaxCodecProfile   = @($FaxCodecProfile)
        CryptoProfile     = @($CryptoProfile)
        DtlsProfile       = @($DtlsProfile)
        MediaList         = @($MediaList)
    }
}
