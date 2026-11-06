#!/bin/bash
# 设置 VNC 密码，写入 ~/.vnc/passwd，供 Xvnc -rfbauth 使用。
# 用法：
#   bash scripts/set-vnc-password.sh            # 交互式输入两次密码（推荐，自己定一个好记的）
#   bash scripts/set-vnc-password.sh --random   # 生成一个随机 8 位密码并打印出来
#   bash scripts/set-vnc-password.sh <密码>     # 直接指定密码（会进 shell 历史，不推荐）
#
# 需要 vncpasswd（tightvncpasswd 或 tigervnc-tools 提供）。
# 没有会自动尝试安装；装不上就报错退出，绝不悄悄回退到无密码。
set -u
PASSWD_FILE="${VNC_PASSWD_FILE:-$HOME/.vnc/passwd}"
mkdir -p "$(dirname "$PASSWD_FILE")"

if ! command -v vncpasswd >/dev/null 2>&1; then
  echo "[set-vnc-password] 未找到 vncpasswd，尝试安装 tightvncpasswd ..."
  if sudo -n apt-get install -y tightvncpasswd >/dev/null 2>&1; then
    echo "[set-vnc-password] 已安装 vncpasswd"
  else
    echo "[set-vnc-password] 安装失败。请手动安装后再试："
    echo "  Debian/Ubuntu: sudo apt install -y tightvncpasswd"
    echo "  （或安装提供 vncpasswd 的 tigervnc-tools）"
    exit 1
  fi
fi

if [ "${1:-}" = "--random" ]; then
  PW="$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 8)"
  printf '%s\n%s\n' "$PW" "$PW" | vncpasswd "$PASSWD_FILE" >/dev/null 2>&1
  chmod 600 "$PASSWD_FILE"
  echo "[set-vnc-password] 已生成随机 VNC 密码（8 位）。打开 noVNC 页面时输入这个密码："
  echo "$PW"
elif [ -n "${1:-}" ]; then
  printf '%s\n%s\n' "$1" "$1" | vncpasswd "$PASSWD_FILE" >/dev/null 2>&1
  chmod 600 "$PASSWD_FILE"
  echo "[set-vnc-password] VNC 密码已写入 $PASSWD_FILE"
else
  echo "[set-vnc-password] 输入 VNC 密码（打开 noVNC 页面时要输这个密码）："
  vncpasswd "$PASSWD_FILE"
  chmod 600 "$PASSWD_FILE"
  echo "[set-vnc-password] VNC 密码已写入 $PASSWD_FILE"
fi
