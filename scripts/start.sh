#!/bin/bash
# 启动 KoishiPro（必须用 UTF-8 locale，否则中文卡组不进下拉列表、按钮中文空白）
export LC_ALL=C.utf8
export LANG=C.utf8
cd "$(dirname "$0")/.." || exit 1
# 默认安装在 ~/KoishiPro；若装在别处，改下面这行
cd ~/KoishiPro || exit 1
exec ./ygopro
