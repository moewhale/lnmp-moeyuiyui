#!/bin/bash
# Redis 8.4 & phpredis 6.3.0 自動化工具
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# 檢查 root 權限
if [ $(id -u) != "0" ]; then
    echo "錯誤: 必須使用 root 權限執行此指令碼。"
    exit 1
fi

# 版本與路徑設定
LATEST_REDIS="8.4.0"
LATEST_PHPREDIS="6.3.0"
INSTALL_DIR="/usr/local/redis"
PHP_CONF_D="/usr/local/php/conf.d"
REDIS_INI="$PHP_CONF_D/007-redis.ini"

clear
echo "======================================================================="
echo "Redis 8.4 安裝與清理工具 (PHP conf.d 模式)"
echo "======================================================================="

# 1. 檢測並強制刪除舊版本與設定
if [ -d "$INSTALL_DIR" ] || [ -f "$REDIS_INI" ]; then
    echo "系統檢測：存在舊版 Redis 或 PHP 設定檔。"
    
    # 停止服務
    systemctl stop redis >/dev/null 2>&1
    
    # 移除 Redis 目錄、服務文件以及 PHP 獨立設定檔
    rm -rf "$INSTALL_DIR"
    rm -f /etc/systemd/system/redis.service
    rm -f "$REDIS_INI"
    echo "舊版本目錄與 $REDIS_INI 已徹底移除。"
else
    echo "系統檢測：環境潔淨，準備開始安裝。"
fi

# 2. 版本選擇
echo "-----------------------------------------------------------------------"
echo "目前建議版本：Redis $LATEST_REDIS / phpredis $LATEST_PHPREDIS"
read -p "請輸入欲安裝的 Redis 版本號 (直接回車則安裝 $LATEST_REDIS): " USER_REDIS_VER
REDIS_VER=${USER_REDIS_VER:-$LATEST_REDIS}

# 3. 安裝 Redis 8.4 主程式
echo "正在下載並編譯 Redis $REDIS_VER..."
wget -c "https://download.redis.io/releases/redis-${REDIS_VER}.tar.gz"
tar zxf "redis-${REDIS_VER}.tar.gz"
cd "redis-${REDIS_VER}/"
make PREFIX=$INSTALL_DIR install

# 配置初始化
mkdir -p $INSTALL_DIR/etc/
cp redis.conf $INSTALL_DIR/etc/
sed -i 's/daemonize no/daemonize yes/g' $INSTALL_DIR/etc/redis.conf
cd ../

# 4. 編譯 PHP Redis 擴充並建立 007-redis.ini
# 注意 php 路徑
echo "正在編譯 phpredis $LATEST_PHPREDIS..."
wget -c "https://pecl.php.net/get/redis-${LATEST_PHPREDIS}.tgz"
tar zxf "redis-${LATEST_PHPREDIS}.tgz"
cd "redis-${LATEST_PHPREDIS}/"
/usr/local/php/bin/phpize
./configure --with-php-config=/usr/local/php/bin/php-config
make && make install
cd ../

# 建立獨立設定檔
mkdir -p "$PHP_CONF_D"
echo "extension = \"redis.so\"" > "$REDIS_INI"
echo "已建立 PHP 設定檔: $REDIS_INI"

# 5. 建立 Systemd 服務管理
cat > /etc/systemd/system/redis.service <<EOF
[Unit]
Description=Redis In-Memory Data Store (Version $REDIS_VER)
After=network.target

[Service]
Type=forking
ExecStart=$INSTALL_DIR/bin/redis-server $INSTALL_DIR/etc/redis.conf
ExecStop=$INSTALL_DIR/bin/redis-cli shutdown
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 啟動新版服務
systemctl daemon-reload
systemctl enable redis
systemctl restart redis

# 重啟 PHP-FPM 以載入新設定
systemctl restart php-fpm >/dev/null 2>&1

echo "======================================================================="
echo "安裝與配置完成！"
echo "Redis 版本: $REDIS_VER"
echo "PHP 設定檔: $REDIS_INI"
echo "服務狀態: $(systemctl is-active redis)"
echo "======================================================================="
