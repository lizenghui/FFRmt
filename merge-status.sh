#!/bin/bash

# 合并所有.status.json文件到all-tasks.json
OUTPUT_FILE="tasks.json"

echo "[+] 开始合并状态文件..."

# 初始化JSON数组
echo "[" > "$OUTPUT_FILE"
FIRST=true

# 查找所有.status.json文件
for file in *.status.json; do
    if [[ -f "$file" ]]; then
        task_id=$(basename "$file" .status.json)
        echo "[+] 处理任务: $task_id"
        
        if [[ "$FIRST" == "true" ]]; then
            FIRST=false
        else
            echo "," >> "$OUTPUT_FILE"
        fi
        
 
        cat "$file" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
done

echo "" >> "$OUTPUT_FILE"
echo "]" >> "$OUTPUT_FILE"

echo "[+] 合并完成，输出文件: $OUTPUT_FILE"