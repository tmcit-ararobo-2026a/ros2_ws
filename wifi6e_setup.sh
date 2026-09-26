#! /bin/bash
set -e  # エラーが発生した時点でスクリプトを停止
cd /home/ararobo
git clone https://git.kernel.org/pub/scm/linux/kernel/git/iwlwifi/backport-iwlwifi.git
cd backport-iwlwifi/
mkdir build
cd build/
cmake ..
cd ..
make -j6
sudo make install