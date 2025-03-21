#!/bin/bash

# Konfigurasi Telegram
TELEGRAM_BOT_TOKEN="<TOKEN-TELEGRAM>"
TELEGRAM_CHAT_ID="<CHAT-ID>"

# Konfigurasi Database untuk backup
datefolderku=$(date +'%Y-%m-%d')
db_user="admin"
db_password="`cat /etc/psa/.psa.shadow`"
backup_folder="/folder-sementara"
base_folder="/DRIVE-GOOGLE"
remote_name="<nama-rclone>"

# Konfigurasi Database untuk logging
LOG_DB_HOST="localhost"
LOG_DB_USER="<db-user>"
LOG_DB_PASSWORD="<password>"
LOG_DB_NAME="<db-name>"
LOG_DB_PORT="3306"

# Flag untuk mode fallback (tanpa logging database)
USE_DB_LOGGING=true

# Timestamp untuk log dan file
datetime=$(date +'%Y%m%d_%H%M%S')
log_filename="backup_log_${datetime}.txt"
detailed_log_filename="detailed_backup_log_${datetime}.txt"
stats_filename="user_stats_${datetime}.txt"

# Variabel untuk statistik global
total_successful_backups=0
total_failed_backups=0
total_db_count=0
total_user_count=0

# Fungsi untuk melakukan query ke database logging dengan penanganan error
exec_sql() {
    local query="$1"
    local fallback_value="$2"
    
    if [ "$USE_DB_LOGGING" = true ]; then
        # Coba jalankan query dengan timeout 5 detik
        local result=$(timeout 5 mysql -h"$LOG_DB_HOST" -P"$LOG_DB_PORT" -u"$LOG_DB_USER" -p"$LOG_DB_PASSWORD" -D"$LOG_DB_NAME" -e "$query" 2>/tmp/mysql_error.log)
        local exit_code=$?
        
        # Jika ada error, catat di log lokal dan kembalikan fallback value
        if [ $exit_code -ne 0 ]; then
            echo "MySQL Error (code $exit_code): $(cat /tmp/mysql_error.log)" >> "$backup_folder/mysql_errors.log"
            if [ -n "$fallback_value" ]; then
                echo "$fallback_value"
            fi
            return $exit_code
        fi
        
        echo "$result"
    else
        # Jika logging database tidak aktif, kembalikan fallback value
        if [ -n "$fallback_value" ]; then
            echo "$fallback_value"
        fi
        return 0
    fi
}

# Fungsi untuk escape string sebelum ditambahkan ke query SQL
escape_sql() {
    local str="$1"
    echo "${str//\'/\\\'}"
}

# Inisialisasi session backup di database
init_session() {
    local start_time=$(date +'%Y-%m-%d %H:%M:%S')
    local base_folder_escaped=$(escape_sql "$base_folder")
    local default_id="local_session_$(date +%s)"
    
    # Insert record untuk session baru dan dapatkan session_id
    local session_id=$(exec_sql "INSERT INTO backup_sessions (start_time, status, base_folder) VALUES ('$start_time', 'running', '$base_folder_escaped'); SELECT LAST_INSERT_ID();" "$default_id" | tail -n 1)
    
    echo "$session_id"
}

# Fungsi untuk mencatat log ke database atau file lokal
log_to_db() {
    local session_id="$1"
    local user_backup_id="$2"
    local database_backup_id="$3"
    local log_level="$4"
    local message=$(escape_sql "$5")
    local log_time=$(date +'%Y-%m-%d %H:%M:%S')
    
    # Atur nilai NULL untuk ID yang tidak ada
    [[ -z "$user_backup_id" ]] && user_backup_id="NULL"
    [[ -z "$database_backup_id" ]] && database_backup_id="NULL"
    
    if [ "$USE_DB_LOGGING" = true ]; then
        # Coba insert ke database
        exec_sql "INSERT INTO backup_logs (session_id, user_backup_id, database_backup_id, log_time, log_level, message) 
                  VALUES ($session_id, $user_backup_id, $database_backup_id, '$log_time', '$log_level', '$message')" >/dev/null 2>&1
        
        # Jika gagal, log ke file lokal
        if [ $? -ne 0 ]; then
            echo "[$log_time][$log_level] Session: $session_id, User: $user_backup_id, DB: $database_backup_id - $message" >> "$backup_folder/database_logs.log"
        fi
    else
        # Log ke file lokal
        echo "[$log_time][$log_level] Session: $session_id, User: $user_backup_id, DB: $database_backup_id - $message" >> "$backup_folder/database_logs.log"
    fi
}

