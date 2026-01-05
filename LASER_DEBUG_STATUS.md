# Laser Coordinate System Debug Status

## Current State (2026-01-05)

We are debugging coordinate system corruption after M322 (disable laser mode) on the Carvera CNC.

### Problem Statement

After laser operations complete, subsequent milling operations sometimes go to wrong positions, triggering soft endstop errors. The issue is related to how M321/M322 handle coordinate offsets.

### Test Results from laser-offset-test.cnc

We ran a test capturing machine coordinates at three stages:

| Stage | Work X | Work Y | Work Z | Machine X | Machine Y | Machine Z |
|-------|--------|--------|--------|-----------|-----------|-----------|
| Baseline (before M321) | 0 | 0 | 10 | -209.210 | -145.315 | -50.120 |
| After M321 | 0 | 0 | 37.530 | -171.220 | -149.535 | -3.000 |
| After M322 | 0 | 0 | 82.530 | -209.210 | -145.315 | -3.000 |

### Key Findings

1. **M321 applies laser offsets**: Machine position shifts by approximately:
   - X: +38.00mm (matches laser X offset of -37.99)
   - Y: -4.22mm (matches laser Y offset of 4.22)
   - Z: +47.12mm (matches laser Z offset of -45.0, plus some positioning)

2. **M322 restores X/Y but NOT Z**: After M322:
   - Machine X/Y return to baseline values (-209.210, -145.315) - GOOD
   - Machine Z stays at -3.000 instead of returning to -50.120 - PROBLEM

3. **Z offset persists**: The ~47mm Z error after M322 matches the laser Z offset, confirming M322 does not fully restore Z.

### Current Teardown Sequence

```gcode
M322 (Disable laser mode - restores X/Y offsets automatically)
G54 (Stabilize coordinate system after M322)
G53 G0 Z-5 (Safe Z retract in machine coords)
M600 (Reinstall vacuum boot and laser cap)
T# M6 (Tool change)
```

### What We're Testing

The current approach:
1. **M322** - Disables laser mode, automatically restores X/Y offsets
2. **G54** - Added immediately after M322 to stabilize the coordinate system (this is new)
3. **G53 G0 Z-5** - Safe Z retract using machine coordinates (bypasses any WCS issues)
4. Tool change proceeds normally

### Important Note About G55 Backup

The G55 backup is still created at the start of the merged file:
```gcode
(--- Backup G54 to G55 for laser recovery ---)
G54 (Ensure G54 is active)
G10 L20 P2 X0 Y0 Z0 (Copy G54 origin to G55)
```

We are **not actively using** the G55 backup in the teardown sequence since M322 + G54 should handle the restoration. The backup remains as a potential fallback if the simpler approach doesn't work.

### Next Steps

1. **Test the updated merged file** (`Heads-merged.cnc`) with the new teardown sequence
2. **Observe**: Does the tool change after laser work correctly?
3. **If it fails**: We may need to restore G54 from the G55 backup after all, specifically for Z

### Files

- `GCodeMerge.ps1` - Main script with updated teardown logic
- `GCodeMerge-test.ps1` - Test script to regenerate merged files without GUI
- `laser-offset-test.cnc` - Standalone test file for capturing offset behavior (in LaserCoin folder)
- `Heads-merged.cnc` - Current test output (in LaserCoin folder)

### Carvera Laser Offset Settings (from machine config)

- X: -37.99mm
- Y: 4.22mm
- Z: -45.0mm
