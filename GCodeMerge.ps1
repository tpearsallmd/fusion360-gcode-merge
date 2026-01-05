<#
.SYNOPSIS
    Fusion G-Code File Merge - Merge multiple G-code files for ATC machines

.DESCRIPTION
    A Windows utility to merge sequenced G-code files from Fusion 360 into a single
    file for CNC machines with automatic tool changers. Includes automatic T99 laser
    transformation for Carvera CNC with surface probing.

.NOTES
    Version: 1.1.0
    Author:  Todd Pearsall
    License: CC BY-NC 4.0
    GitHub:  https://github.com/tpearsallmd/fusion360-gcode-merge
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Hide the PowerShell console window
Add-Type -Name Window -Namespace Console -MemberDefinition '
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[void][Console.Window]::ShowWindow($consolePtr, 0) # 0 = Hide

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Fusion G-Code File Merge"
$form.Size = New-Object System.Drawing.Size(500, 435)
$form.StartPosition = "CenterScreen"
$form.AllowDrop = $true
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# Set application icon (use shell32.dll icon - index 71 is a document/merge style icon)
$iconExtractor = Add-Type -MemberDefinition '
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr ExtractIcon(IntPtr hInst, string lpszExeFileName, int nIconIndex);
' -Name 'IconExtractor' -Namespace 'Win32' -PassThru
$iconHandle = $iconExtractor::ExtractIcon([IntPtr]::Zero, "shell32.dll", 71)
if ($iconHandle -ne [IntPtr]::Zero) {
    $form.Icon = [System.Drawing.Icon]::FromHandle($iconHandle)
}

# Create drop zone label
$dropLabel = New-Object System.Windows.Forms.Label
$dropLabel.Text = "Drag and drop .cnc files here"
$dropLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$dropLabel.Size = New-Object System.Drawing.Size(460, 40)
$dropLabel.Location = New-Object System.Drawing.Point(10, 10)
$dropLabel.TextAlign = "MiddleCenter"
$dropLabel.BorderStyle = "FixedSingle"
$dropLabel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$form.Controls.Add($dropLabel)

# Create listbox to show files
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Size = New-Object System.Drawing.Size(460, 180)
$listBox.Location = New-Object System.Drawing.Point(10, 60)
$listBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$form.Controls.Add($listBox)

# Create clear button
$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = "Clear"
$clearButton.Size = New-Object System.Drawing.Size(100, 30)
$clearButton.Location = New-Object System.Drawing.Point(10, 250)
$form.Controls.Add($clearButton)

# Create laser pause checkbox
$laserPauseCheckbox = New-Object System.Windows.Forms.CheckBox
$laserPauseCheckbox.Text = "Laser Pause"
$laserPauseCheckbox.Checked = $true
$laserPauseCheckbox.Size = New-Object System.Drawing.Size(100, 25)
$laserPauseCheckbox.Location = New-Object System.Drawing.Point(120, 253)
$form.Controls.Add($laserPauseCheckbox)

# Create merge button
$mergeButton = New-Object System.Windows.Forms.Button
$mergeButton.Text = "Merge Files"
$mergeButton.Size = New-Object System.Drawing.Size(100, 30)
$mergeButton.Location = New-Object System.Drawing.Point(370, 250)
$mergeButton.Enabled = $false
$form.Controls.Add($mergeButton)

# Create output filename label
$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Text = "Output:"
$outputLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$outputLabel.Size = New-Object System.Drawing.Size(55, 25)
$outputLabel.Location = New-Object System.Drawing.Point(10, 290)
$outputLabel.TextAlign = "MiddleLeft"
$form.Controls.Add($outputLabel)

# Create output filename textbox
$outputTextbox = New-Object System.Windows.Forms.TextBox
$outputTextbox.Font = New-Object System.Drawing.Font("Consolas", 10)
$outputTextbox.Size = New-Object System.Drawing.Size(415, 25)
$outputTextbox.Location = New-Object System.Drawing.Point(65, 290)
$outputTextbox.Text = ""
$form.Controls.Add($outputTextbox)

