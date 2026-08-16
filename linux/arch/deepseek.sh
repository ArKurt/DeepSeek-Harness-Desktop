#!/bin/sh
# DeepSeek Desktop (Arch/Garuda 包版本) 启动器。
# 应用代码装在 /opt/deepseek/app，dsh bundle 装在 /opt/deepseek/runtime/bundle，
# Node 使用系统 nodejs，Electron 使用 Arch 官方 electron 包。
exec /usr/bin/electron /opt/deepseek/app "$@"
