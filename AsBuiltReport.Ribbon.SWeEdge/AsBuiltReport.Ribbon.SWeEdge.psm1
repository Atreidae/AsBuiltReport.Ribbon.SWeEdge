# Dot-source all Public and Private function files.
# FunctionsToExport in the manifest controls what is visible to callers, so no
# Export-ModuleMember call is needed here.
foreach ($Folder in @('Public', 'Private')) {
    $FolderPath = Join-Path -Path $PSScriptRoot -ChildPath "Src\$Folder"

    if (Test-Path -Path $FolderPath) {
        Get-ChildItem -Path $FolderPath -Filter '*.ps1' -Recurse | ForEach-Object {
            try {
                . $_.FullName
            } catch {
                Write-Warning "Failed to import function $($_.FullName): $_"
            }
        }
    }
}
