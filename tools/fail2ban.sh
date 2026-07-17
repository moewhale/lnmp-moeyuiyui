#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# 1. 检查是否为 Root 用户
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: You must be root to run this script." >&2
    exit 1
fi

. ../lnmp.conf
. ../include/main.sh
Get_Dist_Name
Get_Dist_Version

Press_Start

# 2. 安装系统依赖（移除 pip，因为我们要使用 setup.py）
echo "Installing dependencies..."
if [ "${PM}" = "yum" ]; then
    yum install -y python3 python3-setuptools python3-systemd iptables rsyslog
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart rsyslog
    else
        service rsyslog restart
    fi
elif [ "${PM}" = "apt" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y python3 python3-setuptools iptables rsyslog
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart rsyslog
    else
        /etc/init.d/rsyslog restart
    fi
fi

# 3. 设置版本号与官方 GitHub 下载地址
FAIL2BAN_VER="1.1.0"
FAIL2BAN_TAR="fail2ban-${FAIL2BAN_VER}.tar.gz"
DOWNLOAD_URL="https://github.com/fail2ban/fail2ban/archive/${FAIL2BAN_VER}.tar.gz"

echo "Downloading and Extracting..."
cd ../src || { echo "Error: Directory ../src does not exist."; exit 1; }

# 使用原生 wget 进行强健下载
if [ ! -s "${FAIL2BAN_TAR}" ]; then
    echo "Downloading fail2ban from GitHub..."
    wget -c -O "${FAIL2BAN_TAR}" "${DOWNLOAD_URL}"
fi

if [ ! -s "${FAIL2BAN_TAR}" ]; then
    echo "Error: Failed to download ${FAIL2BAN_TAR}. Please check your network connection."
    exit 1
fi

echo "Extracting..."
rm -rf "fail2ban-${FAIL2BAN_VER}"
tar zxf "${FAIL2BAN_TAR}" || { echo "Error: Failed to extract ${FAIL2BAN_TAR}."; exit 1; }
cd "fail2ban-${FAIL2BAN_VER}" || exit 1

# 4. 强行使用 setup.py 安装并适配现代系统
echo "Installing fail2ban via setup.py..."

# 【核心黑科技】：临时改名系统的 EXTERNALLY-MANAGED 标记，安全绕过 PEP-668 的全局锁定限制
EXT_MARKERS=$(find /usr/lib/python3* /usr/local/lib/python3* -maxdepth 2 -name "EXTERNALLY-MANAGED" 2>/dev/null)
for marker in $EXT_MARKERS; do
    mv "$marker" "${marker}.bak"
done

# 【核心修复】：必须带上 --prefix=/usr，Fail2ban 的安装脚本检测到它后才会把配置文件写入 /etc/fail2ban
python3 setup.py install --prefix=/usr

# 安装完成后立即还原 PEP-668 标记，保护系统 Python 环境
for marker in $EXT_MARKERS; do
    if [ -f "${marker}.bak" ]; then
        mv "${marker}.bak" "$marker"
    fi
done

# 5. 配置 Fail2ban
echo "Configuring fail2ban..."
\cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i '/^#mode   = normal/a \
enabled  = true\
filter   = sshd\
maxretry = 5\
bantime  = 604800' /etc/fail2ban/jail.local

echo "Copying init files..."
mkdir -p /var/run/fail2ban

if ! iptables -h | grep -q "\-w"; then
    sed -i 's/lockingopt =.*/lockingopt =/g' /etc/fail2ban/action.d/iptables-common.conf
fi

# 复制生成的 service 文件
\cp build/fail2ban.service /etc/systemd/system/fail2ban.service

if [ "${PM}" = "yum" ]; then
    \cp files/redhat-initd /etc/init.d/fail2ban
    sed -i 's#^before = paths-debian.conf#before = paths-fedora.conf#' /etc/fail2ban/jail.local
    sed -i 's/^Environment="PYTHONNOUSERSITE=1"/#Environment="PYTHONNOUSERSITE=1"/' /etc/systemd/system/fail2ban.service
    # 注意：这里删除了原脚本中错误的 `sed -i 's/-xf start/-x start/'`
elif [ "${PM}" = "apt" ]; then
    \cp files/debian-initd /etc/init.d/fail2ban
fi
chmod +x /etc/init.d/fail2ban

# 清理无用源码
cd ..
rm -rf "fail2ban-${FAIL2BAN_VER}"

# 6. 注册开机启动并启动服务
StartUp fail2ban

echo "Starting fail2ban..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl start fail2ban
else
    /etc/init.d/fail2ban start
fi

echo "Fail2ban installation completed successfully."
