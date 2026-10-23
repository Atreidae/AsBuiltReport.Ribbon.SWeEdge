function Resolve-AbrRibbonLogging {
    <#
    .SYNOPSIS
        Resolves the logging and SNMP monitoring configuration of a Ribbon SBC.
    .DESCRIPTION
        Returns syslog destinations, SNMP managers and the per subsystem log levels.

        Subsystem log levels are worth reporting because leaving a subsystem at Trace or Debug
        is a common cause of disk and performance problems that survives long after whatever
        it was enabled for.

        SNMP community strings are credentials and are never returned. Note that they are not
        caught by name based redaction, because the field is called snmpCommunity rather than
        anything containing secret, password or key.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with SyslogServer, SnmpManager and
        SubsystemLogLevel.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonLogging -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml

    $LogLevelName = @{
        '0' = 'Default'
        '1' = 'Trace'
        '2' = 'Debug'
        '3' = 'Informational'
        '4' = 'Warning'
        '5' = 'Error'
        '6' = 'Fatal'
    }

    # Subsystem short names as used in the logger name, taken from the Ribbon WebUI.
    $SubsystemName = @{
        'ads' = 'Active Directory Service'; 'alarm' = 'Alarm Service'; 'mfg' = 'Analog Manufacturing Test Tool'
        'bmp' = 'BMP'; 'cas' = 'CAS Protocol'; 'route' = 'Call Routing Service'
        'csm' = 'Certificate Security Manager'; 'ccc' = 'Common Call Control'; 'trans' = 'Common Transport Service'
        'conf' = 'Configuration System'; 'zebos' = 'Core Switching/Routing'; 'dynamichosts' = 'Dynamic Hosts'
        'hosts' = 'Hosts'; 'splitdns' = 'Split DNS'; 'isdn' = 'ISDN Protocol'
        'lic' = 'License Management Service'; 'log' = 'Logging System'; 'msc' = 'Media Stream Control Service'
        'symsock' = 'Network Services'; 'osys' = 'Operating System Logs'; 'pmapi' = 'Platform Management'
        'rad' = 'RADIUS Manager Service'; 'resrc' = 'Resource Management'; 'security' = 'Security'
        'sip' = 'SIP Stack Service'; 'snmp' = 'SNMP'; 'watch' = 'Statistics and Live Info Service'
        'sba' = 'Survivable Branch Appliance'; 'shm' = 'System Health Monitoring'; 'sysio' = 'System I/O Service'
        'stmr' = 'System Timer Service'; 'tip' = 'Telephony Interface Process'; 'trapd' = 'Trap Service (SNMP)'
        'uas' = 'User Authentication Service'
    }

    $SyslogFacilityName = @{
        '0' = 'user'; '1' = 'kernel'; '2' = 'mail'; '3' = 'daemon'; '4' = 'auth'; '5' = 'lpr'
        '6' = 'news'; '7' = 'uucp'; '8' = 'cron'; '9' = 'local0'; '10' = 'local1'; '11' = 'local2'
        '12' = 'local3'; '13' = 'local4'; '14' = 'local5'; '15' = 'local6'; '16' = 'local7'
    }

    $SyslogServer = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='Logging']/Token[@name='SyslogServer']/ID") | ConvertFrom-AbrRibbonIeNode)) {
        [PSCustomObject]@{
            ID        = $Row.ID
            Address   = $Row.ServerAddress
            Port      = $Row.ServerPort
            Transport = if ($Row.ServerTransport -eq '1') { 'TCP' } else { 'UDP' }
            Level     = if ($LogLevelName.ContainsKey([String]$Row.DefaultLevel)) { $LogLevelName[[String]$Row.DefaultLevel] } else { "Unknown ($($Row.DefaultLevel))" }
            # Trace and Debug are the levels worth flagging as left enabled.
            IsVerbose = [String]$Row.DefaultLevel -in @('1', '2')
            Facility  = if ($SyslogFacilityName.ContainsKey([String]$Row.SyslogFacility)) { $SyslogFacilityName[[String]$Row.SyslogFacility] } else { "Unknown ($($Row.SyslogFacility))" }
            State     = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
        }
    }

    $SnmpManager = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='SNMP']/Token[@name='SNMPMgrTable']/ID") | ConvertFrom-AbrRibbonIeNode)) {
        [PSCustomObject]@{
            ID          = $Row.ID
            Address     = $Row.snmpMgrAddr
            Version     = switch ([String]$Row.snmpVersion) {
                '0' { 'v1/v2c' }
                '1' { 'v3' }
                default { "Unknown ($($Row.snmpVersion))" }
            }
            TrapEnabled = if ($Row.snmpTrapEnable -eq '1') { 'Enabled' } else { 'Disabled' }
            UsmUserName = $Row.usmUsername
            State       = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            # snmpCommunity is a credential and is deliberately not carried through.
        }
    }

    # A level is held per subsystem per log destination, so the same subsystem appears several
    # times. Where every destination agrees, which is the normal case, that is one fact and is
    # reported once. Where they differ, each distinct level is kept so the difference shows.
    $SubsystemLogLevel = @($Xml.Configuration.SelectNodes("Token[@name='Logging']/Token[@name='DebugLevels']/ID") | ConvertFrom-AbrRibbonIeNode) |
        ForEach-Object {
            # Logger names look like com.sonus.sbc.sip, the last segment is the subsystem.
            $Short = ([String]$_.LoggerName -split '\.')[-1]

            [PSCustomObject]@{
                LoggerName  = $_.LoggerName
                Destination = $_.LogDestination
                Subsystem   = if ($SubsystemName.ContainsKey($Short)) { $SubsystemName[$Short] } else { $Short }
                Level       = if ($LogLevelName.ContainsKey([String]$_.LogLevel)) { $LogLevelName[[String]$_.LogLevel] } else { "Unknown ($($_.LogLevel))" }
                # Trace and Debug are the levels worth flagging as left enabled.
                IsVerbose   = [String]$_.LogLevel -in @('1', '2')
            }
        } |
        Group-Object -Property Subsystem, Level |
        ForEach-Object {
            $First = $_.Group[0]
            [PSCustomObject]@{
                Subsystem        = $First.Subsystem
                Level            = $First.Level
                IsVerbose        = $First.IsVerbose
                DestinationCount = $_.Count
            }
        }

    [PSCustomObject]@{
        SyslogServer      = @($SyslogServer)
        SnmpManager       = @($SnmpManager)
        SubsystemLogLevel = @($SubsystemLogLevel)
    }
}
