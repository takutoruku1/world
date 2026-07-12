# OpenAI Images API でゲーム用アセットを生成するツール
# 使い方:
#   単発:   .\tools\gen_image.ps1 -Prompt "..." -OutFile assets\illustrations\title.png
#   一括:   .\tools\gen_image.ps1 -All          (tools\art_prompts.json の全プロンプトを生成、既存はスキップ)
# art_prompts.json のエントリごとに size / quality / background / style_key を指定可能。
# APIキーの探索順: $env:OPENAI_API_KEY → tools\openai_key.txt → ~\.codex\auth.json
param(
    [string]$Prompt = "",
    [string]$OutFile = "",
    [switch]$All,
    [string]$Model = "gpt-image-2",   # 存在しなければ gpt-image-1 に自動フォールバック
    [string]$Size = "1536x1024",
    [string]$Quality = "medium"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Get-ApiKey {
    if ($env:OPENAI_API_KEY) { return $env:OPENAI_API_KEY }
    $keyFile = Join-Path $PSScriptRoot "openai_key.txt"
    if (Test-Path $keyFile) {
        $k = (Get-Content $keyFile -Raw).Trim()
        if ($k) { return $k }
    }
    $authFile = "$env:USERPROFILE\.codex\auth.json"
    if (Test-Path $authFile) {
        $auth = Get-Content $authFile -Raw | ConvertFrom-Json
        if ($auth.OPENAI_API_KEY) { return $auth.OPENAI_API_KEY }
    }
    return $null
}

function Invoke-ImageGen([string]$model, [hashtable]$opts, [string]$outPath, [string]$apiKey) {
    $body = @{
        model   = $model
        prompt  = $opts.prompt
        size    = $opts.size
        quality = $opts.quality
        n       = 1
    }
    if ($opts.background) { $body.background = $opts.background }
    $json = $body | ConvertTo-Json
    $headers = @{ Authorization = "Bearer $apiKey"; "Content-Type" = "application/json" }
    $resp = Invoke-RestMethod -Uri "https://api.openai.com/v1/images/generations" `
        -Method Post -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) `
        -TimeoutSec 300
    $b64 = $resp.data[0].b64_json
    $dir = Split-Path -Parent $outPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllBytes($outPath, [Convert]::FromBase64String($b64))
    Write-Output "SAVED: $outPath ($model)"
}

function Generate([hashtable]$opts, [string]$outPath, [string]$apiKey) {
    try {
        Invoke-ImageGen $Model $opts $outPath $apiKey
        return $true
    } catch {
        $msg = $_.ErrorDetails.Message
        if (-not $msg) { $msg = $_.Exception.Message }
        if ($msg -match "model" -and ($msg -match "not exist" -or $msg -match "not found" -or $msg -match "invalid")) {
            Write-Output "NOTE: $Model は使えないため gpt-image-1 にフォールバック"
            try {
                Invoke-ImageGen "gpt-image-1" $opts $outPath $apiKey
                return $true
            } catch {
                $msg = $_.ErrorDetails.Message
                if (-not $msg) { $msg = $_.Exception.Message }
            }
        }
        Write-Output "FAILED: $outPath : $msg"
        if ($msg -match "quota|billing|insufficient|payment|balance") {
            Write-Output "QUOTA_EXHAUSTED"
            exit 3
        }
        return $false
    }
}

$apiKey = Get-ApiKey
if (-not $apiKey) {
    Write-Output "NO_API_KEY: OpenAIのAPIキーが見つかりません。platform.openai.com でキーを発行し、"
    Write-Output "  tools\openai_key.txt に貼り付けるか、`$env:OPENAI_API_KEY を設定してください。"
    exit 2
}

if ($All) {
    $data = Get-Content (Join-Path $PSScriptRoot "art_prompts.json") -Raw -Encoding utf8 | ConvertFrom-Json
    $failed = 0
    foreach ($p in $data.images) {
        $out = Join-Path $root $p.out
        if (Test-Path $out) { Write-Output "SKIP (exists): $($p.out)"; continue }
        $styleKey = if ($p.style_key) { $p.style_key } else { "style" }
        $style = $data.$styleKey
        $opts = @{
            prompt  = "$style $($p.prompt)"
            size    = if ($p.size) { $p.size } else { $Size }
            quality = if ($p.quality) { $p.quality } else { $Quality }
        }
        if ($p.background) { $opts.background = $p.background }
        Write-Output "GEN: $($p.id) ..."
        if (-not (Generate $opts $out $apiKey)) { $failed++ }
    }
    if ($failed -gt 0) { Write-Output "DONE WITH $failed FAILURE(S)"; exit 1 }
    Write-Output "ALL DONE"
} else {
    if (-not $Prompt -or -not $OutFile) { Write-Output "usage: -Prompt <text> -OutFile <path> か -All"; exit 2 }
    Generate @{ prompt = $Prompt; size = $Size; quality = $Quality } (Join-Path $root $OutFile) $apiKey | Out-Null
}
