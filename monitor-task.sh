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

# 监控配置
CHECK_INTERVAL=2    # 检查间隔（秒）
STATUS_FILE="status.json"
STATUS_REMOTE="$FFRMT_STATUS_REMOTE"  # 远程状态存储路径

# 获取任务目录和主进程PID
TASK_DIR="${1:-$(pwd)}"
MAIN_PID="${2:-}"  # 主进程PID
TASK_ID=$(basename "$TASK_DIR")

# 切换到任务目录
cd "$TASK_DIR" || {
    echo "[-] Failed to change to task directory: $TASK_DIR"
    exit 1
}

DOWNLOAD_LOG="downloads.log"
FFMPEG_LOG="ffmpeg.log"
UPLOAD_LOG="upload.log"

echo "[+] Monitoring task: $TASK_ID"
echo "[+] Working in directory: $(pwd)"

while true; do
    # 检查主进程是否还存在
    if [[ -n "$MAIN_PID" ]] && ! kill -0 "$MAIN_PID" 2>/dev/null; then
        echo "[-] Main process (PID: $MAIN_PID) no longer exists, exiting monitor..."
        exit 0
    fi
    
    # 获取下载状态
    DOWNLOAD_STATUS="not_started"
    DOWNLOAD_PROGRESS="0%"
    DOWNLOAD_SPEED=""
    
    if [[ -f "$DOWNLOAD_LOG" ]]; then
        # 获取最后几行日志
        LAST_DOWNLOAD=$(tail -n 10 "$DOWNLOAD_LOG" 2>/dev/null || echo "")
        
        # 分析下载状态
        if echo "$LAST_DOWNLOAD" | grep -q "100%"; then
            DOWNLOAD_STATUS="completed"
            DOWNLOAD_PROGRESS="100%"
        elif echo "$LAST_DOWNLOAD" | grep -q "%"; then
            DOWNLOAD_STATUS="downloading"
            # 提取进度百分比
            DOWNLOAD_PROGRESS=$(echo "$LAST_DOWNLOAD" | grep -o '[0-9]\+%' | tail -n 1 || echo "0%")
            DOWNLOAD_SPEED=$(echo "$LAST_DOWNLOAD" | grep -o '[0-9]\+%[[:space:]]*\([0-9.]\+[KM]\)' | sed 's/.*[[:space:]]\([0-9.]\+[KM]\)/\1\/s/' | tail -n 1 || echo "")
        else
            DOWNLOAD_STATUS="downloading"
        fi
    fi
    
    # 获取转码状态
    FFMPEG_STATUS="not_started"
    FFMPEG_PROGRESS="0%"
    FFMPEG_SPEED=""
  
    
    if [[ -f "$FFMPEG_LOG" ]]; then
        LAST_FFMPEG=$(tail -n 20 "$FFMPEG_LOG" 2>/dev/null | grep -E "frame=.*fps=.*size=.*time=.*speed=" | tail -n 1 || echo "")
        
        if [[ -z "${TOTAL_DURATION:-}" ]] && [[ -f "$FFMPEG_LOG" ]]; then
            TOTAL_DURATION=$(grep -o "Duration: [0-9:.]*" "$FFMPEG_LOG" 2>/dev/null | head -n 1 | sed 's/Duration: //' || echo "")
            if [[ -n "$TOTAL_DURATION" ]]; then
                echo "[+] Got video total duration: $TOTAL_DURATION"
            fi
        fi
        
        # 分析转码状态 - 改进的完成状态识别
        # 检查是否有完成的最终标志
        if grep -q "video:[0-9]\+KiB audio:" "$FFMPEG_LOG" 2>/dev/null || grep -q "muxing overhead:" "$FFMPEG_LOG" 2>/dev/null; then
            FFMPEG_STATUS="completed"
            FFMPEG_PROGRESS="100%"
            FFMPEG_SPEED=$(echo "$LAST_FFMPEG" | grep -o "speed=[0-9.]*x" | sed 's/speed=//' || echo "")
        elif [[ -n "$LAST_FFMPEG" ]]; then
            # 转码进行中，提取进度信息
            FFMPEG_STATUS="transcoding"
            
            # 提取速度（从speed=字段，保持x后缀）
            FFMPEG_SPEED=$(echo "$LAST_FFMPEG" | grep -o "speed=[0-9.]*x" | sed 's/speed=//' || echo "")
            
            # 提取当前时间（从time=字段）
            CURRENT_TIME=$(echo "$LAST_FFMPEG" | grep -o "time=[0-9:.]*" | sed 's/time=//' || echo "")
            
            # 计算进度百分比
            if [[ -n "$CURRENT_TIME" ]] && [[ -n "$TOTAL_DURATION" ]]; then
                # 将时间转换为秒数进行比较
                CURRENT_SECONDS=$(echo "$CURRENT_TIME" | awk -F: '{print int(($1 * 3600) + ($2 * 60) + $3)}')
                TOTAL_SECONDS=$(echo "$TOTAL_DURATION" | awk -F: '{print int(($1 * 3600) + ($2 * 60) + $3)}')
                
                if [[ -n "$CURRENT_SECONDS" ]] && [[ -n "$TOTAL_SECONDS" ]] && [[ "$TOTAL_SECONDS" -gt 0 ]]; then
                    FFMPEG_PROGRESS=$(awk "BEGIN {printf \"%.1f%%\", ($CURRENT_SECONDS / $TOTAL_SECONDS) * 100}")
                else
                    FFMPEG_PROGRESS="0%"
                fi
            else
                FFMPEG_PROGRESS="0%"
            fi
        elif grep -q "Lsize=" "$FFMPEG_LOG" 2>/dev/null && grep -q "speed=" "$FFMPEG_LOG" 2>/dev/null; then
            # 有基本输出但无最新帧信息，可能是刚完成或刚开始
            FFMPEG_STATUS="transcoding"
            FFMPEG_PROGRESS="0%"
        else
            FFMPEG_STATUS="not_started"
            FFMPEG_PROGRESS="0%"
        fi
    fi
    
    UPLOAD_STATUS="not_started"
    UPLOAD_PROGRESS="0%"
    UPLOAD_SPEED=""

    
    if [[ -f "$UPLOAD_LOG" ]]; then
        # 获取最后几行日志
        LAST_UPLOAD=$(tail -n 30 "$UPLOAD_LOG" 2>/dev/null || echo "")
        
        # 分析上传状态 - 基于实际rclone日志格式
        
        # 1. 检查是否完成（文件计数完成）
        if echo "$LAST_UPLOAD" | grep -q "Transferred:.*1 / 1, 100%"; then
            UPLOAD_STATUS="completed"
            UPLOAD_PROGRESS="100%"
            # 尝试从完成行提取速度
            COMPLETED_LINE=$(echo "$LAST_UPLOAD" | grep "Transferred:.*1 / 1, 100%" | tail -n 1)
            UPLOAD_SPEED=$(echo "$COMPLETED_LINE" | grep -o '[0-9.]\+ MiB\/s' | sed 's/ MiB\/s//' | tail -n 1 || echo "")
            
        # 2. 检查是否正在传输
        elif echo "$LAST_UPLOAD" | grep -q "Transferring:"; then
            UPLOAD_STATUS="uploading"
            
            # 获取最后一个完整的Transferring块
            # 从Transferring:开始，到下一个非Transferring行结束
            TRANSFERRING_BLOCK=$(echo "$LAST_UPLOAD" | awk '
                /Transferring:/ {block=""; in_block=1}
                in_block {block = block $0 "\n"}
                !/Transferring:/ && in_block && !/^[[:space:]]*\*/ {in_block=0; print block; exit}
            ' | tail -n 1)
            
            if [[ -n "$TRANSFERRING_BLOCK" ]]; then
                # 从文件名行提取进度（格式： * filename: XX%）
                UPLOAD_PROGRESS=$(echo "$TRANSFERRING_BLOCK" | grep '\*.*:' | grep -o '[0-9]\+%' | head -n 1 || echo "0%")
                
                # 从文件名行提取速度（格式：XX.XXXMi/s）
                UPLOAD_SPEED=$(echo "$TRANSFERRING_BLOCK" | grep '\*.*:' | grep -o '[0-9.]\+Mi\/s' | head -n 1 || echo "")
            fi
            
            # 如果没有从文件名提取到进度，尝试从总传输行提取
            if [[ "$UPLOAD_PROGRESS" == "0%" ]]; then
                LAST_TRANSFERRED=$(echo "$LAST_UPLOAD" | grep "Transferred:" | grep -v "0 / 1" | tail -n 1)
                if [[ -n "$LAST_TRANSFERRED" ]]; then
                    UPLOAD_PROGRESS=$(echo "$LAST_TRANSFERRED" | grep -o '[0-9]\+%' | tail -n 1 || echo "0%")
                    UPLOAD_SPEED=$(echo "$LAST_TRANSFERRED" | grep -o '[0-9.]\+ MiB\/s' | sed 's/ MiB\/s//' | tail -n 1 || echo "")
                fi
            fi
            
        # 3. 只有Transferred行，没有Transferring
        elif echo "$LAST_UPLOAD" | grep -q "Transferred:"; then
            UPLOAD_STATUS="uploading"
            
            # 从最后一行有效的Transferred提取信息
            LAST_TRANSFERRED=$(echo "$LAST_UPLOAD" | grep "Transferred:" | grep -v "0 / 1, 0%" | tail -n 1)
            if [[ -n "$LAST_TRANSFERRED" ]]; then
                UPLOAD_PROGRESS=$(echo "$LAST_TRANSFERRED" | grep -o '[0-9]\+%' | tail -n 1 || echo "0%")
                UPLOAD_SPEED=$(echo "$LAST_TRANSFERRED" | grep -o '[0-9.]\+ MiB\/s' | tail -n 1 || echo "")
            fi
            
        else
            UPLOAD_STATUS="not_started"
        fi
    fi

    # 构建JSON状态（简化版，无jq依赖）
    STATUS_JSON="{
    \"task_id\": \"$TASK_ID\",
    \"timestamp\": \"$(date -Iseconds)\",
    \"download\": {
        \"status\": \"$DOWNLOAD_STATUS\",
        \"progress\": \"$DOWNLOAD_PROGRESS\",
        \"speed\": \"$DOWNLOAD_SPEED\"
    },
    \"ffmpeg\": {
        \"status\": \"$FFMPEG_STATUS\",
        \"progress\": \"$FFMPEG_PROGRESS\",
        \"speed\": \"$FFMPEG_SPEED\"
    },
    \"upload\": {
        \"status\": \"$UPLOAD_STATUS\",
        \"progress\": \"$UPLOAD_PROGRESS\",
        \"speed\": \"$UPLOAD_SPEED\"
    }
    }"
    
    # 写入状态文件
    echo "$STATUS_JSON" > "$STATUS_FILE"
    
    # 上传状态文件到远程位置
    if [[ -n "$STATUS_REMOTE" ]]; then
       REMOTE_STATUS_FILE="$STATUS_REMOTE/$TASK_ID.status.json"
       
       rclone copyto "$STATUS_FILE" "$REMOTE_STATUS_FILE" --no-traverse --ignore-times --ignore-size
    fi
    
    echo "[+] Status updated: $STATUS_FILE"

    sleep $CHECK_INTERVAL
done