#!/bin/bash
# Ralph: Parallel orchestrator — launches all 3 sub-PRD loops in worktrees
# Usage: ./ralph-parallel.sh <iterations-per-loop>
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations-per-loop>"
  exit 1
fi

echo "=== Ralph Parallel Orchestrator ==="
echo "PRD #131: DAW Polish — Performance, Sync, Editing & UX"
echo "Iterations per loop: $1"
echo ""
echo "Launching 3 parallel worktree loops..."
echo ""

# Launch Engine & Transport (2 issues: #132, #133)
./ralph-engine.sh "$1" 2>&1 | tee ralph-engine.log &
PID1=$!
echo "Started engine-transport (PID: $PID1) — #132 Audio Sync, #133 Return-to-Start"

# Launch Automation (3 issues: #134, #135, #136)
./ralph-automation.sh "$1" 2>&1 | tee ralph-automation.log &
PID2=$!
echo "Started automation (PID: $PID2) — #134 Snap, #135 Toolbar, #136 Marquee"

# Launch Containers & UI (7 issues: #137-#143)
./ralph-containers.sh "$1" 2>&1 | tee ralph-containers.log &
PID3=$!
echo "Started containers-ui (PID: $PID3) — #137-#143 Perf, Crossfade, Selection, Glue, Shadow"

echo ""
echo "All loops running. Monitor progress:"
echo "  tail -f progress-engine-transport.txt"
echo "  tail -f progress-automation.txt"
echo "  tail -f progress-containers-ui.txt"
echo ""
echo "Or monitor logs:"
echo "  tail -f ralph-engine.log"
echo "  tail -f ralph-automation.log"
echo "  tail -f ralph-containers.log"
echo ""

# Wait for all to finish
wait $PID1
STATUS1=$?

wait $PID2
STATUS2=$?

wait $PID3
STATUS3=$?

echo ""
echo "=== All Ralph loops finished ==="
echo "engine-transport: exit code $STATUS1"
echo "automation:       exit code $STATUS2"
echo "containers-ui:    exit code $STATUS3"
echo ""
echo "Next steps:"
echo "1. Check each worktree branch: git branch"
echo "2. Merge each into main:"
echo "   git checkout main"
echo "   git merge <worktree-branch-1>"
echo "   git merge <worktree-branch-2>"
echo "   git merge <worktree-branch-3>"
echo "3. Run quality gates: swift build && swift test && swiftlint"
echo "4. Manual QA: see tasks/qa-daw-polish.md"
