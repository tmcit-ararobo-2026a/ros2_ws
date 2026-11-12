# ROS2 Workspace

NHKロボコン2026用ros2_wsです。

## 目次

1. [概要](#1-概要)
2. [ビルド・使い方](#2-ビルド使い方)
3. [ライセンス](#3-ライセンス)

## 1. 概要

一括でROS2関連のリポジトリをクローンし、ワークスペース単位で管理するために作成しました。

## 2. ビルド・使い方

CUDAのパスが通っていない場合：
```bash
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
```
必要なリポジトリのクローンや依存関係の解決
```bash
./setup.sh
```
再ビルド
```bash
./update.sh
```

Jetson用：
sshサーバーやjetpackインストール
```bash
./jetson_basic_setup.sh
```
librealsenseインストール
```bash
./librealsense_setup.sh
```

## 3. ライセンス

本リポジトリは [MITライセンス](./LICENSE) のもとで公開されています。
