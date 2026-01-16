# Ralph Guardrails (Signs)

> Lessons learned from past failures. READ THESE BEFORE ACTING.

## Core Signs

### Sign: Read Before Writing
- **Trigger**: Before modifying any file
- **Instruction**: Always read the existing file first
- **Added after**: Core principle

### Sign: Test After Changes
- **Trigger**: After any code change
- **Instruction**: Run tests to verify nothing broke
- **Added after**: Core principle

### Sign: Commit Checkpoints
- **Trigger**: Before risky changes
- **Instruction**: Commit current working state first
- **Added after**: Core principle

---

## Learned Signs

### Sign: Avoid committing into submodules
- **Trigger**: When trying to add files to a git submodule from the superproject
- **Instruction**: Do not write or commit files into a submodule from the superproject; either update the submodule repo or copy runtime config into the container for CI tests
- **Added after**: Observed CI fix attempt where `.gitignore` prevented adding `config.yaml` to the dashboard submodule

(Signs added from observed failures will appear below)

