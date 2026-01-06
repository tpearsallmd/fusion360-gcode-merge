# Changelog

## v1.2.0 - 2025-01-05

### Bug Fixes

- **Fix first laser cut being output as G0 instead of G1** - After outputting the Z focal depth move, the next XY move is now correctly treated as a cutting move (G1) rather than a positioning move (G0). This was causing the first actual cut line to be missing.

- **Fix laser lift detection** - Detect partial Z lifts (e.g., Z-3.46 vs Z-4.45 cutting depth) to properly output G0 for repositioning moves instead of G1.

- **Add G54 immediately after M322** - Ensures stable coordinate system after disabling laser mode, before any subsequent operations.

### Improvements

- **Simplified laser teardown sequence** - M322 automatically restores X/Y offsets. New sequence:
  1. M322 (disables laser, restores X/Y)
  2. G54 (stabilizes coordinate system)
  3. G53 G0 Z-5 (safe retract in machine coords)
  4. M600 (reinstall vacuum boot and laser cap)

- **Simplified laser setup** - Let M321 handle Z positioning automatically, removing unnecessary G0 Z moves.

- **Feedrate preservation** - Capture feedrate from Z plunge moves and apply to G1 cutting moves so laser engraving uses correct speeds.

- **Improved M600 pause timing** - Moved pauses to after M321 (start) and after safe retract (end) for proper clearance.

- **G55 backup created at file start** - G54 is backed up to G55 at the start of merged files as a fallback for coordinate restoration if needed.

### Documentation

- Updated README to reflect simplified laser workflow
- Removed outdated surface probing documentation (M321 handles this)
- Added LASER_DEBUG_STATUS.md documenting coordinate system debug findings
- Added GCodeMerge-test.ps1 for regenerating merged files without GUI

### Internal

- Removed .exe from repo, added *.exe to .gitignore
- Multiple iterations testing M321/M322 behavior with machine coordinate capture
