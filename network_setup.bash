#! /bin/bash
set -e  # エラーが発生した時点でスクリプトを停止
sudo iptables -P FORWARD ACCEPT