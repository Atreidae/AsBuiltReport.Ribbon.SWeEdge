function Invoke-AsBuiltReport.Ribbon.SWeEdge {
    <#
    .SYNOPSIS
        A PowerShell function to generate a Ribbon SWeEdge As Built report.
    .DESCRIPTION
        Documents the configuration of Ribbon SWeEdge, SWe Lite and SBC 1000/2000 appliances
        in Word/HTML/Text formats using PScribo.
    .PARAMETER Target
        Path to a Ribbon SBC configuration export (.xml, .tar, .tgz or .tar.gz), or the host
        name of an appliance to collect from over REST.

        When used with InputFile, Target carries no source of its own and acts as a display
        name override for each file, mapped 1:1 by position.
    .PARAMETER InputFile
        Path to one or more Ribbon SBC configuration exports to document instead of
        connecting to an appliance. Supplied by AsBuiltReport.Core 1.7.0 and later when the
        user runs New-AsBuiltReport with its InputFile parameter set.

        This module has always been able to read an offline export through Target, so
        InputFile is an alternative entry point to the same importer rather than a new
        capability. Core does not pass Credential in this mode.
    .PARAMETER Credential
        Used only when a target is an appliance host name rather than a file, in which case
        the configuration is collected over REST. Not used for offline exports.
    .NOTES
        Version:        0.3.0
        Author:         James Arber
        Creation Date:  2026-07-30
        Purpose/Change: Added InputFile parameter set support (AsBuiltReport.Core 1.7.0)
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> New-AsBuiltReport -Report Ribbon.SWeEdge -Target 'C:\Configs\sbc01.tar' -Format HTML
    .EXAMPLE
        PS C:\> New-AsBuiltReport -Report Ribbon.SWeEdge -InputFile 'C:\Configs\sbc01.tar','C:\Configs\sbc02.tar' -Target 'Sydney SBC','Melbourne SBC' -Format Word

        Documents two offline exports and names each section after the supplied display name
        rather than the node name held in the configuration.
    #>

    # Do not remove or add to these parameters
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Credential',
        Justification = 'Required by AsBuiltReport.Core for every report module. It is used only when a target is an appliance host name, which the analyzer cannot see because the call sits behind a runtime branch. AsBuiltReport.Core does not supply it at all in the InputFile parameter set.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseDeclaredVarsMoreThanAssignments', '',
        Justification = 'Report, Options and TextInfo are consumed by the Get-Abr private section functions through PowerShell dynamic scoping, which the analyzer cannot follow. Report in particular drives table captions in every section.'
    )]
    [CmdletBinding()]
    param (
        [String[]] $Target,
        [String[]] $InputFile,
        [PSCredential] $Credential
    )

    # Displays the module name and version number at the start of report generation
    Write-ReportModuleInfo -ModuleName 'Ribbon.SWeEdge'

    # Import Report Configuration
    $Report = $ReportConfig.Report
    $InfoLevel = $ReportConfig.InfoLevel
    $Options = $ReportConfig.Options
    $LocalizedData = $reportTranslate.InvokeAsBuiltReportRibbonSWeEdge

    # The diagram engine cannot load in Windows PowerShell, so stop before collecting anything
    # rather than produce a report that silently lacks the requested diagram.
    if ($Options.ShowTopologyDiagram -eq $true -and $PSVersionTable.PSEdition -ne 'Core') {
        $LastCommand = (Get-History -Count 1 -ErrorAction SilentlyContinue).CommandLine
        if ([String]::IsNullOrWhiteSpace($LastCommand)) { $LastCommand = '<the command you just ran>' }
        throw ($LocalizedData.PwshRequired -f $LastCommand)
    }

    # Used to convert strings to TitleCase where required
    $TextInfo = (Get-Culture).TextInfo

    # AsBuiltReport.Core 1.7.0 added an InputFile parameter set for report modules that can
    # document an offline export. This module could already do that through Target, so the
    # two entry points are normalised here into one list and nothing downstream has to know
    # which was used.
    #
    # In InputFile mode Target holds display names rather than sources, mapped 1:1 by
    # position. Core enforces that the counts match, but a caller invoking this function
    # directly may not, so a missing name simply falls back to the node name.
    $Source = if ($InputFile) {
        for ($Index = 0; $Index -lt @($InputFile).Count; $Index++) {
            $Name = if ($Target -and $Index -lt @($Target).Count) { @($Target)[$Index] } else { '' }

            # An existing file in Target means the export was supplied twice, or Target was
            # filled with a path out of habit from before InputFile existed. A path makes a
            # poor heading, so it is dropped and the node name is used instead.
            if ($Name -and (Test-Path -LiteralPath $Name -PathType Leaf)) {
                Write-PScriboMessage -IsWarning ($LocalizedData.TargetFileWithInputFile -f $Name)
                $Name = ''
            }

            [PSCustomObject]@{
                Path        = @($InputFile)[$Index]
                DisplayName = $Name
                IsFile      = $true
            }
        }
    } else {
        foreach ($System in $Target) {
            [PSCustomObject]@{
                Path        = $System
                DisplayName = ''
                # A target that is not an existing file is treated as a host name to collect
                # from. The REST interface returns the same archive the WebUI exports, so
                # both paths converge on the same importer.
                IsFile      = Test-Path -LiteralPath $System
            }
        }
    }

    #region foreach loop
    foreach ($Item in @($Source)) {

        $System = $Item.Path
        $Downloaded = $null

        try {
            if ($Item.IsFile) {
                # InputFile is the native Core mechanism for offline exports. A file passed
                # through Target still works but is deprecated.
                if (-not $InputFile) {
                    Write-PScriboMessage -IsWarning ($LocalizedData.TargetFileDeprecated -f $System)
                }
                Write-PScriboMessage ($LocalizedData.Importing -f $System)
                $SourcePath = $System
            } else {
                Write-PScriboMessage ($LocalizedData.Collecting -f $System)

                # Defaults to enabled because most appliances present a self signed
                # certificate on the interface an administrator reaches them on. The function
                # warns whenever it is used, so it is visible in the log rather than silent.
                $SkipCertificate = $Options.SkipCertificateCheck -ne $false

                $Downloaded = Get-AbrRibbonSWeEdgeBackup -Target $System -Credential $Credential -SkipCertificateCheck:$SkipCertificate
                $SourcePath = $Downloaded
            }

            # Script scope makes the configuration readable by every Get-Abr* private function
            # without passing it as a parameter. It is assigned per target so one appliance's
            # data can never leak into another's section output.
            $script:RibbonConfig = Import-AbrRibbonSWeEdgeConfig -Path $SourcePath
        } catch {
            Write-PScriboMessage -IsWarning ($LocalizedData.ImportError -f $System, $_.Exception.Message)
            continue
        } finally {
            # The downloaded archive holds the appliance's full configuration. It is a working
            # file, not an artefact of the report, so it does not outlive the import.
            if ($Downloaded -and (Test-Path -LiteralPath $Downloaded)) {
                Remove-Item -LiteralPath $Downloaded -Force -ErrorAction SilentlyContinue
            }
        }

        # A display name supplied alongside InputFile is an explicit instruction from the
        # user, so it wins over the node name held in the configuration.
        $NodeName = $Item.DisplayName

        if ([String]::IsNullOrWhiteSpace($NodeName)) {
            $NodeName = $script:RibbonConfig.RawXml.Configuration.SelectSingleNode("Token[@name='System']/Token[@name='SystemNet']/IE/NodeName").InnerText
        }

        if ([String]::IsNullOrWhiteSpace($NodeName)) {
            $NodeName = [System.IO.Path]::GetFileNameWithoutExtension($System)
        }

        Section -Style Heading1 $NodeName {

            if ($InfoLevel.System -gt 0) {
                Get-AbrRibbonSWeEdgeSystem
            }

            # The firewall table is an aid for the network team rather than a record of
            # configuration, so it carries its own report option as well as an InfoLevel.
            # The option is treated as enabled unless it is explicitly set to false, so a
            # configuration saved before this section existed still produces it.
            if ($InfoLevel.Firewall -gt 0 -and $Options.ShowFirewallTable -ne $false) {
                Get-AbrRibbonSWeEdgeFirewall
            }

            if ($InfoLevel.Networking -gt 0) {
                Get-AbrRibbonSWeEdgeNetworking
            }

            if ($InfoLevel.Security -gt 0) {
                Get-AbrRibbonSWeEdgeSecurity
            }

            if ($InfoLevel.Media -gt 0) {
                Get-AbrRibbonSWeEdgeMediaConfiguration
            }

            if ($InfoLevel.SIP -gt 0) {
                Get-AbrRibbonSWeEdgeSip
            }

            if ($InfoLevel.PhysicalTelephonyPort -gt 0) {
                Get-AbrRibbonSWeEdgePhysicalTelephonyPort
            }

            if ($InfoLevel.SignalingGroup -gt 0) {
                Get-AbrRibbonSWeEdgeSignalingGroup
            }

            # Opt in, unlike the firewall table, because it depends on an optional module.
            if ($Options.ShowTopologyDiagram -eq $true) {
                Get-AbrRibbonSWeEdgeTopology -Name $NodeName
            }

            if ($InfoLevel.CallRouting -gt 0) {
                Get-AbrRibbonSWeEdgeCallRouting
            }

            if ($InfoLevel.TelephonyMapping -gt 0) {
                Get-AbrRibbonSWeEdgeTelephonyMapping
            }

            if ($InfoLevel.EmergencyService -gt 0) {
                Get-AbrRibbonSWeEdgeEmergencyService
            }

            if ($InfoLevel.Logging -gt 0) {
                Get-AbrRibbonSWeEdgeLogging
            }

            # A cross cutting check rather than a configuration section, so it is driven by
            # the health check toggle and sits last, after everything it refers to.
            if ($ReportConfig.HealthCheck.Configuration.UnreferencedObject) {
                Get-AbrRibbonSWeEdgeUnreferenced
            }
        }
    }
    #endregion foreach loop
}

