# Laser Z-Height Handling Technical Reference

## The Problem

When using the Carvera CNC with laser operations, the laser can be out of focus if the Fusion 360 CAM setup doesn't correctly place the operation at the material surface.

### Root Cause

The actual root cause was **incorrect Fusion 360 CAM setup**, not M321 behavior:

1. Fusion 360's Engrave operation was configured with the target surface **below** stock top
2. This caused the G-code to reference Z positions below the actual surface (e.g., Z-4.46)
3. When converted to laser operations, the probe found the real surface at Z0, but the original CAM setup's depth offset caused confusion
4. The apparent "M321 offset" (~3.5mm) was actually the engrave depth from the Fusion setup

### The Solution

**Configure the laser operation in Fusion 360 correctly:**
- The fake engraving tool must target the **stock top surface** (Z0)
- The model/sketch being engraved must be at the top of stock
- Engrave depth should be minimal (0.001mm) since lasers don't plunge

---

## Fusion 360 Laser Tool Setup

### Creating the Fake Laser Tool

Since Fusion 360 doesn't have native laser support for the Carvera, we use a chamfer mill (T99) as a placeholder that gets converted to laser operations by the merge script.

1. **Create a new tool** in your Fusion 360 tool library
2. **Tool type:** Chamfer Mill
3. **Tool number:** T99 (this is what the merge script looks for)
4. **Geometry:**
   - Diameter: 0.1mm (small, since laser spot is tiny)
   - Tip angle: 45 degrees
   - Other dimensions: minimal/default

### Setting Up the Engrave Operation

1. **Select Engrave** from the 2D operations
2. **Tool:** Select your T99 chamfer mill
3. **Geometry tab:**
   - Select the contours/sketches to engrave
4. **Heights tab (CRITICAL):**
   - **Clearance Height:** From Retract height, Offset 6mm (or similar safe value)
   - **Retract Height:** From Stock top, Offset 2mm
   - **Feed Height:** From Model top, Offset 0mm
   - **Top Height:** From Stock top, Offset 0mm (or Model top if model is at stock top)
   - **Bottom Height:** From Stock top, Offset 0mm (or -0.001mm if Fusion requires some depth)
