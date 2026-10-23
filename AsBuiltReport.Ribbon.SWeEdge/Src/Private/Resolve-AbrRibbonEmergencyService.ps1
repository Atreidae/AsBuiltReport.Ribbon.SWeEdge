function Resolve-AbrRibbonEmergencyService {
    <#
    .SYNOPSIS
        Resolves the emergency services configuration of a Ribbon SBC.
    .DESCRIPTION
        Emergency services span two top level tokens. EmergencyServices holds the service
        configuration and the callback number pools, while the notification managers that
        raise alerts on an emergency call live under NotificationService.

        Callback numbers and notification recipients are stored as comma separated lists.
        The notification manager credential is never returned.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with Configuration, CallbackPool and
        NotificationManager.
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        The Secret field on a notification manager is a shared credential and is deliberately
        excluded from the returned object so it cannot reach the report.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonEmergencyService -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml

    # Splits a comma separated list without tripping over member enumeration, which collapses
    # a single element array into a string and makes indexing return characters.
    function Split-List {
        param([String] $Value)

        if ([String]::IsNullOrWhiteSpace($Value)) {
            return @()
        }

        @(($Value -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $Configuration = ConvertFrom-AbrRibbonIeNode -Node $Xml.Configuration.SelectSingleNode("Token[@name='EmergencyServices']/Token[@name='ESConfig']/IE")

    $CallbackPool = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='EmergencyServices']/Token[@name='ESCallback']/ID") | ConvertFrom-AbrRibbonIeNode)) {
        [PSCustomObject]@{
            ID              = $Row.ID
            Description     = $Row.Description
            State           = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            PsapNumber      = $Row.PSAPNumber
            # The wrapper matters. PowerShell unwraps a single element array returned from a
            # function, which would turn one callback number into a string and make indexing
            # return individual characters.
            CallbackNumber  = @(Split-List -Value $Row.CallbackNumbersList)
        }
    }

    $NotificationManager = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='NotificationService']/Token[@name='NotificationManager']/ID") | ConvertFrom-AbrRibbonIeNode)) {
        [PSCustomObject]@{
            ID                 = $Row.ID
            Description        = $Row.Description
            State              = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            ServiceProvider    = $Row.ServiceProvider
            ProjectId          = $Row.ProjectID
            ClientId           = $Row.ClientID
            MonitoringInterval = $Row.MonitoringInterval
            Recipient          = @(Split-List -Value $Row.E911RecipientsList)
            Message            = $Row.E911Message
            # Secret is deliberately not carried through.
        }
    }

    [PSCustomObject]@{
        Configuration       = $Configuration
        CallbackPool        = @($CallbackPool)
        NotificationManager = @($NotificationManager)
    }
}
