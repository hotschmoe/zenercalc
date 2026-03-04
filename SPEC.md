# zenercalc — Technical Specification

**Version:** 0.1-draft
**Date:** March 2026
**Author:** Isaac
**Zig Target:** 0.15.2 (stable), migration to 0.16.0 upon release

---

## 1. Overview

zenercalc is a from-scratch structural engineering calculation suite targeting full parity with ENERCALC SEL 20 (64+ modules). It covers residential and low-rise commercial structural design per current U.S. building codes. The application is a single native binary with a Vulkan-rendered UI, SQLite-backed project files, and PDF report output.

The non-negotiable constraints are:

- Every formula traces to a code provision. No hidden math.
- One statically-linked binary per platform. No runtime dependencies.
- All C dependencies have a filed rewrite timeline except SQLite.
- The Zig build system compiles everything from source. No system libraries except the Vulkan loader.

---

## 2. Zig Version Strategy

### 2.1 Why 0.15.2 (not 0.16.0 nightly)

Zig 0.16.0 introduces a complete overhaul of the I/O subsystem (`std.Io`), filesystem, networking, timers, process management, and the `zig-pkg` local dependency format. As of February 2026, Andrew Kelley described the release cycle as "approaching the end," but the milestone still has open blockers on Codeberg. Key breaking changes include:

- `std.ArrayList` is now unmanaged (allocator passed per-call) — already landed in 0.15.x
- File I/O, readers, and writers have been restructured around `std.Io`
- `main()` signature may change to accept `std.process.Init`
- Randomness, process, and environment APIs moved to `std.Io`
- Package dependencies now stored in `zig-pkg/` directory instead of global cache

zenercalc's core engine (math, FEM, code rules) uses none of these APIs — it's pure computation. The UI layer and project I/O do use filesystem and windowing, but through C interop (GLFW, SQLite, libharu), which is stable across Zig versions. The risk of building on 0.16.0-dev is daily breakage in areas we touch (build system, readers/writers, process spawning for tests).

**Decision:** Build on 0.15.2. Maintain a `zig-0.16` branch that tracks nightly. Migrate main branch within 2 weeks of 0.16.0 stable release.

### 2.2 Build System Notes (0.15.x)

Key 0.15.x patterns for `build.zig`:

- Use `b.addLibrary(.{ .linkage = .static, ... })` — `addStaticLibrary()` no longer exists
- Use `b.createModule(.{ .root_source_file = ... })` with `root_module`
- C source compilation: `exe.addCSourceFile(.{ .file = ..., .flags = ... })`
- Cross-compilation: Zig 0.15.x self-hosted x86_64 backend is default in Debug (5x faster than LLVM)

---

## 3. Dependency Analysis

### 3.1 Vulkan Bindings — vulkan-zig

