# Stacked PR + Worktree Workflow

Use `gh stack` and git worktrees to parallelize multi-issue work and keep PRs small and reviewable.

## When to use

- A milestone has 3+ issues that can be grouped into independent work streams
- Issues within a group have a dependency chain (stacked PRs)
- You want to avoid context-switching costs between unrelated branches

## Workflow

### 1. Group issues by independence

Split issues into groups that can run in parallel. Within each group, order issues by dependency (each builds on the previous).

### 2. Create a worktree per group

```bash
git worktree add ../project-worktrees/group-a -b group-a-branch
git worktree add ../project-worktrees/group-b -b group-b-branch
```

Each worktree is an independent checkout — no switching branches, no stashing.

### 3. Within a group, use `gh stack` for dependent PRs

```bash
# First issue in the group — branch from main
git checkout -b feature/issue-178 main
# ... implement ...
git push -u origin feature/issue-178
gh stack create "feat: MCP client for context providers (#178)"

# Second issue — branch from the first (stacked)
git checkout -b feature/issue-179 feature/issue-178
# ... implement ...
git push -u origin feature/issue-179
gh stack create "feat: context aggregator (#179)"

# Third issue — branch from the second
git checkout -b feature/issue-181 feature/issue-179
# ... implement ...
git push -u origin feature/issue-181
gh stack create "feat: rails_get_context tool (#181)"
```

`gh stack` sets the base of each PR to the previous branch, so the diff stays small and focused.

### 4. Merge in dependency order

Merge the bottom of the stack first. `gh stack` can restack remaining PRs onto `main` after each merge:

```bash
gh stack rebase
```

### 5. Clean up worktrees when done

```bash
git worktree remove ../project-worktrees/group-a
git worktree remove ../project-worktrees/group-b
git fetch --prune origin
```

## Rules

- One worktree per independent group, not per issue
- Within a group, stack PRs in dependency order (bottom merges first)
- Run `bundle exec rspec` and `bundle exec rubocop` in each worktree before pushing
- If a rebase causes conflicts, resolve in the worktree, force-push with `--force-with-lease`
- Clean up worktrees after all PRs in a group are merged
- Never force-push to `main`

## Conflict resolution during rebase

When merging the bottom of a stack changes files that upper PRs also touch:

```bash
# In the worktree for the stacked branch
git fetch origin main
git rebase origin/main
# Resolve conflicts in the affected files
git add <resolved-files>
GIT_EDITOR=true git rebase --continue
git push --force-with-lease
```

Common conflict patterns in this repo:
- **Doc count updates** (README.md, AGENTS.md, CLAUDE.md, CONTRIBUTING.md): take the higher count
- **Tool/introspector counts in specs**: update to match the new actual count
- **Workflow YAML**: remove empty `env:` blocks left by line deletions
