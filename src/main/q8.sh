#!/bin/bash
# Q8：repair 时识别并停止采集器、修复 HTTP 服务；cleanup 时停止修复后的服务。
# 完整接口与验收规格见 Problem.pdf。只修改本文件，不修改测试或工具。
set -eu
input=${1:?需要输入目录}
output=${2:?需要输出目录}

action=${3:-repair}

# TODO：删除下方提示和 exit 77，再填写你的命令。
service_dir=$output/service

is_alive() {
    local pid=$1 state
    kill -0 "$pid" 2>/dev/null || return 1
    state=$(ps -o stat= -p "$pid" 2>/dev/null || true)
    case $state in
        '' | Z*) return 1 ;;
        *) return 0 ;;
    esac
}

# 发送 SIGTERM 正常停止进程，然后等待它真正退出（最多约 5 秒）。
stop_process() {
    local pid=$1
    kill -TERM "$pid" 2>/dev/null || true
    for _ in {1..50}; do
        is_alive "$pid" || return 0
        sleep 0.1
    done
    return 1
}

if [ "$action" = "cleanup" ]; then
    # cleanup：按 repair 阶段留下的记录停止修复后的服务，等待端口释放。
    if [ -f "$service_dir/pid" ]; then
        stop_process "$(cat "$service_dir/pid")" || true
    fi
    exit 0
fi

source "$input/process.env"

ps_line=$(ps -ww -o pid=,user=,state=,command= -p "$TARGET_PID")
read -r pid user state cmd <<< "$ps_line"
printf 'pid=%s\nuser=%s\nstate=%s\ncommand=%s\n' "$pid" "$user" "$state" "$cmd" > "$output/process.txt"


tail -n 2 "$WORKER_LOG" > "$output/collector-sample.log"

stop_process "$TARGET_PID"

stop_process "$SERVICE_PID"

printf 'bind=127.0.0.1\nport=%s\nroute=/status\n' "$TARGET_PORT" > "$output/server.conf"

bash "$START_TOOL" "$output/server.conf" "$service_dir"

http_code=000
for _ in {1..40}; do
    http_code=$(curl -s --max-time 1 -o "$output/http-body.txt" \
        -w '%{http_code}' "http://127.0.0.1:$TARGET_PORT/status") || true
    if [ "$http_code" = "200" ]; then
        break
    fi
    sleep 0.1
done
printf '%s\n' "$http_code" > "$output/http-status.txt"
if [ "$http_code" != "200" ]; then
    printf '%s\n' 'service did not become ready' >&2
    exit 1
fi


