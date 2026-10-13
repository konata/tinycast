#!/bin/bash
# 拉取上游并推送；手动构建完成后安装指定运行的产物
set -euo pipefail
cd "$(dirname "$0")"
[[ $(git branch --show-current) == main ]] || { echo "Run update.sh from main" >&2; exit 1; }
if [[ $# -eq 0 ]]; then
  [[ -z $(git status --porcelain) ]] || { echo "Commit all changes before updating" >&2; exit 1; }
  git fetch upstream
  git merge upstream/main
  git push origin main
  echo "Manually run Personal build (stable) for $(git rev-parse HEAD), then ./update.sh <run-id>"
  exit 0
fi
[[ $# -eq 1 && $1 =~ ^[0-9]+$ ]] || { echo "Usage: ./update.sh [run-id]" >&2; exit 1; }
run=$1
commit=$(git rev-parse HEAD)
valid=$(gh run view "$run" --repo konata/tinycast --json workflowName,event,headSha \
  --jq ".workflowName == \"Personal build\" and .event == \"workflow_dispatch\" and .headSha == \"$commit\"")
[[ $valid == true ]] || { echo "Run $run is not a manual Personal build for $commit" >&2; exit 1; }
gh run watch "$run" --repo konata/tinycast --exit-status >/dev/null
rm -rf /tmp/tinycast-update && mkdir -p /tmp/tinycast-update
gh run download "$run" --repo konata/tinycast --name tinycast-personal-stable --dir /tmp/tinycast-update
ditto -x -k /tmp/tinycast-update/personal-stable.zip /tmp/tinycast-update
pkill -x Tinycast || true; sleep 1
ditto /tmp/tinycast-update/Tinycast.app /Applications/Tinycast.app
xattr -dr com.apple.quarantine /Applications/Tinycast.app 2>/dev/null || true
open -a Tinycast
echo "tinycast 更新完成(配置不动的哦)"
