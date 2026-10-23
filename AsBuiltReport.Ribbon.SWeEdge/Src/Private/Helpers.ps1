function ConvertFrom-AbrRibbonSequence {
    <#
    .SYNOPSIS
        Decodes a base64 encoded Ribbon sequence field into an ordered array of integers.
    .DESCRIPTION
        Ribbon SBC configuration exports store ordered lists of row identifiers as base64
        encoded byte sequences. Two byte sequences are little-endian Int16 values, single
        byte sequences are raw byte values. Zero values are padding and are discarded.

        Used for fields such as Sequence, SignalingGroupList and VoiceFaxProfileID.
    .PARAMETER EncodedSequence
        The base64 string taken from the configuration element.
    .PARAMETER ByteCount
        The width of each value in bytes. Use 2 for Int16 sequences, 1 for byte sequences.
    .OUTPUTS
        System.Int32[]
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    [OutputType([System.Int32[]])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [String] $EncodedSequence,

        [Parameter(Mandatory = $false)]
        [ValidateSet(1, 2)]
        [Int] $ByteCount = 2
    )

    process {
        if ([String]::IsNullOrWhiteSpace($EncodedSequence)) {
            return @()
        }

        try {
            $Bytes = [System.Convert]::FromBase64String($EncodedSequence.Trim())
        } catch {
            Write-PScriboMessage -IsWarning "Unable to decode sequence '$EncodedSequence': $($_.Exception.Message)"
            return @()
        }

        $Values = [System.Collections.Generic.List[Int32]]::new()

        if ($ByteCount -eq 1) {
            foreach ($Byte in $Bytes) {
                if ($Byte -ne 0) {
                    $Values.Add([Int32]$Byte)
                }
            }
        } else {
            for ($Index = 0; $Index -lt ($Bytes.Length - 1); $Index += 2) {
                $Value = [BitConverter]::ToInt16($Bytes, $Index)
                if ($Value -ne 0) {
                    $Values.Add([Int32]$Value)
                }
            }
        }

        return $Values.ToArray()
    }
}

function ConvertFrom-AbrRibbonIeNode {
    <#
    .SYNOPSIS
        Converts a Ribbon configuration ID/IE node pair into a flat PowerShell object.
    .DESCRIPTION
        Every configurable row in a Ribbon SBC export is an <ID value="n"> element wrapping
        a single <IE classname="..."> element whose child elements are the row's fields.

        Singleton settings groups, such as System/SystemNet, carry their <IE> directly under
        the token with no <ID> wrapper. Both shapes are accepted. Singletons report an ID of
        zero because the configuration gives them no identifier.

        This function flattens that structure, preserving every field verbatim so that
        downstream resolvers can look up cross-references by identifier. Rows with no
        classname are deleted or empty slots in the configuration and return nothing.
    .PARAMETER Node
        One or more <ID> or <IE> elements taken from the configuration document.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        The row identifier and class name are exposed as ID and ClassName. These are written
        after the row fields, so if a configuration element is itself named ID or ClassName
        the row identifier wins.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [System.Xml.XmlElement[]] $Node
    )

    process {
        foreach ($Element in $Node) {
            if ($null -eq $Element) {
                continue
            }

            # Accept either an <ID> wrapper or a bare <IE> singleton. LocalName is used
            # throughout because PowerShell's XML adapter shadows Name with a name attribute.
            if ($Element.LocalName -eq 'IE') {
                $InformationElement = $Element
                $RowId = '0'
            } else {
                $InformationElement = $Element.SelectSingleNode('IE')
                $RowId = $Element.GetAttribute('value')
            }

            # A row without a classname is a deleted or never-populated slot.
            if ($null -eq $InformationElement -or [String]::IsNullOrEmpty($InformationElement.GetAttribute('classname'))) {
                continue
            }

            $Row = [Ordered]@{
                ID        = $null
                ClassName = $null
            }

            foreach ($Field in $InformationElement.ChildNodes) {
                # LocalName rather than Name. PowerShell's XML adapter shadows the Name
                # property with a name attribute when the element carries one.
                if ($Field.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                    $Row[$Field.LocalName] = [String]$Field.InnerText
                }
            }

            $ParsedId = 0
            $Row['ID'] = if ([Int]::TryParse($RowId, [ref]$ParsedId)) { $ParsedId } else { $RowId }
            $Row['ClassName'] = $InformationElement.GetAttribute('classname')

            [PSCustomObject]$Row
        }
    }
}

