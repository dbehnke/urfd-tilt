# AGENTS.md

This file provides essential information for agentic coding tools working in this repository.

## Project Structure

Monorepo with multiple services:
- `src/allstar-nexus/` - AllStar Nexus (Go backend + Vue 3 frontend)
- `src/urfd-nng-dashboard/` - URFD NNG Dashboard (Go backend + Vue 3 frontend)
- `src/urfd/`, `src/tcd/`, `src/imbe_vocoder/`, `src/md380_vocoder_dynarmic/` - C-based services

## Build Commands

### Root Level (`Taskfile.yml`)

Docker Compose + Task is the primary local workflow. Tilt remains in the repository for legacy/local experimentation, but new agent work should prefer the Task/Compose commands below unless explicitly asked otherwise.

- `task init` - Initialize development environment: sync/update submodules and copy default configs into `config/local/`
- `task init-config` - Copy default configs to `config/local/` without overwriting existing local files
- `task dev-env` - Generate `.env.dev` for the selected isolated Compose dev instance; defaults to `INSTANCE=URF010`
- `task dev-build` - Build local `latest` Docker images for Compose development
- `task dev` - Start the Compose dev stack and show container status
- `task dev-usrp` - Start the Compose dev stack with AllStar Nexus/USRP support via `docker-compose.usrp.yml`
- `task dev-ps` - Show containers for the current Compose dev stack
- `task dev-logs` - Follow logs for the current Compose dev stack
- `task dev-down` - Stop the current Compose dev stack
- `task smoke` - Run Compose config, process, dashboard, and URFD listener smoke checks
- `task test` - Run development tests for initialized service repositories
- `task clean` - Remove local configuration files

Common overrides:
- `INSTANCE=URF011` selects another local instance and port offset.
- `ENV_FILE=.env.URF011.dev` lets multiple local instances keep separate env files.
- The current port-offset scheme supports `URF000` through `URF035`.

### AllStar Nexus (`src/allstar-nexus/Taskfile.yml`)
- `task build` - Build entire application (dashboard + backend)
- `task run` - Run in development mode
- `task test` - Run all tests (backend + frontend)
- `task test-backend` - Run Go tests: `go test ./... -count=1`
- `task test-frontend` - Run Vitest tests (dir: frontend)
- `task test-e2e` - Run Playwright E2E tests: `bun run test:e2e` or `npm run test:e2e`
- `task lint` - Run static analysis (placeholder - add golangci-lint/staticcheck)
- `task frontend-audit` - `bun audit` or `npm audit --audit-level=moderate`
- `task vulncheck` - Go vulnerability check via govulncheck
- `task audit-rules` - Self-check on rule compliance

### URFD NNG Dashboard (`src/urfd-nng-dashboard/Taskfile.yml`)
- `task build` - Full build (frontend then backend)
- `task build-backend` - Go backend: `go build -ldflags="-X main.Version=..." -o urfd-dashboard ./cmd/dashboard`
- `task test-backend` - Go tests: `go test -v ./...`
- `task lint-backend` - `golangci-lint run ./...`
- `task build-frontend` - Frontend: `bun run build` in `web/`
- `task test-frontend` - Frontend tests: `bun run test` in `web/`

### Running a Single Test

**Go:**
```bash
go test ./path/to/package -run TestFunctionName -v
```

**Vitest (Vue/TypeScript):**
```bash
cd frontend
bun run test path/to/test.spec.ts
# OR with npm
npx vitest run path/to/test.spec.ts
```

**Playwright E2E:**
```bash
cd frontend
bun run test:e2e -- tests-e2e/file.spec.ts
# OR with npm
npm run test:e2e -- tests-e2e/file.spec.ts
```

## Code Style Guidelines

### Go Backend

**Imports:** Group standard library, third-party, local (blank lines between groups)
```go
import (
    "context"
    "fmt"

    "go.uber.org/zap"
    "gorm.io/gorm"

    "github.com/dbehnke/allstar-nexus/internal/ami"
)
```

**Error Handling:** Return wrapped errors with context
```go
result, err := doSomething()
if err != nil {
    return fmt.Errorf("failed to do something: %w", err)
}
```

**Context:** Use `context` for cancellation and timeouts
```go
func (c *Connector) Run(ctx context.Context) error {
    select {
    case <-ctx.Done():
        return ctx.Err()
    }
}
```

