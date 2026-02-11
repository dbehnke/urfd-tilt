This directory contains helper notes and commands to perform a local dry-run of GitHub Actions workflows using act (nektos/act).

Usage:

1. Install act (https://github.com/nektos/act)
2. Run a syntax-only check:

   act -j build-packages --secret GITHUB_TOKEN=xxx --container-architecture linux/amd64 --reuse

Notes:
- Local runs with act will not execute the full QEMU multi-arch build, but they will validate workflow syntax and step shell commands.
- Use a disposable token or skip steps that upload artifacts when testing locally.
