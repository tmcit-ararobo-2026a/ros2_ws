#! /bin/bash
set -e  # エラーが発生した時点でスクリプトを停止

echo "=== Checking CUDA environment ==="
if ! command -v nvcc &> /dev/null; then
    echo "WARN: CUDA (nvcc) のパスが通っていません。デフォルト`/usr/local/cuda`のパスを通します"
    export PATH=/usr/local/cuda/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
    if ! command -v nvcc &> /dev/null; then
        echo "ERROR: CUDA (nvcc) のパスが通りませんでした。"
        exit 1
    fi
fi
echo "CUDA PATH Check OK: $(which nvcc)"

# -------------------------------------------------------------------------
# 1. 依存関係のインストールとビルド
# -------------------------------------------------------------------------
sudo apt update
sudo apt install -y libceres-dev libeigen3-dev nlohmann-json3-dev tmux

vcs import src < ararobo_2026a.repos
vcs import data < private_2026a.repos
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
SCRIPTS_DIR="${HOME}/ros2_ws/src/robot-bringup/scripts"

echo "=== Granting execution permissions to scripts ==="
chmod +x ${SCRIPTS_DIR}/launch_ros2.sh
chmod +x ${SCRIPTS_DIR}/ros2_node_finish.sh