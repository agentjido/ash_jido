# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Reactive bridge for Ash notifications to `Jido.Signal` publications
- `AshJido.Notifier` for publishing resource lifecycle events to `Jido.Signal.Bus`
- `publish` and `publish_all` DSL entities in the `jido` section
- `signal_bus` and `signal_prefix` DSL options for publication configuration
- `AshJido.SignalFactory` for pure notification-to-signal transformation
- `AshJido.Info` introspection helpers for signal bridge configuration

### Changed

- Added `AshJido.Resource.Transformers.CompilePublications` to compile and validate publication configs

## [0.1.0] - 2026-01-09

### Added

- Ash DSL extension (`AshJido`) for defining Jido actions within Ash resources
- `AshJido.Generator` - Generates `Jido.Action` modules from Ash action definitions
- `AshJido.TypeMapper` - Maps Ash types to Jido schema types
- `AshJido.Mapper` - Handles data transformation between Ash and Jido formats
- Support for action inputs, outputs, and metadata configuration
- Compile-time code generation for Jido actions

[Unreleased]: https://github.com/agentjido/ash_jido/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/agentjido/ash_jido/releases/tag/v0.1.0