# Fungsi untuk mencatat notifikasi Telegram ke database atau file lokal
log_telegram_notification() {
    local session_id="$1"
    local user_backup_id="$2"
    local database_backup_id="$3"
    local notification_type="$4"
    local message=$(escape_sql "$5")
    local status="$6"
    local send_time=$(date +'%Y-%m-%d %H:%M:%S')
    
    # Atur nilai NULL untuk ID yang tidak ada
    [[ -z "$user_backup_id" ]] && user_backup_id="NULL"
    [[ -z "$database_backup_id" ]] && database_backup_id="NULL"
    
    if [ "$USE_DB_LOGGING" = true ]; then
        # Coba insert ke database
        exec_sql "INSERT INTO telegram_notifications (session_id, user_backup_id, database_backup_id, send_time, notification_type, message, status) 
                  VALUES ($session_id, $user_backup_id, $database_backup_id, '$send_time', '$notification_type', '$message', '$status')" >/dev/null 2>&1
        
        # Jika gagal, log ke file lokal
        if [ $? -ne 0 ]; then
            echo "[$send_time][TELEGRAM][$status] Session: $session_id, Type: $notification_type - ${message:0:100}..." >> "$backup_folder/telegram_logs.log"
        fi
    else
        # Log ke file lokal
        echo "[$send_time][TELEGRAM][$status] Session: $session_id, Type: $notification_type - ${message:0:100}..." >> "$backup_folder/telegram_logs.log"
    fi
}

# Fungsi untuk mengirim pesan ke Telegram dan mencatatnya di database
send_telegram_message() {
    local session_id="$1"
    local user_backup_id="$2"
    local database_backup_id="$3"
    local notification_type="$4"
    local message="$5"
    
    # Kirim pesan ke Telegram
    local response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message" \
        -d parse_mode="HTML")
    
    # Cek status pengiriman
    if [[ $response == *"\"ok\":true"* ]]; then
        log_telegram_notification "$session_id" "$user_backup_id" "$database_backup_id" "$notification_type" "$message" "sent"
    else
        log_telegram_notification "$session_id" "$user_backup_id" "$database_backup_id" "$notification_type" "$message" "failed"
        # Log error
        log_to_db "$session_id" "$user_backup_id" "$database_backup_id" "error" "Failed to send Telegram notification: $response"
    fi
}

# Fungsi untuk menampilkan progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\rProgress: ["
    printf "%${completed}s" | tr ' ' '█'
    printf "%${remaining}s" | tr ' ' '.'
    printf "] %d%%" "$percentage"
}

