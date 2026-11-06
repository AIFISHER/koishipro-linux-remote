#!/bin/bash
# 一键重建 KoishiPro 远程游玩全套（云电脑重启后用这个恢复）。
# 用法：bash scripts/setup-remote.sh
# 完成后打印公开链接，用 curl 验证返回 200 后再发给人。
set -u
cd "$(dirname "$0")/.." || exit 1

KOISHI_DIR="${KOISHI_DIR:-$HOME/KoishiPro}"
NOVNC_DIR="${NOVNC_DIR:-$HOME/koishipro-download/novnc}"
BORE_BIN="${BORE_BIN:-$HOME/koishipro-download/bore}"
RELAY_PY="$(dirname "$0")/relay.py"
LOG_DIR="${LOG_DIR:-/tmp}"
DISPLAY_NUM=99
VNC_PORT=5900
WEB_PORT=6080

log() { echo "[setup-remote] $*"; }

# 1. 虚拟显示 + VNC（无密码，访问控制只靠随机隧道链接）
if pgrep -x Xvnc >/dev/null; then
    log "Xvnc 已在运行"
else
    log "启动 Xvnc :${DISPLAY_NUM} ..."
    nohup Xvnc :${DISPLAY_NUM} -geometry 1024x640 -depth 24 \
        -rfbport ${VNC_PORT} -SecurityTypes None \
        > "${LOG_DIR}/xvnc99.log" 2>&1 &
    sleep 3
    pgrep -x Xvnc >/dev/null && log "Xvnc 已启动" || { log "Xvnc 启动失败，看 ${LOG_DIR}/xvnc99.log"; exit 1; }
fi

# 2. 游戏（必须带 UTF-8 locale，见 README 第 3 节）
if pgrep -x ygopro >/dev/null; then
    log "游戏已在运行"
else
    log "启动游戏 ..."
    (cd "$KOISHI_DIR" && DISPLAY=:${DISPLAY_NUM} LC_ALL=C.utf8 LANG=C.utf8 \
        nohup ./ygopro > "${LOG_DIR}/ygopro99.log" 2>&1 &)
    sleep 8
    pgrep -x ygopro >/dev/null && log "游戏已启动" || { log "游戏启动失败，看 ${LOG_DIR}/ygopro99.log"; exit 1; }
fi

# 3. 网页客户端 websockify + noVNC
if [ ! -f "$NOVNC_DIR/vnc.html" ]; then
    log "没找到 noVNC（$NOVNC_DIR/vnc.html），先下载："
    log "  curl -L -o novnc.tar.gz https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.tar.gz"
    log "  tar xzf novnc.tar.gz && mv noVNC-1.5.0 <放到 $NOVNC_DIR>"
    exit 1
fi
if ss -tln 2>/dev/null | grep -q ":${WEB_PORT} "; then
    log "websockify 已在监听 ${WEB_PORT}"
else
    log "启动 websockify ..."
    nohup python3 -m websockify --web="$NOVNC_DIR" 0.0.0.0:${WEB_PORT} 127.0.0.1:${VNC_PORT} \
        > "${LOG_DIR}/websockify.log" 2>&1 &
    sleep 3
    curl -s -o /dev/null "http://127.0.0.1:${WEB_PORT}/vnc.html" \
        && log "本机 noVNC 已通 (http://127.0.0.1:${WEB_PORT}/vnc.html)" \
        || { log "websockify 启动失败，看 ${LOG_DIR}/websockify.log"; exit 1; }
fi

# 4. 中继 + bore 隧道
if ! pgrep -f "rela[y].py" >/dev/null; then
    log "启动 bore 中继 ..."
    nohup python3 "$RELAY_PY" > "${LOG_DIR}/relay.log" 2>&1 &
    sleep 2
fi
if pgrep -x bore >/dev/null; then
    log "bore 已在运行，复用已有隧道（端口见旧日志）"
    grep -o "remote_port=[0-9]*" "${LOG_DIR}/bore.log" 2>/dev/null | tail -1
else
    log "启动 bore ..."
    nohup "$BORE_BIN" local ${WEB_PORT} --to 127.0.0.1 > "${LOG_DIR}/bore.log" 2>&1 &
    sleep 8
    PORT=$(grep -o "remote_port=[0-9]*" "${LOG_DIR}/bore.log" 2>/dev/null | tail -1 | cut -d= -f2)
    if [ -n "$PORT" ]; then
        LINK="http://bore.pub:${PORT}/vnc.html?autoconnect=true&resize=scale"
        log "公开链接：$LINK"
        if curl -s -o /dev/null --max-time 15 "$LINK"; then
            log "链接验证通过（HTTP 200），可以直接发给人了"
        else
            log "链接暂时打不开，等几秒再试：$LINK"
        fi
    else
        log "没拿到 bore 端口，看 ${LOG_DIR}/bore.log"
        exit 1
    fi
fi

log "完成。玩完后记得断开（见 README 第 8 节）。"