# Create status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$statusLabel.Size = New-Object System.Drawing.Size(460, 60)
$statusLabel.Location = New-Object System.Drawing.Point(10, 325)
$statusLabel.BorderStyle = "FixedSingle"
$form.Controls.Add($statusLabel)

# Store file info
$script:fileList = [System.Collections.ArrayList]::new()

# Function to parse filename and extract prefix and sequence number
function Parse-FileName {
    param([string]$filePath)

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)

    # Match pattern: prefix-number (e.g., TrumpCoin-1001)
    if ($fileName -match '^(.+)-(\d+)$') {
        return [PSCustomObject]@{
            Path = $filePath
            FileName = $fileName
            Prefix = $matches[1]
            Sequence = [int]$matches[2]
        }
    }
    return $null
}

# Function to validate files
function Validate-Files {
    if ($script:fileList.Count -lt 1) {
        return @{ Valid = $false; Message = "Add at least 1 file to process" }
    }

    $prefixes = $script:fileList | ForEach-Object { $_.Prefix } | Select-Object -Unique

    if ($prefixes.Count -gt 1) {
        return @{ Valid = $false; Message = "All files must have the same prefix. Found: $($prefixes -join ', ')" }
    }

    # Check for gaps in sequence numbers (only if more than 1 file)
    if ($script:fileList.Count -gt 1) {
        $sortedSeq = $script:fileList | Sort-Object -Property Sequence | ForEach-Object { $_.Sequence }
        $missingSeq = @()

        for ($i = 0; $i -lt $sortedSeq.Count - 1; $i++) {
            $current = $sortedSeq[$i]
            $next = $sortedSeq[$i + 1]

            # Check for any missing numbers between current and next
            for ($j = $current + 1; $j -lt $next; $j++) {
                $missingSeq += $j
            }
        }

        if ($missingSeq.Count -gt 0) {
            $prefix = $script:fileList[0].Prefix
            $missingFiles = $missingSeq | ForEach-Object { "$prefix-$_.cnc" }
            return @{ Valid = $false; Message = "Missing file(s) in sequence:`n$($missingFiles -join ', ')" }
        }

        return @{ Valid = $true; Message = "Ready to merge $($script:fileList.Count) files" }
    }

    return @{ Valid = $true; Message = "Ready to process 1 file" }
}

# Function to update UI
function Update-UI {
    $listBox.Items.Clear()

    # Sort by sequence number (keep as ArrayList)
    $sorted = $script:fileList | Sort-Object -Property Sequence
    $script:fileList.Clear()
    foreach ($item in $sorted) {
        [void]$script:fileList.Add($item)
    }

    foreach ($file in $script:fileList) {
        [void]$listBox.Items.Add("$($file.FileName).cnc (Seq: $($file.Sequence))")
    }

    # Update output filename suggestion
    if ($script:fileList.Count -gt 0) {
        $prefix = $script:fileList[0].Prefix
        $outputTextbox.Text = "$prefix-merged.cnc"
    } else {
        $outputTextbox.Text = ""
    }

    $validation = Validate-Files
    $statusLabel.Text = $validation.Message

    if ($validation.Valid) {
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        $mergeButton.Enabled = $true
    } else {
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $mergeButton.Enabled = $false
    }
}

