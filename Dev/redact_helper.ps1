function Redact-String {
    param([string]$s)
    if ($null -eq $s) { return $s }
    # redact XML tag contents for common secret-like tags
    $tags = @('Secret','Password','Token','ApiKey','ClientSecret','Key')
    foreach ($t in $tags) {
        $pattern = "(?is)<\s*${t}[^>]*>.*?<\s*/\s*${t}\s*>"
        $s = [regex]::Replace($s, $pattern, { param($m) $open = ($m.Value -replace '(?is)(<\s*' + $t + '[^>]*>).*', '$1'); $close = "</$t>"; return "$open<redacted>$close" })
        # redact key: value lines in text output
        $s = [regex]::Replace($s, "(?im)^(\s*${t}\s*:\s*).+$", '$1<redacted>')
    }
    return $s
}

function Redact-ObjectProperties {
    param([psobject]$obj)
    if ($null -eq $obj) { return $null }
    $copy = [ordered]@{}
    foreach ($p in $obj.PSObject.Properties) {
        $name = $p.Name
        $val = $p.Value
        if ($name -match '(?i)secret|password|token|apikey|clientsecret|key') {
            $copy[$name] = '<redacted>'
        } else {
            if ($val -is [string]) { $copy[$name] = Redact-String $val } else { $copy[$name] = $val }
        }
    }
    return [pscustomobject]$copy
}
