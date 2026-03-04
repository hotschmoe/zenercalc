# zenercalc

Open-source structural engineering calculation suite for residential and low-rise construction. Full-coverage replacement for ENERCALC SEL 20: 64+ modules spanning beams, columns, foundations, walls, diaphragms, 3D FEM frames, and code compliance per IBC 2024 / ASCE 7-22 / ACI 318-19 / AISC 360-22 / NDS 2024 / SDPWS 2021.

Built from scratch in Zig. Native Vulkan UI. Zero bloat. Every formula cites its code section. All calculation logic is auditable and testable.

**License:** AGPL-3.0

---

## Philosophy

- **Auditable by design.** Every calculation step traces to a specific code provision. No black box. Engineers can trust what they stamp.
- **Dependency sovereignty.** External C libraries are permitted short-term with a mandatory Zig rewrite timeline. Nothing stays a permanent foreign dependency unless the rewrite ROI is negligible (e.g. SQLite amalgamation at ~200KB).
- **One binary per target.** No installer, no runtime, no DLLs. Cross-compile from any host.
- **Engineering clarity over aesthetics.** The UI is optimized for numeric input density, printable precision, and keyboard-first workflows.

---

## Zig Version

**Target: Zig 0.15.2** (latest stable, released October 2025)

Zig 0.16.0 is in late development with massive breaking changes to `std.Io`, filesystem, networking, and process APIs. The new async I/O primitives and `zig-pkg` local dependency storage are compelling, but the API is still churning. zenercalc will target 0.15.2 for initial development with a migration branch tracking 0.16.0 nightly. Migration to 0.16.0 stable will occur within one release cycle of its ship date.

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
zig build -Doptimize=ReleaseFast

