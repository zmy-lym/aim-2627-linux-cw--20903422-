#!/bin/bash
# Bonus：start 时创建分离的 tmux 会话和采集器；stop 时正常停止采集器并结束会话。
# 完整接口与验收规格见 Problem.pdf。只修改本文件，不修改测试或工具。
set -eu
input=${1:?需要输入目录}
output=${2:?需要输出目录}

action=${3:-start}

# TODO：删除下方提示和 exit 77，再填写你的命令。
source "$input/bonus.env"
if [ "$action" = "start" ]; then
    # 如果之前同名会话意外存在，先结束它，确保只启动一个实例。
    tmux -L "$TMUX_SOCKET" kill-session -t "$SESSION" 2>/dev/null || true

    # 创建 detached session。
    # sh -c 后面的命令会在 tmux 会话里执行；exec 让 shell 被 python3 进程替换。
    tmux -L "$TMUX_SOCKET" new-session -d -s "$SESSION" \
        "exec python3 '$WORKER_TOOL' --token '$TOKEN' --log '$output/bonus.log'"

elif [ "$action" = "stop" ]; then
    # 给指定会话发送 Ctrl-C，让里面的采集器正常处理 SIGINT/SIGTERM 逻辑。
    # 如果会话已经不存在，忽略错误，保持 cleanup 风格稳定。
    tmux -L "$TMUX_SOCKET" send-keys -t "$SESSION" C-c 2>/dev/null || true

    # 给程序一点时间写 STOP 日志并退出。
    sleep 0.2

    # 结束指定会话。只杀这个 session，不 kill-server，避免影响其他会话。
    tmux -L "$TMUX_SOCKET" kill-session -t "$SESSION" 2>/dev/null || true

else
    printf 'unknown action: %s\n' "$action" >&2
    exit 2
fi