function ConvertTo-AbrRibbonAddressText {
    <#
    .SYNOPSIS
        Renders a Ribbon address field, treating the unconfigured sentinels as not set.
    .DESCRIPTION
        Ribbon writes 0.0.0.0 rather than an empty value when an address is not configured.
        This appears on DNS servers, NTP servers, secondary interface addresses and subnet
        masks. Rendering it verbatim makes an unconfigured field look deliberately set to a
        real address, so it is normalised to a placeholder here.
    .PARAMETER Value
        The raw address value from the configuration.
    .PARAMETER Placeholder
        Text to show when the address is not configured. Pass the localized string.
    .OUTPUTS
        System.String
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [String] $Value,

        [Parameter(Mandatory = $false, Position = 1)]
        [String] $Placeholder = 'Not set'
    )

    process {
        if ([String]::IsNullOrWhiteSpace($Value) -or $Value -in @('0.0.0.0', '::', '0:0:0:0:0:0:0:0')) {
            return $Placeholder
        }

        return $Value
    }
}

function ConvertTo-AbrRibbonTransformField {
    <#
    .SYNOPSIS
        Converts a transformation rule input or output field identifier to its name.
    .DESCRIPTION
        Transformation rules address call fields by number. Input and output share the same
        enumeration.

        The values covered here are those observed across the sample configurations, plus the
        remainder of the documented range. Anything unrecognised is returned marked rather
        than silently blanked, so an unexpected value is visible in the report instead of
        being hidden.
    .PARAMETER Value
        The numeric field identifier from the configuration.
    .OUTPUTS
        System.String
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        Field names follow the Ribbon WebUI. Verified in use: 0, 3, 6, 8, 10, 14, 15, 22, 23,
        24, 27 and 28.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [String] $Value
    )

    switch ($Value) {
        '0' { 'Called Address/Number' }
        '1' { 'Called Numbering Type' }
        '2' { 'Called Numbering Plan' }
        '3' { 'Calling Address/Number' }
        '4' { 'Calling Numbering Type' }
        '5' { 'Calling Numbering Plan' }
        '6' { 'Calling Number Presentation' }
        '7' { 'Calling Number Screening' }
        '8' { 'Calling Name' }
        '9' { 'Original Called Number' }
        '10' { 'Redirecting Number' }
        '11' { 'Redirecting Number Type' }
        '12' { 'Redirecting Numbering Plan' }
        '13' { 'Transfer Capability' }
        '14' { 'User Value 1' }
        '15' { 'User Value 2' }
        '16' { 'User Value 3' }
        '17' { 'User Value 4' }
        '18' { 'User Value 5' }
        '19' { 'Calling Number, User Specified' }
        '20' { 'ELIN Identifier' }
        '21' { 'Called Extension' }
        '22' { 'Calling Extension' }
        '23' { 'Called Phone Context' }
        '24' { 'Calling Phone Context' }
        '25' { 'Original Destination Number' }
        '26' { 'Callback Pool Identifier' }
        '27' { 'SG User Value 1' }
        '28' { 'SG User Value 2' }
        '29' { 'SG User Value 3' }
        '30' { 'SG User Value 4' }
        '31' { 'SG User Value 5' }
        '32' { 'Called SubAddress/Number' }
        '33' { 'Calling SubAddress/Number' }
        '34' { 'Destination Trunk Group' }
        '35' { 'Connected Name' }
        '38' { 'Called Free Phone Number' }
        default {
            if ([String]::IsNullOrWhiteSpace($Value)) { '' } else { "Unknown ($Value)" }
        }
    }
}

function Get-AbrRibbonOrderedRow {
    <#
    .SYNOPSIS
        Orders Ribbon configuration rows using the parent table's decoded sequence.
    .DESCRIPTION
        Ribbon stores child rows in creation order, not evaluation order. The parent table
        holds a base64 Sequence field listing child identifiers in the order the SBC actually
        evaluates them. Rendering rows in document order therefore misrepresents call routing
        and transformation behaviour.

        Rows missing from the sequence are placed last, preserving their identifier order.
    .PARAMETER Row
        Flattened rows produced by ConvertFrom-AbrRibbonIeNode.
    .PARAMETER Order
        Decoded identifiers from ConvertFrom-AbrRibbonSequence, in evaluation order.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        An ExecutionOrder property is added so the order survives any later re-sorting. Named
        with Get rather than Sort because Sort is not an approved PowerShell verb, despite
        Sort-Object existing.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [PSCustomObject[]] $Row,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [Int[]] $Order
    )

    if (-not $Row) {
        return @()
    }

    $Position = @{}
    for ($Index = 0; $Index -lt @($Order).Count; $Index++) {
        $Position[[String]$Order[$Index]] = $Index
    }

    foreach ($Entry in $Row) {
        $Key = [String]$Entry.ID
        $ExecutionOrder = if ($Position.ContainsKey($Key)) { [Int]$Position[$Key] } else { [Int]::MaxValue }
        $Entry | Add-Member -NotePropertyName 'ExecutionOrder' -NotePropertyValue $ExecutionOrder -Force
    }

    @($Row | Sort-Object -Property @{ Expression = { [Int]$_.ExecutionOrder } }, @{ Expression = { [Int]$_.ID } })
}

