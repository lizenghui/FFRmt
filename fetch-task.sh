#!/bin/bash

set -euo pipefail

# 解析命令行参数
FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-f|--force]"
            exit 1
            ;;
    esac
done

MONITOR="monitor-task.sh"

REMOTE="jdcloud:tasks"
PENDING="$REMOTE/pending"
RUNNING="$REMOTE/running"
LOCAL_TASK_DIR="/tmp/tasks"
BASE_DIR="/tmp/jobs"          
mkdir -p "$LOCAL_TASK_DIR"

# 取第一条对象
TASK_NAME=$(rclone lsf "$PENDING" --files-only | head -n 1 || true)

if [[ -z "${TASK_NAME}" ]]; then
    exit 0
fi
echo "[+] Found task: $TASK_NAME"

REMOTE_PENDING_TASK="$PENDING/$TASK_NAME"
REMOTE_RUNNING_TASK="$RUNNING/$TASK_NAME"
LOCAL_TASK_PATH="$LOCAL_TASK_DIR/$TASK_NAME"


#rclone moveto "$REMOTE_PENDING_TASK" "$REMOTE_RUNNING_TASK"
rclone copyto "$REMOTE_PENDING_TASK" "$REMOTE_RUNNING_TASK"

rclone copyto "$REMOTE_RUNNING_TASK" "$LOCAL_TASK_PATH"

echo "[+] get task: $TASK_NAME"

# Source the task file to load variables
if [[ -f "$LOCAL_TASK_PATH" ]]; then
    echo "[+] Loading task file: $LOCAL_TASK_PATH"
    source "$LOCAL_TASK_PATH"
    
    # Output the variables you specified
    echo "=== Task Information ==="
    echo "TID: ${TID:-'not set'}"
    echo "SRC: ${SRC:-'not set'}"
    echo "CMD: ${CMD:-'not set'}"
    echo "DEST: ${DEST:-'not set'}"
    echo "========================"

    # Create work directory based on TID
    if [[ -n "${TID:-}" ]]; then
        WORK_DIR="$BASE_DIR/$TID"
        mkdir -p "$WORK_DIR"
        echo "[+] Created work directory: $WORK_DIR"
        
        bash "$MONITOR" "$WORK_DIR" $$ &
        MONITOR_PID=$!
        
        # Download file from SRC if it's set
        if [[ -n "${SRC:-}" ]]; then
            echo "=== Downloading from SRC ==="
            
            # Extract filename from URL, removing query parameters
            FILENAME=$(basename "${SRC%%\?*}")
            DOWNLOAD_PATH="$WORK_DIR/$FILENAME"
            LOG_FILE="$WORK_DIR/downloads.log"
          
            echo "Filename: $FILENAME"
        
            # Download with progress and log to file
            
            #curl -L --progress-bar "$SRC" -o "$DOWNLOAD_PATH" 2>&1 | tee -a "$LOG_FILE"
            if [[ ! -f "$DOWNLOAD_PATH" ]]; then
                wget --progress=dot:mega "$SRC" -O "$DOWNLOAD_PATH" 2>&1 | tee -a "$LOG_FILE"
            fi
            IN=$DOWNLOAD_PATH
            OUT=$WORK_DIR/out_$FILENAME
        fi
    fi

    FFMPEG_LOG="$WORK_DIR/ffmpeg.log"
    UPLOAD_LOG="$WORK_DIR/upload.log"
    
    # Execute the CMD if it's set
    if [[ -n "${CMD:-}" ]]; then
        # 检查输出文件是否已存在
        if [[ -f "${OUT:-}" ]] && [[ "$FORCE" == "false" ]]; then
            echo "[+] Output file already exists: $OUT"
            echo "[+] Skipping transcoding (use -f to force re-transcode)"
        else
            echo "[+] Transcoding…"
            
            rm -vf "$OUT"
            eval "$CMD" 2>&1 |  stdbuf -oL tr '\r' '\n' | tee -a "$FFMPEG_LOG"
            echo "[+] Transcoding completed successfully"
        fi
    else
        echo "[-] CMD variable is not set, skipping execution"
    fi

    if [[ -n "${DEST:-}" ]] && [[ -n "${OUT:-}" ]] && [[ -f "$OUT" ]]; then
        echo "[+] Starting upload to $DEST"
        
        # 构建完整的上传路径（如果DEST是目录，添加文件名）
        UPLOAD_DEST="$DEST"
        if [[ "$DEST" == */ ]]; then
            # DEST是目录，添加文件名
            BASENAME=$(basename "$OUT")
            UPLOAD_DEST="${DEST}${BASENAME}"
        fi
        
        rclone copyto "$OUT" "$UPLOAD_DEST" --progress 2>&1 | stdbuf -oL tr '\r' '\n' | tee -a "$UPLOAD_LOG"
        
        echo "[+] Upload completed successfully"
    fi
   
else
    echo "[-] Task file not found: $LOCAL_TASK_PATH"
    exit 1
fi

if [[ -n "${MONITOR_PID:-}" ]]; then
    echo "[+] Waiting 3 seconds before stopping monitor process..."
    sleep 3
    echo "[+] Stopping monitor process (PID: $MONITOR_PID)..."
    kill "$MONITOR_PID" 2>/dev/null || echo "[-] Failed to kill monitor process or process already terminated"
fi

echo "[+] done"


