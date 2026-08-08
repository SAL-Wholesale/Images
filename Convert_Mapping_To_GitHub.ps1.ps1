<#
Convert_Mapping_To_GitHub.ps1

Purpose:
  Rewrites your image mapping so every Image URL points at your public GitHub
  repo raw URLs. Because files are named Item_UPC.ext and the repo URL is
  predictable, updating an image later = just replace the file in GitHub
  (same filename). Every portal auto-shows the new image. No rebuild needed.

Repo assumed:
  https://github.com/SAL-Wholesale/Images
  Raw base: https://raw.githubusercontent.com/SAL-Wholesale/Images/main/

Two modes:
  1) -FromFolder ".": build the mapping directly from the image files in a folder
  2) -InputCsv ".\Image_Mapping_FromFolder.csv": rewrite an existing mapping's URLs

Run examples (from PowerShell):

  # Build straight from the image files in the current folder
  cd "C:\Users\anorezi\OneDrive - Save A Lot\Desktop\Wholesale Storefront\images"
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  .\Convert_Mapping_To_GitHub.ps1 -FromFolder "."

  # Or rewrite an existing mapping file
  .\Convert_Mapping_To_GitHub.ps1 -InputCsv "$env:USERPROFILE\Downloads\Image_Mapping_FromFolder.csv"

Output:
  - Image_Mapping_GitHub.csv  (upload this to the V45 Builder as Image_Mapping.csv)
#>

param(
    [string]$FromFolder,
    [string]$InputCsv,
    [string]$Owner = "SAL-Wholesale",
    [string]$Repo = "Images",
    [string]$Branch = "main",
    [string]$OutputCsv = "$env:USERPROFILE\Downloads\Image_Mapping_GitHub.csv"
)

$ErrorActionPreference = "Stop"
$rawBase = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/"
Write-Host "GitHub raw base: $rawBase" -ForegroundColor Cyan

# URL-encode a filename (spaces, etc.) but keep it readable for normal names
function Encode-FileName {
    param([string]$Name)
    return [uri]::EscapeDataString($Name)
}

$rows = New-Object System.Collections.Generic.List[object]
$validExt = @('.jpg','.jpeg','.png','.webp','.gif')

if ($FromFolder) {
    if (-not (Test-Path $FromFolder)) { throw "Folder not found: $FromFolder" }
    $FromFolder = (Resolve-Path $FromFolder).Path
    Write-Host "Building mapping from files in: $FromFolder" -ForegroundColor Cyan
    $files = Get-ChildItem -Path $FromFolder -File | Where-Object { $validExt -contains $_.Extension.ToLower() }
    foreach ($f in $files) {
        $base = $f.BaseName -replace '\.(jpg|jpeg|png|webp|gif)$',''
        $parts = $base -split '_',2
        $item = $parts[0]
        $upc  = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        if (-not ($item -match '^\d+$')) { continue }   # skip logo/stray files
        $rows.Add([pscustomobject]@{
            Item        = $item
            UPC         = $upc
            'Image URL' = $rawBase + (Encode-FileName $f.Name)
            'Apply?'    = 'Y'
        })
    }
}
elseif ($InputCsv) {
    if (-not (Test-Path $InputCsv)) { throw "CSV not found: $InputCsv" }
    Write-Host "Rewriting URLs in: $InputCsv" -ForegroundColor Cyan
    $csv = Import-Csv $InputCsv
    foreach ($r in $csv) {
        $item = $r.Item
        $upc  = $r.UPC
        # Derive the filename from the existing Image URL (strip any folder prefix)
        $existing = "$($r.'Image URL')"
        $fileName = ($existing -split '[\\/]')[-1]
        if (-not $fileName) { continue }
        $rows.Add([pscustomobject]@{
            Item        = $item
            UPC         = $upc
            'Image URL' = $rawBase + (Encode-FileName $fileName)
            'Apply?'    = if ($r.'Apply?') { $r.'Apply?' } else { 'Y' }
        })
    }
}
else {
    throw "Provide either -FromFolder or -InputCsv."
}

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 $OutputCsv

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
Write-Host "Rows written: $($rows.Count)"
Write-Host "Output: $OutputCsv"
Write-Host ""
if ($rows.Count -gt 0) {
    Write-Host "Sample URLs:" -ForegroundColor Cyan
    $rows | Select-Object -First 3 | ForEach-Object { Write-Host "  $($_.Item)  ->  $($_.'Image URL')" }
}
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Make sure all image files are uploaded to https://github.com/$Owner/$Repo (branch: $Branch)."
Write-Host "  2. Confirm the repo is PUBLIC (Settings > General > Danger Zone > Change visibility)."
Write-Host "  3. Test one URL in a private/incognito browser window (no GitHub login)."
Write-Host "  4. Upload Image_Mapping_GitHub.csv to the V45 Builder as your Image Mapping file, then rebuild."
