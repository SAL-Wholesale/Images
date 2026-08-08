<#
Rebuild_Image_Mapping_From_Folder.ps1

Purpose:
  Rebuilds Image_Mapping_FromFolder.csv based on the ACTUAL image files
  currently sitting in your images folder. This guarantees the mapping
  matches reality regardless of any file-type/extension changes from
  re-saving images.

  Also flags:
    - Double-extension files (e.g. 10000_075725100007.jpg.png)
    - Files that do not follow the Item_UPC naming pattern
    - Duplicate Item numbers with more than one image file

Run examples (from PowerShell):

  cd "C:\Users\anorezi\OneDrive - Save A Lot\Desktop\Wholesale Storefront\Images"
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  .\Rebuild_Image_Mapping_From_Folder.ps1 -ImagesFolder ".\images"

Outputs (written to Downloads by default to avoid OneDrive locks):
  - Image_Mapping_FromFolder.csv          (clean mapping to upload to builder)
  - Image_Mapping_Issues.csv              (double extensions + bad names + duplicates)
#>

param(
    [string]$ImagesFolder = ".\images",
    [string]$OutputMapping = "$env:USERPROFILE\Downloads\Image_Mapping_FromFolder.csv",
    [string]$IssuesCsv = "$env:USERPROFILE\Downloads\Image_Mapping_Issues.csv"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ImagesFolder)) {
    throw "Images folder not found: $ImagesFolder"
}
$ImagesFolder = (Resolve-Path $ImagesFolder).Path
Write-Host "Scanning: $ImagesFolder" -ForegroundColor Cyan

$validExt = @('.jpg','.jpeg','.png','.webp','.gif')

$files = Get-ChildItem -Path $ImagesFolder -File | Where-Object {
    $validExt -contains $_.Extension.ToLower()
}

Write-Host "Found $($files.Count) image files." -ForegroundColor Cyan

$mapping = New-Object System.Collections.Generic.List[object]
$issues  = New-Object System.Collections.Generic.List[object]
$itemSeen = @{}

foreach ($f in $files) {
    $name = $f.Name
    $base = $f.BaseName    # filename without the final extension

    # --- Check 1: Double extension ---
    # e.g. "10000_075725100007.jpg.png" -> BaseName is "10000_075725100007.jpg"
    $doubleExt = $false
    if ($base -match '\.(jpg|jpeg|png|webp|gif)$') {
        $doubleExt = $true
        $issues.Add([pscustomobject]@{
            FileName = $name
            IssueType = 'Double extension'
            Detail = "File appears to have two image extensions. Rename to a single extension."
            SuggestedFix = ($base -replace '\.(jpg|jpeg|png|webp|gif)$','') + $f.Extension.ToLower()
        })
    }

    # Strip any trailing image extension from base for parsing Item_UPC
    $cleanBase = $base -replace '\.(jpg|jpeg|png|webp|gif)$',''

    # --- Check 2: Naming pattern Item_UPC ---
    $parts = $cleanBase -split '_', 2
    $item = $parts[0]
    $upc  = if ($parts.Count -gt 1) { $parts[1] } else { '' }

    $badName = $false
    if (-not $item) {
        $badName = $true
        $issues.Add([pscustomobject]@{
            FileName = $name
            IssueType = 'Unparseable name'
            Detail = "Could not extract an Item number from the filename."
            SuggestedFix = 'Rename to Item_UPC.ext'
        })
    }

    # Track duplicate item numbers
    if ($item) {
        if ($itemSeen.ContainsKey($item)) { $itemSeen[$item]++ } else { $itemSeen[$item] = 1 }
    }

    if (-not $badName) {
        $mapping.Add([pscustomobject]@{
            Item        = $item
            UPC         = $upc
            'Image URL' = "images/$name"
            'Apply?'    = 'Y'
            DoubleExt   = if ($doubleExt) { 'YES' } else { '' }
        })
    }
}

# --- Check 3: Duplicate item numbers (more than one image file) ---
foreach ($kv in $itemSeen.GetEnumerator()) {
    if ($kv.Value -gt 1) {
        $dupeFiles = ($mapping | Where-Object { $_.Item -eq $kv.Key } | ForEach-Object { ($_.'Image URL' -replace '^images/','') }) -join '; '
        $issues.Add([pscustomobject]@{
            FileName = $dupeFiles
            IssueType = 'Duplicate item'
            Detail = "Item $($kv.Key) has $($kv.Value) image files. Keep only one."
            SuggestedFix = 'Delete extras so each item has a single image.'
        })
    }
}

# --- Write outputs ---
$mapping | Select-Object Item, UPC, 'Image URL', 'Apply?' |
    Export-Csv -NoTypeInformation -Encoding UTF8 $OutputMapping

if ($issues.Count -gt 0) {
    $issues | Export-Csv -NoTypeInformation -Encoding UTF8 $IssuesCsv
} else {
    # still create an empty issues file with headers so you know it ran
    [pscustomobject]@{ FileName=''; IssueType='None'; Detail='No issues found'; SuggestedFix='' } |
        Export-Csv -NoTypeInformation -Encoding UTF8 $IssuesCsv
}

# --- Summary ---
$doubleCount = ($issues | Where-Object { $_.IssueType -eq 'Double extension' }).Count
$badNameCount = ($issues | Where-Object { $_.IssueType -eq 'Unparseable name' }).Count
$dupeCount = ($issues | Where-Object { $_.IssueType -eq 'Duplicate item' }).Count

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
Write-Host "Image files scanned:      $($files.Count)"
Write-Host "Mapping rows written:     $($mapping.Count)"
Write-Host "Double-extension files:   $doubleCount" -ForegroundColor $(if($doubleCount -gt 0){'Yellow'}else{'Green'})
Write-Host "Unparseable names:        $badNameCount" -ForegroundColor $(if($badNameCount -gt 0){'Yellow'}else{'Green'})
Write-Host "Duplicate items:          $dupeCount" -ForegroundColor $(if($dupeCount -gt 0){'Yellow'}else{'Green'})
Write-Host ""
Write-Host "Mapping file: $OutputMapping"
Write-Host "Issues file:  $IssuesCsv"

if ($doubleCount -gt 0) {
    Write-Host ""
    Write-Host "TIP: Open the issues file, review the SuggestedFix column, then rename the flagged files." -ForegroundColor Yellow
    Write-Host "     After renaming, just run this script again to refresh the mapping." -ForegroundColor Yellow
}
