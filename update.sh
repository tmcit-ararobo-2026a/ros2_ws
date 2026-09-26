#! /bin/bash

echo "=== Checking CUDA environment ==="
if ! command -v nvcc &> /dev/null; then
    echo "エラー: CUDA (nvcc) のパスが通っていません。" >&2
    echo "PATH および LD_LIBRARY_PATH に CUDA が設定されているか確認してください。" >&2
    exit 1
fi
echo "CUDA PATH Check OK: $(which nvcc)"

vcs pull src < ararobo_2026a.repos
source /opt/ros/humble/setup.bash
rosdep update --rosdistro humble
rosdep install --from-paths . --ignore-src -y --rosdistro humble
colcon build --symlink-install