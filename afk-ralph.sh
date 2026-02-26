#!/bin/bash
# Ralph: Fully autonomous version
# Runs Claude in a loop, picking tasks from GitHub issues until the PRD is complete.
# Usage: ./afk-ralph.sh <iterations>
# Example: ./afk-ralph.sh 15

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  echo "Example: $0 15"
  exit 1
fi

PARENT_PRD=122
REPO="modplug/loops"

# Initialize progress file if it doesn't exist
if [ ! -f progress.txt ]; then
  echo "# Ralph Progress Log" > progress.txt
  echo "# PRD: SwiftUI Performance — Observable Blast Radius & View Memoization (#$PARENT_PRD)" >> progress.txt
  echo "# Started: $(date)" >> progress.txt
  echo "" >> progress.txt
fi

echo "Starting Ralph loop: up to $1 iterations for PRD #$PARENT_PRD"
echo "---"

for ((i=1; i<=$1; i++)); do
  echo ""
  echo "=== Iteration $i of $1 ==="
  echo ""

  result=$(claude --permission-mode bypassPermissions -p "\
You are working on the Loops DAW project. Your task source is GitHub Issues.

## Context
- Parent PRD: https://github.com/$REPO/issues/$PARENT_PRD
- All vertical slice issues are children of the PRD.
- Progress log: @progress.txt

## Instructions
1. Read progress.txt to see what has already been completed.
2. Run: gh issue list --repo $REPO --state open --json number,title,body --limit 50
   Filter to issues whose body contains 'Refs #$PARENT_PRD'.
3. For each issue, check its 'Blocked by' section. Skip issues that are blocked by still-open issues.
   An issue is unblocked if all issues in its 'Blocked by' list are closed.
4. Pick the lowest-numbered unblocked issue — this is your task.
5. Read the full issue body: gh issue view <number> --repo $REPO
6. Explore the codebase to understand the current state.
7. Implement the feature end-to-end (model, engine, UI, tests) as described in the acceptance criteria.
8. Run 'swift build' to verify compilation.
9. Run 'swift test' to verify all tests pass (existing + new).
10. If build or tests fail, fix the issues before proceeding.
11. Commit your changes with a message referencing the issue: 'Implement <title> (#<number>)'.
12. Close the issue: gh issue close <number> --repo $REPO
13. Append to progress.txt: iteration number, issue number, title, and brief summary of changes.

ONLY WORK ON A SINGLE ISSUE. Do not start the next one.
If there are no open child issues of #$PARENT_PRD remaining, output <promise>COMPLETE</promise>.")

  echo "$result"

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo ""
    echo "=== PRD COMPLETE after $i iterations ==="
    echo "All issues for #$PARENT_PRD have been implemented."
    exit 0
  fi

  echo ""
  echo "--- Iteration $i complete ---"
done

echo ""
echo "=== Reached iteration limit ($1). Some issues may remain open. ==="
echo "Run './afk-ralph.sh <more-iterations>' to continue."
