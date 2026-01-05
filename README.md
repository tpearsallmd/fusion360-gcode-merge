# Fusion G-Code File Merge

A Windows utility to merge multiple G-code files from Fusion 360 into a single file for CNC machines with automatic tool changers (ATC), with built-in laser support for Carvera CNC.

## Problem

Fusion 360 Personal Use license does not allow exporting G-code with multiple tools in a single file. This forces users to export separate files for each tool operation (e.g., `Job-1001.cnc`, `Job-1002.cnc`, `Job-1003.cnc`) and run them one at a time, preventing use of automatic tool changers. Additionally, Fusion 360 doesn't natively support laser modules like the Carvera's laser attachment.

## Solution

This utility merges sequenced G-code files into a single file that can be run on CNC machines with ATC support. It also automatically transforms dummy tool T99 operations into proper Carvera laser G-code, complete with surface probing for correct focal height.

![Screenshot](Screenshot.jpg)

## Features

- Drag-and-drop GUI interface
- Automatic file sequence detection and validation
- Validates all files have the same prefix
- Detects missing files in the sequence
- Single file processing supported (for laser-only jobs)
- Preserves proper G-code structure:
  - Header from first file (setup commands, work coordinates)
  - Tool changes and operations from each file in sequence
  - Footer from last file only (spindle stop, return home, program end)
- Adds debug comments showing source file boundaries
- Ignores `-merged.cnc` files if accidentally included in selection
- Automatically transforms dummy tool T99 into laser G-code
- Optional M600 pauses for vacuum boot removal/reinstallation (checkbox in UI)

## ⚠️ Safety Warning & Disclaimer

**This software manipulates G-code that controls CNC machinery. Improper use can result in:**
- Damaged tools, workpieces, or machine
- Personal injury
- Fire (especially with laser operations)

**Before running merged G-code:**
1. Review the merged file in a G-code viewer/simulator
2. Stay within reach of the emergency stop button during the first run
3. Start with conservative feeds and speeds until you're confident in the output
4. Never leave laser operations unattended

**Disclaimer:** This software is provided "as is" without warranty of any kind. The authors are not responsible for any damage to equipment, property, or persons resulting from the use of this software or G-code produced by it. Use at your own risk.

## Requirements

- Windows 10/11
- PowerShell 5.1+ (included with Windows)

## Usage

### Option 1: Run the EXE
Double-click `GCodeMerge.exe` to open the GUI.

### Option 2: Drag files onto the EXE
Select your `.cnc` files in Explorer and drag them onto `GCodeMerge.exe`. The GUI will open with the files pre-loaded.

### Option 3: Run the PowerShell script
```powershell
powershell -ExecutionPolicy Bypass -File "GCodeMerge.ps1"
```

### Merging Files

1. Drag and drop your sequenced `.cnc` files onto the application window
2. Verify the files are listed in the correct sequence order
3. **Laser Pause** checkbox (checked by default): When enabled, adds M600 pauses before and after laser operations so you can remove/reinstall the vacuum boot
4. Click "Merge Files"
5. The merged file will be created in the same folder as the source files with `-merged` suffix

## File Naming Convention

Files must follow this naming pattern:
```
{ProjectName}-{SequenceNumber}.cnc
```

Examples:
- `Coin-1001.cnc`
- `Coin-1002.cnc`
- `Coin-1003.cnc`

The sequence numbers must be consecutive with no gaps.

## Output

The merged file is named `{ProjectName}-merged.cnc` and placed in the same folder as the source files.

## Carvera Laser Support (T99)

The Carvera CNC has a laser module, but Fusion 360 doesn't natively support it. This utility provides a workaround by transforming dummy T99 tool operations into proper Carvera laser G-code.

### Setup in Fusion 360

1. Create a dummy tool **T99** in your Fusion 360 tool library (any tool type works)
2. Set the "spindle speed" to your desired laser power:
   - `S100` = 10% laser power
   - `S500` = 50% laser power
   - `S1000` = 100% laser power (maximum)
3. Set the "cutting feedrate" appropriate for laser engraving:
   - The Carvera's 2.5W laser needs slow feed rates (100-300 mm/min) to burn properly
   - Too fast (e.g., 1000 mm/min) will result in faint or invisible marks
   - Experiment with feed rate and power to find the right combination for your material
4. Use T99 for engraving/marking operations in your CAM setup
   - **Note:** Laser support has only been tested with **2D Milling → Trace** operations

### What the Tool Does

When T99 is detected in the G-code, the utility automatically handles the complete laser workflow. The M321 command handles Z positioning automatically.

**Job Start** (added to beginning of merged file):

```gcode
G54                     ; Ensure G54 is active
G10 L20 P2 X0 Y0 Z0     ; Backup G54 origin to G55
```

**Laser Start Sequence** (replaces `T99 M6`):

```gcode
M5                      ; Spindle stop
M321                    ; Enable laser mode (handles Z positioning)
M600                    ; Pause - remove vacuum boot for laser (optional)
M325 S##                ; Set laser power (0-100%)
M3                      ; Enable laser firing
```

