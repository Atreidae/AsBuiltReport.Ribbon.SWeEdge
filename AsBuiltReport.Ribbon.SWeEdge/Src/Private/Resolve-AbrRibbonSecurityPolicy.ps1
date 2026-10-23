function Resolve-AbrRibbonSecurityPolicy {
    <#
    .SYNOPSIS
        Resolves the account, directory and authentication policy of a Ribbon SBC.
    .DESCRIPTION
        Covers the parts of the security configuration that govern who may sign in and how,
        rather than the certificates and TLS profiles that protect signalling.

        Three areas are returned:

        - The global password and session policy, which is what an auditor opens an as built
          document to check and which is otherwise invisible in the report.
        - Active Directory integration and its domain controllers.
        - RADIUS authentication and accounting, with the server references resolved to names.

        Shared secrets and encrypted passwords are dropped here rather than masked at render
        time, so no caller can reach them by accident. Fields whose enumeration has not been
        confirmed against the WebUI are carried through as their raw value rather than being
        given an invented label.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with PasswordPolicy, SessionPolicy,
        Directory, DomainController, Radius and RadiusServer.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonSecurityPolicy -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml

    $State = {
        param([String] $Value)
        if ($Value -eq '1') { 'Enabled' } else { 'Disabled' }
    }

    # A threshold of zero means the control is off, which reads far better than a bare zero in
    # a table an auditor is scanning for gaps.
    $Threshold = {
        param([String] $Value, [String] $ZeroMeans = 'Not enforced')
        if ([String]::IsNullOrWhiteSpace($Value) -or $Value -eq '0') { $ZeroMeans } else { $Value }
    }

    #region Global options
    $Options = $Xml.Configuration.SelectNodes("Token[@name='GlobalSecurityOptions']") | ConvertFrom-AbrRibbonIeNode

    $PasswordPolicy = $null
    $SessionPolicy = $null

    if ($Options) {
        # The WebUI hides most of the composition rules behind the Enhanced Password Security
        # toggle, and hides the password lifetime behind Set Password Lifetime. A value sitting
        # behind a switch that is off was never chosen by anyone, so the flags are exposed here
        # and the section decides what is worth showing.
        $EnhancedEnabled = $Options.EnhPassSecurity -eq '1'
        $LifetimeEnabled = $Options.SetPasswordLife -eq '1'

        $PasswordPolicy = [PSCustomObject]@{
            EnhancedSecurity   = & $State $Options.EnhPassSecurity
            EnhancedEnabled    = $EnhancedEnabled
            LifetimeEnforced   = & $State $Options.SetPasswordLife
            LifetimeEnabled    = $LifetimeEnabled
            MaximumLife        = $Options.MaxPassLife
            DisplayAllowed     = & $State $Options.PasswordDisplay
            BrowserSaveAllowed = & $State $Options.BrowserPasswordSave

            # Only meaningful when Enhanced Password Security is on. These are counts of each
            # character class, not switches, so a value of 1 means one character is required.
            MinimumLength      = $Options.MinPassLen
            MinimumUpper       = $Options.MinPassUpper
            MinimumLower       = $Options.MinPassLower
            MinimumDigits      = $Options.MinPassDigits
            MinimumSpecial     = $Options.MinPassSpecial
            MinimumChanged     = & $Threshold $Options.MinPassDelta
            MaximumConsecutive = & $Threshold $Options.MaxPassConsec 'No limit'
            MaximumSameClass   = & $Threshold $Options.MaxPassConsecClass 'No limit'
            MinimumLife        = $Options.MinPassLife
            HistoryRemembered  = & $Threshold $Options.PassHistoryReuse 'Not enforced'
        }

        # Zero values are rendered with the wording the WebUI uses for them, so a reader
        # comparing the document against the appliance sees the same words.
        $SessionPolicy = [PSCustomObject]@{
            FailedLoginsBeforeLockout = & $Threshold $Options.NumFailedLoginsForLockout 'No Lockout'
            LockoutDuration           = $Options.LockoutDuration
            LockoutEnabled            = $Options.NumFailedLoginsForLockout -ne '0'
            IdleTimeout               = & $Threshold $Options.IdleTimeout 'Not configured'
            MaximumSessions           = & $Threshold $Options.MaxNumUserSessions 'No Limit'
            InactivityDisable         = & $Threshold $Options.InactivityAccountDisable 'Not configured'
            PreLoginAcknowledgement   = & $State $Options.ExpAckPreLoginInfo
            TestCallAllowed           = & $State $Options.TestCall
        }
    }
    #endregion Global options

    #region Active Directory
    # Confirmed against a 13.1.0 appliance where Auth-Only reads as 2. The remaining values
    # follow the order the WebUI presents them in. An unrecognised value is passed through as
    # its number rather than being mapped to the nearest match.
    $OperatingMode = @{
        '0' = 'Updates'
        '1' = 'Online'
        '2' = 'Auth-Only'
        '3' = 'Cache Lookup Only'
    }

    $DirectoryConfig = $Xml.Configuration.SelectNodes("Token[@name='AD']/IE[@classname='ADS_AD_CONFIG']") | ConvertFrom-AbrRibbonIeNode

    $Directory = $null
    if ($DirectoryConfig) {
        $Directory = [PSCustomObject]@{
            State            = & $State $DirectoryConfig.Enabled
            UseTls           = & $State $DirectoryConfig.UseTLS
            UpdateFrequency  = $DirectoryConfig.UpdateFrequency
            NestedGroups     = & $State $DirectoryConfig.NestedGroupLookups
            CacheEncrypted   = & $State $DirectoryConfig.ADCacheEncrypt
            BackupEnabled    = & $State $DirectoryConfig.ADBackup
            NormalizeCache   = & $State $DirectoryConfig.NormalizeCache
            Attributes       = $DirectoryConfig.Attributes
            OperatingMode    = if ($OperatingMode.ContainsKey([String]$DirectoryConfig.OperatingMode)) {
                $OperatingMode[[String]$DirectoryConfig.OperatingMode]
            } else {
                $DirectoryConfig.OperatingMode
            }
        }
    }

    # The bind password is deliberately absent. It is never carried out of this function.
    $DomainController = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='AD']//ID") | ConvertFrom-AbrRibbonIeNode)) {
        if ($Row.ClassName -ne 'ADS_AD_DOMAINCONTROLLERS') {
            continue
        }

        [PSCustomObject]@{
            ID          = $Row.ID
            State       = & $State $Row.Enabled
            Description = $Row.Description
            Server      = $Row.DomainController
            SearchScope = $Row.SearchScope
            Timeout     = $Row.LdapTimeout
            Priority    = $Row.DCPriority
            UserName    = $Row.UserName
            LdapQuery   = $Row.LDAPQuery
        }
    }
    #endregion Active Directory

    #region RADIUS
    # Despite the name, SendConnectivityPacket is not a switch. It selects which packet the
    # appliance uses to test the server, and there is no separate control for turning the test
    # on. Confirmed on a 13.0 appliance by changing only the dropdown and re-exporting: the
    # server left on Status-Server held 0, the one moved to Request held 1.
    $PacketType = @{
        '0' = 'Status-Server (RFC 5997)'
        '1' = 'Request'
    }

    # The shared secret is deliberately absent, as with the directory bind password.
    $RadiusServer = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='RAD']//ID") | ConvertFrom-AbrRibbonIeNode)) {
        if ($Row.ClassName -ne 'RAD_RADIUS_SERVERS') {
            continue
        }

        [PSCustomObject]@{
            ID          = $Row.ID
            State       = & $State $Row.Enabled
            Description = $Row.Description
            Server      = $Row.RadiusServer
            Port        = $Row.Port
            PacketType  = if ($PacketType.ContainsKey([String]$Row.SendConnectivityPacket)) {
                $PacketType[[String]$Row.SendConnectivityPacket]
            } else {
                $Row.SendConnectivityPacket
            }
        }
    }

    $RadiusConfig = $Xml.Configuration.SelectNodes("Token[@name='RAD']//IE[@classname='RAD_RADIUS_CONFIG']") | ConvertFrom-AbrRibbonIeNode

    # Confirmed by setting Round-Robin on a 13.0 appliance and re-exporting, which produced 2.
    # Every other sample holds 1 with accounting disabled, which is the Active-Active default.
    $AccountingMode = @{
        '0' = 'Active-Standby'
        '1' = 'Active-Active'
        '2' = 'Round-Robin'
    }

    $Radius = $null
    if ($RadiusConfig) {
        # Servers are referenced by identifier. Resolving them to names means a reader does not
        # have to cross reference the table below by hand, and an identifier that does not
        # exist is reported as unresolved rather than silently dropped.
        $Lookup = Get-AbrRibbonIdLookup -Row @($RadiusServer)

        $Radius = [PSCustomObject]@{
            State             = & $State $RadiusConfig.Enabled
            Authentication    = & $State $RadiusConfig.Authentication
            Accounting        = & $State $RadiusConfig.Accounting
            FailoverTimeout   = $RadiusConfig.failoverTimeout
            PrimaryServer     = Resolve-AbrRibbonReference -Id $RadiusConfig.PrimaryRADServer -Lookup $Lookup
            SecondaryServer   = Resolve-AbrRibbonReference -Id $RadiusConfig.SecondaryRADServer -Lookup $Lookup
            AccountingServer1 = Resolve-AbrRibbonReference -Id $RadiusConfig.AccountingServer1 -Lookup $Lookup
            AccountingServer2 = Resolve-AbrRibbonReference -Id $RadiusConfig.AccountingServer2 -Lookup $Lookup
            AccountingMode    = if ($AccountingMode.ContainsKey([String]$RadiusConfig.AccountingMode)) {
                $AccountingMode[[String]$RadiusConfig.AccountingMode]
            } else {
                $RadiusConfig.AccountingMode
            }
        }
    }
    #endregion RADIUS

    [PSCustomObject]@{
        PasswordPolicy   = $PasswordPolicy
        SessionPolicy    = $SessionPolicy
        Directory        = $Directory
        DomainController = @($DomainController)
        Radius           = $Radius
        RadiusServer     = @($RadiusServer)
    }
}
