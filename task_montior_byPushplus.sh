#!/bin/bash

# ========== 用户参数区 ==========
APPKEY="你的token"                            # 请替换为你从 https://www.pushplus.plus/ 获取的 token
USERNAME=$(id -un)                            # 当前用户
CHECK_SLURM_ONLY=0                            # =1时启用 SLURM 作业监控，=0时启用其他进程监控
SLURM_STATE_FILTER=("R")                      # 默认仅监控 Running 状态，可设为空 () 代表不过滤 (PENDING、RUNNING、COMPLETED、FAILED 等)
KEYWORDS=("lammps")                           # 默认无关键词过滤；如需筛选，设置为 ("train" "sim")。注意CHECK_SLURM_ONLY=0时，一定要设置关键词，否则会监控所有进程
INTERVAL=3600                                 # 每次检查间隔（秒）
MAX_RETRY=0                                   # 最大重试次数，0 表示无限次
ENABLE_VERBOSE=1                              # 是否记录详细日志
MAX_TASK_DISPLAY=10                           # 推送中最多展示多少个任务，超出显示省略号

# ========== 系统信息 & 日志 ==========
SERVER_IP=$(hostname -I | awk '{print $1}')
LOG_FILE="monitor.log"
LAST_TASK_SIGNATURE=""

# ========== 推送函数 ==========
function push_notification() {
    local task_count=$1
    local task_list_text="$2"
    local extra_info="$3"

    local msg_title="🖥️ 任务播报 - ${SERVER_IP}"
    local formatted_list=$(echo "$task_list_text" | sed 's/%0A/\n\n/g')
    local msg_content="### 🎯 任务更新通知\n\n- 📍 主机：\`${SERVER_IP}\`\n- 👤 用户：\`${USERNAME}\`\n- 📌 检测到 \`${task_count}\` 个匹配任务\n\n#### 当前任务列表：\n\n${formatted_list}\n\n> ${extra_info}"

    curl -s -X POST "https://www.pushplus.plus/send" -H "Content-Type: application/json" -d '{
        "token": "'"${APPKEY}"'",
        "title": "'"${msg_title}"'",
        "content": "'"${msg_content//\"/\\\"}"'",
        "template": "markdown"
    }' > /dev/null

    echo "[通知] 推送成功：${task_count} 个任务" | tee -a "$LOG_FILE"
    echo -e "$task_list_text\n$extra_info" > last_tasks.txt
}


