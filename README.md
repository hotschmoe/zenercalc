# zenercalc

Open-source structural engineering calculation suite for residential and low-rise construction. Full-coverage replacement for ENERCALC SEL 20: 64+ modules spanning beams, columns, foundations, walls, diaphragms, 3D FEM frames, and code compliance per IBC 2024 / ASCE 7-22 / ACI 318-19 / AISC 360-22 / NDS 2024 / SDPWS 2021.

Built from scratch in Zig. Zero bloat. Every formula cites its code section. All calculation logic is auditable and testable.

**License:** AGPL-3.0

---

## Current Status: Phase 1 Complete

Wood beam and wood column calculators are implemented and functional:

**Wood Beam:**
- NDS 2018 sawn lumber (5 species x 4 grades) and glulam (7 stress classes)
- All 8 NDS adjustment factors (CD, CM, Ct, CF, Cfu, Ci, Cr, CL) with code citations
- ASCE 7-22 ASD load combinations (21 combos including wind uplift)
- Simple beam analysis with moment, shear, and deflection diagrams (51 points)
- Design checks with DCR ratios for bending, shear, and deflection

**Wood Column:**
- NDS 2018 Section 3.7 column stability factor (Cp) with biaxial buckling
- NDS 2018 Section 3.9 combined axial + bending interaction (Eq. 3.9-3)
- Per-combo load duration adjustment across all 21 ASD combos
- Supports axial loads + biaxial moments, self-weight, effective length factors (Ke)
- Design checks with DCR ratios for compression and interaction

Both modules use CLI with JSON-in/JSON-out.

### Quick Start

```bash
zig build

# Wood beam
echo '{"module":"wood_beam","span_ft":12,"material":{"type":"sawn_lumber","species":"DF-L","grade":"No.2"},"width_in":1.5,"depth_in":9.25,"dead_load_plf":15,"live_load_plf":40,"include_self_weight":true}' | zig-out/bin/zenercalc

# Wood column
echo '{"module":"wood_column","height_ft":10,"width_in":5.5,"depth_in":5.5,"material":{"type":"sawn_lumber","species":"DF-L","grade":"No.2"},"axial_dead_lb":5000,"axial_live_lb":10000}' | zig-out/bin/zenercalc
```

Output is pretty-printed JSON with section properties, NDS adjustment factors, actual stresses, and pass/fail status for each design check.

---

## Philosophy

- **Auditable by design.** Every calculation step traces to a specific code provision. No black box. Engineers can trust what they stamp.
- **Dependency sovereignty.** External C libraries are permitted short-term with a mandatory Zig rewrite timeline. Nothing stays a permanent foreign dependency unless the rewrite ROI is negligible (e.g. SQLite amalgamation at ~200KB).
- **One binary per target.** No installer, no runtime, no DLLs. Cross-compile from any host.
- **Engineering clarity over aesthetics.** The UI is optimized for numeric input density, printable precision, and keyboard-first workflows.

---

## Zig Version

**Target: Zig 0.15.2** (minimum)

---

## Targets

| Platform | Architecture | Status |
|---|---|---|
| Linux | x86_64 | Primary dev target |
| Linux | aarch64 | Supported |
| Windows | x86_64 | Supported |
| Windows | aarch64 | Supported (Snapdragon X) |

---

## Build

```bash
# Host target
zig build

# Run all tests
zig build test

# Optimized build
zig build -Doptimize=ReleaseFast

# Cross-compile
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-linux-gnu
zig build -Dtarget=x86_64-windows-gnu
zig build -Dtarget=aarch64-windows-gnu
```

---

## Code Editions

| Standard | Implemented | Default Target |
|---|---|---|
| NDS | 2018 | 2024 |
| ASCE 7 | 22 (ASD combos) | 22 |
| IBC | -- | 2024 |
| ACI 318 | -- | 19 |
| AISC 360 | -- | 22 |
| SDPWS | -- | 2021 |
| TMS 402/602 | -- | 2022 |

Code year is configurable per-project. The rule engine applies the correct edition's provisions at runtime.

---

## Dependencies

**Phase 1: Zero external dependencies.** Pure Zig, no C interop.

All computation uses comptime-baked material tables and pure Zig math. The CLI uses only `std.json` and `std.fs`.