# Function to pre-scan T99 file content to extract first XY position and spindle speed
function Get-LaserSetupInfo {
    param([string[]]$lines)

    $firstX = $null
    $firstY = $null
    $laserPower = $null
    $inT99Section = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        # Detect T99 tool change
        if ($trimmed -match '^T99\s*M6') {
            $inT99Section = $true
            continue
        }

        # Stop if we hit another tool change
        if ($inT99Section -and $trimmed -match '^T\d+\s*M6' -and $trimmed -notmatch '^T99') {
            break
        }

        if ($inT99Section) {
            # Extract spindle speed (laser power)
            if ($null -eq $laserPower -and ($trimmed -match '^S(\d+)\s*M3' -or $trimmed -match '^M3\s*S(\d+)')) {
                $laserPower = [int]$matches[1]
            }

            # Extract first X position
            if ($null -eq $firstX -and $trimmed -match 'X([-\d\.]+)') {
                $firstX = $matches[1]
            }

            # Extract first Y position
            if ($null -eq $firstY -and $trimmed -match 'Y([-\d\.]+)') {
                $firstY = $matches[1]
            }

            # Once we have all info, we can stop
            if ($null -ne $firstX -and $null -ne $firstY -and $null -ne $laserPower) {
                break
            }
        }
    }

    return @{
        FirstX = $firstX
        FirstY = $firstY
        LaserPower = $laserPower
    }
}