# Fungsi untuk memulai backup user dan mencatatnya di database
init_user_backup() {
    local session_id="$1"
    local mysql_user="$2"
    local total_databases="$3"
    local user_folder="$4"
    local start_time=$(date +'%Y-%m-%d %H:%M:%S')
    local user_folder_escaped=$(escape_sql "$user_folder")
    local default_id="local_user_$(date +%s)"
    
    # Insert record untuk user backup baru dan dapatkan user_backup_id
    local user_backup_id=$(exec_sql "INSERT INTO user_backups (session_id, mysql_user, start_time, total_databases, user_folder) 
                VALUES ($session_id, '$mysql_user', '$start_time', $total_databases, '$user_folder_escaped'); 
                SELECT LAST_INSERT_ID();" "$default_id" | tail -n 1)
    
    echo "$user_backup_id"
}

# Fungsi untuk memperbarui status backup user
update_user_backup() {
    local user_backup_id="$1"
    local successful_backups="$2"
    local failed_backups="$3"
    local end_time=$(date +'%Y-%m-%d %H:%M:%S')
    
    exec_sql "UPDATE user_backups 
              SET end_time='$end_time', successful_backups=$successful_backups, failed_backups=$failed_backups 
              WHERE user_backup_id=$user_backup_id"
}

# Fungsi untuk mencatat backup database
log_database_backup() {
    local user_backup_id="$1"
    local session_id="$2"
    local database_name="$3"
    local status="$4"
    local file_size="$5"
    local backup_filename="$6"
    local error_message="$7"
    local start_time="$8"
    local end_time=$(date +'%Y-%m-%d %H:%M:%S')
    local backup_filename_escaped=$(escape_sql "$backup_filename")
    local error_message_escaped=$(escape_sql "$error_message")
    
    [[ -z "$file_size" ]] && file_size="NULL" || file_size="'$file_size'"
    [[ -z "$error_message" ]] && error_message_query="NULL" || error_message_query="'$error_message_escaped'"
    
    # Insert record untuk database backup dan dapatkan database_backup_id
    local database_backup_id=$(exec_sql "INSERT INTO database_backups (user_backup_id, session_id, database_name, start_time, end_time, status, file_size, backup_filename, error_message) 
                 VALUES ($user_backup_id, $session_id, '$database_name', '$start_time', '$end_time', '$status', $file_size, '$backup_filename_escaped', $error_message_query); 
                 SELECT LAST_INSERT_ID();" | tail -n 1)
    
    echo "$database_backup_id"
}

# Fungsi untuk memperbarui statistik session backup
update_session_stats() {
    local session_id="$1"
    local total_users="$2"
    local total_databases="$3"
    local successful_backups="$4"
    local failed_backups="$5"
    local status="$6"
    local end_time=$(date +'%Y-%m-%d %H:%M:%S')
    
    exec_sql "UPDATE backup_sessions 
              SET end_time='$end_time', status='$status', 
                  total_users=$total_users, total_databases=$total_databases, 
                  successful_backups=$successful_backups, failed_backups=$failed_backups 
              WHERE session_id=$session_id"
}

# Inisialisasi log file
mkdir -p "$backup_folder"
echo "=== Backup Log - Started at $(date) ===" | tee "$backup_folder/$log_filename" "$backup_folder/$detailed_log_filename"
echo "=== User Database Statistics ===" > "$backup_folder/$stats_filename"

# Cek koneksi ke database logging
echo "Testing connection to logging database..."
if mysql -h"$LOG_DB_HOST" -P"$LOG_DB_PORT" -u"$LOG_DB_USER" -p"$LOG_DB_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
    echo "Successfully connected to logging database at $LOG_DB_HOST" | tee -a "$backup_folder/$log_filename"
    USE_DB_LOGGING=true
else
    echo "WARNING: Cannot connect to logging database at $LOG_DB_HOST. Will continue with local logging only." | tee -a "$backup_folder/$log_filename"
    USE_DB_LOGGING=false
    # Buat session ID lokal
    SESSION_ID="local_$(date +%s)"
fi

# Inisialisasi session di database dan dapatkan session ID jika DB logging aktif
if [ "$USE_DB_LOGGING" = true ]; then
    SESSION_ID=$(init_session)
    log_to_db "$SESSION_ID" "" "" "info" "Backup session started"
else
    echo "[LOCAL LOG] Session started: $SESSION_ID" | tee -a "$backup_folder/$log_filename"
fi

# Kirim notifikasi awal ke Telegram
initial_message="🚀 <b>Database Backup Started</b>
📅 Date: $(date)
👥 Processing backups by user
🔄 Session ID: $SESSION_ID"

send_telegram_message "$SESSION_ID" "" "" "session_start" "$initial_message"

# Mendapatkan daftar user MySQL
mysql_users=$(mysql -u"$db_user" -p"$db_password" -e "SELECT DISTINCT User FROM mysql.db WHERE User NOT IN ('mysql.sys', 'debian-sys-maint', 'root', 'mysql');" | grep -v "User")

# Hitung total user
total_user_count=$(echo "$mysql_users" | wc -w)

# Loop untuk setiap user
for current_user in $mysql_users; do
    echo -e "\n\n👤 Processing user: $current_user" | tee -a "$backup_folder/$detailed_log_filename"
    log_to_db "$SESSION_ID" "" "" "info" "Processing user: $current_user"
    
    # Buat folder user di Google Drive
    user_folder="$base_folder/$current_user/$datefolderku"
    mkdir -p "$backup_folder/$current_user"
    
    # Mendapatkan daftar database untuk user ini
    user_databases=$(mysql -u"$db_user" -p"$db_password" -e "SELECT DISTINCT Db FROM mysql.db WHERE User='$current_user' AND Db NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys');" | grep -v "Db")
    total_databases=$(echo "$user_databases" | wc -w)
    total_db_count=$((total_db_count + total_databases))
    
    # Catat statistik user
    echo "User: $current_user - Total Databases: $total_databases" >> "$backup_folder/$stats_filename"
    
    # Inisialisasi user backup di database dan dapatkan ID
    if [ "$USE_DB_LOGGING" = true ]; then
        USER_BACKUP_ID=$(init_user_backup "$SESSION_ID" "$current_user" "$total_databases" "$user_folder")
    else
        USER_BACKUP_ID="local_user_$(date +%s)_$current_user"
        echo "[LOCAL LOG] User backup started: $USER_BACKUP_ID" | tee -a "$backup_folder/$log_filename"
    fi
    
    # Inisialisasi counter untuk user ini
    current_db=0
    successful_backups=0
    failed_backups=0
    
    # Kirim notifikasi per user ke Telegram
    user_message="👤 <b>Processing User: $current_user</b>
💾 Total Databases: $total_databases
🔄 User Backup ID: $USER_BACKUP_ID"
    
    send_telegram_message "$SESSION_ID" "$USER_BACKUP_ID" "" "user_start" "$user_message"
    
    # Loop untuk setiap database user
    for database in $user_databases; do
        ((current_db++))
        backup_filename="backup_${database}_${datetime}.sql.gz"
        
        # Update progress bar
        echo -e "\n🔄 Processing database ($current_db/$total_databases): $database"
        show_progress $current_db $total_databases
        
        # Log detail
        echo -e "\nBacking up database: $database" | tee -a "$backup_folder/$detailed_log_filename"
        echo "Started at: $(date)" | tee -a "$backup_folder/$detailed_log_filename"
        
        # Catat waktu mulai
        db_start_time=$(date +'%Y-%m-%d %H:%M:%S')
        
        # Variabel untuk error message
        error_message=""
        
        # Backup database
        if mysqldump -u"$db_user" -p"$db_password" "$database" 2> /tmp/mysqldump_error.log | gzip > "$backup_folder/$current_user/$backup_filename"; then
            # Cek apakah ada error
            if [ -s /tmp/mysqldump_error.log ]; then
                error_message=$(cat /tmp/mysqldump_error.log)
                cat /tmp/mysqldump_error.log >> "$backup_folder/$detailed_log_filename"
            fi
            
            # Get backup size
            backup_size=$(du -h "$backup_folder/$current_user/$backup_filename" | cut -f1)
            
            echo "Database $database backup completed. Size: $backup_size" | tee -a "$backup_folder/$detailed_log_filename"
            
            # Upload ke Google Drive dalam folder user
            echo "Uploading to Google Drive..." | tee -a "$backup_folder/$detailed_log_filename"
            if rclone move "$backup_folder/$current_user/$backup_filename" "$remote_name:$user_folder" --progress 2>> "$backup_folder/$detailed_log_filename"; then
                ((successful_backups++))
                total_successful_backups=$((total_successful_backups + 1))
                
                # Log ke file
                echo "✅ Successfully backed up and uploaded $database (Size: $backup_size)" | tee -a "$backup_folder/$log_filename"
                
                # Log ke database jika logging database aktif
                if [ "$USE_DB_LOGGING" = true ]; then
                    DB_BACKUP_ID=$(log_database_backup "$USER_BACKUP_ID" "$SESSION_ID" "$database" "successful" "$backup_size" "$backup_filename" "" "$db_start_time")
                    log_to_db "$SESSION_ID" "$USER_BACKUP_ID" "$DB_BACKUP_ID" "info" "Successfully backed up and uploaded database: $database (Size: $backup_size)"
                else
                    DB_BACKUP_ID="local_db_$(date +%s)_$database"
                    echo "[LOCAL LOG] Database backup successful: $DB_BACKUP_ID - Size: $backup_size" | tee -a "$backup_folder/$log_filename"
                fi
                
                # Kirim notifikasi ke Telegram setiap 10 database berhasil (untuk efisiensi)
                if (( successful_backups % 10 == 0 )) || (( current_db == total_databases )); then
                    db_message="✅ <b>Backup Progress</b>: $current_user
💾 Processed: $current_db/$total_databases
✅ Successful: $successful_backups
❌ Failed: $failed_backups"
                    
                    send_telegram_message "$SESSION_ID" "$USER_BACKUP_ID" "$DB_BACKUP_ID" "database_status" "$db_message"
                fi
            else
                ((failed_backups++))
                
                # Catat error dari rclone
                error_message="Failed to upload to Google Drive"
                
                # Log ke file
                echo "❌ Failed to upload $database to Google Drive" | tee -a "$backup_folder/$log_filename"
                
                # Log ke database jika logging database aktif
                if [ "$USE_DB_LOGGING" = true ]; then
                    DB_BACKUP_ID=$(log_database_backup "$USER_BACKUP_ID" "$SESSION_ID" "$database" "failed" "$backup_size" "$backup_filename" "$error_message" "$db_start_time")
                    log_to_db "$SESSION_ID" "$USER_BACKUP_ID" "$DB_BACKUP_ID" "error" "Failed to upload database to Google Drive: $database"
                else
                    DB_BACKUP_ID="local_db_$(date +%s)_$database"
                    echo "[LOCAL LOG] Database backup failed: $DB_BACKUP_ID - Error: Failed to upload to Google Drive" | tee -a "$backup_folder/$log_filename"
                fi
                
                # Notifikasi error ke Telegram
                error_message="❌ <b>Upload Error</b>: $current_user - $database
🔍 Error: Failed to upload to Google Drive"
                
                send_telegram_message "$SESSION_ID" "$USER_BACKUP_ID" "$DB_BACKUP_ID" "error" "$error_message"
            fi
        else
            ((failed_backups++))
            
            # Catat error dari mysqldump
            if [ -s /tmp/mysqldump_error.log ]; then
                error_message=$(cat /tmp/mysqldump_error.log)
                cat /tmp/mysqldump_error.log >> "$backup_folder/$detailed_log_filename"
            else
                error_message="Unknown error during mysqldump"
            fi
            
            # Log ke file
            echo "❌ Failed to backup $database: $error_message" | tee -a "$backup_folder/$log_filename"
            
            # Log ke database jika logging database aktif
            if [ "$USE_DB_LOGGING" = true ]; then
                DB_BACKUP_ID=$(log_database_backup "$USER_BACKUP_ID" "$SESSION_ID" "$database" "failed" "" "$backup_filename" "$error_message" "$db_start_time")
                log_to_db "$SESSION_ID" "$USER_BACKUP_ID" "$DB_BACKUP_ID" "error" "Failed to backup database: $database - $error_message"
            else
                DB_BACKUP_ID="local_db_$(date +%s)_$database"
                echo "[LOCAL LOG] Database backup failed: $DB_BACKUP_ID - Error: $error_message" | tee -a "$backup_folder/$log_filename"
            fi
            
            # Notifikasi error ke Telegram
            error_message="❌ <b>Backup Error</b>: $current_user - $database
🔍 Error: ${error_message:0:200}..."
            
            send_telegram_message "$SESSION_ID" "$USER_BACKUP_ID" "$DB_BACKUP_ID" "error" "$error_message"
        fi
        
        # Hapus file error temporari
        rm -f /tmp/mysqldump_error.log
    done
    
    # Update status backup user di database jika logging database aktif
    if [ "$USE_DB_LOGGING" = true ]; then
        update_user_backup "$USER_BACKUP_ID" "$successful_backups" "$failed_backups"
    else
        echo "[LOCAL LOG] User backup completed: $USER_BACKUP_ID - Success: $successful_backups, Failed: $failed_backups" | tee -a "$backup_folder/$log_filename"
    fi
    
    # Ringkasan per user
    user_summary="🔄 <b>User Backup Summary: $current_user</b>
📅 Date: $(date)
✅ Successful: $successful_backups
❌ Failed: $failed_backups
💾 Total: $total_databases
📂 Backup Location: $user_folder
🆔 User Backup ID: $USER_BACKUP_ID"
    
    send_telegram_message "$SESSION_ID" "$USER_BACKUP_ID" "" "user_end" "$user_summary"
    echo -e "\n$user_summary" >> "$backup_folder/$stats_filename"
    
    # Log ringkasan di database
    log_to_db "$SESSION_ID" "$USER_BACKUP_ID" "" "info" "User backup completed: $current_user ($successful_backups successful, $failed_backups failed)"
done

# Upload file statistik ke Google Drive
echo "Uploading statistics file..."
rclone move "$backup_folder/$stats_filename" "$remote_name:$base_folder/statistics"

# Upload log files ke folder statistik
echo "Uploading log files..."
rclone move "$backup_folder/$log_filename" "$remote_name:$base_folder/statistics"
rclone move "$backup_folder/$detailed_log_filename" "$remote_name:$base_folder/statistics"

# Update status session di database jika logging database aktif
if [ "$USE_DB_LOGGING" = true ]; then
    update_session_stats "$SESSION_ID" "$total_user_count" "$total_db_count" "$total_successful_backups" "$failed_backups" "completed"
else
    echo "[LOCAL LOG] Session completed: $SESSION_ID - Users: $total_user_count, DBs: $total_db_count, Success: $total_successful_backups, Failed: $failed_backups" | tee -a "$backup_folder/$log_filename"
fi

# Kirim ringkasan akhir ke Telegram
final_summary="📊 <b>Final Backup Statistics</b>
📅 Date: $(date)
👥 Total Users: $total_user_count
💾 Total Databases: $total_db_count
✅ Successfully Backed Up: $total_successful_backups
❌ Failed Backups: $failed_backups
🆔 Session ID: $SESSION_ID
📂 Base Folder: $base_folder"

send_telegram_message "$SESSION_ID" "" "" "session_end" "$final_summary"

# Log selesai
log_to_db "$SESSION_ID" "" "" "info" "Backup session completed ($total_successful_backups successful, $failed_backups failed)"

echo -e "\nBackup process completed!"
