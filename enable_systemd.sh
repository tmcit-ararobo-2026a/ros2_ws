#! /bin/bash
set -e  # エラーが発生した時点でスクリプトを停止

# -------------------------------------------------------------------------
# 3. リポジトリ内の systemd サービスファイルの配置
# -------------------------------------------------------------------------
SOURCE_SERVICE_FILE="/home/ararobo/ros2_ws/src/robot-bringup/systemd/robot.service"
TARGET_SERVICE_FILE="/etc/systemd/system/robot.service"

echo "=== Linking systemd service file ==="
# 既存のリンクやファイルがあれば削除してシンボリックリンクを作成
sudo rm -f ${TARGET_SERVICE_FILE}
sudo ln -s ${SOURCE_SERVICE_FILE} ${TARGET_SERVICE_FILE}

# -------------------------------------------------------------------------
# 4. systemd サービスの登録と起動
# -------------------------------------------------------------------------
echo "=== Enabling and starting systemd service ==="
sudo systemctl daemon-reload
sudo systemctl enable robot.service
sudo systemctl restart robot.service

echo "=== Setup complete! Service status: ==="
sudo systemctl status robot.service --no-pager