#!/bin/bash
# Ralph: Human-in-the-loop version
# Pulls the next task from GitHub issues and implements one vertical slice at a time.
# Usage: ./ralph-once.sh

set -e

PARENT_PRD=105
REPO="modplug/loops"

claude --permission-mode bypassPermissions "\
You are working on the Loops DAW project. Your task source is GitHub Issues.

## Context
- Parent PRD: https://github.com/$REPO/issues/$PARENT_PRD
- All vertical slice issues are children of the PRD.

## Instructions
1. Run: gh issue list --repo $REPO --state open --label '' --json number,title,body --limit 50
   Filter to issues whose body contains 'Refs #$PARENT_PRD'.
2. For each issue, check its 'Blocked by' section. Skip issues that are blocked by still-open issues.
3. Pick the lowest-numbered unblocked issue — this is your task.
4. Read the issue body carefully. Understand the acceptance criteria.
5. Explore the codebase to understand the current state.
6. Implement the feature end-to-end (model, engine, UI, tests) as described in the acceptance criteria.
7. Run 'swift build' and 'swift test' to verify everything passes.
8. Commit your changes with a descriptive message referencing the issue number (e.g., 'Implement container effect chain (#51)').
9. Close the issue: gh issue close <number> --repo $REPO
10. Update progress.txt with what you did and which issue you completed.

ONLY WORK ON A SINGLE ISSUE. Do not start the next one.
If all child issues of #$PARENT_PRD are closed, output <promise>COMPLETE</promise>."
