#! /bin/bash
vcs pull src < ararobo_2026a.repos
source /opt/ros/humble/setup.bash
rosdep update --rosdistro humble
rosdep install --from-paths . --ignore-src -y --rosdistro humble
colcon build --symlink-install