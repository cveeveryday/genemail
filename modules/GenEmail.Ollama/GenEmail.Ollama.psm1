function New-GenEmailContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Model,
        [string]$BaseUrl = 'http://localhost:11434'
    )

    # stream=false is required: Ollama defaults to NDJSON streaming, which
    # Invoke-RestMethod cannot parse as a single JSON response.
    $requestBody = @{
        model  = $Model
        prompt = $Prompt
        stream = $false
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$BaseUrl/api/generate" -Method Post `
        -ContentType 'application/json' -Body $requestBody

    $text = $response.response
    $subjectMatch = [regex]::Match($text, '(?im)^SUBJECT:\s*(.+)$')
    $bodyMatch = [regex]::Match($text, '(?ims)^BODY:\s*(.+)$')

    [PSCustomObject]@{
        Subject = if ($subjectMatch.Success) { $subjectMatch.Groups[1].Value.Trim() } else { 'Generated message' }
        Body    = if ($bodyMatch.Success) { $bodyMatch.Groups[1].Value.Trim() } else { $text.Trim() }
    }
}

function Test-GenEmailOllamaConnection {
    [CmdletBinding()]
    param(
        [string]$BaseUrl = 'http://localhost:11434',
        [string]$Model
    )

    try {
        $tags = Invoke-RestMethod -Uri "$BaseUrl/api/tags" -Method Get -ErrorAction Stop
    }
    catch {
        return $false
    }

    if ($Model) {
        return [bool]($tags.models | Where-Object { $_.name -like "$Model*" })
    }

    $true
}

Export-ModuleMember -Function New-GenEmailContent, Test-GenEmailOllamaConnection
