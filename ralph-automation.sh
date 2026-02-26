#!/bin/bash
# Ralph: Autonomous loop for Automation (Sub-PRD #131, worktree: automation)
# Issues: #134 (Snap), #135 (Toolbar/Shapes), #136 (Marquee Select)
# Usage: ./ralph-automation.sh <iterations>
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

PARENT_PRD=131
REPO="modplug/loops"
CLUSTER="automation"
PROGRESS="progress-${CLUSTER}.txt"

if [ ! -f "$PROGRESS" ]; then
  echo "# Ralph Progress: $CLUSTER (#$PARENT_PRD)" > "$PROGRESS"
  echo "# Issues: #134 (Snap), #135 (Toolbar/Shapes), #136 (Marquee)" >> "$PROGRESS"
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
- Sub-PRD file: tasks/prd-daw-polish-automation.md (read this for full context)

## Important Rules
- Never use \`any\` type — use generics for type safety
- Before adding new types, check for existing conflicting/duplicate types
- Automation snapping must respect TimelineViewModel.effectiveSnapResolution()
- SnapResolution.snap(_:) already exists — reuse for automation time axis
- Cmd key override (invertSnap) pattern already used in timeline — replicate
- Style automation toolbar consistently with existing piano roll toolbar

## Instructions
1. Read $PROGRESS to see what has been completed.
2. Run: gh issue list --repo $REPO --state open --json number,title,body --limit 50
   Filter to issues whose body contains 'Refs #$PARENT_PRD'.
3. For each issue, check its 'Blocked by' section. Skip blocked issues (where the blocking issue is still open).
4. Pick the lowest-numbered unblocked issue.
5. Read the full issue: gh issue view <number> --repo $REPO
6. Read the sub-PRD file: tasks/prd-daw-polish-automation.md
7. Explore the codebase thoroughly before making changes. Key files:
   - Sources/LoopsApp/Views/Timeline/AutomationSubLaneView.swift
   - Sources/LoopsApp/Views/Timeline/AutomationOverlayView.swift
   - Sources/LoopsCore/Models/AutomationLane.swift
   - Sources/LoopsCore/Models/MIDISequence.swift (SnapResolution, GridMode)
   - Sources/LoopsApp/Views/MIDI/InlinePianoRollView.swift (reference for toolbar style)
8. Implement the feature end-to-end per acceptance criteria.
9. Run quality gates: swift build && swift test && swiftlint. Fix any failures.
10. Commit with message referencing the issue.
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
