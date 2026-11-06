#!/bin/bash
# 一键重建 KoishiPro 远程游玩全套（云电脑重启后用这个恢复）。
# 用法：bash scripts/setup-remote.sh
# 完成后打印公开链接，用 curl 验证返回 200 后再发给人。
#
# 安全默认值（不要改回不安全的写法）：
# - VNC 必须输密码：Xvnc 用 -rfbauth + VncAuth，密码文件由 scripts/set-vnc-password.sh 生成。
#   绝不用 -SecurityTypes None（无密码时任何拿到链接的人都能操作桌面）。
# - noVNC 只监听本机 127.0.0.1:6080，不监听 0.0.0.0。
#   这样网页只能经 bore 隧道进来，不会直接暴露在云电脑的公网网卡上。
set -u
cd "$(dirname "$0")/.." || exit 1

KOISHI_DIR="${KOISHI_DIR:-$HOME/KoishiPro}"
NOVNC_DIR="${NOVNC_DIR:-$HOME/koishipro-download/novnc}"
BORE_BIN="${BORE_BIN:-$HOME/koishipro-download/bore}"
RELAY_PY="$(dirname "$0")/relay.py"
SET_PASSWD_SH="$(dirname "$0")/set-vnc-password.sh"
PASSWD_FILE="${VNC_PASSWD_FILE:-$HOME/.vnc/passwd}"
LOG_DIR="${LOG_DIR:-/tmp}"
DISPLAY_NUM=99
VNC_PORT=5900
WEB_PORT=6080

log() { echo "[setup-remote] $*"; }

# 0. VNC 密码文件：没有就生成一个随机的并打印出来（只生成一次，文件留在 ~/.vnc/passwd 里复用）
if [ ! -s "$PASSWD_FILE" ]; then
    log "没有 VNC 密码文件，正在生成（打开 noVNC 页面时要输这个密码）..."
    bash "$SET_PASSWD_SH" --random || { log "生成 VNC 密码失败"; exit 1; }
else
    log "VNC 密码文件已存在（$PASSWD_FILE），打开 noVNC 页面时输入该密码"
fi

# 1. 虚拟显示 + VNC（密码认证，绝不用 -SecurityTypes None）
if pgrep -x Xvnc >/dev/null; then
    log "Xvnc 已在运行"
else
    log "启动 Xvnc :${DISPLAY_NUM} ..."
    nohup Xvnc :${DISPLAY_NUM} -geometry 1024x640 -depth 24 \
        -rfbport ${VNC_PORT} -rfbauth "$PASSWD_FILE" -SecurityTypes VncAuth \
        > "${LOG_DIR}/xvnc99.log" 2>&1 &
    sleep 3
    pgrep -x Xvnc >/dev/null && log "Xvnc 已启动（密码认证）" || { log "Xvnc 启动失败，看 ${LOG_DIR}/xvnc99.log"; exit 1; }
fi

# 2. 游戏（必须带 UTF-8 locale，见 README 第 4 节）
if pgrep -x ygopro >/dev/null; then
    log "游戏已在运行"
else
    log "启动游戏 ..."
    (cd "$KOISHI_DIR" && DISPLAY=:${DISPLAY_NUM} LC_ALL=C.utf8 LANG=C.utf8 \
        nohup ./ygopro > "${LOG_DIR}/ygopro99.log" 2>&1 &)
    sleep 8
    pgrep -x ygopro >/dev/null && log "游戏已启动" || { log "游戏启动失败，看 ${LOG_DIR}/ygopro99.log"; exit 1; }
fi

# 3. 网页客户端 websockify + noVNC（只监听本机 127.0.0.1，不监听 0.0.0.0）
if [ ! -f "$NOVNC_DIR/vnc.html" ]; then
    log "没找到 noVNC（$NOVNC_DIR/vnc.html），先下载："
    log "  curl -L -o novnc.tar.gz https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.tar.gz"
    log "  tar xzf novnc.tar.gz && mv noVNC-1.5.0 <放到 $NOVNC_DIR>"
    exit 1
fi
if ss -tln 2>/dev/null | grep -q "127.0.0.1:${WEB_PORT} "; then
    log "websockify 已在监听 127.0.0.1:${WEB_PORT}"
else
    log "启动 websockify（仅本机）..."
    nohup python3 -m websockify --web="$NOVNC_DIR" 127.0.0.1:${WEB_PORT} 127.0.0.1:${VNC_PORT} \
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
        log "打开链接后会提示输入 VNC 密码（见上面的密码），输对才能进游戏画面"
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

log "完成。玩完后记得断开（见 README 第 9 节）。"
