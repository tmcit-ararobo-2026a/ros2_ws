#! /bin/bash
set -e  # エラーが発生した時点でスクリプトを停止

# -------------------------------------------------------------------------
# 1. 依存関係のインストールとビルド
# -------------------------------------------------------------------------
sudo apt update
sudo apt install -y libceres-dev libeigen3-dev nlohmann-json3-dev tmux

vcs import src < ararobo_2026a.repos
source /opt/ros/humble/setup.bash

# rosdep init の重複実行エラーを回避
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    sudo rosdep init
fi

rosdep update --rosdistro humble
rosdep install --from-paths . --ignore-src -y --rosdistro humble
colcon build --symlink-install

# -------------------------------------------------------------------------
# 2. スクリプト群への実行権限付与
# -------------------------------------------------------------------------
SCRIPTS_DIR="/home/ararobo/ros2_ws/src/robot-bringup/scripts"

echo "=== Granting execution permissions to scripts ==="
chmod +x ${SCRIPTS_DIR}/launch_ros2.sh
chmod +x ${SCRIPTS_DIR}/ros2_node_finish.sh

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