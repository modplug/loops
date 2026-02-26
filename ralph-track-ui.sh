#!/bin/bash
# Ralph: Autonomous loop for Track UI & Tools (Sub-PRD #144, worktree: track-ui-tools)
# Issues: #153 (Track Header), #154 (Lane Visuals), #155 (Freeze), #156 (Clip Gain), #157 (LUFS)
# Uses a SINGLE persistent worktree so commits accumulate across iterations.
# Usage: ./ralph-track-ui.sh <iterations>
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

PARENT_PRD=144
REPO="modplug/loops"
CLUSTER="track-ui-tools"
PROGRESS="progress-${CLUSTER}.txt"
WORKTREE_DIR=".claude/worktrees/ralph-${CLUSTER}"
WORKTREE_BRANCH="ralph-${CLUSTER}"

# Create persistent worktree if it doesn't exist
if [ ! -d "$WORKTREE_DIR" ]; then
  echo "Creating persistent worktree: $WORKTREE_DIR (branch: $WORKTREE_BRANCH)"
  git branch "$WORKTREE_BRANCH" main 2>/dev/null || true
  git worktree add "$WORKTREE_DIR" "$WORKTREE_BRANCH"
else
  echo "Reusing existing worktree: $WORKTREE_DIR"
fi

if [ ! -f "$PROGRESS" ]; then
  echo "# Ralph Progress: $CLUSTER (#$PARENT_PRD)" > "$PROGRESS"
  echo "# Issues: #153-#157 (Track Header, Lane Visuals, Freeze, Clip Gain, LUFS)" >> "$PROGRESS"
  echo "# Started: $(date)" >> "$PROGRESS"
  echo "" >> "$PROGRESS"
fi

echo "Starting Ralph [$CLUSTER]: up to $1 iterations for PRD #$PARENT_PRD"
echo "Worktree: $WORKTREE_DIR (branch: $WORKTREE_BRANCH)"

for ((i=1; i<=$1; i++)); do
  echo ""
  echo "=== [$CLUSTER] Iteration $i of $1 ==="

  result=$(cd "$WORKTREE_DIR" && claude --permission-mode bypassPermissions -p "\
You are working on the Loops DAW project (Swift/SwiftUI macOS app). Your task source is GitHub Issues.
You are in a persistent worktree for the '$CLUSTER' feature cluster.
All your commits accumulate on the '$WORKTREE_BRANCH' branch.

## Context
- Parent PRD: https://github.com/$REPO/issues/$PARENT_PRD
- Progress: Read the file at the repo root: $PROGRESS
- Sub-PRD file: tasks/prd-pro-daw-trackui.md (read this for full context)

## CRITICAL: Issue Scope
You may ONLY work on these specific issue numbers: #153, #154, #155, #156, #157.
Do NOT work on any other issues, even if they reference the same parent PRD.
If none of these issues are open, output <promise>COMPLETE</promise>.

## Important Rules
- Never use \`any\` type — use generics for type safety
- Before adding new types, check for existing conflicting/duplicate types
- Performance: use Canvas for drawing, .equatable() to prevent redraws
- Track header: current width 160pt, expanding to ~240pt
- Volume display: 20 * log10(gain) for dB conversion
- Freeze: use OfflineRenderer for bounce, store in project bundle
- LUFS: ITU-R BS.1770-4, K-weighting + gating
- Clip gain: applied pre-fader, pre-effects

## Instructions
1. Read $PROGRESS to see what has been completed.
2. Run: gh issue list --repo $REPO --state open --json number,title,body --limit 50
   Filter to ONLY issues #153, #154, #155, #156, or #157. Ignore all other issues.
3. For each issue, check its 'Blocked by' section. Skip blocked issues (where the blocking issue is still open).
4. Pick the lowest-numbered unblocked issue from the allowed set (#153, #154, #155, #156, #157).
5. Read the full issue: gh issue view <number> --repo $REPO
6. Read the sub-PRD file: tasks/prd-pro-daw-trackui.md
7. Explore the codebase thoroughly before making changes. Key files:
   - Sources/LoopsApp/Views/Timeline/TrackHeaderView.swift
   - Sources/LoopsApp/Views/Timeline/TrackLaneView.swift
   - Sources/LoopsApp/Views/Timeline/TimelineView.swift
   - Sources/LoopsApp/Views/Timeline/ContainerView.swift
   - Sources/LoopsApp/Views/Mixer/MixerStripView.swift
   - Sources/LoopsApp/Views/Mixer/LevelMeterView.swift
   - Sources/LoopsEngine/Audio/OfflineRenderer.swift
   - Sources/LoopsCore/Models/Track.swift
   - Sources/LoopsCore/Models/Container.swift
8. Implement the feature end-to-end per acceptance criteria.
9. Run quality gates: swift build && swift test && swiftlint. Fix any failures.
10. Commit with message referencing the issue.
11. Close the issue: gh issue close <number> --repo $REPO
12. Append to $PROGRESS: iteration number, issue number, title, summary of changes.

ONLY WORK ON A SINGLE ISSUE PER ITERATION.
If no open issues from (#153, #154, #155, #156, #157) remain, output <promise>COMPLETE</promise>.")

  echo "$result"

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo "=== [$CLUSTER] COMPLETE after $i iterations ==="
    exit 0
  fi
done

echo "=== [$CLUSTER] Reached limit ($1). Run again to continue. ==="
