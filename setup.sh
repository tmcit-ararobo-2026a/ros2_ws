#! /bin/bash
sudo apt update
sudo apt install -y libceres-dev libeigen3-dev nlohmann-json3-dev
vcs import src < ararobo_2026a.repos
source /opt/ros/humble/setup.bash
rosdep update --rosdistro humble
rosdep install --from-paths . --ignore-src -y --rosdistro humble
colcon build --symlink-install