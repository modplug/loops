You are building "Loops" — a macOS live looper DAW. Read the full PRD and technical architecture at tasks/prd-loops.md FIRST before doing anything.

## Workflow for each iteration

1. Read tasks/prd-loops.md for full context (especially the Technical Architecture section)
2. Check GitHub issues: `gh issue list --repo modplug/loops --state open --label user-story`
3. Find the LOWEST numbered unblocked issue (check "Blocked by" — an issue is unblocked when all blockers are closed)
4. Implement that single issue following the PRD architecture EXACTLY (module structure, data models, file paths, design constraints)
5. Run `swift build` and `swift test` — fix any errors
6. Commit with a descriptive message referencing the issue number
7. Close the issue: `gh issue close <number> --repo modplug/loops`
8. Push: `git push`

## Rules

- Follow the Technical Architecture section EXACTLY — file paths, module boundaries, @Observable pattern, typed IDs, no `any` types
- One issue per iteration. Small, focused commits.
- Always verify `swift build && swift test` pass before committing
- If stuck on an issue for more than 2 attempts, skip it and move to the next unblocked one
- The PRD issue #27 is the parent — never close it
- Never use `any` type — use generics with protocol constraints instead

Start with issue #28 (Empty app with project scaffold) which has no blockers.

Output <promise>ALL ISSUES COMPLETE</promise> when all issues are closed.