5. **Passes tab:**
   - Tolerance: 0.01mm
   - Multiple Depths: Unchecked (laser doesn't need multiple passes for depth)

### Critical Setup Requirements

- **Model must be at stock top:** If your engraved sketch/model is below the stock top surface, Fusion will generate Z positions below Z0
- **Heights must reference stock top:** All height settings should be relative to stock top, not model top (unless model IS at stock top)
- **Minimal depth:** Set bottom height to 0mm or -0.001mm - the laser doesn't actually cut into material

### Common Mistakes

| Mistake | Result | Fix |
|---------|--------|-----|
| Model below stock top | Z moves go negative (e.g., Z-4.46) | Move model/sketch to stock top surface |
| Bottom Height set deep | Unnecessary Z plunges in G-code | Set Bottom Height to Stock top, 0mm |
| Using Model top when model is below stock | Wrong Z reference | Use Stock top for height references |

---

## Current Solution: Simple Probe and Go

With correct Fusion setup, the laser sequence is straightforward:

### Laser Setup Sequence
```gcode
G54 (Ensure G54 WCS)
G0 Z20 (Safe Z height)
G0 X[first_laser_X] Y[first_laser_Y] (Move to first laser position)
G38.2 Z-50 F100 (Probe surface)
G0 Z5 (Retract after probe)
M321 (Enable laser mode - returns probe automatically)
G54 (Re-confirm G54 WCS after M321)
G0 Z0 (Move to laser focal height)
M325 S[power] (Set laser power)
M3 (Enable laser firing)
```

### Laser Teardown Sequence
```gcode
M5 (Laser off)
M322 (Disable laser mode)
G0 Z20 (Safe Z retract)
T[next] M6 (Next tool change)
```

### Why This Works

1. **Probe finds the actual surface** - G38.2 touches the material and the machine knows where it is
2. **M321 enables laser mode** - The Carvera switches to laser, moves Z up, and handles its internal offsets
3. **G54 re-confirms WCS** - Ensures we're using the correct coordinate system
4. **G0 Z0 goes to focus height** - With correct Fusion setup, Z0 is the surface, which is the laser focal point

No compensation needed when Fusion is set up correctly!

---

## Mill -> Laser Workflows

For jobs that mill first then laser, additional considerations apply:

### The Challenge
- Milling operations may remove material (surfacing, pocketing)
- The laser needs to focus on the **new** surface, not the original stock top
- We probe at the first laser position to find the actual current surface

### Key Points
- Probe location matters: Probe where the laser will operate, not at origin
- The probed surface becomes the laser's Z0
- After laser, subsequent milling tools will use their own tool length compensation

---

## Approaches That Don't Work

### 1. G10 L20 with G55 (Overcomplicates things)

```gcode
G38.2 Z-50 F100 (Probe surface)
G10 L20 P2 Z0 (Set G55 Z0 to probed surface)
M321 (Enable laser mode)
G55 (Switch to G55)
G0 Z0 (Go to Z0)
```
**Why it fails:** Adds unnecessary complexity. M321 handles its own coordinate setup. Adding G10 L20 before M321 causes conflicts. Simple probe + M321 + G0 Z0 works fine.

### 2. Manual Z Compensation

```gcode
G0 Z0 (Go to Z0)
G91 (Relative mode)
G0 Z-3.5 (Compensate for "M321 offset")
G90 (Absolute mode)
```
**Why it's wrong:** The "3.5mm offset" wasn't from M321 - it was from incorrect Fusion CAM setup. Fix the setup, not the G-code.

### 3. Re-probe After M321

```gcode
M321 (Enable laser mode)
G38.2 Z-50 F100 (Re-probe)
```
**Why it fails:** The laser module doesn't have probing capability. G38.2 only works with the wireless probe (T0), which is returned when M321 is called.

---

## Key G-Code Reference

| Code | Function | Notes |
|------|----------|-------|
| `G54` | Select Work Coordinate System 1 | Primary WCS |
| `G38.2 Z-50 F100` | Probe Z until contact | Use before M321 |
| `M321` | Enable Carvera laser mode | Moves Z, returns probe |
| `M322` | Disable Carvera laser mode | - |
| `M325 S##` | Set laser power (0-100%) | - |
| `M3` | Enable laser firing | - |
| `M5` | Disable laser firing | - |
| `G90` | Absolute positioning mode | - |
| `G91` | Relative/incremental mode | - |

---

## Debugging Tips

### Adding Debug Pauses
Use M600 (Carvera pause) to stop at specific points and check Z values:
```gcode
G38.2 Z-50 F100 (Probe surface)
(DEBUG: After probe - check Z)
M600
```

### Key Values to Check
- **Work Z** (green on controller): The coordinate used by G-code commands
- **Machine Z** (gray below): Absolute physical position

### Checking Fusion Output
Before running the merge script, check the raw Fusion G-code:
- Look at ZMIN in the header comment (should be ~0, not -4.46 or similar)
- Check the first G1 Z move (should be Z0 or Z-0.001, not deep negative)

---

## File Locations

- Main script: `GCodeMerge.ps1`
- Laser setup code: `Process-LaserLine` function, around line 316
- Laser teardown (mid-job): `Process-LaserLine` function, around line 332
- Laser teardown (end of job): `Merge-GCodeFiles` function, around line 618

---

## Version History

| Date | Change | Outcome |
|------|--------|---------|
| 2026-01-03 | Initial: No Z adjustment after probe | Laser out of focus |
| 2026-01-03 | Tried G10 L20, G55, G92 approaches | Various failures |
| 2026-01-03 | Implemented 3.5mm compensation | Appeared to work |
| 2026-01-04 | **Discovered root cause: Fusion CAM setup** | Engrave depth was causing Z offset |
| 2026-01-04 | Fixed Fusion setup (model at stock top) | Laser in focus, no compensation needed |
| 2026-01-04 | Reverted to simple probe + M321 + G0 Z0 | Working correctly |

---

## Summary

The laser focus issue was caused by **incorrect Fusion 360 CAM setup**, not M321 behavior. When the engrave operation is correctly configured with:
- Model/sketch at stock top surface
- Heights referencing stock top
- Minimal engrave depth (0.001mm)

The simple sequence of probe -> M321 -> G0 Z0 works perfectly. No compensation or complex WCS manipulation needed.
