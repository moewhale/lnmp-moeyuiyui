#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# 1. 优化 Root 检查：使用 $EUID 更可靠且执行更快
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: You must be root to run this script. Please use root to install." >&2
    exit 1
fi

. ../lnmp.conf
. ../include/main.sh
Get_Dist_Name
Get_Dist_Version

Press_Start

# 2. 优化依赖安装：合并安装包为一个命令，大幅缩短 yum/apt 处理事务的时间
echo "Installing dependencies..."
if [ "${PM}" = "yum" ]; then
    yum install -y python3 python3-setuptools python3-systemd iptables rsyslog
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart rsyslog
    else
        service rsyslog restart
    fi
elif [ "${PM}" = "apt" ]; then
    export DEBIAN_FRONTEND=noninteractive # 防止 apt 安装时弹出交互确认框
    apt-get update -y
    apt-get install -y python3 python3-setuptools iptables rsyslog
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart rsyslog
    else
        /etc/init.d/rsyslog restart
    fi
fi

# 提取版本号变量，方便日后升级
FAIL2BAN_VER="1.1.0"
FAIL2BAN_TAR="fail2ban-${FAIL2BAN_VER}.tar.gz"

echo "Downloading and Extracting..."
cd ../src || { echo "Error: Directory ../src does not exist."; exit 1; }

# 【修改这里】：直接使用官方 GitHub 的 Tags 源码链接，避开奇奇怪怪的文件名
# GitHub 会自动将该包打包提供，链接格式固定且可靠
DOWNLOAD_URL="https://github.com/fail2ban/fail2ban/archive/refs/tags/${FAIL2BAN_VER}.tar.gz"

# LNMP 的 Download_Files 会把下载下来的文件自动重命名为我们在第二个参数指定的 fail2ban-1.1.0.tar.gz
Download_Files "${DOWNLOAD_URL}" "${FAIL2BAN_TAR}"

# 确保旧的解压目录被清理
rm -rf "fail2ban-${FAIL2BAN_VER}"
# 解压，GitHub 默认解压出来的文件夹名字就是 fail2ban-1.1.0
tar zxf "${FAIL2BAN_TAR}" || { echo "Error: Failed to extract ${FAIL2BAN_TAR}."; exit 1; }
cd "fail2ban-${FAIL2BAN_VER}" || exit 1

echo "Installing fail2ban..."
# 使用现代的 pip 方式安装当前目录 (.) 的源码
# 如果遇到新版 Linux 系统的 PEP 668 全局环境锁定报错，则追加 --break-system-packages 参数
if ! python3 -m pip install . ; then
    echo "Modern Python environment detected. Using --break-system-packages..."
    python3 -m pip install . --break-system-packages
fi

echo "Configuring fail2ban..."
\cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i '/^#mode   = normal/a \
enabled  = true\
filter   = sshd\
maxretry = 5\
bantime  = 604800' /etc/fail2ban/jail.local

echo "Copying init files..."
# 4. 优化目录创建：直接使用 mkdir -p
mkdir -p /var/run/fail2ban

# 5. 优化 grep 检查：直接利用退出码和 -q 静默输出，不使用繁杂的反引号比较
if ! iptables -h | grep -q "\-w"; then
    sed -i 's/lockingopt =.*/lockingopt =/g' /etc/fail2ban/action.d/iptables-common.conf
fi

\cp build/fail2ban.service /etc/systemd/system/fail2ban.service

if [ "${PM}" = "yum" ]; then
    \cp files/redhat-initd /etc/init.d/fail2ban
    sed -i 's#^before = paths-debian.conf#before = paths-fedora.conf#' /etc/fail2ban/jail.local
    sed -i 's/^Environment="PYTHONNOUSERSITE=1"/#Environment="PYTHONNOUSERSITE=1"/' /etc/systemd/system/fail2ban.service
    sed -i 's/-xf start/-x start/' /etc/systemd/system/fail2ban.service
elif [ "${PM}" = "apt" ]; then
    \cp files/debian-initd /etc/init.d/fail2ban
fi
chmod +x /etc/init.d/fail2ban

# 清理无用源码
cd ..
rm -rf "fail2ban-${FAIL2BAN_VER}"

# 6. 优化服务启动：加入 daemon-reload 并优先使用 systemd 管理
StartUp fail2ban

echo "Starting fail2ban..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl start fail2ban
else
    /etc/init.d/fail2ban start
fi

echo "Fail2ban installation completed successfully."
