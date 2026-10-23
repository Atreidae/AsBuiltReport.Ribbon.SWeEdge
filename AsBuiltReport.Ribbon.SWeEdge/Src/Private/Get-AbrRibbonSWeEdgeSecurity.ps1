function Get-AbrRibbonSWeEdgeSecurity {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge security information.
    .DESCRIPTION
        Documents the certificates and TLS profiles of a Ribbon SBC in Word/HTML/Text formats
        using PScribo.
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        Certificate content, key identifiers and passwords are never rendered. Only metadata
        is reported.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeSecurity
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Security)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Security = Resolve-AbrRibbonCertificate -Config $script:RibbonConfig

            if (-not $Security.Certificate -and -not $Security.TlsProfile) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            # Trusted roots are numerous and rarely actionable, so the headline table
            # covers only the certificates presented by this appliance.
            $Appliance = @($Security.Certificate | Where-Object { $_.Type -ne 'Trusted Root' })

            # An expired or soon to expire appliance certificate takes the SBC out of
            # service, so it is worth flagging prominently. Only explain the highlighting
            # to the reader when the health check is on AND something is actually flagged.
            $WarningDays = $ReportConfig.HealthCheck.Security.CertificateExpiryWarningDays
            if (-not $WarningDays) {
                $WarningDays = 60
            }
            $HighlightExpiry = [bool]$ReportConfig.HealthCheck.Security.CertificateExpiry -and
                ($Appliance | Where-Object { $_.DaysRemaining -is [Int] -and $_.DaysRemaining -le $WarningDays })

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                if ($HighlightExpiry) {
                    Paragraph $LocalizedData.ExpiryInfo
                }
                BlankLine

                #region Appliance certificates
                if ($Appliance) {
                    Section -Style Heading3 $LocalizedData.CertHeading {

                        $CertInfo = foreach ($Certificate in $Appliance) {
                            $Row = [Ordered]@{
                                $LocalizedData.CommonName    = $Certificate.CommonName
                                $LocalizedData.CertType      = $Certificate.Type
                                $LocalizedData.Expires       = if ($Certificate.NotAfter) { $Certificate.NotAfter.ToString('yyyy-MM-dd') } else { $LocalizedData.NotSet }
                                $LocalizedData.DaysRemaining = if ($null -ne $Certificate.DaysRemaining) { $Certificate.DaysRemaining } else { $LocalizedData.NotSet }
                            }

                            if ($InfoLevel.Security -ge 2) {
                                $Row[$LocalizedData.SubjectAltName] = $Certificate.SubjectAltName
                                $Row[$LocalizedData.Issuer] = $Certificate.Issuer
                            }

                            if ($InfoLevel.Security -ge 5) {
                                $Row[$LocalizedData.SignatureAlgo] = $Certificate.SignatureAlgo
                                $Row[$LocalizedData.VerifyStatus] = $Certificate.VerifyStatus
                            }

                            [PSCustomObject]$Row
                        }

                        if ($HighlightExpiry) {
                            foreach ($Row in $CertInfo) {
                                $Remaining = $Row.$($LocalizedData.DaysRemaining)
                                if ($Remaining -isnot [Int]) {
                                    continue
                                }

                                # Styled without -Property so the whole row is highlighted.
                                # A single coloured cell is easy to miss when the table runs
                                # to a dozen certificates.
                                if ($Remaining -lt 0) {
                                    $Row | Set-Style -Style Critical
                                } elseif ($Remaining -le $WarningDays) {
                                    $Row | Set-Style -Style Warning
                                }
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.CertTable
                            List         = $false
                            ColumnWidths = switch ($InfoLevel.Security) {
                                { $_ -ge 5 } { 18, 12, 10, 8, 18, 18, 8, 8 }
                                { $_ -ge 2 } { 24, 14, 12, 10, 20, 20 }
                                default { 40, 20, 20, 20 }
                            }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $CertInfo | Table @TableParams
                    }
                }
                #endregion Appliance certificates

                #region Trusted roots
                $Root = @($Security.Certificate | Where-Object { $_.Type -eq 'Trusted Root' })

                if ($InfoLevel.Security -ge 3 -and $Root) {
                    Section -Style Heading3 $LocalizedData.RootHeading {

                        $RootInfo = foreach ($Certificate in $Root) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.CommonName = $Certificate.CommonName
                                $LocalizedData.Expires    = if ($Certificate.NotAfter) { $Certificate.NotAfter.ToString('yyyy-MM-dd') } else { $LocalizedData.NotSet }
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.RootTable
                            List         = $false
                            ColumnWidths = 70, 30
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $RootInfo | Sort-Object $LocalizedData.CommonName | Table @TableParams
                    }
                }
                #endregion Trusted roots

                #region TLS profiles
                if ($Security.TlsProfile) {
                    Section -Style Heading3 $LocalizedData.TlsHeading {

                        # Not named Profile. That is a PowerShell automatic variable.
                        $TlsInfo = foreach ($TlsRow in $Security.TlsProfile) {
                            $Row = [Ordered]@{
                                $LocalizedData.ProfileName = $TlsRow.Description
                                $LocalizedData.TlsVersion  = $TlsRow.TlsVersion
                                $LocalizedData.MutualAuth  = $TlsRow.MutualAuth
                            }

                            if ($InfoLevel.Security -ge 3) {
                                $Row[$LocalizedData.VerifyPeer] = $TlsRow.VerifyPeer
                                $Row[$LocalizedData.ValidateServer] = $TlsRow.ValidateServer
                                $Row[$LocalizedData.ValidateClient] = $TlsRow.ValidateClient
                                $Row[$LocalizedData.OcspStapling] = $TlsRow.OcspStapling
                                $Row[$LocalizedData.CipherCount] = $TlsRow.CipherCount
                            }

                            [PSCustomObject]$Row
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.TlsTable
                            List         = $false
                            ColumnWidths = if ($InfoLevel.Security -ge 3) { 20, 12, 12, 12, 12, 12, 12, 8 } else { 45, 30, 25 }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $TlsInfo | Table @TableParams
                    }
                }
                #endregion TLS profiles

                #region Account policy
                # Certificates and TLS protect signalling. This governs who may sign in to the
                # appliance and how, which is the other half of the security question and the
                # part an auditor usually opens the document to check.
                $Policy = Resolve-AbrRibbonSecurityPolicy -Config $script:RibbonConfig

                if ($Policy.PasswordPolicy) {
                    Section -Style Heading3 $LocalizedData.PolicyHeading {

                        $PolicyRow = $Policy.PasswordPolicy
                        $PasswordFields = [Ordered]@{
                            $LocalizedData.EnhancedSecurity   = $PolicyRow.EnhancedSecurity
                            $LocalizedData.ExpiryEnforced     = $PolicyRow.LifetimeEnforced
                        }

                        # The WebUI only reveals the password lifetime once the enforcement
                        # switch is on, so a value shown while it is off would be a number
                        # nobody chose.
                        if ($PolicyRow.LifetimeEnabled) {
                            $PasswordFields[$LocalizedData.MaximumLife] = $PolicyRow.MaximumLife
                        }

                        $PasswordFields[$LocalizedData.DisplayAllowed] = $PolicyRow.DisplayAllowed
                        $PasswordFields[$LocalizedData.BrowserSaveAllowed] = $PolicyRow.BrowserSaveAllowed

                        # The composition rules sit behind Enhanced Password Security in the
                        # WebUI. They are detail rather than headline, so they also wait for a
                        # reader who asked for it.
                        if ($PolicyRow.EnhancedEnabled -and $InfoLevel.Security -ge 4) {
                            $PasswordFields[$LocalizedData.MinimumLength] = $PolicyRow.MinimumLength
                            $PasswordFields[$LocalizedData.MinimumUpper] = $PolicyRow.MinimumUpper
                            $PasswordFields[$LocalizedData.MinimumLower] = $PolicyRow.MinimumLower
                            $PasswordFields[$LocalizedData.MinimumDigits] = $PolicyRow.MinimumDigits
                            $PasswordFields[$LocalizedData.MinimumSpecial] = $PolicyRow.MinimumSpecial
                            $PasswordFields[$LocalizedData.MinimumChanged] = $PolicyRow.MinimumChanged
                            $PasswordFields[$LocalizedData.MaximumConsecutive] = $PolicyRow.MaximumConsecutive
                            $PasswordFields[$LocalizedData.MaximumSameClass] = $PolicyRow.MaximumSameClass
                            $PasswordFields[$LocalizedData.MinimumLife] = $PolicyRow.MinimumLife
                            $PasswordFields[$LocalizedData.HistoryRemembered] = $PolicyRow.HistoryRemembered
                        }

                        $PasswordInfo = [PSCustomObject]$PasswordFields

                        $TableParams = @{
                            Name         = $LocalizedData.PasswordTable
                            List         = $true
                            ColumnWidths = 40, 60
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $PasswordInfo | Table @TableParams

                        if ($Policy.SessionPolicy) {
                            $SessionRow = $Policy.SessionPolicy
                            $SessionInfo = [PSCustomObject][Ordered]@{
                                $LocalizedData.FailedLogins   = $SessionRow.FailedLoginsBeforeLockout
                                $LocalizedData.LockoutTime    = $SessionRow.LockoutDuration
                                $LocalizedData.IdleTimeout    = $SessionRow.IdleTimeout
                                $LocalizedData.MaximumSession = $SessionRow.MaximumSessions
                                $LocalizedData.InactivityOff  = $SessionRow.InactivityDisable
                                $LocalizedData.PreLoginAck    = $SessionRow.PreLoginAcknowledgement
                            }

                            $TableParams = @{
                                Name         = $LocalizedData.SessionTable
                                List         = $true
                                ColumnWidths = 40, 60
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $SessionInfo | Table @TableParams
                        }
                    }
                }
                #endregion Account policy

                #region Active Directory
                # Only rendered when the feature is configured, so appliances that do not use
                # it are not padded with an empty section.
                if ($Policy.Directory -and ($Policy.Directory.State -eq 'Enabled' -or $Policy.DomainController)) {
                    Section -Style Heading3 $LocalizedData.DirectoryHeading {

                        $DirectoryRow = $Policy.Directory
                        $DirectoryInfo = [PSCustomObject][Ordered]@{
                            $LocalizedData.State           = $DirectoryRow.State
                            $LocalizedData.OperatingMode   = $DirectoryRow.OperatingMode
                            $LocalizedData.UseTls          = $DirectoryRow.UseTls
                            $LocalizedData.UpdateFrequency = $DirectoryRow.UpdateFrequency
                            $LocalizedData.NestedGroups    = $DirectoryRow.NestedGroups
                            $LocalizedData.CacheEncrypted  = $DirectoryRow.CacheEncrypted
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.DirectoryTable
                            List         = $true
                            ColumnWidths = 40, 60
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $DirectoryInfo | Table @TableParams

                        if ($Policy.DomainController) {
                            $ControllerInfo = foreach ($Controller in $Policy.DomainController) {
                                $Row = [Ordered]@{
                                    $LocalizedData.Server   = $Controller.Server
                                    $LocalizedData.Priority = $Controller.Priority
                                    $LocalizedData.State    = $Controller.State
                                }

                                if ($InfoLevel.Security -ge 3) {
                                    $Row[$LocalizedData.SearchScope] = $Controller.SearchScope
                                    $Row[$LocalizedData.Timeout] = $Controller.Timeout
                                }

                                [PSCustomObject]$Row
                            }

                            $TableParams = @{
                                Name         = $LocalizedData.ControllerTable
                                List         = $false
                                ColumnWidths = if ($InfoLevel.Security -ge 3) { 30, 10, 12, 36, 12 } else { 55, 20, 25 }
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $ControllerInfo | Table @TableParams
                        }
                    }
                }
                #endregion Active Directory

                #region RADIUS
                if ($Policy.Radius -and ($Policy.Radius.State -eq 'Enabled' -or $Policy.RadiusServer)) {
                    Section -Style Heading3 $LocalizedData.RadiusHeading {

                        $RadiusRow = $Policy.Radius
                        $RadiusFields = [Ordered]@{
                            $LocalizedData.State          = $RadiusRow.State
                            $LocalizedData.Authentication = $RadiusRow.Authentication
                            $LocalizedData.Accounting     = $RadiusRow.Accounting
                            $LocalizedData.PrimaryServer  = $RadiusRow.PrimaryServer
                            $LocalizedData.SecondServer   = $RadiusRow.SecondaryServer
                            $LocalizedData.FailoverTime   = $RadiusRow.FailoverTimeout
                        }

                        # The accounting mode and accounting servers have no effect unless
                        # accounting is switched on, so showing them otherwise just invites the
                        # question of why they are set.
                        if ($RadiusRow.Accounting -eq 'Enabled') {
                            $RadiusFields[$LocalizedData.AccountingMode] = $RadiusRow.AccountingMode
                            $RadiusFields[$LocalizedData.AccountServer1] = $RadiusRow.AccountingServer1
                            $RadiusFields[$LocalizedData.AccountServer2] = $RadiusRow.AccountingServer2
                        }

                        $RadiusInfo = [PSCustomObject]$RadiusFields

                        $TableParams = @{
                            Name         = $LocalizedData.RadiusTable
                            List         = $true
                            ColumnWidths = 40, 60
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $RadiusInfo | Table @TableParams

                        if ($Policy.RadiusServer) {
                            $ServerInfo = foreach ($Server in $Policy.RadiusServer) {
                                [PSCustomObject][Ordered]@{
                                    $LocalizedData.ProfileName = $Server.Description
                                    $LocalizedData.Server      = $Server.Server
                                    $LocalizedData.Port        = $Server.Port
                                    $LocalizedData.PacketType  = $Server.PacketType
                                    $LocalizedData.State       = $Server.State
                                }
                            }

                            $TableParams = @{
                                Name         = $LocalizedData.RadiusServerTable
                                List         = $false
                                ColumnWidths = 26, 22, 10, 27, 15
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $ServerInfo | Table @TableParams
                        }
                    }
                }
                #endregion RADIUS
            }
        } catch {
            Write-PScriboMessage -IsWarning "Security: $($_.Exception.Message)"
        }
    }

    end {}
}
