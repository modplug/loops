#!/bin/bash
# Ralph: Autonomous loop for PDC & Engine (Sub-PRD #144, worktree: pdc-engine)
# Issues: #145 (PDC), #146 (Low-Latency Monitoring), #147 (Audio Test Suite)
# Uses a SINGLE persistent worktree so commits accumulate across iterations.
# Usage: ./ralph-pdc-engine.sh <iterations>
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

PARENT_PRD=144
REPO="modplug/loops"
CLUSTER="pdc-engine"
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
  echo "# Issues: #145 (PDC), #146 (Low-Latency), #147 (Test Suite)" >> "$PROGRESS"
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
- Sub-PRD file: tasks/prd-pro-daw-engine.md (read this for full context)

## CRITICAL: Issue Scope
You may ONLY work on these specific issue numbers: #145, #146, #147.
Do NOT work on any other issues, even if they reference the same parent PRD.
If none of these issues are open, output <promise>COMPLETE</promise>.

## Important Rules
- Never use \`any\` type — use generics for type safety
- Before adding new types, check for existing conflicting/duplicate types
- CRITICAL: engine.connect() silently fails on running engine — must engine.stop() before graph rebuild
- Tests requiring audio hardware: gate behind XCTSkipUnless(audioOutputAvailable)
- Offline tests: use engine.enableManualRenderingMode(.offline)
- PDC: query AVAudioUnit.auAudioUnit.latency (returns seconds), convert to samples
- Low-latency bypass: use auAudioUnit.shouldBypassEffect = true (preserves state)

## Instructions
1. Read $PROGRESS to see what has been completed.
2. Run: gh issue list --repo $REPO --state open --json number,title,body --limit 50
   Filter to ONLY issues #145, #146, or #147. Ignore all other issues.
3. For each issue, check its 'Blocked by' section. Skip blocked issues (where the blocking issue is still open).
4. Pick the lowest-numbered unblocked issue from the allowed set (#145, #146, #147).
5. Read the full issue: gh issue view <number> --repo $REPO
6. Read the sub-PRD file: tasks/prd-pro-daw-engine.md
7. Explore the codebase thoroughly before making changes. Key files:
   - Sources/LoopsEngine/Playback/PlaybackScheduler.swift
   - Sources/LoopsEngine/AudioUnit/AudioUnitHost.swift
   - Sources/LoopsEngine/Audio/AudioEngineManager.swift
   - Sources/LoopsEngine/Recording/RecordingManager.swift
   - Sources/LoopsEngine/Audio/OfflineRenderer.swift
   - Tests/LoopsEngineTests/PlaybackSchedulerTests.swift
8. Implement the feature end-to-end per acceptance criteria.
9. Run quality gates: swift build && swift test && swiftlint. Fix any failures.
10. Commit with message referencing the issue.
11. Close the issue: gh issue close <number> --repo $REPO
12. Append to $PROGRESS: iteration number, issue number, title, summary of changes.

ONLY WORK ON A SINGLE ISSUE PER ITERATION.
If no open issues from (#145, #146, #147) remain, output <promise>COMPLETE</promise>.")

  echo "$result"

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo "=== [$CLUSTER] COMPLETE after $i iterations ==="
    exit 0
  fi
done

echo "=== [$CLUSTER] Reached limit ($1). Run again to continue. ==="