**Note:** G55 serves as a backup of the original G54 coordinates. M321 handles the laser module setup including Z positioning. After laser operations, G54 is restored from the G55 backup.

**During Laser Operation**:

- All Z-axis movements are stripped (laser operates at fixed Z0)
- Repositioning moves output as G0 (laser off during rapid moves)
- Cutting moves output as G1 (laser on during linear moves)
- Power changes mid-file are detected and output as `M325 S##`

**Laser End Sequence** (when switching to next tool or end of file):

```gcode
M5                      ; Laser off
M322                    ; Disable laser mode
G0 Z20                  ; Safe retract
G55                     ; Switch to G55 (backup of original G54)
G10 L20 P1 X0 Y0 Z0     ; Restore G54 from G55 backup
G54                     ; Switch back to G54 for milling
T# M6                   ; Next tool change (if applicable)
M600                    ; Pause - reinstall vacuum boot (optional)
```

Note: The G54 restoration from G55 ensures subsequent milling operations use the original work coordinate system. The tool change happens before the M600 pause so the spindle is raised and out of the way when reinstalling the vacuum boot.

**Multiple Consecutive Laser Operations:** If you have two or more T99 laser operations in a row (without milling operations between them), the surface is only probed once at the start of the first laser operation. All consecutive laser operations are assumed to be at the same surface height. If your laser operations are on surfaces at different heights, separate them with a non-laser operation or manually adjust the G-code.

### Validation

- Laser power must be between 0-1000 (0-100%)
- An error is shown if spindle speed exceeds 1000

### Example Workflow

1. Design your part in Fusion 360
2. Create CAM operations:
   - Operations 1-2: Milling with real tools (T1, T2, etc.) - removes material
   - Operation 3: Laser engraving with dummy tool T99 - engraves on new surface
   - Operation 4: Final cutout with real tool (T1)
3. Export each operation as a separate file (Fusion Personal limitation)
4. Drop all files into this utility and merge
5. The merged file will automatically:
   - Probe the surface at the first laser position
   - Set correct laser focal height (Z0)
   - Handle laser mode enable/disable (M321/M322)
   - Convert moves to G0 (repositioning) and G1 (cutting)
   - Handle mid-file power changes

## Troubleshooting

### Laser marks are faint or invisible

The feed rate is too fast. The Carvera's 2.5W laser needs slow feed rates to burn effectively:
- Try 100-200 mm/min for deep engraving
- Try 200-300 mm/min for light marking
- Increase laser power (S value in Fusion) if needed

Check your T99 tool settings in Fusion 360 - the "cutting feedrate" controls how fast the laser moves.

### Machine stops unexpectedly during laser operation

This is likely the M600 pause working as intended. The **Laser Pause** checkbox (enabled by default) adds pauses:
- **Before laser**: So you can remove the vacuum boot and laser cap
- **After laser**: So you can reinstall them before milling resumes

If you don't need these pauses (e.g., laser-only job, or you've modified your setup), uncheck the **Laser Pause** checkbox before merging.

### Milling operation after laser is at wrong height

The tool restores G54 from a G55 backup after laser operations. If your G55 was already in use for something else, this could cause issues. The tool assumes G55 is available for temporary backup storage.

### Laser doesn't fire at all

1. Verify the laser cap is removed
2. Check that M3 (laser enable) appears in the merged G-code after M321
3. Ensure laser power is set (M325 S## where ## is 1-100)
4. Confirm the Carvera laser module is properly installed and calibrated

### Files won't merge - "missing file in sequence" error

File names must be consecutive with no gaps. If you have `Job-1001.cnc` and `Job-1003.cnc`, the tool expects `Job-1002.cnc` to exist. Either:
- Export the missing file from Fusion 360
- Rename files to be consecutive (e.g., rename 1003 to 1002)

### Wrong tool picked up after laser operation

The G54 coordinate system is restored from G55 after laser mode ends. If milling tools are picking up at wrong positions, verify your original G54 zero point is correct before running the job.

## Building the EXE

To rebuild the executable after modifying the PowerShell script:

1. Install PS2EXE module (one-time):
   ```powershell
   Install-Module -Name ps2exe -Scope CurrentUser
   ```

2. Set execution policy for the current session:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

3. Build the EXE:
   ```powershell
   Invoke-ps2exe .\GCodeMerge.ps1 .\GCodeMerge.exe -noConsole
   ```

## Tested With

- Fusion 360 Personal Use
- Makera Carvera 3-axis CNC with ATC

## Future Enhancements

- [ ] **Per-operation laser probing** - Option to probe for each laser operation when multiple T99 operations target different surface heights (e.g., engraving on stepped surfaces or pockets at different depths)
- [ ] **Per-operation laser feedrate** - Currently the feedrate from the first laser operation is used for all subsequent laser operations. If you need different feedrates for different laser operations (e.g., faster for light marking, slower for deep engraving), this is not yet supported.

## License

CC BY-NC 4.0 - Free for non-commercial use. See [LICENSE](LICENSE) for details.
