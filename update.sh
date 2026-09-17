#!/bin/bash
# 拉上游更新 + 保留 alias+空格 patch + CI 构建 + 本机替换
set -euo pipefail
cd "$(dirname "$0")"
git fetch upstream
git merge upstream/main   # 冲突时手动解决后重跑本脚本
git push origin main
sleep 8
run=$(gh run list --repo konata/tinycast --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run" --repo konata/tinycast --exit-status >/dev/null
rm -rf /tmp/tinycast-update && mkdir -p /tmp/tinycast-update
gh run download "$run" --repo konata/tinycast --name tinycast-personal-stable --dir /tmp/tinycast-update
ditto -x -k /tmp/tinycast-update/personal-stable.zip /tmp/tinycast-update
pkill -x Tinycast || true; sleep 1
ditto /tmp/tinycast-update/Tinycast.app /Applications/Tinycast.app
xattr -dr com.apple.quarantine /Applications/Tinycast.app 2>/dev/null || true
open -a Tinycast
echo "tinycast 更新完成(配置不动的哦)"
