#!/usr/bin/env bash
# ====================================================================
# Function: Backup website files and MySQL/MariaDB databases
# ====================================================================

# 發生錯誤時停止執行腳本，避免產生錯誤的空備份覆蓋原有數據
set -e
set -o pipefail

# 設定嚴格的預設權限，確保建立的備份檔只有擁有者可以讀寫 (600/700)
umask 077

# ==================== 設定區域 ====================
Host_name="host_name"
Backup_Home="/data/backup"
# LCMP
MySQL_Dump="/usr/bin/mariadb-dump"
# LNMP
# MySQL_Dump="/usr/local/mariadb/bin/mariadb-dump"

# 保留備份的天數
Keep_Days=7

######~ 資料庫備份設定 (1: 啟用; 0: 停用) ~######
Backup_All_Databases=1
Backup_Single_Databases=1

######~ 需要備份的網站目錄 ~######
Backup_Dir=(
    "/data/www/domain.com"
)

######~ 需要備份的非目錄檔案 ~######
Backup_Files=(
	"/data/name.txt"
)

######~ 需要備份的資料庫名稱 ~######
Backup_Database=(
    "database_name_1"
)

######~ 資料庫帳號與密碼 ~######
MYSQL_UserName='root'
MYSQL_PassWord='password'

######~ FTP 備份設定 (1: 啟用; 0: 停用) ~######
Enable_FTP=0 
FTP_Host='ftp.domain.com'
FTP_Username='username'
FTP_Password='password'
FTP_Dir="/"

# ==================== 變數初始化 ====================
TODAY=$(date +"%Y%m%d")
TodayWWWBackup="${TODAY}-${Host_name}-www.tar.gz"
TodayDBBackup="${TODAY}-${Host_name}-db.tar.gz"

export MYSQL_PWD="${MYSQL_PassWord}"

# ==================== 前置檢查 ====================
if [ ! -x "${MySQL_Dump}" ]; then  
    echo "錯誤: 找不到 ${MySQL_Dump} 或無執行權限，請檢查設定。" >&2
    exit 1
fi

mkdir -p "${Backup_Home}"

if [ "${Enable_FTP}" -eq 1 ] && ! command -v lftp >/dev/null 2>&1; then
    echo "錯誤: lftp 指令不存在。" >&2
    echo "安裝指令: CentOS: yum install lftp | Debian/Ubuntu: apt-get install lftp" >&2
    exit 1
fi

# ==================== 1. 備份網站檔案 ====================
echo "[$(date +'%H:%M:%S')] 開始備份網站檔案..."

TAR_ARGS=()

# 處理網站目錄
for dir in "${Backup_Dir[@]}"; do
    if [ -d "${dir}" ]; then
        # 利用 -C 參數切換目錄，避免打包時包含絕對路徑的根目錄結構
        TAR_ARGS+=("-C" "$(dirname "${dir}")" "$(basename "${dir}")")
    else
        echo "警告: 目錄 ${dir} 不存在，已跳過。" >&2
    fi
done

# 處理單一檔案
for file in "${Backup_Files[@]}"; do
    if [ -f "${file}" ]; then
        # 針對單一檔案一樣利用 -C 切換目錄，確保解壓縮時不會產生冗長的空資料夾結構
        TAR_ARGS+=("-C" "$(dirname "${file}")" "$(basename "${file}")")
    else
        echo "警告: 檔案 ${file} 不存在，已跳過。" >&2
    fi
done

if [ ${#TAR_ARGS[@]} -gt 0 ]; then
    # 使用 || true 是為了防止網站有日誌頻繁寫入時，tar 返回退出碼 1 (file changed as we read it) 導致腳本中斷
    tar -czf "${Backup_Home}/${TodayWWWBackup}" "${TAR_ARGS[@]}" || [ $? -eq 1 ]
    echo "[$(date +'%H:%M:%S')] 網站檔案打包完成: ${TodayWWWBackup}"
else
    echo "錯誤: 沒有找到任何可備份的網站目錄！" >&2
fi

# ==================== 2. 備份資料庫 ====================
echo "[$(date +'%H:%M:%S')] 開始備份資料庫..."

TMP_SQL_DIR="${Backup_Home}/tmp_sql_${TODAY}"
mkdir -p "${TMP_SQL_DIR}"

if [ "${Backup_All_Databases}" -eq 1 ]; then
    echo "  - 導出所有資料庫 (All Databases)..."
    "${MySQL_Dump}" -u"${MYSQL_UserName}" --all-databases --events --routines --triggers > "${TMP_SQL_DIR}/all_databases.sql"
fi

if [ "${Backup_Single_Databases}" -eq 1 ]; then
    for db in "${Backup_Database[@]}"; do
        echo "  - 導出指定資料庫: ${db}"
        "${MySQL_Dump}" -u"${MYSQL_UserName}" "${db}" --events --routines --triggers > "${TMP_SQL_DIR}/${db}.sql"
    done
fi

# 使用子 shell 進行目錄切換與打包，確保不會因為 cd 失敗而發生意外，並用 . 取代 * 避免參數過長
( cd "${TMP_SQL_DIR}" && tar -czf "${Backup_Home}/${TodayDBBackup}" . )

rm -rf "${TMP_SQL_DIR}"
echo "[$(date +'%H:%M:%S')] 資料庫打包完成: ${TodayDBBackup}"

# ==================== 3. 清理舊本地備份 ====================
echo "[$(date +'%H:%M:%S')] 刪除 ${Keep_Days} 天前的本地舊備份..."
find "${Backup_Home}" -type f -name "*-${Host_name}-*.tar.gz" -mtime +${Keep_Days} -delete

# ==================== 4. FTP 遠端備份 ====================
if [ "${Enable_FTP}" -eq 1 ]; then
    echo "[$(date +'%H:%M:%S')] 開始上傳備份至 FTP 伺服器..."

    # FTP 清理邏輯：這裡使用 lftp 的自帶指令來刪除遠端超過 Keep_Days 的檔案 (可選用)
	# 計算出需要刪除的舊備份日期與檔名 (例如 7 天前的日期)
    # DEL_DATE=$(date -d "-${Keep_Days} days" +"%Y%m%d")
    # DelWWWBackup="${DEL_DATE}-${Host_name}-www.tar.gz"
    # DelDBBackup="${DEL_DATE}-${Host_name}-db.tar.gz"
	
	# 執行 lftp 傳輸與清理
    # 加上 set xfer:clobber on 允許覆蓋同名檔案
    lftp -u "${FTP_Username},${FTP_Password}" "${FTP_Host}" << EOF
#set xfer:clobber on
cd "${FTP_Dir}"

# 1. 上傳今日的新備份
put "${Backup_Home}/${TodayWWWBackup}"
put "${Backup_Home}/${TodayDBBackup}"

# 2. 刪除舊備份 (使用 rm -f，即使該日期的檔案不存在也不會報錯中斷)
# rm -f "${DelWWWBackup}"
# rm -f "${DelDBBackup}"

bye
EOF
    echo "[$(date +'%H:%M:%S')] FTP 上傳完成."
fi

echo "[$(date +'%H:%M:%S')] 所有備份任務已順利完成！"