# Function to process a single line for laser (T99) transformation
function Process-LaserLine {
    param(
        [string]$line,
        [string]$trimmedLine,
        [ref]$inLaserMode,
        [ref]$laserStarted,
        [ref]$lastRampX,
        [ref]$lastRampY,
        [ref]$firstLaserMove,
        [ref]$laserLifted,
        [ref]$currentLaserPower,
        [ref]$currentFeedrate,
        [ref]$laserCuttingDepth,
        [string]$fileName,
        [hashtable]$laserSetupInfo,
        [bool]$laserPauseEnabled
    )

    # Detect T99 tool change - start laser mode
    if ($trimmedLine -match '^T99\s*M6') {
        $inLaserMode.Value = $true
        $laserStarted.Value = $false
        $lastRampX.Value = $null
        $lastRampY.Value = $null
        $firstLaserMove.Value = $true
        $laserLifted.Value = $true  # Start lifted so first move is G0 positioning
        $laserCuttingDepth.Value = $null  # Will be set on first plunge

        # Validate laser power
        if ($null -ne $laserSetupInfo.LaserPower -and $laserSetupInfo.LaserPower -gt 1000) {
            throw "Laser power cannot exceed 1000 (100%). Found S$($laserSetupInfo.LaserPower) in $fileName"
        }

        # Build the probing XY position
        $probeX = if ($null -ne $laserSetupInfo.FirstX) { $laserSetupInfo.FirstX } else { "0" }
        $probeY = if ($null -ne $laserSetupInfo.FirstY) { $laserSetupInfo.FirstY } else { "0" }

        # Convert spindle speed (0-1000) to laser power percentage (0-100)
        $spindleSpeed = if ($null -ne $laserSetupInfo.LaserPower) { $laserSetupInfo.LaserPower } else { 500 }
        $laserPowerPercent = [math]::Round($spindleSpeed / 10)

        # Mark laser as started and track current power level
        $laserStarted.Value = $true
        $currentLaserPower.Value = $spindleSpeed

        # Build laser setup sequence
        # No reprobe needed - Fusion CAM already knows the target Z depth relative to stock top
        # M321 will use the existing G54 Z0 (stock top) and Fusion's Z moves position the laser
        $setupLines = @(
            "(--- Begin Laser Setup ---)",
            "M5 (Spindle stop)",
            "M321 (Enable laser mode)"
        )
        if ($laserPauseEnabled) {
            $setupLines += "M600 (Remove vacuum boot and laser cap for laser engraving)"
        }
        $setupLines += @(
            "M325 S$laserPowerPercent (Set laser power $laserPowerPercent%)",
            "M3 (Enable laser firing)",
            "(--- Begin Laser Paths ---)"
        )
        return $setupLines
    }

    # Detect other tool change - end laser mode if active
    if ($trimmedLine -match '^T\d+\s*M6' -and $inLaserMode.Value) {
        $inLaserMode.Value = $false
        # Return laser teardown with safe retract, restore G54 from G55, then tool change
        $teardownLines = @(
            "(--- End Laser Paths ---)",
            "M5 (Laser off)",
            "M322 (Disable laser mode)",
            "G54 (Ensure G54 active after laser mode)",
            "G0 Z20 (Safe Z retract)"
        )
        if ($laserPauseEnabled) {
            $teardownLines += "M600 (Reinstall vacuum boot and laser cap)"
        }
        $teardownLines += @(
            "(--- Restore G54 from G55 backup ---)",
            "G55 (Switch to G55 - our backup of original G54)",
            "G10 L20 P1 X0 Y0 Z0 (Restore G54 from G55)",
            "G54 (Switch back to G54 for milling)",
            $line
        )
        return $teardownLines
    }

    # If not in laser mode, return line unchanged
    if (-not $inLaserMode.Value) {
        return @($line)
    }

    # In laser mode - process laser-specific transformations

    # Handle spindle/power commands - detect power changes
    if ($trimmedLine -match '^S(\d+)\s*M3' -or $trimmedLine -match '^M3\s*S(\d+)') {
        $newPower = [int]$matches[1]
        $laserStarted.Value = $true

        # If power changed, output M325 command
        if ($newPower -ne $currentLaserPower.Value) {
            $currentLaserPower.Value = $newPower
            $newPowerPercent = [math]::Round($newPower / 10)
            return @("M325 S$newPowerPercent (Change laser power to $newPowerPercent%)")
        }
        return @()
    }

    # Strip standalone spindle commands in laser mode
    if ($trimmedLine -match '^M3$') {
        return @()
    }

    # Strip G54/G55 WCS commands in laser mode - we manage WCS ourselves
    if ($trimmedLine -match '^G5[45]$') {
        return @()
    }

    # Handle Z moves in laser mode
    # Pass through the first Z plunge (to get laser to target depth), then track lifted state
    $zMatch = $null
    if ($trimmedLine -match '^Z([-\d\.]+)') {
        $zMatch = $matches[1]
    } elseif ($trimmedLine -match '^G[01]\s+Z([-\d\.]+)') {
        $zMatch = $matches[1]
    }

    if ($null -ne $zMatch) {
        $zValue = [double]$zMatch
        # Capture feedrate from Z moves (modal, applies to subsequent G1 moves)
        if ($line -match 'F([\d\.]+)') {
            $currentFeedrate.Value = $matches[1]
        }

        # Positive Z is always a lift (above workpiece)
        if ($zValue -gt 0) {
            $laserLifted.Value = $true
            return @()  # Don't output retracts
        }

        # Track the deepest negative Z as cutting depth
        if ($null -eq $laserCuttingDepth.Value -or $zValue -lt $laserCuttingDepth.Value) {
            $laserCuttingDepth.Value = $zValue
        }

        # Determine if this Z is a "lift" (shallower than cutting depth) or at cutting depth
        # A lift is when Z is more than 0.1mm above the cutting depth
        $isLift = $null -ne $laserCuttingDepth.Value -and $zValue -gt ($laserCuttingDepth.Value + 0.1)

        if ($isLift) {
            # Partial lift (e.g., Z-3.46 when cutting at Z-4.45) = laser off
            $laserLifted.Value = $true
            return @()  # Don't output lift moves
        } else {
            # At cutting depth = plunge
            # Pass through the first plunge, skip subsequent ones
            if ($firstLaserMove.Value) {
                $laserLifted.Value = $false
                return @("G0 Z$zMatch (Move to laser focal depth)")
            } else {
                $laserLifted.Value = $false
                return @()  # Already at depth, skip
            }
        }
    }

    # Handle G0 rapid moves in laser mode - extract XY and output as G0 (repositioning)
    if ($trimmedLine -match '^G0\s') {
        $xCoord = ""
        $yCoord = ""
        if ($line -match 'X([-\d\.]+)') { $xCoord = "X$($matches[1])" }
        if ($line -match 'Y([-\d\.]+)') { $yCoord = "Y$($matches[1])" }

        # If there are XY coordinates, output as G0 repositioning move
        if ($xCoord -ne "" -or $yCoord -ne "") {
            $laserLifted.Value = $true  # G0 means we're repositioning, laser off
            return @("G0 $xCoord $yCoord".Trim())
        }
        # No coordinates, just strip it
        return @()
    }

    # Handle lines with Z component (ramp/entry moves)
    if ($line -match 'Z([-\d\.]+)') {
        $zValue = [double]$matches[1]

        # Positive Z is always a lift
        if ($zValue -gt 0) {
            $laserLifted.Value = $true
            # Save XY from ramp moves
            if ($line -match 'X([-\d\.]+)') { $lastRampX.Value = $matches[1] }
            if ($line -match 'Y([-\d\.]+)') { $lastRampY.Value = $matches[1] }
            return @()
        }

        # Track cutting depth (deepest negative Z)
        if ($null -eq $laserCuttingDepth.Value -or $zValue -lt $laserCuttingDepth.Value) {
            $laserCuttingDepth.Value = $zValue
        }

        # Determine if lifted based on cutting depth
        $isLift = $null -ne $laserCuttingDepth.Value -and $zValue -gt ($laserCuttingDepth.Value + 0.1)
        $laserLifted.Value = $isLift

        # Save the X and Y coordinates from ramp moves
        if ($line -match 'X([-\d\.]+)') {
            $lastRampX.Value = $matches[1]
        }
        if ($line -match 'Y([-\d\.]+)') {
            $lastRampY.Value = $matches[1]
        }
        # For first move with Z at cutting depth, output the Z to set focal depth
        if ($firstLaserMove.Value -and -not $isLift) {
            # Build output with XY if present, plus Z
            $xCoord = ""
            $yCoord = ""
            if ($line -match 'X([-\d\.]+)') { $xCoord = "X$($matches[1])" }
            if ($line -match 'Y([-\d\.]+)') { $yCoord = "Y$($matches[1])" }
            return @("G0 $xCoord $yCoord Z$zValue (Initial position and focal depth)".Trim())
        }
        return @()
    }

    # Build the output line with explicit G0 or G1
    # Extract coordinates from the line
    $xCoord = ""
    $yCoord = ""
    $fValue = ""

    if ($line -match 'X([-\d\.]+)') { $xCoord = "X$($matches[1])" }
    if ($line -match 'Y([-\d\.]+)') { $yCoord = "Y$($matches[1])" }
    if ($line -match 'F([\d\.]+)') { $fValue = "F$($matches[1])" }

    # If no coordinates found, skip this line (comments, blank lines, etc.)
    if ($xCoord -eq "" -and $yCoord -eq "") {
        return @()
    }

    # For the first actual laser move, use saved coordinates from ramp if needed
    $isFirstMove = $firstLaserMove.Value
    if ($firstLaserMove.Value) {
        $firstLaserMove.Value = $false
        if ($xCoord -eq "" -and $null -ne $lastRampX.Value) {
            $xCoord = "X$($lastRampX.Value)"
        }
        if ($yCoord -eq "" -and $null -ne $lastRampY.Value) {
            $yCoord = "Y$($lastRampY.Value)"
        }
    }

    # Build the output with explicit G command
    # First move is always G0 (positioning without firing)
    if ($isFirstMove -or $laserLifted.Value) {
        # First move or lifted state = G0 rapid move (laser off)
        $outputLine = "G0 $xCoord $yCoord".Trim()
    } else {
        # Not lifted = G1 cutting move (laser on)
        # Use feedrate from line if present, otherwise use captured feedrate from Z moves
        $feedToUse = $fValue
        if ($feedToUse -eq "" -and $null -ne $currentFeedrate.Value -and $currentFeedrate.Value -ne "") {
            $feedToUse = "F$($currentFeedrate.Value)"
        }
        $parts = @("G1", $xCoord, $yCoord)
        if ($feedToUse -ne "") { $parts += $feedToUse }
        $outputLine = ($parts | Where-Object { $_ -ne "" }) -join " "
    }

    return @($outputLine)
}