# ========== 获取 SLURM 任务列表 ==========
function get_slurm_tasks() {
    local current_tasks=()
    local display_tasks=()
    local count=0
    local running_count=0
    local pending_count=0

    while IFS= read -r line; do
        jobid=$(echo "$line" | awk '{print $1}')
        state=$(echo "$line" | awk '{print $2}')
        state=$(echo "$state" | tr -d '\r[:space:]')
        elapsed=$(echo "$line" | awk '{print $3}')
        name=$(echo "$line" | cut -d' ' -f4-)

        # 关键词过滤
        if [ ${#KEYWORDS[@]} -gt 0 ]; then
            match_keyword=0
            for kw in "${KEYWORDS[@]}"; do
                [[ "$name" == *"$kw"* ]] && match_keyword=1 && break
            done
            [ $match_keyword -eq 0 ] && continue
        fi

        # 统计任务状态
        [[ "$state" == "R" ]] && ((running_count++))
        [[ "$state" == "PD" ]] && ((pending_count++))

                # 状态过滤
        if [ ${#SLURM_STATE_FILTER[@]} -gt 0 ]; then
            match_state=0
            for s in "${SLURM_STATE_FILTER[@]}"; do
                [ "$state" == "$s" ] && match_state=1 && break
            done
            [ $match_state -eq 0 ] && continue
        fi

        current_tasks+=("$jobid|$state|$name")
        display_tasks+=("$jobid [$state] $name - 用时 $elapsed")
        ((count++))
    done < <(squeue -u "$USERNAME" --noheader -o "%i %t %M %j")

    # 组装推送任务展示内容
    local task_output=""
    for ((i=0; i<${#display_tasks[@]}; i++)); do
        if [ "$i" -lt "$MAX_TASK_DISPLAY" ]; then
            task_output+="${display_tasks[$i]}"$'%0A'
        fi
    done
    if [ "$count" -gt "$MAX_TASK_DISPLAY" ]; then
        task_output+="... 等 ${count} 个任务"
    fi

    # 汇总信息：运行数 + 排队数
    local extra_info="运行中：${running_count}，排队中：${pending_count}"

    # 生成任务签名用于变更检测
    local task_signature=$(printf "%s\n" "${current_tasks[@]}" | sort | md5sum | awk '{print $1}')

    echo "$count|$task_output|$extra_info|$task_signature"
}



# ========= 获取其他任务列表 ==========
function get_other_tasks() {
    local current_tasks=()
    local display_tasks=()
    local count=0


    # 输出格式：pid etime cmd（cmd 可能包含空格，必须放最后）
    while IFS= read -r line; do
        pid=$(echo "$line" | awk '{print $1}')
        elapsed=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | cut -d' ' -f3-)

        # 关键词过滤
        if [ ${#KEYWORDS[@]} -gt 0 ]; then
            match_keyword=0
            for kw in "${KEYWORDS[@]}"; do
                [[ "$cmd" == *"$kw"* ]] && match_keyword=1 && break
            done
            [ $match_keyword -eq 0 ] && continue
        fi

        current_tasks+=("$pid|$cmd")
        display_tasks+=("PID $pid -- 用时 $elapsed -- $cmd")
        ((count++))
    done < <(ps -u "$USERNAME" -o pid,etime,cmd --no-headers)

    # 组装展示内容
    local task_output=""
    for ((i=0; i<${#display_tasks[@]}; i++)); do
        if [ "$i" -lt "$MAX_TASK_DISPLAY" ]; then
            task_output+="${display_tasks[$i]}"$'%0A'
        fi
    done
    if [ "$count" -gt "$MAX_TASK_DISPLAY" ]; then
        task_output+="... 等 ${count} 个任务"
    fi

    local extra_info="后台进程数：${count}"
    local task_signature=$(printf "%s\n" "${current_tasks[@]}" | sort | md5sum | awk '{print $1}')

    echo "$count|$task_output|$extra_info|$task_signature"
}





# ========== 主循环 ==========
echo "[启动] 监控 SLURM 作业（用户：$USERNAME，间隔 ${INTERVAL}s）..." | tee -a "$LOG_FILE"
RETRY_COUNT=0

while true; do
    if [ "$CHECK_SLURM_ONLY" -eq 1 ]; then
        result=$(get_slurm_tasks)
    else
        result=$(get_other_tasks)
    fi
    task_num=$(echo "$result" | cut -d"|" -f1)
    task_text=$(echo "$result" | cut -d"|" -f2)
    extra_text=$(echo "$result" | cut -d"|" -f3)
    CURRENT_TASK_SIGNATURE=$(echo "$result" | cut -d"|" -f4)

    if [ "$CURRENT_TASK_SIGNATURE" != "$LAST_TASK_SIGNATURE" ]; then
        push_notification "$task_num" "$task_text" "$extra_text"
        LAST_TASK_SIGNATURE="$CURRENT_TASK_SIGNATURE"
    else
        echo "[$(date '+%F %T')] [跳过] 无任务变动，任务数 $task_num" | tee -a "$LOG_FILE"
    fi

    ((RETRY_COUNT++))
    if [ "$MAX_RETRY" -ne 0 ] && [ "$RETRY_COUNT" -ge "$MAX_RETRY" ]; then
        echo "[退出] 达到最大检查次数 $MAX_RETRY 次" | tee -a "$LOG_FILE"
        break
    fi
    sleep "$INTERVAL"
done

# ========== 结束 ==========
echo "[$(date '+%F %T')] 任务监控脚本已结束" >> "$LOG_FILE"





# 强制退出可用
# pkill -f task_monitor_push.sh
