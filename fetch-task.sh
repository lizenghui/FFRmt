#!/bin/bash

set -euo pipefail

# Source configuration file
CONFIG_FILE="$(dirname "$0")/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "[-] Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

PENDING="$FFRMT_TASK_REMOTE/pending"
RUNNING="$FFRMT_TASK_REMOTE/running"

BASE_DIR="$FFRMT_BASE_DIR"
LOCAL_TASK_DIR="$BASE_DIR/tasks"
mkdir -p "$LOCAL_TASK_DIR"

# 取第一条对象
TASK_NAME=$(rclone lsf "$PENDING" --files-only | head -n 1 || true)

if [[ -z "${TASK_NAME}" ]]; then
    exit 0
fi
echo "[+] Found task: $TASK_NAME"

# 提取taskid（去掉.task扩展名）
TASK_ID="${TASK_NAME%.task}"

REMOTE_PENDING_TASK="$PENDING/$TASK_NAME"
REMOTE_RUNNING_TASK="$RUNNING/$TASK_NAME"
LOCAL_TASK_PATH="$LOCAL_TASK_DIR/$TASK_NAME"

# 将任务从pending复制到running状态
rclone moveto "$REMOTE_PENDING_TASK" "$REMOTE_RUNNING_TASK"
rclone copyto "$REMOTE_RUNNING_TASK" "$LOCAL_TASK_PATH"

echo "[+] get task: $TASK_NAME"
echo "[+] task id: $TASK_ID"

# 启动systemd服务
if [[ -n "$TASK_ID" ]]; then
    echo "[+] Starting service: FFRmt@$TASK_ID.service"
    systemctl start "FFRmt@$TASK_ID.service"
    echo "[+] Service started successfully"
else
    echo "[-] Cannot determine task ID from filename: $TASK_NAME"
    exit 1
fi

echo "[+] done"


