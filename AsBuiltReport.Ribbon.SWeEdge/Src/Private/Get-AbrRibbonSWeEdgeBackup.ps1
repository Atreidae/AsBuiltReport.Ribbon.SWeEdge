function Get-AbrRibbonSWeEdgeBackup {
    <#
    .SYNOPSIS
        Downloads a configuration backup from a Ribbon SBC over its REST interface.
    .DESCRIPTION
        The appliance's REST interface can produce the same backup archive the WebUI does. That
        matters more than it sounds: the file returned here is byte for byte the sort of export
        Import-AbrRibbonSWeEdgeConfig already reads, so collecting over the network needs no
        second parser and no second data contract. Every resolver and section behaves
        identically whether the configuration came from a file or from an appliance.

        Two calls are involved. A form post to /rest/login establishes a session cookie, then a
        post to /rest/system?action=backup streams the archive to disk.

        The account used must have REST level access. That is not granted by default and has to
        be created on the appliance first.
    .PARAMETER Target
        Host name or address of the appliance.
    .PARAMETER Credential
        Credentials for a REST enabled account on the appliance.
    .PARAMETER Path
        Where to write the downloaded archive. A temporary file is used when omitted.
    .PARAMETER SkipCertificateCheck
        Accept the appliance's certificate without validating it. Most appliances present a self
        signed certificate on their internal interface, so this is usually required.

        Certificate validation is a process wide setting on Windows PowerShell. This function
        restores whatever was in place before it ran, so a report does not quietly leave the
        rest of the session accepting any certificate.
    .OUTPUTS
        System.String, the path to the downloaded archive.
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        The REST call shape follows the interface Ribbon publishes. Thanks to Andrew Morpeth,
        whose Backup-SBC1k2k made the login and backup endpoints easy to identify.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Get-AbrRibbonSWeEdgeBackup -Target 'sbc1.contoso.com' -Credential $Credential
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String] $Target,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential] $Credential,

        [Parameter(Mandatory = $false)]
        [String] $Path,

        [Parameter(Mandatory = $false)]
        [Switch] $SkipCertificateCheck
    )

    if (-not $Path) {
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ('AbrRibbon_{0}_{1}.tar' -f ($Target -replace '[^\w\.\-]', '_'), [Guid]::NewGuid().ToString('N').Substring(0, 8))
    }

    $BaseUrl = 'https://{0}' -f $Target

    # Windows PowerShell and PowerShell 6+ disable certificate validation by completely
    # different mechanisms, and neither works on the other. Invoke-RestMethod gained
    # SkipCertificateCheck in version 6; before that the only route is the process wide
    # ServicePointManager callback, which PowerShell 6+ largely ignores because its web cmdlets
    # are built on HttpClient rather than HttpWebRequest.
    $IsModernShell = $PSVersionTable.PSVersion.Major -ge 6

    $PreviousCallback = $null
    $PreviousProtocol = $null
    $CallbackChanged = $false

    try {
        if ($SkipCertificateCheck) {
            # Deliberately noisy. A reporting tool that turns off certificate validation without
            # saying so is exactly the sort of thing that surfaces later as an audit finding.
            Write-PScriboMessage -IsWarning ("Certificate validation is disabled for {0}. The appliance identity is not being verified." -f $Target)

            if (-not $IsModernShell) {
                $PreviousCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
                $CallbackChanged = $true
            }
        }

        if (-not $IsModernShell) {
            # Windows PowerShell does not reliably negotiate TLS 1.2, which current firmware
            # requires. The existing value is added to rather than replaced, so nothing else in
            # the session loses a protocol it was relying on.
            $PreviousProtocol = [System.Net.ServicePointManager]::SecurityProtocol
            if (-not ($PreviousProtocol -band [System.Net.SecurityProtocolType]::Tls12)) {
                [System.Net.ServicePointManager]::SecurityProtocol = $PreviousProtocol -bor [System.Net.SecurityProtocolType]::Tls12
            }
        }

        #region Authenticate
        # The login endpoint takes a form encoded body rather than JSON. Values are escaped
        # because a password containing an ampersand would otherwise truncate the request.
        $Password = [System.Net.NetworkCredential]::new('', $Credential.Password).Password
        $Body = 'Username={0}&Password={1}' -f
            [System.Uri]::EscapeDataString($Credential.UserName),
            [System.Uri]::EscapeDataString($Password)
        $Password = $null

        $LoginArgs = @{
            Uri             = '{0}/rest/login' -f $BaseUrl
            Method          = 'Post'
            Body            = $Body
            SessionVariable = 'RestSession'
            ErrorAction     = 'Stop'
        }

        if ($SkipCertificateCheck -and $IsModernShell) {
            $LoginArgs['SkipCertificateCheck'] = $true
        }

        Write-PScriboMessage ("Authenticating to {0} as {1}." -f $Target, $Credential.UserName)

        try {
            $LoginResult = Invoke-RestMethod @LoginArgs
        } catch {
            throw ("Could not reach the REST interface on {0}. {1}" -f $Target, $_.Exception.Message)
        } finally {
            $Body = $null
        }

        # The appliance answers with an XML document carrying its own status code. A refused
        # login still returns HTTP 200, so the payload has to be checked rather than trusted.
        $ResponseText = if ($LoginResult -is [System.Xml.XmlDocument]) { $LoginResult.OuterXml } else { [String]$LoginResult }

        if ($ResponseText -notmatch '<http_code>200</http_code>') {
            throw ("The appliance at {0} rejected the credentials supplied. Confirm the account exists and has REST level access, which is not granted by default." -f $Target)
        }
        #endregion Authenticate

        #region Download
        $BackupArgs = @{
            Uri         = '{0}/rest/system?action=backup' -f $BaseUrl
            Method      = 'Post'
            Body        = ''
            WebSession  = $RestSession
            OutFile     = $Path
            ErrorAction = 'Stop'
        }

        if ($SkipCertificateCheck -and $IsModernShell) {
            $BackupArgs['SkipCertificateCheck'] = $true
        }

        Write-PScriboMessage ("Requesting a configuration backup from {0}." -f $Target)

        try {
            Invoke-RestMethod @BackupArgs | Out-Null
        } catch {
            throw ("The backup request to {0} failed. {1}" -f $Target, $_.Exception.Message)
        }

        if (-not (Test-Path -LiteralPath $Path)) {
            throw ("The appliance at {0} did not return a backup archive." -f $Target)
        }

        # A zero length file means the request succeeded but produced nothing, which is more
        # confusing to debug later than failing here.
        if ((Get-Item -LiteralPath $Path).Length -eq 0) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            throw ("The appliance at {0} returned an empty backup archive." -f $Target)
        }
        #endregion Download

        Write-PScriboMessage ("Downloaded {0:N0} bytes from {1}." -f (Get-Item -LiteralPath $Path).Length, $Target)
        $Path
    } finally {
        # Restoring matters. These are process wide, and this function runs inside somebody
        # else's PowerShell session alongside other report modules.
        if ($CallbackChanged) {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $PreviousCallback
        }
        if ($null -ne $PreviousProtocol) {
            [System.Net.ServicePointManager]::SecurityProtocol = $PreviousProtocol
        }
    }
}
