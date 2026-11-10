# Lidglow – Claude Code guidelines

## Git workflow

- **Never push directly to `main`** unless the project owner explicitly says so for that specific change.
- **Every task gets its own new branch** named `christhisway/<task-name>` (short, kebab-case, e.g. `christhisway/fix-login-crash`).
- Branch from the latest `main`, commit the work there, and push that branch. The project owner reviews and merges into `main` themselves.
- Don't merge into `main` yourself and don't open a pull request unless asked.
