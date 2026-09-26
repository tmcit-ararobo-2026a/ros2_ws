#! /bin/bash
set -e  # エラーが発生した時点でスクリプトを停止
# Ensure the directory exists
sudo mkdir -p /etc/apt/keyrings
# Download and dearmor
curl -sSf https://librealsense.realsenseai.com/Debian/librealsenseai.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/librealsenseai.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/librealsenseai.gpg] https://librealsense.realsenseai.com/Debian/apt-repo `lsb_release -cs` main" | sudo tee /etc/apt/sources.list.d/librealsense.list
sudo apt-get update
sudo apt-get install librealsense2-utils
sudo apt-get install librealsense2-dev