# Function to merge G-code files
function Merge-GCodeFiles {
    param(
        [bool]$laserPauseEnabled = $true,
        [string]$outputFileName = ""
    )

    $sortedFiles = $script:fileList | Sort-Object -Property Sequence
    $outputFolder = [System.IO.Path]::GetDirectoryName($sortedFiles[0].Path)

    # Use custom filename if provided, otherwise default to prefix-merged.cnc
    if ([string]::IsNullOrWhiteSpace($outputFileName)) {
        $prefix = $sortedFiles[0].Prefix
        $outputFileName = "$prefix-merged.cnc"
    }

    # Ensure .cnc extension
    if (-not $outputFileName.EndsWith(".cnc", [StringComparison]::OrdinalIgnoreCase)) {
        $outputFileName = "$outputFileName.cnc"
    }

    $outputPath = Join-Path $outputFolder $outputFileName

    $mergedContent = New-Object System.Text.StringBuilder

    # Header patterns to skip in subsequent files
    $headerPatterns = @(
        '^\(.*\)$',           # Comments at start
        '^G90\s*G94',         # Absolute positioning
        '^G17$',              # XY plane
        '^G21$',              # Metric
        '^G54$'               # Work coordinate system
    )

    # Footer patterns to remove from all but last file
    $footerPatterns = @(
        '^M5$',               # Spindle stop
        '^G28$',              # Return home
        '^M30$'               # Program end
    )

    # Pre-scan all files to find T99 laser setup info
    $laserSetupInfo = @{ FirstX = $null; FirstY = $null; LaserPower = $null }
    foreach ($file in $sortedFiles) {
        try {
            $fileLines = Get-Content -Path $file.Path -ErrorAction Stop
        }
        catch {
            throw "Failed to read file '$($file.FileName).cnc': $($_.Exception.Message)"
        }
        $hasT99 = $fileLines | Where-Object { $_ -match '^T99\s*M6' }
        if ($hasT99) {
            $laserSetupInfo = Get-LaserSetupInfo -lines $fileLines
            break
        }
    }

    # Track laser mode across all files
    $inLaserMode = $false
    $laserStarted = $false
    $lastRampX = $null
    $lastRampY = $null
    $firstLaserMove = $true
    $laserLifted = $false
    $currentLaserPower = 0
    $currentFeedrate = $null
    $laserCuttingDepth = $null

    # Add G54→G55 backup at the very start of the merged file
    # This preserves the original G54 WCS so we can restore it after laser operations
    [void]$mergedContent.AppendLine("(--- Backup G54 to G55 for laser recovery ---)")
    [void]$mergedContent.AppendLine("G54 (Ensure G54 is active)")
    [void]$mergedContent.AppendLine("G10 L20 P2 X0 Y0 Z0 (Copy G54 origin to G55)")
    [void]$mergedContent.AppendLine("")

    for ($i = 0; $i -lt $sortedFiles.Count; $i++) {
        $file = $sortedFiles[$i]
        $isFirst = ($i -eq 0)
        $isLast = ($i -eq $sortedFiles.Count - 1)

        try {
            $lines = Get-Content -Path $file.Path -ErrorAction Stop
        }
        catch {
            throw "Failed to read file '$($file.FileName).cnc': $($_.Exception.Message)"
        }

        # Add source file comment
        [void]$mergedContent.AppendLine("")
        [void]$mergedContent.AppendLine("(--- Start of $($file.FileName).cnc ---)")

        $inHeader = $true

        foreach ($line in $lines) {
            $trimmedLine = $line.Trim()

            # Skip empty lines at the very start
            if ($trimmedLine -eq "" -and $mergedContent.Length -eq 0) {
                continue
            }

            # Check if this is a header line
            $isHeaderLine = $false
            if ($inHeader) {
                foreach ($pattern in $headerPatterns) {
                    if ($trimmedLine -match $pattern) {
                        $isHeaderLine = $true
                        break
                    }
                }

                # Header ends when we hit a tool command or non-header G-code
                if ($trimmedLine -match '^T\d+\s*M6' -or ($trimmedLine -match '^[GXY]' -and -not $isHeaderLine)) {
                    $inHeader = $false
                }
            }

            # Skip header lines for non-first files
            if (-not $isFirst -and $isHeaderLine -and $inHeader) {
                continue
            }

            # Check if this is a footer line
            $isFooterLine = $false
            foreach ($pattern in $footerPatterns) {
                if ($trimmedLine -match $pattern) {
                    $isFooterLine = $true
                    break
                }
            }

            # Skip footer lines for non-last files
            if (-not $isLast -and $isFooterLine) {
                continue
            }

            # Process line for laser transformation
            $processedLines = Process-LaserLine -line $line -trimmedLine $trimmedLine -inLaserMode ([ref]$inLaserMode) -laserStarted ([ref]$laserStarted) -lastRampX ([ref]$lastRampX) -lastRampY ([ref]$lastRampY) -firstLaserMove ([ref]$firstLaserMove) -laserLifted ([ref]$laserLifted) -currentLaserPower ([ref]$currentLaserPower) -currentFeedrate ([ref]$currentFeedrate) -laserCuttingDepth ([ref]$laserCuttingDepth) -fileName $file.FileName -laserSetupInfo $laserSetupInfo -laserPauseEnabled $laserPauseEnabled

            foreach ($processedLine in $processedLines) {
                if ($processedLine -ne $null -and $processedLine -ne '') {
                    [void]$mergedContent.AppendLine($processedLine)
                }
            }
        }

        # If file ends while still in laser mode and this is the last file, add laser teardown
        if ($isLast -and $inLaserMode) {
            [void]$mergedContent.AppendLine("(--- End Laser Paths ---)")
            [void]$mergedContent.AppendLine("M5 (Laser off)")
            [void]$mergedContent.AppendLine("M322 (Disable laser mode)")
            [void]$mergedContent.AppendLine("G54 (Ensure G54 active after laser mode)")
            [void]$mergedContent.AppendLine("G0 Z20 (Safe Z retract)")
            if ($laserPauseEnabled) {
                [void]$mergedContent.AppendLine("M600 (Reinstall vacuum boot and laser cap)")
            }
            [void]$mergedContent.AppendLine("(--- Restore G54 from G55 backup ---)")
            [void]$mergedContent.AppendLine("G55 (Switch to G55 - our backup of original G54)")
            [void]$mergedContent.AppendLine("G10 L20 P1 X0 Y0 Z0 (Restore G54 from G55)")
            [void]$mergedContent.AppendLine("G54 (Switch back to G54)")
        }

        [void]$mergedContent.AppendLine("(--- End of $($file.FileName).cnc ---)")
    }

    # Write the merged file
    try {
        $mergedContent.ToString() | Out-File -FilePath $outputPath -Encoding ASCII -ErrorAction Stop
    }
    catch {
        throw "Failed to write output file '$([System.IO.Path]::GetFileName($outputPath))': $($_.Exception.Message)"
    }

    return $outputPath
}

