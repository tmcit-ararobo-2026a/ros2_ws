#! /bin/bash

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

vcs pull src < ararobo_2026a.repos
vcs pull data < private_2026a.repos
source /opt/ros/humble/setup.bash
rosdep update --rosdistro humble
rosdep install --from-paths . --ignore-src -y --rosdistro humble
colcon build --symlink-install