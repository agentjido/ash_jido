# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-09

### Added

- Ash DSL extension (`AshJido`) for defining Jido actions within Ash resources
- `lib/ash_jido/generator.ex` - Generates `Jido.Action` modules from Ash action definitions
- `lib/ash_jido/type_mapper.ex` - Maps Ash types to Jido schema types
- `lib/ash_jido/mapper.ex` - Handles data transformation between Ash and Jido formats
- Support for action inputs, outputs, and metadata configuration
- Compile-time code generation for Jido actions

[Unreleased]: https://github.com/agentjido/ash_jido/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/agentjido/ash_jido/releases/tag/v0.1.0

<!-- changelog -->

## [1.0.1](https://github.com/agentjido/ash_jido/compare/v1.0.1...1.0.1) (2026-08-12)




### Bug Fixes:

* deps: update Jido for release preflight by mikehostetler

* deps: require patched Ash for CVE-2026-67579 by mikehostetler

* deps: update Ash to 3.31.2 (#102) by mikehostetler

* deps: update Mint for CVE-2026-59249 by mikehostetler