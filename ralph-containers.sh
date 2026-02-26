#!/bin/bash
# Ralph: Autonomous loop for Containers & UI (Sub-PRD #131, worktree: containers-ui)
# Issues: #137 (Perf), #138 (Piano Roll), #139 (Crossfade), #140 (Multi-Select Containers),
#         #141 (Multi-Select Tracks), #142 (Glue), #143 (Shadow)
# Usage: ./ralph-containers.sh <iterations>
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

PARENT_PRD=131
REPO="modplug/loops"
CLUSTER="containers-ui"
PROGRESS="progress-${CLUSTER}.txt"

if [ ! -f "$PROGRESS" ]; then
  echo "# Ralph Progress: $CLUSTER (#$PARENT_PRD)" > "$PROGRESS"
  echo "# Issues: #137-#143 (Performance, Piano Roll, Crossfade, Multi-Select, Glue, Shadow)" >> "$PROGRESS"
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
- Sub-PRD file: tasks/prd-daw-polish-containers.md (read this for full context)

## Important Rules
- Never use \`any\` type — use generics for type safety
- Before adding new types, check for existing conflicting/duplicate types
- Performance is critical: use Canvas for drawing, .equatable() to prevent redraws, LazyVStack for off-screen culling
- Use drawingGroup() for complex rendering, avoid triggering SwiftUI relayouts during scroll/zoom
- SelectionState already has selectedContainerIDs: Set — build on existing patterns
- Crossfade: equal-power formula is gainA = cos(t * π/2), gainB = sin(t * π/2)
- Container shadows must use allowsHitTesting(false) so clicks pass through

## Instructions
1. Read $PROGRESS to see what has been completed.
2. Run: gh issue list --repo $REPO --state open --json number,title,body --limit 50
   Filter to issues whose body contains 'Refs #$PARENT_PRD'.
3. For each issue, check its 'Blocked by' section. Skip blocked issues (where the blocking issue is still open).
4. Pick the lowest-numbered unblocked issue.
5. Read the full issue: gh issue view <number> --repo $REPO
6. Read the sub-PRD file: tasks/prd-daw-polish-containers.md
7. Explore the codebase thoroughly before making changes. Key files:
   - Sources/LoopsApp/Views/Timeline/TimelineView.swift
   - Sources/LoopsApp/Views/Timeline/TrackLaneView.swift
   - Sources/LoopsApp/Views/Timeline/ContainerView.swift
   - Sources/LoopsApp/Views/Timeline/GridOverlayView.swift
   - Sources/LoopsApp/ViewModels/TimelineViewModel.swift
   - Sources/LoopsApp/ViewModels/SelectionState.swift
   - Sources/LoopsApp/Views/MIDI/InlinePianoRollView.swift
   - Sources/LoopsCore/Models/Container.swift
   - Sources/LoopsCore/Models/FadeSettings.swift
   - Sources/LoopsEngine/Audio/OfflineRenderer.swift
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