**Source:** [Snektron/vulkan-zig](https://github.com/Snektron/vulkan-zig) (632 stars, MIT license)
**Strategy:** Fork into `deps/vulkan-zig`

vulkan-zig is a binding *generator* — it reads `vk.xml` and produces idiomatic Zig bindings at build time. It generates dispatch tables, converts Vulkan error codes to Zig error sets, renames fields to Zig conventions, and handles bitfields. It is tested daily against the latest `vk.xml` and Zig nightly.

**Why fork instead of package dependency:**
- We need to pin a specific Vulkan spec version (1.3.x) for reproducible builds
- We may need to patch the generator for zenercalc-specific validation layer integration
- Zig package manager behavior is changing between 0.15 and 0.16

**Rewrite timeline:** None. The generator is pure Zig. The generated output is pure Zig. This is already "native."

### 3.2 Windowing — GLFW 3.4

**Source:** GLFW 3.4 C source, vendored in `deps/glfw/`
**Strategy:** Compile from source via `build.zig`, thin Zig wrapper in `src/ui/window.zig`

GLFW provides window creation, input handling, and Vulkan surface creation across X11, Wayland, and Win32. It is the most battle-tested option for getting a Vulkan triangle on screen quickly.

**Alternatives considered:**
- **zinit / StoryTreeGames**: Pure Zig windowing. Promising but immature — limited Vulkan surface support, small user base.
- **Direct xcb/Wayland/Win32**: This is the Phase 7 endgame (see andrewrk's DAW project for reference: direct Vulkan + libxcb). But writing cross-platform windowing from scratch in Phase 0 is scope creep.
- **mach-glfw (Hexops)**: Zig bindings for GLFW. Tied to Mach engine versioning; we'd rather own the C compilation ourselves.

**Integration pattern:**
```
build.zig compiles GLFW from source → links statically
src/ui/window.zig wraps GLFW via @cImport
src/ui/window.zig exposes platform-agnostic Window struct
Phase 7: window.zig reimplemented against xcb/Wayland/Win32 directly
```

**Rewrite timeline:** Phase 7 (Week 41+). The `window.zig` abstraction layer is designed so the GLFW backend can be swapped without touching any UI widget code.

### 3.3 Font Rasterization — FreeType 2

**Source:** FreeType 2.14.x C source, vendored in `deps/freetype/`
**Strategy:** Compile from source via `build.zig`. Use for SDF glyph atlas generation only.

FreeType is used exclusively for offline glyph rasterization at startup: load a monospace font (and optionally a proportional font), rasterize each glyph to a signed distance field, pack into a GPU texture atlas. At runtime, all text rendering is a Vulkan quad draw — FreeType is not called per-frame.

**Zig build integration:** Use [mitchellh/zig-build-freetype](https://github.com/mitchellh/zig-build-freetype) as a reference for the `build.zig` setup, or vendor directly. The hexops fork strips unnecessary files and provides a clean `build.zig`.

**Rewrite target:** [andrewrk/TrueType](https://codeberg.org/andrewrk/TrueType/) — a pure Zig port of stb_truetype, actively maintained by Andrew Kelley himself (last updated January 2026). It supports TrueType parsing, glyph bitmap rendering, and scaling. It does not yet support font shaping or ligatures, but for an engineering UI with primarily ASCII numeric content, this is sufficient. The rewrite replaces FreeType's glyph bitmap output with TrueType's, then feeds into our existing SDF atlas generator.

**Rewrite timeline:** Phase 4 end (Week 24). By this point the SDF atlas pipeline is stable and the swap is a backend change.

### 3.4 PDF Generation — libharu 2.4.5

**Source:** libharu 2.4.5 C source (March 2025), vendored in `deps/libharu/`
**License:** zlib/libpng (permissive)

libharu is a write-only PDF library: lines, text, images, annotations, outlines, TrueType embedding, encryption. It is ANSI C, compiles everywhere, and has no dependencies except optionally zlib and libpng (which we can skip since we embed our own images as raw RGBA).

**Why libharu over alternatives:**
- **pdf-nano** (pure Zig): Too minimal — no TrueType embedding, no vector graphics, no page layout control. Fine for receipts, not for engineering calc sheets with diagrams and formula traces.
- **Raw PDF stream writing**: This is the Phase 5 rewrite target. PDF is a well-documented format and a streaming writer for our specific output (text, lines, rectangles, embedded images) is ~2-3K lines of Zig. libharu gets us to working PDF output in Phase 2 without that upfront investment.

**Rewrite timeline:** Phase 5 (Weeks 25–28). The replacement is a purpose-built Zig PDF stream writer that handles exactly zenercalc's output needs: title blocks, formula traces, moment/shear diagrams as vector graphics, and page layout. No general-purpose PDF library needed.

### 3.5 Database — SQLite Amalgamation

**Source:** sqlite3.c + sqlite3.h amalgamation (~200KB), vendored in `deps/sqlite/`
**License:** Public domain

SQLite is the permanent C dependency. The amalgamation is a single C file that compiles in seconds via `zig cc`. A Zig rewrite of SQLite would be tens of thousands of lines for no functional benefit — the amalgamation is one of the most tested codebases on earth.

**Zig wrapper:** Fork [karlseguin/zqlite.zig](https://github.com/karlseguin/zqlite.zig) into `deps/zqlite/`. zqlite provides an idiomatic Zig API: connection pooling, prepared statements, row iteration, type-safe binding. It compiles the amalgamation from source with configurable flags:

```zig
// Recommended SQLite compile flags for zenercalc
"-DSQLITE_DQS=0",
"-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
"-DSQLITE_THREADSAFE=0",          // single-threaded access in zenercalc
"-DSQLITE_TEMP_STORE=3",          // temp tables in memory
"-DSQLITE_ENABLE_API_ARMOR=1",
"-DSQLITE_OMIT_DEPRECATED=1",
"-DSQLITE_OMIT_SHARED_CACHE=1",
"-DSQLITE_DEFAULT_MEMSTATUS=0",
"-DSQLITE_LIKE_DOESNT_MATCH_BLOBS=1",
```

**Alternative considered:** [nDimensional/zig-sqlite](https://zigistry.dev/programs/github/nDimensional/zig-sqlite/) — newer, lower-level, comptime type checking on queries. Worth evaluating if zqlite proves too opinionated.

**Rewrite timeline:** Never. This is an intentional permanent dependency.

### 3.6 Math / FEM — Pure Zig (no external dependency)

The math engine is written from scratch in pure Zig. For residential structural engineering, frame models are small:

- A typical residential project has < 200 members, < 500 nodes → < 3000 DOF
- Even a large low-rise commercial project rarely exceeds 5000 DOF
- At this scale, a direct solver (LDL^T decomposition) with skyline/banded storage is faster and simpler than iterative methods

**Implementation plan:**

| Component | Storage | Algorithm | Notes |
|---|---|---|---|
| Simple beam solver | Dense (small matrices) | Direct Gaussian | Point loads, UDL, trapezoidal, reactions, V/M/Δ |
| Multi-span beam solver | Banded | Three-moment equation or stiffness method | Continuous beams |
| 2D frame analysis | Skyline | LDL^T factorization | Direct stiffness method |
| 3D FEM frame | CSR sparse | LDL^T with bandwidth minimization (Cuthill-McKee) | Direct stiffness, sparse LU fallback |
| Section properties | Dense | Green's theorem for arbitrary cross-sections | I, S, A, r, Cw for built-up sections |

**Reference:** Tim Davis, *Direct Methods for Sparse Linear Systems* (2006) — CSparse algorithm implemented in pure Zig. For our problem sizes, the "simple" path (no METIS partitioning, no supernodal factorization) is sufficient and keeps the code auditable.

---

## 4. Architecture

### 4.1 Module System

Each calculation module (e.g. `wood_beam.zig`) is a self-contained unit:

```zig
pub const WoodBeam = struct {
    // Inputs — serialized to/from SQLite
    inputs: Inputs,
    // Outputs — cached, recomputed on input change
    outputs: Outputs,
    // Code edition — determines which provision set to use
    code_edition: CodeEdition,

    pub const Inputs = struct {
        species: wood.Species,
        grade: wood.Grade,
        nominal_size: wood.NominalSize,
        span_ft: f64,
        // ... load cases, support conditions, etc.
    };

    pub const Outputs = struct {
        fb_adj: f64,       // adjusted bending stress
        fv_adj: f64,       // adjusted shear stress
        moment_max: f64,   // maximum moment
        shear_max: f64,    // maximum shear
        deflection_max: f64,
        dcr_bending: f64,  // demand-capacity ratio
        dcr_shear: f64,
        dcr_deflection: f64,
        status: CalcStatus, // .pass, .fail, .warning
        // ... diagrams as point arrays
    };

    pub fn compute(self: *WoodBeam) !void {
        // Every line references a code section:
        // Fb' = Fb × CD × CM × Ct × CL × CF × Ci × Cr
        // NDS 2024 §4.3.1
        self.outputs.fb_adj = self.inputs.fb_reference
            * nds2024.cd(self.inputs.load_duration)   // NDS Table 2.3.2
            * nds2024.cm(self.inputs.moisture)         // NDS Table 4A footnote 1
            * nds2024.ct(self.inputs.temperature)      // NDS §2.3.3
            * nds2024.cl(...)                          // NDS §3.3.3
            * nds2024.cf(...)                          // NDS Table 4A
            * nds2024.ci(...)                          // NDS §4.3.8
            * nds2024.cr(...);                         // NDS §4.3.9
        // ...
    }
};
```

### 4.2 Code Rule Engine

Code provisions are organized by standard and edition:

```
src/engine/codes/
├── nds2024.zig       # NDS 2024 — adjustment factors, capacity checks
├── nds2018.zig       # NDS 2018 — for legacy project support
├── aci318.zig        # ACI 318-19
├── aisc360.zig       # AISC 360-22
├── asce7.zig         # ASCE 7-22
├── sdpws.zig         # SDPWS 2021
├── tms402.zig        # TMS 402-22
└── ibc2024.zig       # IBC 2024 load combinations, overrides
```

Each file exposes pure functions that take design parameters and return code-compliant results. Every function has a doc comment citing the exact code section. Edition selection is a comptime or runtime switch — modules call `codes.nds.cd()` and the project's selected edition dispatches to the correct implementation.

### 4.3 UI Architecture

The UI is an immediate-mode GPU renderer built on Vulkan:

```
Frame loop:
1. Poll GLFW events (keyboard, mouse, window resize)
2. Walk the widget tree, collect draw commands
3. Submit Vulkan command buffer (instanced quads for table cells,
   SDF text atlas for all glyphs, line primitives for diagrams)
4. Present swapchain image
```

Key design decisions:
- **Instanced quad rendering** for table cells — a single draw call renders the entire input/output table
- **SDF text atlas** — signed distance field glyphs scale cleanly at any DPI and render with a single texture sample per glyph
- **Print-accurate scaling** — the on-screen layout matches the PDF output at 1:1 (72 DPI reference, scaled to monitor DPI)
- **Keyboard-first** — Tab/Enter navigation between input fields, immediate recomputation on value change

### 4.4 Project I/O

```
User action → Module.compute() → update calc_sheets row → trigger dependent recalc
File > Save → serialize all calc_sheets to SQLite → flush WAL → < 50ms for 500 calcs
File > Open → read project_meta → lazy-load calc_sheets on navigation
File > Export PDF → iterate modules → render each to PDF pages via report.zig
```

---

## 5. Material Databases

Material properties are stored as JSON source files in `data/` and baked into the binary at comptime via `@embedFile` + `std.json.parseFromSlice`:

| Database | Source | Contents |
|---|---|---|
| `aisc_shapes.json` | AISC Shapes Database v16.0 | W, S, C, L, HSS, Pipe — A, d, bf, tf, tw, Ix, Iy, Sx, Sy, Zx, Zy, rx, ry, J, Cw |
| `nds_lumber.json` | NDS 2024 Supplement Table 4A | Species-grade combinations, Fb, Ft, Fv, Fc⊥, Fc, E, Emin |
| `nds_glulam.json` | NDS 2024 Supplement Table 5A-5D | Glulam combination symbols, layup properties |
| `aci_rebar.json` | ACI 318-19 | Bar sizes #3–#18, areas, diameters, weights |
| `tms_cmu.json` | TMS 402-22 | CMU unit strengths, f'm by mortar type |

Comptime baking means:
- Zero runtime file I/O for material lookup
- Binary size increase is minimal (AISC shapes ≈ 500KB JSON → ~200KB in binary)
- Type safety — the Zig compiler catches missing fields at build time

---

## 6. Roadmap

### Phase 0 — Bootstrap (Week 1)

- `build.zig` with all four cross-compilation targets
- GLFW compiled from source, Vulkan triangle on Linux and Windows
- vulkan-zig fork vendored and generating bindings
- FreeType, libharu, SQLite amalgamation compiling from source via `build.zig`
- zqlite fork integrated, basic open/create/query test passing
- CI: build matrix across all four targets on push (GitHub Actions or Forgejo/Woodpecker)

**Exit criteria:** `zig build -Dtarget=aarch64-windows-gnu` produces a binary that opens a Vulkan window on the target platform.

### Phase 1 — Math Core (Weeks 2–4)

- Section properties calculator (I, S, A, r — rectangular and standard shapes)
- Simple beam solver: point loads, uniform + trapezoidal distributed loads, reactions, V/M/Δ
- IBC 2024 load combination generator (ASD + LRFD, all 16 basic combos)
- NDS 2024 adjustment factor engine (CD, CM, Ct, CL, CF, Ci, Cr, Cfu, CT)
- AISC shape database baked at comptime from JSON
- NDS lumber + glulam databases baked at comptime from JSON
- Unit test suite: all formulas validated against published NDS/AISC code examples

**Exit criteria:** `zig build test` passes with >95% formula coverage against hand calculations.

### Phase 2 — MVP Modules (Weeks 5–8)

Three modules, fully working end-to-end with UI and PDF output:

**Wood Beam (NDS 2024)**
- Species/grade selector from baked NDS database
- Simple + multi-span configurations
- Full NDS adjustment factor chain
- Bending, shear, bearing, deflection checks per NDS §3.3–3.4
- V/M/Δ diagrams rendered in UI and PDF

**Wood Column (NDS 2024)**
- Sawn + glulam + LVL
- Biaxial bending + axial interaction per NDS §3.9
- Cp column stability factor per NDS §3.7
- Combined loading interaction equation

**Spread Footing (ACI 318-19)**
- Square, rectangular, circular geometry
- Soil bearing pressure (uniform + eccentric load)
- One-way shear per ACI §22.5
- Two-way (punching) shear per ACI §22.6
- Flexural steel design per ACI §7.6
- Overturning and sliding stability checks

**Exit criteria:** An engineer can open zenercalc, design a wood beam, column, and footing for a real residential project, and generate a stampable PDF calc package.

### Phase 3 — Vulkan UI Framework (Weeks 9–12)

- SDF glyph atlas generation via FreeType (monospace + proportional)
- Immediate-mode GPU widgets: table, numeric input, dropdown, toggle, checkbox
- Calc sheet layout engine: input panel left, output/diagram right
- Project navigator: sidebar with module tree, add/remove/reorder
- Print-accurate scaling (what you see = what the PDF outputs)
- Theme: high contrast, engineering monospace, ENERCALC-familiar density
- Keyboard navigation: Tab between fields, Enter to confirm, Esc to revert

**Exit criteria:** All three MVP modules render in the Vulkan UI with keyboard-driven input and live recomputation.

### Phase 4 — Expanded Module Coverage (Weeks 13–24)

Priority order based on residential SE workflow frequency:

1. Steel beam (AISC 360-22) — W-shape selection, Mn, Vn, Δ, Lb checks
2. Steel column (AISC 360-22) — W-shape, KL/r, Pn, combined loading
3. Continuous footing (ACI 318-19) — strip footing under bearing wall
4. Wood shear wall (SDPWS 2021) — unit shear, aspect ratio, hold-down forces
5. Retaining wall — cantilever, active pressure, sliding/overturning/bearing
6. ASCE 7 snow loads — ground snow, flat/sloped roof, drift, unbalanced
7. ASCE 7 wind loads (MWFRS) — Directional Procedure Ch. 27
8. Multi-span beam solver — 3+ span continuous beams, moment distribution
9. Concrete beam (ACI 318-19) — rectangular, singly/doubly reinforced
10. Masonry wall (TMS 402-22) — reinforced, out-of-plane, in-plane
11. Pile cap / pile design — ACI 318 strut-and-tie, group effects
12. Anchor bolt (ACI 318-19 Ch. 17) — tension, shear, combined, breakout
13. Baseplate (AISC DG1) — bearing, anchor bolt tension/shear
14. ASCE 7 seismic (ELF) — Cs, V, Fx vertical distribution
15. 2D frame analysis — direct stiffness method, portal/cantilever approximations

**Also in Phase 4:**
- Rewrite FreeType SDF generator → pure Zig using andrewrk/TrueType fork
- File FreeType removal from build graph

**Exit criteria:** 18+ modules working. FreeType C dependency eliminated.

### Phase 5 — PDF + Project Format (Weeks 25–28)

- Full PDF report generator: title block, engineer stamp block, revision history
- Per-module calc sheet: inputs table, formula trace with code citations, results, diagrams
- Project-wide PDF: table of contents, sequential page numbering, all selected modules
- Vector moment/shear/deflection diagrams embedded in PDF (line primitives, not bitmaps)
- Rewrite libharu bridge → pure Zig PDF stream writer (text, lines, rectangles, embedded fonts)
- SQLite project schema finalized + forward-compatible migration system
- Import/export: `.zenercalc` ↔ CSV input dump for batch verification

**Exit criteria:** libharu C dependency eliminated. PDF output matches on-screen layout pixel-for-pixel.

### Phase 6 — FEM + Advanced Modules (Weeks 29–40)

- 3D FEM frame solver (direct stiffness, CSR sparse, LDL^T with Cuthill-McKee ordering)
- Diaphragm design (flexible + rigid, chord forces, collector design)
- Seismic force distribution to shear walls
- Wind pressure (C&C) for component design
- Composite beam (formed steel deck + concrete topping, AISC 360 Chapter I)
- Flitch beam (wood + steel laminate)
- Section properties for arbitrary built-up sections (Green's theorem on polygon vertices)
- Torsional beam analysis

**Exit criteria:** Full ENERCALC SEL 20 module parity achieved.

### Phase 7 — Native Windowing + Polish (Week 41+)

- Replace GLFW with pure Zig platform windowing:
  - Linux: xcb (X11) + libwayland-client (Wayland) — runtime detection
  - Windows: Win32 API via Zig's `@cImport` of windows.h
- Revision history UI + engineer stamp workflow (PE seal placement in PDF)
- Material property editor (custom species, custom steel grades)
- Project templates (residential starter, commercial starter)
- v1.0 release with documentation and example projects

**Exit criteria:** Zero C dependencies except SQLite amalgamation. GLFW removed from build graph.

### Future Roadmap (Post v1.0)

- **AI layer:** Local LLM (ONNX Runtime or llama.cpp) for natural language calc input, result narration, and member size optimization. NPU-accelerated on Snapdragon X and Ryzen AI.
- Additional code editions (IBC 2021, ASCE 7-16, NDS 2018 for legacy support)
- TMS masonry full module coverage
- Cold-formed steel (AISI S100)
- Plugin API for community modules (WASM sandboxed?)
- Headless / batch mode for CI-driven calc verification
- Cloud sync via CRDTs on the SQLite project file (optional, self-hostable)

---

## 7. Dependency Rewrite Tracker

| Dependency | Language | Introduced | Rewrite Phase | Rewrite To | Status |
|---|---|---|---|---|---|
| vulkan-zig | Zig (generator) | Phase 0 | — | Already Zig | ✅ Native |
| GLFW | C | Phase 0 | Phase 7 | Pure Zig xcb/Wayland/Win32 | 🔲 Planned |
| FreeType 2 | C | Phase 0 | Phase 4 | andrewrk/TrueType (pure Zig) | 🔲 Planned |
| libharu | C | Phase 0 | Phase 5 | Pure Zig PDF stream writer | 🔲 Planned |
| SQLite 3 | C | Phase 0 | — | Keep permanently | ✅ Permanent |
| zqlite | Zig (wrapper) | Phase 0 | — | Already Zig | ✅ Native |

---

## 8. Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| Zig 0.16.0 lands mid-development with massive breakage | High | Core engine is pure computation — no std.Io dependency. UI/IO layer is behind C interop. Migration branch tracks nightly. |
| andrewrk/TrueType lacks SDF generation | Medium | We only need glyph bitmaps — our SDF pipeline converts bitmaps to distance fields on the GPU. TrueType's bitmap output is sufficient. |
| GLFW Vulkan surface creation quirks on Wayland | Low | GLFW 3.4 prefers Wayland when available. Fallback to X11 via `GLFW_PLATFORM` hint. Phase 7 native windowing eliminates this entirely. |
| AISC shapes JSON accuracy | Medium | Cross-reference against AISC Shapes Database v16.0 published values. Comptime baking catches structural errors at build time. |
| Module count scope creep | High | MVP is 3 modules. Phase 4 priority order is based on residential workflow frequency. Parity is a target, not a v1.0 blocker. |
| PDF output fidelity (libharu → Zig rewrite) | Medium | libharu is well-understood. The Zig rewrite targets only zenercalc's specific output patterns, not a general-purpose PDF library. |
| SQLite schema migration across versions | Low | Schema version table + migration functions. SQLite's ALTER TABLE and forward-compatible column additions. |

---

## 9. Validation and Certification

zenercalc is not a certified product. It is a tool that assists licensed engineers in performing calculations. The engineer of record is responsible for verifying all output.

That said, zenercalc's testing strategy is designed to build confidence:

- Every formula function has a unit test citing its code provision
- Every module has integration tests using published worked examples from code commentaries (ACI SP-17, AISC Design Examples, AWC DES)
- Cross-validation against ENERCALC output on identical inputs is documented
- All test data and expected results are committed to the repository

The AGPL license ensures that any modifications to the calculation logic are publicly auditable.
