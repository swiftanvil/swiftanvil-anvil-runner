# iStudio Agent Rules

These rules apply to all agent work in this repository.

## Host-Agnostic Source Of Truth

The load-bearing workflow is defined by repository files and shell scripts, not
by any one LLM host.

For any goal, task, or chain workflow, use the repo-local skill:

```text
skills/istudio-goal-workflow/SKILL.md
```

That skill is the operator-facing entrypoint and owns role/model strategy. It
uses these host-agnostic repository artifacts as its mechanical backing:

```text
scripts/goal-start.sh
docs/02-contracts/goal-workflow.md
docs/02-contracts/task-chain-communication-contract.md
```

Host-specific adapters may be added later, but they must remain optional
wrappers over this repo-local skill. They must not become the source of truth.

## Branch And Worktree Policy

- Never commit directly on `main`.
- Never push `main` from a local checkout.
- PRs into `main` must use rebase (linear history). Squash is permitted only
  for small PRs. Merge commits on `main` are forbidden.
- Every task or goal must run from a dedicated worktree and feature branch,
  created or selected through `scripts/goal-start.sh` unless a recorded plan
  explains why a manual path was required.
- Feature branches are the source branches for pull requests into `main`.
- Implementation tasks inside a chain should use task worktrees branched from
  the chain feature branch when parallel or isolated execution is useful.
- Completed task work should merge back into the chain feature branch through a
  controlled squash or rebase flow.
- A chain feature branch is pushed only after planned tasks, reviews, and
  checks are complete enough for PR review.

## Goal Workflow

Goal work must follow:

1. Run `scripts/goal-start.sh <goal-slug>` to create or select a dedicated
   feature worktree and plan artifact.
2. Produce a plan artifact before implementation.
3. Review the plan through self-review and exhaustive sibling or cross-host
   critique.
4. Address review feedback before implementation.
5. Implement in isolated task worktrees when useful.
6. Review implementation exhaustively against the finalized plan, goals,
   non-goals, policy, tests, recovery behavior, and field execution risks.
7. Refactor where needed for testability, SOLID principles, and clean
   architecture.
8. Add or update unit and integration tests for meaningful use cases.
9. Emit task and chain briefs for operator visibility.
10. Push the feature branch and create a pull request against `main`.

### Fast Path For "What Is Next"

When the operator asks `goal next`, `what is next`, or similar, use the
repo-local goal discovery mechanism defined in
`skills/istudio-goal-workflow/SKILL.md` rather than manually exploring plans,
briefs, branches, and roadmap files. Only fall back to manual artifact
exploration if the repo-local mechanism is unavailable, fails, or produces
ambiguous output.

These rules are non-negotiable unless the operator explicitly records an
override in the relevant plan artifact.
