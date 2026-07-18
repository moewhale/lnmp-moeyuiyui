#!/usr/bin/env bash

# 1. 检查是否为 Root 用户
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: You must be root to run this script." >&2
    exit 1
fi

echo "Stopping fail2ban service..."
# 2. 停止服务并移除开机自启
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop fail2ban >/dev/null 2>&1
    systemctl disable fail2ban >/dev/null 2>&1
else
    /etc/init.d/fail2ban stop >/dev/null 2>&1
    # 兼容 sysvinit 的自启清理
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --del fail2ban >/dev/null 2>&1
    elif command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d -f fail2ban remove >/dev/null 2>&1
    fi
fi

echo "Removing system service files..."
# 3. 删除服务管理脚本
rm -f /etc/systemd/system/fail2ban.service
rm -f /etc/init.d/fail2ban
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
fi

echo "Removing configuration, logs, and runtime files..."
# 4. 删除配置、运行目录、数据库和日志
rm -rf /etc/fail2ban
rm -rf /var/run/fail2ban
rm -rf /var/lib/fail2ban
rm -f /var/log/fail2ban.log

echo "Removing fail2ban executables and Python libraries..."
# 5. 尝试通过 pip 卸载（如果 setup.py 注册了包信息）
if command -v pip3 >/dev/null 2>&1; then
    pip3 uninstall -y fail2ban >/dev/null 2>&1
fi

# 6. 暴力清理系统路径下的残留可执行文件和 Python 包库（双重保险）
rm -f /usr/bin/fail2ban-*
rm -f /usr/local/bin/fail2ban-*

# 寻找并删除 Python 环境下的 fail2ban 模块
# 根据系统的不同，可能安装在 site-packages 或 dist-packages
find /usr/lib/python3* /usr/local/lib/python3* -maxdepth 2 -type d \( -name "fail2ban" -o -name "fail2ban-*.egg-info" \) -exec rm -rf {} + 2>/dev/null

echo "Fail2ban has been completely uninstalled."
