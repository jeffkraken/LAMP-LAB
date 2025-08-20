#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Config (match your CTF design)
# -----------------------------
SFTP_USER="sftpadmin"
SFTP_PASS="FTPSucks3!"
SQL_USER="sqladmin"
SQL_PASS="p!nkMouse23"
ROOT_DB_PASS="P@ssw0rd"
DB_NAME="testDB"
SUBNET_HOST="%"
REPO_URL="https://github.com/jeffkraken/LAMP-LAB"
WEB_ROOT="/var/www/html"
PCAP_NAME="netaudit.pcap"

# -----------------------------
# Helpers
# -----------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1; }
ensure_user() {
  local user="$1" pass="$2"
  if id "$user" >/dev/null 2>&1; then
    echo "[*] User $user already exists."
  else
    useradd -m "$user"
    echo "$user:$pass" | chpasswd
    echo "[+] Created user $user"
  fi
}

# -----------------------------
# Pre-flight
# -----------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (use sudo)."
  exit 1
fi

echo "[*] Updating package metadata..."
dnf -y makecache

echo "[*] Installing packages..."
# Use python3-pip (package name differs from 'pip')
dnf -y install git httpd mariadb mariadb-server python3-pip firewalld policycoreutils-python-utils

# Some systems ship both pip and pip3; be explicit:
python3 -m pip install --upgrade pip
python3 -m pip install scapy

# -----------------------------
# Users
# -----------------------------
ensure_user "$SFTP_USER" "$SFTP_PASS"
ensure_user "$SQL_USER"  "$SQL_PASS"

# -----------------------------
# Firewall (ensure firewalld is running)
# -----------------------------
systemctl enable firewalld --now
echo "[*] Opening HTTP (80) and MySQL (3306) in firewalld..."
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=mysql
firewall-cmd --reload

# -----------------------------
# Services
# -----------------------------
echo "[*] Enabling and starting httpd and mariadb..."
systemctl enable httpd --now
systemctl enable mariadb --now

# -----------------------------
# App files
# -----------------------------
WORKDIR="/opt/LAMP-LAB"
if [[ -d "$WORKDIR/.git" ]]; then
  echo "[*] Repo already present, pulling latest..."
  git -C "$WORKDIR" pull --ff-only
else
  echo "[*] Cloning repo..."
  git clone "$REPO_URL" "$WORKDIR"
fi

echo "[*] Deploying web assets..."
install -d "$WEB_ROOT"
# Copy (not move) so re-running the script won't fail if files already placed
install -m 0644 "$WORKDIR/index.html" "$WEB_ROOT/index.html"
install -m 0644 "$WORKDIR/script.js"  "$WEB_ROOT/script.js"

echo "[*] Setting ownership/permissions/SELinux contexts on $WEB_ROOT..."
chown -R apache:apache "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"
restorecon -Rv "$WEB_ROOT" || true

# -----------------------------
# Generate PCAP and place for sftpadmin
# -----------------------------
echo "[*] Generating PCAP via packet_gen.py..."
# Run in repo directory to respect relative paths
pushd "$WORKDIR" >/dev/null
python3 packet_gen.py
popd >/dev/null

echo "[*] Placing PCAP in $SFTP_USER home..."
install -o "$SFTP_USER" -g "$SFTP_USER" -m 0644 "$WORKDIR/$PCAP_NAME" "/home/$SFTP_USER/$PCAP_NAME"

# -----------------------------
# Secure MariaDB (non-interactive)
# Mirrors mysql_secure_installation choices:
#  - set root password
#  - remove anonymous users
#  - disallow remote root
#  - remove test DB
#  - flush privileges
# -----------------------------
echo "[*] Hardening MariaDB and creating DB, user, and table..."

# Many distros default root@localhost to unix_socket auth, so we can log in without a password here.
mysql --protocol=socket -uroot <<SQL
-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Disallow remote root: keep only localhost variants
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');

-- Set root password (MariaDB 10.2+ supports ALTER USER)
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_DB_PASS}';

-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\\_%';

FLUSH PRIVILEGES;
SQL

# -----------------------------
# Create challenge DB, user, grants, schema, and seed data
# -----------------------------
mysql -uroot -p"${ROOT_DB_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME};

-- Create or replace the lab user for your internal subnet
CREATE USER IF NOT EXISTS '${SQL_USER}'@'${SUBNET_HOST}' IDENTIFIED BY '${SQL_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${SQL_USER}'@'${SUBNET_HOST}';
FLUSH PRIVILEGES;

USE ${DB_NAME};

-- Create table if missing
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) NOT NULL,
  password VARCHAR(16) NOT NULL
);

-- Seed data (INSERT IGNORE to avoid duplicates on rerun)
INSERT IGNORE INTO users (id, username, password) VALUES
  (1, 'root',     'jolly82L!quid'),
  (2, 'sqladmin', '${SQL_PASS}');

-- Show grants for verification
SHOW GRANTS FOR '${SQL_USER}'@'${SUBNET_HOST}';
-- Show user table so you can eyeball it if desired
SELECT * FROM users;
SQL

echo "[+] LAMP-LAB setup complete."
echo "    Web root: ${WEB_ROOT}"
echo "    PCAP: /home/${SFTP_USER}/${PCAP_NAME}"
echo "    DB: ${DB_NAME}, user: ${SQL_USER}@${SUBNET_HOST}"