# Cross-compile
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-linux-gnu
zig build -Dtarget=x86_64-windows-gnu
zig build -Dtarget=aarch64-windows-gnu
```

No system Vulkan SDK required at runtime. Validation layers available via compile flag:

```bash
zig build -Dvulkan-validation=true
```

---

## Code Editions (Default)

| Standard | Edition |
|---|---|
| IBC | 2024 |
| ASCE 7 | 22 |
| ACI 318 | 19 |
| AISC 360 | 22 |
| NDS / SDPWS | 2024 / 2021 |
| TMS 402/602 | 2022 |

Code year is configurable per-project. The rule engine applies the correct edition's provisions at runtime.

---

## Dependencies

All C dependencies compile from source via `build.zig`. No system libraries linked except the Vulkan loader (dynamically loaded at runtime).

### Zig Dependencies (owned via fork)

| Library | Use | Source | License |
|---|---|---|---|
| vulkan-zig | Vulkan binding generator | Fork of [Snektron/vulkan-zig](https://github.com/Snektron/vulkan-zig) | MIT |

### C Dependencies (compiled from source, rewrite scheduled)

| Library | Use | Version | Rewrite Target | Notes |
|---|---|---|---|---|
| GLFW | Window creation, input, Vulkan surface | 3.4 | Phase 7 (pure xcb/Wayland/Win32) | Temporary — provides cross-platform windowing until native Zig windowing is built. Battle-tested Vulkan surface creation. |
| FreeType 2 | Font rasterization (SDF atlas generation) | 2.14+ | Phase 4 (fork andrewrk/TrueType) | andrewrk's pure-Zig TrueType renderer (stb_truetype port) is the rewrite target. |
| libharu | PDF generation | 2.4.5 | Phase 5 (pure Zig PDF stream writer) | ANSI C, zlib license, ~200KB. Write-only PDF — sufficient for calc sheet output. |
| SQLite 3 | Project database | Amalgamation | **Keep permanently** | ~200KB single-file C. Rewrite ROI is negative — SQLite is battle-tested, public domain, and the amalgamation compiles cleanly via `zig cc`. |

### Zig Wrapper (thin, over SQLite amalgamation)

| Library | Use | Source |
|---|---|---|
| zqlite.zig | Idiomatic Zig SQLite API | Fork of [karlseguin/zqlite.zig](https://github.com/karlseguin/zqlite.zig) |

### No External Dependency (pure Zig from day one)

| Component | Notes |
|---|---|
| Math engine | Beam theory, section properties, matrix ops — all pure Zig. |
| FEM solver | Direct stiffness method, banded/skyline LDL^T. Residential frames are small (<1000 DOF); no need for PETSc/MUMPS. Sparse solver based on CSR/skyline storage. |
| Code rule engine | NDS, ACI, AISC, ASCE 7, IBC provision logic — all pure Zig with comptime code tables. |
| Material databases | AISC shapes, NDS lumber/glulam, ACI rebar, TMS CMU — JSON baked at comptime. |

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
│   ├── main.zig
│   ├── engine/
│   │   ├── math.zig              # beam theory, section props, matrix ops
│   │   ├── fem.zig               # direct stiffness, skyline LDL^T solver
│   │   ├── loads.zig             # ASCE 7 load generation, IBC combinations
│   │   ├── materials/
│   │   │   ├── steel.zig         # AISC shape database (comptime baked)
│   │   │   ├── wood.zig          # NDS sawn lumber, glulam, LVL tables
│   │   │   ├── concrete.zig      # ACI rebar sizes, mix properties
│   │   │   └── masonry.zig       # TMS CMU properties
│   │   └── codes/
│   │       ├── aci318.zig        # ACI 318-19 compliance rules
│   │       ├── aisc360.zig       # AISC 360-22 compliance rules
│   │       ├── nds2024.zig       # NDS 2024 adjustment factors, checks
│   │       ├── sdpws.zig         # SDPWS 2021 shear wall tables
│   │       ├── asce7.zig         # ASCE 7-22 load provisions
│   │       └── ibc2024.zig       # IBC 2024 load combos, overrides
│   ├── ui/
│   │   ├── vulkan.zig            # renderer, swapchain, command buffers
│   │   ├── text.zig              # SDF atlas, glyph layout, FreeType bridge
│   │   ├── window.zig            # GLFW bridge (Phase 0–6), native (Phase 7)
│   │   ├── widgets/
│   │   │   ├── table.zig         # instanced quad table renderer
│   │   │   ├── input.zig         # numeric + text inputs
│   │   │   ├── diagram.zig       # moment/shear/deflection plots
│   │   │   └── calcsheet.zig     # per-module calc sheet layout
│   │   └── theme.zig             # metrics, colors, print-accurate scaling
│   ├── modules/                  # one file per calc module
│   │   ├── wood_beam.zig         # MVP
│   │   ├── wood_column.zig       # MVP
│   │   ├── spread_footing.zig    # MVP
│   │   ├── steel_beam.zig
│   │   ├── steel_column.zig
│   │   └── ...                   # 64 total at parity
│   ├── project/
│   │   ├── db.zig                # zqlite wrapper (thin Zig over amalgamation)
│   │   ├── schema.zig            # table definitions, migrations
│   │   └── io.zig                # load/save, import/export
│   ├── pdf/
│   │   └── report.zig            # libharu bridge → pure Zig in Phase 5
│   └── ai/                       # stubbed, not implemented in v1
│       └── README.md
├── deps/
│   ├── vulkan-zig/               # forked, Zig package
│   ├── glfw/                     # vendored C source, compiled via build.zig
│   ├── freetype/                 # vendored C source
│   ├── sqlite/                   # amalgamation (sqlite3.c + sqlite3.h)
│   ├── zqlite/                   # forked Zig SQLite wrapper
│   └── libharu/                  # vendored C source
├── data/
│   ├── aisc_shapes.json          # AISC shape database → comptime baked
│   ├── nds_lumber.json           # NDS sawn lumber properties
│   └── nds_glulam.json           # Glulam combination symbols
├── tests/
│   ├── engine/                   # unit tests against known solutions
│   ├── modules/                  # per-module validation against hand calcs
│   └── codes/                    # code provision regression tests
├── docs/
│   ├── SPEC.md                   # detailed specification
│   └── CONTRIBUTING.md
├── examples/
│   └── residential_sample.zenercalc
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