# Drag enter event
$form.Add_DragEnter({
    if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = [Windows.Forms.DragDropEffects]::Copy
        $dropLabel.BackColor = [System.Drawing.Color]::FromArgb(200, 255, 200)
    }
})

# Drag leave event
$form.Add_DragLeave({
    $dropLabel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
})

# Drop event
$form.Add_DragDrop({
    $dropLabel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

    $files = $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)

    foreach ($filePath in $files) {
        # Only accept .cnc files
        if ([System.IO.Path]::GetExtension($filePath).ToLower() -ne ".cnc") {
            $statusLabel.Text = "Skipped non-.cnc file: $([System.IO.Path]::GetFileName($filePath))"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
            continue
        }

        # Skip already-merged files
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
        if ($fileName -match '-merged$') {
            $statusLabel.Text = "Skipped merged file: $([System.IO.Path]::GetFileName($filePath))"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
            continue
        }

        $parsed = Parse-FileName -filePath $filePath

        if ($null -eq $parsed) {
            $statusLabel.Text = "Invalid filename format: $([System.IO.Path]::GetFileName($filePath))`nExpected: prefix-number.cnc"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
            continue
        }

        # Check for duplicates
        $exists = $script:fileList | Where-Object { $_.Path -eq $filePath }
        if ($null -eq $exists) {
            [void]$script:fileList.Add($parsed)
        }
    }

    Update-UI
})

