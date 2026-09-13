# ROS2 Workspace

NHKロボコン2026用ros2_wsです。

## 目次

1. [概要](#1-概要)
2. [ドキュメント](#2-ドキュメント)
3. [ビルド・使い方](#3-ビルド使い方)
4. [システム構成](#4-システム構成)
5. [ライセンス](#5-ライセンス)

## 1. 概要

一括でROS2関連のリポジトリをクローンし、ワークスペース単位で管理するために作成しました。

## 2. ドキュメント

| ドキュメント | 説明 |
| :-: | :-: |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | 開発フロー・コミット規約・コーディング規約 |
| [docs/coding-rules.md](./docs/coding-rules.md) | コーディング規約の詳細 |
| [docs/uml/](./docs/uml/) | UML図 |

## 3. ビルド・使い方

一括クローン
```bash
vcs import src < ararobo_2026a.repos
```

一括ビルド
```bash
source /opt/ros/humble/setup.bash
rosdep update
rosdep install --from-paths src --ignore-src -y
colcon build
```

## 4. システム構成

gn10-pointcloud-localization: PointCloud2より２次元的な自己位置推定を行うCUDA用パッケージ
opponent-tracker: gn10-pointcloud-localizationが生成する動的点群を用いて相手チームのロボットを追跡する軽量パッケージ
robot-bringup: ロボット全体のlaunchや自動起動用スクリプト＆サービスファイルを扱うパッケージ
robot-port: ロボットとの通信を行いTopic通信とUDP通信の変換を行うパッケージ

## 5. ライセンス

本リポジトリは [MITライセンス](./LICENSE) のもとで公開されています。
