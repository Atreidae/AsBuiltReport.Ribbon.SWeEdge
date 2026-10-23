function Get-AbrRibbonSWeEdgeUnreferenced {
    <#
    .SYNOPSIS
        Used by As Built Report to report unreferenced Ribbon SWeEdge configuration objects.
    .DESCRIPTION
        Documents configuration objects that nothing refers to, in Word/HTML/Text formats
        using PScribo.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeUnreferenced
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Objects = @(Resolve-AbrRibbonUnreferencedObject -Config $script:RibbonConfig)

            if (-not $Objects) {
                Write-PScriboMessage $LocalizedData.NotFound
                return
            }

            $TypeName = @{
                TransformationTable = $LocalizedData.TypeTransformation
                TranslationTable    = $LocalizedData.TypeTranslation
                RoutingTable        = $LocalizedData.TypeRoutingTable
                MessageRuleTable    = $LocalizedData.TypeMessageRule
                MediaList           = $LocalizedData.TypeMediaList
                SipProfile          = $LocalizedData.TypeSipProfile
                SipServerTable      = $LocalizedData.TypeSipServer
                TlsProfile          = $LocalizedData.TypeTlsProfile
                ToneTable           = $LocalizedData.TypeToneTable
                ActionSet           = $LocalizedData.TypeActionSet
            }

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                BlankLine

                $ObjectInfo = foreach ($Object in ($Objects | Sort-Object Type, { [Int]$_.ID })) {
                    [PSCustomObject][Ordered]@{
                        $LocalizedData.ObjectType = if ($TypeName.ContainsKey($Object.Type)) { $TypeName[$Object.Type] } else { $Object.Type }
                        $LocalizedData.ObjectId   = $Object.ID
                        $LocalizedData.ObjectName = $Object.Name
                        $LocalizedData.Status     = if ($Object.Status -eq 'Unreferenced') { $LocalizedData.StatusUnreferenced } else { $LocalizedData.StatusDisabledReferrer }
                    }
                }

                $TableParams = @{
                    Name         = $LocalizedData.SummaryTable
                    List         = $false
                    ColumnWidths = 28, 8, 40, 24
                }
                if ($Report.ShowTableCaptions) {
                    $TableParams['Caption'] = "- $($TableParams.Name)"
                }
                $ObjectInfo | Table @TableParams
            }
        } catch {
            Write-PScriboMessage -IsWarning "Unreferenced: $($_.Exception.Message)"
        }
    }

    end {}
}