**Concurrency:** Use `sync.RWMutex` for struct field access, channels for events
```go
type Connector struct {
    mu   sync.RWMutex
    data map[string]string
}
```

**Testing:** Table-driven tests in `_test.go` files (TDD approach)
```go
func TestParseXStat(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected int
    }{
        {"basic", "data", 42},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // test code
        })
    }
}
```

**Simulators:** Build simulator tools for complex workflows
- Simulators in `cmd/simulator/` or `tools/*/` directories
- Use simulators to mock external dependencies (NNG, AMI, WebSocket)
- Test edge cases and failure modes without requiring full stack

**Logging:** Use `go.uber.org/zap` logger (production)
```go
logger.Info("event", zap.String("key", "value"))
logger.Error("error", zap.Error(err))
```

**Linting:** All Go code must pass `golangci-lint` checks before merging

### Vue 3 Frontend

**Single File Components:** Use `<script setup lang="ts">`
```vue
<script setup lang="ts">
import { ref, computed } from 'vue'
import { useLiveStore } from '@/stores/live'

const props = defineProps<{ title?: string }>()
const emit = defineEmits<{ (e: 'update', val: string): void }>()
</script>
```

**TypeScript Config:** Strict mode enabled
- `strict: true`
- `noUnusedLocals: true`
- `noUnusedParameters: true`
- `noFallthroughCasesInSwitch: true`
- `noUncheckedSideEffectImports: true`

**Path Aliases:** `@/*` maps to `./src/*`

**State Management:** Use Pinia stores
```typescript
import { defineStore } from 'pinia'

export const useLiveStore = defineStore('live', () => {
  const state = ref({})
  return { state }
})
```

**Styling:** Tailwind CSS (utility-first)
```vue
<div class="bg-white border rounded-lg p-4 hover:shadow-md transition">
```

**Testing:** Vitest with jsdom environment
- Use `describe`, `it`, `expect` from 'vitest'
- Component tests with `@vue/test-utils`
- E2E with Playwright

**Linting:** All TypeScript/JavaScript must be linted and type-checked before merging

### General Rules

**Agent Usage:** Use subagents whenever possible. Never use the main agent to perform tasks directly. Launch appropriate subagents (general, explore, etc.) for specific work to maintain modularity and focused context.

**Session Management:** Always clear context and start a new session when switching from plan mode to build mode.

**Naming Conventions:**
- Go: PascalCase for exported, camelCase for unexported
- TypeScript/JS: camelCase
- Files: lowercase_with_underscores for Go, PascalCase.vue for components

**Comments:** Minimal; prefer self-documenting code

**Secrets:** NEVER commit API keys, passwords, or secrets

**GitHub Interactions:** Use `gh` CLI for PRs/issues

**Branch Management:** Never commit directly to main branches. Always create pull requests for any branches checked out using `gh` commands. All code changes must go through PR review process.

**Development Workflow (from .cursorrules):**
1. Planning - Create detailed implementation plan, wait for approval
2. TDD - Write failing tests first (mandatory for new features)
3. Implementation - Write minimum code to pass tests
4. Refactoring - Clean up while tests remain green
5. Simulators - Build simulators for complex workflows to enable comprehensive testing

**Code Review:** Generate SSE analysis (impact, edge cases, security, performance) before requesting human review

**Packaging:** Implementation and how-to are documented in `/PACKAGING.md`. See PACKAGING.md for building, testing, and CI details.

**Documentation:** Keep documentation up to date. Audit documentation when:
- Making architecture changes
- Preparing for new version releases

**Deployment:** Prioritize ease of deployment for end users. Focus on:
- Simple installation process
- Clear upgrade paths
- Minimal configuration requirements

**Configuration:** All features must have fully documented configuration examples
- No hidden or secret configurations
- Every feature implemented must have documented config examples
- Default values should be clearly specified
- Configuration validation should be provided

**Tools:**
- Docker Compose V2 for local orchestration (`docker compose`, usually through `task` wrappers)
- Task (go-task) for development, test, smoke, and production wrapper commands
- Docker Desktop or Colima for the local container runtime; on macOS with Colima, use `--port-forwarder grpc` so UDP ports work
- Go 1.25.6 for backend services
- Node.js with bun (preferred) or npm for frontend services
- Tiltfile is legacy/available, but Compose + Task is the canonical workflow documented in `README.md` and `SETUP.md`