Future phases will add C dependencies (SQLite, GLFW, FreeType, libharu) compiled from source via `build.zig`, each with a Zig rewrite timeline. See SPEC.md for full dependency analysis.

---

## Module Coverage (Target: ENERCALC SEL 20 Parity)

### Beams
- Steel beam (AISC 360)
- Wood beam (NDS) ← **MVP**
- Concrete beam (ACI 318)
- Masonry beam (TMS 402)
- Composite beam
- Flitch beam
- Ledger bolt group
- Torsional beam

### Columns
- Wood column (NDS) ← **MVP**
- Steel column (AISC 360)
- Concrete column (ACI 318)
- Masonry column (TMS 402)

### Foundations
- Spread footing (ACI 318) ← **MVP**
- Continuous footing
- Pile cap
- Pile design

### Walls
- Masonry wall (TMS 402)
- Retaining wall
- Concrete shear wall
- Wood shear wall (SDPWS)

### Loads & Analysis
- ASCE 7 snow loads
- ASCE 7 wind loads (MWFRS + C&C)
- ASCE 7 seismic (ELF)
- IBC load combinations (ASD + LRFD)
- Simple beam solver
- Multi-span beam solver
- 2D frame analysis
- 3D FEM frame
- Diaphragm design
- Section properties calculator

### Other
- Baseplate design (AISC)
- Anchor bolt design (ACI 318 Chapter 17)
- Steel connection design

---

## Project Format

Projects are stored as **SQLite databases** with a `.zenercalc` extension:

```
project.zenercalc  (SQLite)
├── project_meta       -- name, engineer, code editions, revision history
├── calc_sheets        -- one row per module instance (inputs + cached outputs)
├── load_cases         -- named load cases referenced by modules
├── assets             -- embedded PDFs, images, reference documents (BLOB)
└── audit_log          -- timestamped change history
```

- Single-file project = easy email, version control, backup
- SQLite means any engineer can inspect/query their own project data
- Forward-compatible via schema versioning
- Load/save target: < 50ms for 500-calc projects

---

## Directory Structure

```
zenercalc/
├── build.zig
├── build.zig.zon
├── src/
│   ├── root.zig                  # library root, re-exports engine modules
│   ├── main.zig                  # CLI entry point, JSON-in/JSON-out
│   ├── engine/
│   │   ├── math.zig              # section properties, beam solver (51-point)
│   │   ├── loads.zig             # load types, ASCE 7-22 ASD combinations
│   │   ├── materials/
│   │   │   └── wood.zig          # NDS lumber + glulam comptime tables
│   │   └── codes/
│   │       └── nds2018.zig       # NDS 2018 adjustment factors + design checks
│   └── modules/
│       ├── wood_beam.zig         # Inputs/Outputs/compute() for wood beams
│       └── wood_column.zig       # Inputs/Outputs/compute() for wood columns
├── data/
│   ├── nds_lumber_2018.json      # NDS Table 4A audit trail (5 species x 4 grades)
│   └── nds_glulam_2018.json      # NDS Table 5A/5B audit trail (7 stress classes)
├── tests/
│   └── conformance/
│       └── wood_beam_enercalc.json  # ENERCALC reference fixtures
├── SPEC.md
└── LICENSE (AGPL-3.0)
```

---

## Testing Strategy

Every calculation module ships with:

1. **Unit tests** — individual formula functions against textbook solutions
2. **Code example tests** — published worked examples from ACI, AISC, AWC, ASCE as regression fixtures
3. **Cross-validation** — selected outputs validated against ENERCALC on identical inputs (documented in `tests/modules/`)

```bash
zig build test                    # all tests
zig build test -- --filter engine # engine only
zig build test -- --filter nds    # NDS module tests only
```

---

## Contributing

See `docs/CONTRIBUTING.md`. Short version:

- All formula implementations must cite the exact code provision (`// NDS 2024 Table 4A`)
- New modules require published validation examples as tests before merge
- C interop must have a filed issue tracking the Zig rewrite timeline
- AGPL-3.0 — contributions are open source

---

## Why AGPL?

zenercalc is free, open, and stays that way. AGPL ensures that if a firm or SaaS wraps this in a product, the improvements come back to the community. Engineering software has been locked behind expensive licenses for too long.
