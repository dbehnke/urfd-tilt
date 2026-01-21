# Production Deployment Plan - Outstanding Questions & Answers

**Date**: 2026-01-20

## Questions & Answers

### 1. Default Instance Location
**Question**: Confirm `/opt/urfd-production/instances/` is the default, overridable via `URFD_INSTANCES_DIR` environment variable?

**Answer**: YES - Use `/opt/urfd-production/instances/` as default, allow override via `URFD_INSTANCES_DIR`

---

### 2. Template Variable Format
**Question**: Should we use `${VARIABLE}` or `{{VARIABLE}}` for substitution?

**Answer**: Use `${VARIABLE}` format - bash-compatible, works with envsubst, familiar to users

---

### 3. Config Template Iteration
**Question**: For the config templates, approach?

**Answer**: 
- Create initial version with ~20 core fields per config
- Add TODO comments where additional fields should be added later
- Include link/reference to full source config examples
- Iterate and expand in future PRs

---

### 4. Systemd Service User
**Question**: Should the systemd service run as root, specific user, or current user?

**Answer**: Run as **root** (typical for docker-compose, simplest approach)

---

### 5. Image Build Caching
**Question**: Should `build-images.sh` use Docker BuildKit and caching strategies?

**Answer**: Keep it **simple for now** - standard docker build commands, can optimize later

---

### 6. Deployment Backup
**Question**: Should `deploy-instance.sh` backup existing instance or fail?

**Answer**: **FAIL if instance already exists** - prevents accidental overwrites. User must manually remove instance first. Add `--force` flag for override if needed later.

---

### 7. Image Versions Tracking
**Question**: Should `.image-versions` be git-tracked or git-ignored?

**Answer**: **Git-ignored** - it's machine-specific build history, not source code

---

## Implementation Approach

Based on answers above:

1. **Start with Phase 1** (Build System)
2. **Test thoroughly** before proceeding to next phase
3. **Iterate on config templates** - start minimal, expand over time
4. **Simple is better** - optimize later if needed
5. **Safety first** - fail on conflicts, require explicit overrides

---

## Ready for Implementation

All questions answered. Proceeding with implementation in order:

- [x] Phase 1: Foundation & Build System
- [ ] Phase 2: Templates
- [ ] Phase 3: Deployment Scripts
- [ ] Phase 4: Management Tools
- [ ] Phase 5: Documentation
- [ ] Phase 6: Repository Configuration
