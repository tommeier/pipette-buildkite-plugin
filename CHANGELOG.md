# Changelog

All notable changes to this project will be documented in this file.

## [0.5.1](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.5.0...v0.5.1) — 2026-04-09

### Fixed

- `ignore_global_scope` now shields groups from `activates: :all` scope propagation, not just
  branch-level `scopes: :all`. Previously, a scope like `root_config` with `activates: :all` would
  bypass `ignore_global: true` and activate excluded groups on every build.

## [0.5.0](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.4.7...v0.5.0) — 2026-04-07

### Added

- Step-level `only:` branch filtering — restrict individual steps to specific branches
- `ignore_global` option to scope pipette within groups (#1)

## [0.4.7](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.4.6...v0.4.7) — 2026-04-01

### Fixed

- Fix Spark duplicate `Branch` warning

### Documentation

- Document `Pipette.Constructors` in dynamic groups guide
- Add single-file pattern to production example

## [0.4.6](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.4.5...v0.4.6) — 2026-04-01

### Changed

- Harden atom conversions throughout the pipeline
- Add integration test for explicit group key dependencies

## [0.4.5](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.4.4...v0.4.5) — 2026-04-01

### Fixed

- Keep group/trigger `depends_on` as atoms internally, resolve to string keys at YAML output time

## [0.4.4](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.4.3...v0.4.4) — 2026-04-01

### Fixed

- Fix group `depends_on` resolution when group has an explicit key

## [0.4.3](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.4.2...v0.4.3) — 2026-04-01

### Changed

- Enable `Spark.Formatter` plugin for consistent DSL formatting

## [0.4.2](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.4.1...v0.4.2) — 2026-03-31

### Added

- `Pipette.Constructors` module for runtime struct building (useful for dynamic group generation)

## [0.4.1](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.4.0...v0.4.1) — 2026-03-31

### Fixed

- Fix step `depends_on` resolution when step has an explicit key

### Changed

- Validate that `concurrency_group` requires `concurrency` to be set
- Remove noisy step defaults from YAML output

## [0.4.0](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.3.0...v0.4.0) — 2026-03-31

### Added

- **Spark DSL** — compile-time pipeline definitions with validation, replacing the runtime DSL
- `Pipette.Info` accessor module for querying compiled pipeline metadata
- Compile-time verifiers: scope reference validation, cycle detection, step label uniqueness
- `GenerateKeys` transformer with full `depends_on` resolution
- Support for plugin-only steps (command is now optional)

### Changed

- Replaced runtime `validate!/1` and `generate_keys/1` with compile-time Spark transformers
- Updated all tests to use Spark DSL

## [0.3.0](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.2.0...v0.3.0) — 2026-03-30

### Changed

- Rename `Pipette.DSL.pipeline/1` to `Pipette.DSL.build_pipeline/1` for clarity

## [0.2.0](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.1.1...v0.2.0) — 2026-03-30

### Added

- `Pipette.DSL` module — optional constructor functions for cleaner pipeline definitions
- Production example guide with realistic 5-group monorepo pipeline
- Updated all guides to use DSL syntax

## [0.1.1](https://github.com/tommeier/pipette-buildkite-plugin/compare/v0.1.0...v0.1.1) — 2026-03-30

### Fixed

- Fix `Pipette.upload/1` — use temp file instead of `System.cmd/3` `:input` option
- Fix plugin reference to use short ID (`tommeier/pipette`)

### Added

- BATS tests, plugin linter, and shellcheck in CI

## [0.1.0](https://github.com/tommeier/pipette-buildkite-plugin/releases/tag/v0.1.0) — 2026-03-30

Initial release of Pipette — declarative Buildkite pipeline generation for monorepos.

### Added

- Scope-based change detection
- Branch policies
- Commit message targeting (`[ci:api/test]` syntax)
- `CI_TARGET` env var for manual targeting
- Dependency graph with cycle detection
- Force activation via env vars
- Dynamic group generation (`extra_groups` callback)
- Buildkite YAML serialization
- Runtime pipeline validation
