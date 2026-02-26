#!/bin/bash
# Ralph: Autonomous loop for Engine & Transport (Sub-PRD #131, worktree: engine-transport)
# Issues: #132 (Audio Sync), #133 (Return-to-Start)
# Usage: ./ralph-engine.sh <iterations>
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

PARENT_PRD=131
REPO="modplug/loops"
CLUSTER="engine-transport"
PROGRESS="progress-${CLUSTER}.txt"

if [ ! -f "$PROGRESS" ]; then
  echo "# Ralph Progress: $CLUSTER (#$PARENT_PRD)" > "$PROGRESS"
  echo "# Issues: #132 (Audio Sync), #133 (Return-to-Start)" >> "$PROGRESS"
  echo "# Started: $(date)" >> "$PROGRESS"
  echo "" >> "$PROGRESS"
fi

echo "Starting Ralph [$CLUSTER]: up to $1 iterations for PRD #$PARENT_PRD"

for ((i=1; i<=$1; i++)); do
  echo ""
  echo "=== [$CLUSTER] Iteration $i of $1 ==="

  result=$(claude --worktree --permission-mode bypassPermissions -p "\
You are working on the Loops DAW project (Swift/SwiftUI macOS app). Your task source is GitHub Issues.
You are in an isolated worktree for the '$CLUSTER' feature cluster.

## Context
- Parent PRD: https://github.com/$REPO/issues/$PARENT_PRD
- Progress: @$PROGRESS
- Sub-PRD file: tasks/prd-daw-polish-engine.md (read this for full context)

## Important Rules
- Never use \`any\` type — use generics for type safety
- Before adding new types, check for existing conflicting/duplicate types
- Audio engine topology changes: engine.connect() silently fails on running engine — must engine.stop() before graph rebuild
- Tests requiring audio hardware: gate behind XCTSkipUnless check for available output devices
- Tests using offline rendering: use engine.enableManualRenderingMode(.offline)

## Instructions
1. Read $PROGRESS to see what has been completed.
2. Run: gh issue list --repo $REPO --state open --json number,title,body --limit 50
   Filter to issues whose body contains 'Refs #$PARENT_PRD'.
3. For each issue, check its 'Blocked by' section. Skip blocked issues (where the blocking issue is still open).
4. Pick the lowest-numbered unblocked issue.
5. Read the full issue: gh issue view <number> --repo $REPO
6. Read the sub-PRD file: tasks/prd-daw-polish-engine.md
7. Explore the codebase thoroughly before making changes. Key files:
   - Sources/LoopsEngine/Playback/PlaybackScheduler.swift
   - Sources/LoopsEngine/Playback/TransportManager.swift
   - Sources/LoopsEngine/Audio/AudioEngineManager.swift
   - Sources/LoopsApp/ViewModels/TransportViewModel.swift
8. Implement the feature end-to-end per acceptance criteria.
9. Run quality gates: swift build && swift test && swiftlint. Fix any failures.
10. Commit with message referencing the issue (e.g., 'Fix multi-track audio sync #132').
11. Close the issue: gh issue close <number> --repo $REPO
12. Append to $PROGRESS: iteration number, issue number, title, summary of changes.

ONLY WORK ON A SINGLE ISSUE PER ITERATION.
If no open child issues remain, output <promise>COMPLETE</promise>.")

  echo "$result"

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo "=== [$CLUSTER] COMPLETE after $i iterations ==="
    exit 0
  fi
done

echo "=== [$CLUSTER] Reached limit ($1). Run again to continue. ==="