# Clear button click
$clearButton.Add_Click({
    $script:fileList = [System.Collections.ArrayList]::new()
    $listBox.Items.Clear()
    $outputTextbox.Text = ""
    $statusLabel.Text = ""
    $statusLabel.ForeColor = [System.Drawing.Color]::Black
    $mergeButton.Enabled = $false
})

# Merge button click
$mergeButton.Add_Click({
    try {
        # Validate output filename
        $customFilename = $outputTextbox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($customFilename)) {
            $statusLabel.Text = "Error: Output filename cannot be empty"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
            return
        }

        # Check for invalid filename characters
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        $filenameOnly = [System.IO.Path]::GetFileName($customFilename)
        foreach ($char in $invalidChars) {
            if ($filenameOnly.Contains($char)) {
                $statusLabel.Text = "Error: Output filename contains invalid characters"
                $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
                return
            }
        }

        # Build output path to check for overwrite
        $outputFolder = [System.IO.Path]::GetDirectoryName($script:fileList[0].Path)
        $outputFileName = $customFilename
        if (-not $outputFileName.EndsWith(".cnc", [StringComparison]::OrdinalIgnoreCase)) {
            $outputFileName = "$outputFileName.cnc"
        }
        $outputPath = Join-Path $outputFolder $outputFileName

        # Check if output file already exists
        if (Test-Path $outputPath) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "File '$outputFileName' already exists.`n`nDo you want to overwrite it?",
                "Confirm Overwrite",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
                $statusLabel.Text = "Merge cancelled - file not overwritten"
                $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
                return
            }
        }

        $statusLabel.Text = "Merging files..."
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkBlue
        $form.Refresh()

        $outputPath = Merge-GCodeFiles -laserPauseEnabled $laserPauseCheckbox.Checked -outputFileName $customFilename

        $statusLabel.Text = "Success! Created:`n$([System.IO.Path]::GetFileName($outputPath))"
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
    }
    catch {
        $statusLabel.Text = "Error: $($_.Exception.Message)"
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
    }
})

# Function to add files from command line arguments
function Add-FilesFromArgs {
    param([string[]]$filePaths)

    foreach ($filePath in $filePaths) {
        if (-not (Test-Path $filePath)) {
            continue
        }

        # Only accept .cnc files
        if ([System.IO.Path]::GetExtension($filePath).ToLower() -ne ".cnc") {
            continue
        }

        # Skip already-merged files
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
        if ($fileName -match '-merged$') {
            continue
        }

        $parsed = Parse-FileName -filePath $filePath

        if ($null -eq $parsed) {
            continue
        }

        # Check for duplicates
        $exists = $script:fileList | Where-Object { $_.Path -eq $filePath }
        if ($null -eq $exists) {
            [void]$script:fileList.Add($parsed)
        }
    }
}

# Pre-load files if passed as command line arguments
if ($args.Count -gt 0) {
    [void](Add-FilesFromArgs -filePaths $args)
    [void](Update-UI)
}

# Show the form
[void]$form.ShowDialog()
