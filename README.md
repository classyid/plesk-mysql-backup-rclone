# Plesk MySQL Backup System

![GitHub](https://img.shields.io/github/license/yourusername/plesk-mysql-backup-rclone)
![Bash](https://img.shields.io/badge/language-bash-green.svg)
![Plesk](https://img.shields.io/badge/platform-plesk-blue.svg)

A comprehensive solution for automated MySQL database backups from Plesk Panel with real-time Telegram notifications, robust logging, and Google Drive integration via rclone.

## 🚀 Features

- **User-based Backup Architecture**: Organizes backups by MySQL user and database
- **Real-time Telegram Notifications**: Sends notifications throughout the backup process 
- **Comprehensive Logging System**: Maintains detailed logs in both MySQL database and text files
- **Google Drive Integration**: Automatically uploads backups to Google Drive using rclone
- **Progress Visualization**: Displays progress bar during backup operation
- **Error Handling & Fallback System**: Maintains operation even when primary logging fails
- **Detailed Statistics**: Generates comprehensive statistics for each backup session

## 📋 Prerequisites

- Plesk Panel server with root access
- MySQL/MariaDB server
- rclone configured with a remote for Google Drive
- Telegram Bot Token & Chat ID
- MySQL database for logging (optional, system works in fallback mode without it)

## 🔧 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/plesk-mysql-backup-rclone.git
   cd plesk-mysql-backup-rclone
   ```

2. Make the script executable:
   ```bash
   chmod +x backup.sh
   ```

3. Configure the script by editing variables in the configuration section:
   ```bash
   nano backup.sh
   ```

4. Set up the logging database by importing the included SQL schema:
   ```bash
   mysql -u root -p < database_schema.sql
   ```

5. Configure rclone for Google Drive access if you haven't already:
   ```bash
   rclone config
   ```

## ⚙️ Configuration

Update the following variables in the script:

### Telegram Configuration
```bash
TELEGRAM_BOT_TOKEN="your_telegram_bot_token"
TELEGRAM_CHAT_ID="your_telegram_chat_id"
```

### Backup Configuration
```bash
db_user="admin"
db_password="`cat /etc/psa/.psa.shadow`"
backup_folder="/opt/sementara"
base_folder="/FOLDER-GOOGLE-DRIVE"
remote_name="your_rclone_remote_name"
```

### Logging Database Configuration
```bash
LOG_DB_HOST="localhost"
LOG_DB_USER="backup_user"
LOG_DB_PASSWORD="your_password"
LOG_DB_NAME="backup_database"
LOG_DB_PORT="3306"
```

## 🏃‍♂️ Usage

### Manual Execution

```bash
./backup.sh
```

### Scheduled Execution (Cron)

Add to crontab to run automatically:

```bash
# Run daily at 1 AM
0 1 * * * /path/to/backup.sh
```

## 📊 Database Schema

The logging system uses the following tables:

1. **backup_sessions**: Records each backup run
2. **user_backups**: Tracks user-level backup operations
3. **database_backups**: Stores information about individual database backups
4. **backup_logs**: Maintains detailed logs of all operations
5. **telegram_notifications**: Records all Telegram notification attempts

The schema creation script is included in `database_schema.sql`.

## 🔔 Notification Format

Sample Telegram notification:

```
🚀 Database Backup Started
📅 Date: [Timestamp]
👥 Processing backups by user
🔄 Session ID: [ID]

[... Progress Updates ...]

📊 Final Backup Statistics
📅 Date: [Timestamp]
👥 Total Users: 10
💾 Total Databases: 237
✅ Successfully Backed Up: 235
❌ Failed Backups: 2
🆔 Session ID: [ID]
📂 Base Folder: /RCLONE-DB/CLASSY
```

## 🛠️ Troubleshooting

1. **Database Connection Issues**
   - Verify database credentials
   - Ensure MySQL server is running
   - Check if user has proper permissions

2. **Telegram Notification Failures**
   - Verify bot token and chat ID
   - Check internet connectivity
   - Ensure bot has not been blocked

3. **rclone Upload Errors**
   - Verify Google Drive API access
   - Check rclone configuration
   - Ensure sufficient Google Drive space

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📧 Contact

Andri Wiratmono - kontak@classy.id
