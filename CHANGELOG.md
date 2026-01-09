# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-09

> ⚠️ **Experimental/Pre-release**: This package is in early development. APIs may change.

### Added

- Ash DSL extension (`AshJido`) for defining Jido actions within Ash resources
- `AshJido.Generator` - Generates `Jido.Action` modules from Ash action definitions
- `AshJido.TypeMapper` - Maps Ash types to Jido schema types
- `AshJido.Mapper` - Handles data transformation between Ash and Jido formats
- Support for action inputs, outputs, and metadata configuration
- Compile-time code generation for Jido actions

[Unreleased]: https://github.com/agentjido/ash_jido/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/agentjido/ash_jido/releases/tag/v0.1.0
