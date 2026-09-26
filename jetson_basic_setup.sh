#! /bin/bash
set -e  # エラーが発生した時点でスクリプトを停止
sudo apt update
sudo apt install nvidia-jetpack openssh-server
sudo iptables -P FORWARD ACCEPT