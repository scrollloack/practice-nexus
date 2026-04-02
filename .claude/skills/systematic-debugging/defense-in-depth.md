# Defense-in-Depth Validation

## Overview

When you fix a bug caused by invalid data, adding validation at one place feels sufficient. But that single check can be bypassed by different code paths, refactoring, or mocks.

**Core principle:** Validate at EVERY layer data passes through. Make the bug structurally impossible.

## Why Multiple Layers

Single validation: "We fixed the bug"
Multiple layers: "We made the bug impossible"

Different layers catch different cases:

- Entry validation catches most bugs
- Business logic catches edge cases
- Environment guards prevent context-specific dangers
- Debug logging helps when other layers fail

## The Four Layers

### Layer 1: Entry Point Validation

**Purpose:** Reject obviously invalid input at API boundary

```ruby
# Ruby
def create_project(name, working_directory)
  raise ArgumentError, "working_directory cannot be empty" if working_directory.blank?
  raise ArgumentError, "working_directory does not exist: #{working_directory}" unless File.exist?(working_directory)
  raise ArgumentError, "working_directory is not a directory: #{working_directory}" unless File.directory?(working_directory)
  # ... proceed
end
```

```typescript
// TypeScript
function createProject(name: string, workingDirectory: string) {
  if (!workingDirectory || workingDirectory.trim() === "") {
    throw new Error("workingDirectory cannot be empty");
  }
  if (!existsSync(workingDirectory)) {
    throw new Error(`workingDirectory does not exist: ${workingDirectory}`);
  }
  if (!statSync(workingDirectory).isDirectory()) {
    throw new Error(`workingDirectory is not a directory: ${workingDirectory}`);
  }
  // ... proceed
}
```

### Layer 2: Business Logic Validation

**Purpose:** Ensure data makes sense for this operation

```ruby
# Ruby
def initialize_workspace(project_dir, session_id)
  raise ArgumentError, "project_dir required for workspace initialization" if project_dir.blank?
  # ... proceed
end
```

```typescript
// TypeScript
function initializeWorkspace(projectDir: string, sessionId: string) {
  if (!projectDir) {
    throw new Error("projectDir required for workspace initialization");
  }
  // ... proceed
}
```

### Layer 3: Environment Guards

**Purpose:** Prevent dangerous operations in specific contexts

```ruby
# Ruby
def git_init(directory)
  # In tests, refuse git init outside temp directories
  if Rails.env.test?
    normalized = File.expand_path(directory)
    tmp_dir    = File.expand_path(Dir.tmpdir)

    unless normalized.start_with?(tmp_dir)
      raise "Refusing git init outside temp dir during tests: #{directory}"
    end
  end
  # ... proceed
end
```

```typescript
// TypeScript
async function gitInit(directory: string) {
  if (process.env.NODE_ENV === "test") {
    const normalized = normalize(resolve(directory));
    const tmpDir = normalize(resolve(tmpdir()));

    if (!normalized.startsWith(tmpDir)) {
      throw new Error(
        `Refusing git init outside temp dir during tests: ${directory}`,
      );
    }
  }
  // ... proceed
}
```

### Layer 4: Debug Instrumentation

**Purpose:** Capture context for forensics

```ruby
# Ruby
def git_init(directory)
  Rails.logger.debug("About to git init", {
    directory: directory,
    cwd: Dir.pwd,
    caller: caller.first(5)
  })
  # ... proceed
end
```

```typescript
// TypeScript
async function gitInit(directory: string) {
  const stack = new Error().stack;
  logger.debug("About to git init", {
    directory,
    cwd: process.cwd(),
    stack,
  });
  // ... proceed
}
```

## Applying the Pattern

When you find a bug:

1. **Trace the data flow** - Where does bad value originate? Where used?
2. **Map all checkpoints** - List every point data passes through
3. **Add validation at each layer** - Entry, business, environment, debug
4. **Test each layer** - Try to bypass layer 1, verify layer 2 catches it

## Example from Session

Bug: Empty `projectDir` caused `git init` in source code

**Data flow:**

1. Test setup → empty string
2. `Project.create(name, '')`
3. `WorkspaceManager.createWorkspace('')`
4. `git init` runs in `process.cwd()`

**Four layers added:**

- Layer 1: `Project.create()` validates not empty/exists/writable
- Layer 2: `WorkspaceManager` validates projectDir not empty
- Layer 3: `WorktreeManager` refuses git init outside tmpdir in tests
- Layer 4: Stack trace logging before git init

**Result:** All 1847 tests passed, bug impossible to reproduce

## Key Insight

All four layers were necessary. During testing, each layer caught bugs the others missed:

- Different code paths bypassed entry validation
- Mocks bypassed business logic checks
- Edge cases on different platforms needed environment guards
- Debug logging identified structural misuse

**Don't stop at one validation point.** Add checks at every layer.
