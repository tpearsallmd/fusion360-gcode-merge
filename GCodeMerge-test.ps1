# Test script to run merge without GUI
. "$PSScriptRoot\GCodeMerge.ps1" -NoGUI

# Source files from LaserCoin
$sourceDir = "c:\Users\todd\OneDrive\Desktop\CNC\LaserCoin"
$files = @(
    "$sourceDir\Heads-1001.cnc",
    "$sourceDir\Heads-1002.cnc",
    "$sourceDir\Heads-1003.cnc"
)

# Add files to the file list
foreach ($filePath in $files) {
    if (Test-Path $filePath) {
        $parsed = Parse-FileName -filePath $filePath
        if ($null -ne $parsed) {
            [void]$script:fileList.Add($parsed)
        }
    }
}

# Run the merge
$outputPath = Merge-GCodeFiles -laserPauseEnabled $true -outputFileName "Heads-merged.cnc"
Write-Host "Created: $outputPath"