function Get-AbrRibbonIdLookup {
    <#
    .SYNOPSIS
        Builds an identifier to description hashtable from a collection of Ribbon rows.
    .DESCRIPTION
        Ribbon cross-references are numeric identifiers. This builds the reverse map used to
        render a friendly name in place of a bare number.
    .PARAMETER Row
        Flattened rows produced by ConvertFrom-AbrRibbonIeNode.
    .PARAMETER Property
        The field to use as the display value. Defaults to Description.
    .OUTPUTS
        System.Collections.Hashtable
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    [OutputType([Hashtable])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [AllowNull()]
        [PSCustomObject[]] $Row,

        [Parameter(Mandatory = $false)]
        [String] $Property = 'Description'
    )

    begin {
        $Lookup = @{}
    }

    process {
        foreach ($Entry in $Row) {
            if ($null -eq $Entry) {
                continue
            }

            $Key = [String]$Entry.ID
            if (-not [String]::IsNullOrWhiteSpace($Key) -and -not $Lookup.ContainsKey($Key)) {
                $Lookup[$Key] = [String]$Entry.$Property
            }
        }
    }

    end {
        $Lookup
    }
}

function Resolve-AbrRibbonReference {
    <#
    .SYNOPSIS
        Resolves a Ribbon cross-reference identifier to its display name.
    .DESCRIPTION
        Returns the description held in the supplied lookup table. Unresolved identifiers are
        returned in a clearly marked form rather than being guessed at, because a Ribbon
        configuration always references other objects by exact identifier.
    .PARAMETER Id
        The identifier held in the referencing field.
    .PARAMETER Lookup
        An identifier to description hashtable from Get-AbrRibbonIdLookup.
    .PARAMETER None
        The value to return when the reference is empty or zero. Ribbon uses 0 for "not set".
    .OUTPUTS
        System.String
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [String] $Id,

        [Parameter(Mandatory = $true, Position = 1)]
        [Hashtable] $Lookup,

        [Parameter(Mandatory = $false)]
        [String] $None = '--None--'
    )

    if ([String]::IsNullOrWhiteSpace($Id) -or $Id -eq '0') {
        return $None
    }

    if ($Lookup.ContainsKey($Id)) {
        $Name = $Lookup[$Id]
        if (-not [String]::IsNullOrWhiteSpace($Name)) {
            return $Name
        }
    }

    # Deliberately explicit. Never fall back to name matching to fill this in.
    # The "Unresolved (" prefix is the marker Test-AbrRibbonUnresolvedReference looks for.
    return "Unresolved (ID $Id)"
}

function Test-AbrRibbonUnresolvedReference {
    <#
    .SYNOPSIS
        Tests whether any supplied resolved value is an unresolved Ribbon cross-reference.
    .DESCRIPTION
        Resolve-AbrRibbonReference marks an identifier it cannot resolve rather than guessing
        at it, and the signaling group interface resolver uses the same marker. This reports
        whether any of the supplied values carry it.

        An unresolved reference means the configuration points at an object that no longer
        exists, usually because the object was deleted and the reference was left behind. The
        appliance does not behave the way the configuration appears to describe, so it is
        worth surfacing rather than rendering as though it were an ordinary name.
    .PARAMETER Value
        Resolved display values to test. Null and empty entries are ignored.
    .OUTPUTS
        System.Boolean
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        The marker is matched by prefix because the two producers format the remainder
        differently: one emits the identifier, the other the interface key.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Test-AbrRibbonUnresolvedReference -Value $Group.RouteTableName, $Group.MediaListName
    #>
    [CmdletBinding()]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [String[]] $Value
    )

    begin {
        $Found = $false
    }

    process {
        foreach ($Entry in $Value) {
            if ($Entry -like 'Unresolved (*') {
                $Found = $true
            }
        }
    }

    end {
        $Found
    }
}
