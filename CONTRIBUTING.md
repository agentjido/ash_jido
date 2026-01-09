# Contributing to Ash Jido

Thank you for your interest in contributing to Ash Jido! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Install dependencies: `mix deps.get`
4. Run tests: `mix test`
5. Run quality checks: `mix quality`

## Development Workflow

1. Create a feature branch from `main`
2. Make your changes
3. Add tests for new functionality
4. Ensure all tests pass: `mix test`
5. Run quality checks: `mix quality`
6. Submit a pull request

## Code Style

- Follow the existing code style and patterns
- Use `mix format` to format your code
- Ensure Dialyzer passes: `mix dialyzer`
- Follow Credo guidelines: `mix credo`

## Quality Checks

The `mix quality` command runs the full quality check suite:

- Format verification (`mix format --check-formatted`)
- Compilation with warnings as errors
- Credo static analysis
- Dialyzer type checking

## Testing

- Add tests for all new functionality
- Maintain existing test coverage
- Use property-based testing where appropriate
- Include integration tests for complex features

Check coverage locally:
```bash
mix coveralls.html
```

## Documentation

- Update documentation for any API changes
- Add examples for new features
- Ensure `mix docs` builds without errors

All public APIs must be properly documented:

- **@moduledoc**: All public modules must have module documentation
- **@doc**: All public functions must have function documentation
- **@spec**: All public functions must have type specifications

## Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only changes |
| `style` | Changes that don't affect code meaning |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or correcting tests |
| `chore` | Changes to build process or auxiliary tools |
| `ci` | CI configuration changes |

### Examples

```bash
# Feature
git commit -m "feat(actions): add new Jido action resource"

# Bug fix
git commit -m "fix(extension): resolve action registration"

# Breaking change
git commit -m "feat(api)!: change action schema"
```

## Pull Request Guidelines

- Provide a clear description of the changes
- Use commit messages following conventional commits
- Reference any related issues
- Include tests and documentation updates
- Ensure CI passes

## Questions?

Feel free to open an issue for questions or discussion about potential contributions.
