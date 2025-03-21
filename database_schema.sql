-- Create backup_sessions table
CREATE TABLE IF NOT EXISTS backup_sessions (
    session_id INT AUTO_INCREMENT PRIMARY KEY,
    start_time DATETIME NOT NULL,
    end_time DATETIME NULL,
    status ENUM('running', 'completed', 'failed') NOT NULL DEFAULT 'running',
    base_folder VARCHAR(255) NOT NULL,
    total_users INT NULL DEFAULT 0,
    total_databases INT NULL DEFAULT 0,
    successful_backups INT NULL DEFAULT 0,
    failed_backups INT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create user_backups table
CREATE TABLE IF NOT EXISTS user_backups (
    user_backup_id INT AUTO_INCREMENT PRIMARY KEY,
    session_id INT NOT NULL,
    mysql_user VARCHAR(64) NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NULL,
    total_databases INT NOT NULL,
    successful_backups INT NULL DEFAULT 0,
    failed_backups INT NULL DEFAULT 0,
    user_folder VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES backup_sessions(session_id) ON DELETE CASCADE
);

-- Create database_backups table
CREATE TABLE IF NOT EXISTS database_backups (
    database_backup_id INT AUTO_INCREMENT PRIMARY KEY,
    user_backup_id INT NOT NULL,
    session_id INT NOT NULL,
    database_name VARCHAR(64) NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NOT NULL,
    status ENUM('successful', 'failed') NOT NULL,
    file_size VARCHAR(20) NULL,
    backup_filename VARCHAR(255) NOT NULL,
    error_message TEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_backup_id) REFERENCES user_backups(user_backup_id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES backup_sessions(session_id) ON DELETE CASCADE
);

-- Create backup_logs table
CREATE TABLE IF NOT EXISTS backup_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    session_id INT NOT NULL,
    user_backup_id INT NULL,
    database_backup_id INT NULL,
    log_time DATETIME NOT NULL,
    log_level ENUM('info', 'warning', 'error', 'debug') NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES backup_sessions(session_id) ON DELETE CASCADE,
    FOREIGN KEY (user_backup_id) REFERENCES user_backups(user_backup_id) ON DELETE SET NULL,
    FOREIGN KEY (database_backup_id) REFERENCES database_backups(database_backup_id) ON DELETE SET NULL
);

-- Create telegram_notifications table
CREATE TABLE IF NOT EXISTS telegram_notifications (
    notification_id INT AUTO_INCREMENT PRIMARY KEY,
    session_id INT NOT NULL,
    user_backup_id INT NULL,
    database_backup_id INT NULL,
    send_time DATETIME NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    status ENUM('sent', 'failed') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES backup_sessions(session_id) ON DELETE CASCADE,
    FOREIGN KEY (user_backup_id) REFERENCES user_backups(user_backup_id) ON DELETE SET NULL,
    FOREIGN KEY (database_backup_id) REFERENCES database_backups(database_backup_id) ON DELETE SET NULL
);

-- Add indexes for performance
CREATE INDEX idx_session_status ON backup_sessions(status);
CREATE INDEX idx_user_backup_session ON user_backups(session_id);
CREATE INDEX idx_database_backup_user ON database_backups(user_backup_id);
CREATE INDEX idx_database_backup_session ON database_backups(session_id);
CREATE INDEX idx_database_backup_status ON database_backups(status);
CREATE INDEX idx_log_session ON backup_logs(session_id);
CREATE INDEX idx_log_level ON backup_logs(log_level);
CREATE INDEX idx_telegram_session ON telegram_notifications(session_id);
CREATE INDEX idx_telegram_status ON telegram_notifications(status);
