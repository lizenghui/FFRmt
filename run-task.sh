#!/bin/bash

set -euo pipefail

FORCE=false

# Source configuration file
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "[-] Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

BASE_DIR="$FFRMT_BASE_DIR"
MONITOR="$SCRIPT_DIR/monitor-task.sh"
LOCAL_JOB_DIR="$BASE_DIR/jobs"
LOCAL_TASK_DIR="$BASE_DIR/tasks"

TASK_ID="${1:-}"

if [[ -z "$TASK_ID" ]]; then
    echo "Usage: $0 <task_id>"
    exit 1
fi

# 构建任务文件名和路径
TASK_NAME="$TASK_ID.task"
LOCAL_TASK_PATH="$LOCAL_TASK_DIR/$TASK_NAME"

echo "[+] Processing task: $TASK_NAME"
echo "[+] Task ID: $TASK_ID"
echo "[+] Task file path: $LOCAL_TASK_PATH"

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
        WORK_DIR="$LOCAL_JOB_DIR/$TID"
        mkdir -p "$WORK_DIR"
        echo "[+] Created work directory: $WORK_DIR"
        
        bash "$MONITOR" "$WORK_DIR" $$ &
        MONITOR_PID=$!
        
        # Download file from SRC if it's set
        if [[ -n "${SRC:-}" ]]; then
            echo "=== Downloading from SRC ==="
            
            # Extract filename from URL, removing query parameters
            FILENAME=$(basename "${SRC%%\?*}")
            # Keep the full filename including extension for input
            IN_BASENAME="$FILENAME"
            # Remove file extension to get base name for output (without extension)
            BASENAME="${FILENAME%.*}"
            DOWNLOAD_PATH="$WORK_DIR/$FILENAME"
            LOG_FILE="$WORK_DIR/downloads.log"
        
            # Download with progress and log to file
            
            #curl -L --progress-bar "$SRC" -o "$DOWNLOAD_PATH" 2>&1 | tee -a "$LOG_FILE"
            if [[ ! -f "$DOWNLOAD_PATH" ]]; then
                wget --progress=dot:mega "$SRC" -O "$DOWNLOAD_PATH" 2>&1 | tee -a "$LOG_FILE"
            fi
            IN=$DOWNLOAD_PATH
            # 保持文件扩展名：如果输入是.mkv，输出也是.mkv
            OUT=$WORK_DIR/out_$IN_BASENAME
        fi
    fi

    FFMPEG_LOG="$WORK_DIR/ffmpeg.log"
    UPLOAD_LOG="$WORK_DIR/upload.log"
    
    if [[ -n "${CMD:-}" ]]; then
    
        echo "[+] Transcoding…"
        echo "[+] CMD: $(echo "$CMD" | sed "s|\${IN}|$IN|g" | sed "s|\${OUT}|$OUT|g")"
        
        rm -vf "$OUT"
        
        # 执行FFmpeg命令并捕获输出
        set +e  # 暂时禁用错误立即退出
        eval "$CMD" 2>&1 |  stdbuf -oL tr '\r' '\n' | tee -a "$FFMPEG_LOG"
        FFMPEG_EXIT_CODE=$?
        set -e  # 重新启用错误立即退出
        
        if [[ $FFMPEG_EXIT_CODE -ne 0 ]]; then
            echo "[-] FFmpeg failed with exit code: $FFMPEG_EXIT_CODE"
            echo "[+] Attempting to fix the command using AI..."
            
            # 构建完整的命令字符串
            FULL_CMD=$(echo "$CMD" | sed "s|\${IN}|$IN|g" | sed "s|\${OUT}|$OUT|g")
            
            # 调用fix_ffmpeg_command.py来修正命令
            if [[ -f "$SCRIPT_DIR/fix_ffmpeg_command.py" ]]; then
                echo "[+] Calling fix_ffmpeg_command.py"
                
                # 使用配置的Python命令运行修复脚本
                PYTHON_CMD="${FFRMT_PYTHON_CMD:-python}"
                echo "[+] Using Python command: $PYTHON_CMD"
                
                # 运行修复命令，捕获stdout（修正后的命令）
                # Python脚本会自动在同目录下生成fix.log
                FIXED_CMD=$($PYTHON_CMD "$SCRIPT_DIR/fix_ffmpeg_command.py" --command "$FULL_CMD" --log-file "$FFMPEG_LOG")
                FIXED_EXIT_CODE=$?  # 获取python命令的退出码
                
                # 如果python命令失败，使用原始命令
                if [[ $FIXED_EXIT_CODE -ne 0 ]]; then
                    echo "[-] fix_ffmpeg_command.py failed with exit code: $FIXED_EXIT_CODE"
                    FIXED_CMD="$FULL_CMD"
                fi
                
                if [[ "$FIXED_CMD" != "$FULL_CMD" ]]; then
                    echo "[+] Fixed command: $FIXED_CMD"
                    echo "[+] Retrying transcoding with fixed command..."
                    
                    # 重新执行修正后的命令
                    set +e
                    eval "$FIXED_CMD" 2>&1 |  stdbuf -oL tr '\r' '\n' | tee -a "$FFMPEG_LOG"
                    FFMPEG_EXIT_CODE=$?
                    set -e
                    
                    if [[ $FFMPEG_EXIT_CODE -eq 0 ]]; then
                        echo "[+] Transcoding completed successfully with fixed command"
                    else
                        echo "[-] Fixed command also failed with exit code: $FFMPEG_EXIT_CODE"
                        exit $FFMPEG_EXIT_CODE
                    fi
                else
                    echo "[-] Could not fix the command, using original command"
                    exit $FFMPEG_EXIT_CODE
                fi
            else
                echo "[-] fix_ffmpeg_command.py not found, cannot fix the command"
                exit $FFMPEG_EXIT_CODE
            fi
        else
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
    else
        echo "[-] Upload skipped: DEST or OUT not set, or output file not found"
        echo "[-] DEST: ${DEST:-'not set'}, OUT: ${OUT:-'not set'}, file exists: $([ -f "${OUT:-}" ] && echo "yes" || echo "no")"
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