function Normalize-StringForComparison {
    [CmdletBinding()]
    param(
        [Parameter()][string]$InputString = ''
    )
    if (-not $InputString) { return '' }
    $s = [string]$InputString
    $normalized = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $normalized.ToCharArray()) {
        $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    $str = $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
    # Collapse whitespace, trim and lowercase invariant
    $str = ($str -replace '\s+', ' ').Trim().ToLowerInvariant()
    return $str
}

Export-ModuleMember -Function Normalize-StringForComparison
