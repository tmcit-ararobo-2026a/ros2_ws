# ROS 2 ワークスペース調査報告

- 調査対象: `/home/gn10/ros2_ws/src`
- 調査日: 2026-10-16
- 調査方法: `package.xml`、`CMakeLists.txt`、launchファイル、ノード実装、interface定義、READMEを静的に確認
- 表記: 「確認済み」はソースで実装を確認した事項、「候補」は構成から追加確認が必要な事項

## 1. パッケージとノード

| パッケージ | ノード・実行ファイル | 主な起動方法 | 役割 |
|---|---|---|---|
| `gn10_navigation` | `costmap_generator_node`、`path_planner_node`、`path_follower_node` | `costmap_generator.launch.py`、`navigation.launch.py` | コストマップ生成、経路計画、経路追従 |
| `gn10_pointcloud_localization` | `gn10_pointcloud_localization_node`、`localization_status_monitor_node`、`pcd_to_esdf_converter` | `localization.launch.py`、`red.launch.py`、`blue.launch.py` | LiDAR/IMUを用いた自己位置推定と状態監視 |
| `auto_mode_manager` | `auto_mode_manager_node`、`navigation_safety_monitor.py` | `auto_mode_manager.launch.py`、`integration_test.launch.py` | 自動走行の状態管理、安全監視、各機能の調停 |
| `lidar_perception_system` | `moving_bucket_detector`、`track_freshness_guard_node`、`replay_static_tf.py` | `moving_bucket.launch.py`、`moving_bucket_rviz.launch.py` | 移動バケット検出と検出結果のfreshness監視 |
| `opponent_tracker` | `opponent_tracker_node` | `opponent_tracker.launch.py`、`integrated_system.launch.py` | 相手機体の位置・速度推定 |
| `field_target_pub` | `field_target_node` | `field-target-pub.launch.py` | フィールド上の目標物を配信 |
| `robot_port` | `udp_node` | `robot_port.launch.py` | ROSとメイン基板間のUDPブリッジ |
| `Lakibeam_ROS2_Driver` (`lakibeam1`) | `lakibeam1_scan_node` | `lakibeam1_scan.launch.py` | LaserScan LiDARドライバ |
| `livox_ros_driver2` | `${PROJECT_NAME}_node` | Livox用launchまたは個別実行 | Livox LiDARドライバ |
| `realsense_dust_cloth` | `cloth_tracker_cuda_node`、`trajectory_probability_analyzer.py` | `cloth_tracker.launch.py` | RealSense画像・深度から布の位置と軌跡を推定 |
| `robot_bringup` | `robot_debugger`、統合launch | `blue.launch.py`、`red.launch.py` | 複数パッケージの統合起動 |

`localization_status_monitor_node`、`track_freshness_guard_node`、fixture類は、検出・推定本体ではなく品質監視またはテスト補助である。

## 2. ノード間の接続

### 2.1 実機・自動走行の主経路

```text
LiDAR / IMU
    │
    ▼
gn10_pointcloud_localization_node
    │ /localization/status_raw
    ▼
localization_status_monitor_node
    │ /localization/status
    ▼
auto_mode_manager_node
    ├── /navigation/compute_path ──► path_planner_node
    │                                  ▲
    │                                  │ /costmap
    │                         costmap_generator_node
    │
    ├── /navigation/follow_path ─────► path_follower_node
    │                                  │ /robot/operation/cmd_vel
    │                                  ▼
    │                              ロボット制御系
    │
    └── /robot/operation ───────────► udp_node ── UDP ──► メイン基板
```

### 2.2 認識・目標物の経路

```text
PointCloud2 ─► moving_bucket_detector
                   │ ~/target_raw
                   ▼
             track_freshness_guard_node
                   │ /moving_bucket_detector/target
                   ▼
             auto_mode_manager_node

PointCloud2 ─► opponent_tracker_node
                   ├── /opponent_robot/pose
                   ├── /opponent_robot/bucket_target
                   └── /opponent_robot/velocity

field_target_node ──► /field/targets [TargetSet]
```

`moving_bucket_detector`の入力点群topicは設定ファイルの`input_topic`で決まり、localizationの入力・出力topicもYAMLパラメータで決まる。そのため、以下の表にない入力topicはlaunchで渡す設定ファイルを併せて確認する必要がある。

## 3. 通信内容、topic名、用途

### 3.1 ナビゲーションと自動モード

| 通信 | 型 | 用途 | 根拠 |
|---|---|---|---|
| `/costmap` | `nav_msgs/msg/OccupancyGrid` | コストマップ生成ノードから経路計画ノードへ障害物・通行コストを渡す | `gn10-navigation/src/costmap_generator_node.cpp`、`path_planner_node.cpp` |
| `/navigation/compute_path` | `gn10_navigation/srv/ComputePath` | 開始姿勢と目標姿勢を受け取り、成功状態・エラーコード・`nav_msgs/Path`を返す | `gn10-navigation/srv/ComputePath.srv` |
| `/planned_path` | `nav_msgs/msg/Path` | 計画済み経路のlegacy入力 | `gn10-navigation/src/path_planner_node.cpp`、`path_follower_node.cpp` |
| `/navigation/follow_path` | `gn10_navigation/action/FollowPath` | 経路、producer session、generationを受け取り、追従結果を返す | `gn10-navigation/action/FollowPath.action` |
| `/navigation/control_lease` | `gn10_navigation/msg/ControlLease` | 経路追従の制御権と世代を管理する | `auto-mode-manager/scripts/auto_mode_manager_runtime.py`、`path_follower_node.cpp` |
| `/navigation/path_velocity` | `gn10_navigation/msg/PathVelocity` | 経路追従中の速度・状態をmanagerへ返す | 同上 |
| `/robot/operation/cmd_vel` | `geometry_msgs/msg/Twist` | path followerが生成する速度指令 | `gn10-navigation/src/path_follower_node.cpp` |

### 3.2 基板通信

| 通信 | 型 | 用途 |
|---|---|---|
| `/robot/operation` | `robot_port/msg/RobotOperation` | managerからUDP bridgeへ操作要求を渡す |
| `/robot/command` | `robot_port/msg/RobotCommand` | `udp_node`からROS側へ基板向けコマンドを公開する |
| `/robot/feedback` | `robot_port/msg/RobotFeedback` | 基板からの状態・センサフィードバックを公開する |
| `/robot/communication_status` | `robot_port/msg/BridgeHealth` | UDP通信の健全性を公開する |

実装上の流れは、`auto_mode_manager_node -> /robot/operation -> udp_node -> UDP -> メイン基板`、およびその逆方向の`/robot/feedback`・`/robot/communication_status`である。

### 3.3 Localizationと認識

| 通信 | 型 | 用途 |
|---|---|---|
| `/localization/status_raw` | `gn10_pointcloud_localization/msg/LocalizationStatus` | localization本体の推定品質・入力freshnessを公開 |
| `/localization/status` | `gn10_pointcloud_localization/msg/LocalizationStatus` | status monitorが品質ゲート後に公開 |
| `/moving_bucket_detector/target_raw` | `lidar_perception_system/msg/MovingBucketTrack` | 移動バケット検出の生データ |
| `/moving_bucket_detector/target` | `lidar_perception_system/msg/MovingBucketTrack` | freshness確認済みの移動バケット情報をmanagerへ渡す |
| `/opponent_robot/pose` | `geometry_msgs/msg/PoseStamped` | 相手機体の位置・姿勢 |
| `/opponent_robot/bucket_target` | `geometry_msgs/msg/PointStamped` | 相手機体のバケット目標位置 |
| `/opponent_robot/velocity` | `geometry_msgs/msg/TwistStamped` | 相手機体の速度 |
| `/field/targets` | `field_target_pub/msg/TargetSet` | フィールド上の目標物一覧 |

Localization本体の入力は設定依存の`PointCloud2`、`Imu`、必要に応じた`PoseWithCovarianceStamped`である。`moving_bucket_detector`は設定内の`input_topic`から`PointCloud2`を受け取る。`opponent_tracker_node`のデフォルト入力は`/dynamic_points`である。

### 3.4 Cloth trackerと可視化

`cloth_tracker_cuda_node`は、ROS画像入力モードで深度画像、カメラ情報、カラー画像を購読し、以下を公開する。

- `/cloth/position` (`geometry_msgs/msg/PointStamped`)
- `/cloth/trajectory_marker` (`visualization_msgs/msg/Marker`)
- `/cloth/measured_path` (`nav_msgs/msg/Path`)
- `/camera/camera/color/image_raw` (`sensor_msgs/msg/Image`)
- `/camera/camera/color/image_raw/compressed` (`sensor_msgs/msg/CompressedImage`)
- `/camera/camera/color/camera_info` (`sensor_msgs/msg/CameraInfo`)
- `/cloth/camera_view` (`sensor_msgs/msg/Image`)
- `/cloth/debug/roi_markers` (`visualization_msgs/msg/MarkerArray`)
- `/cloth/debug/cluster_points`、`/cloth/debug/filtered_points` (`sensor_msgs/msg/PointCloud2`)

## 4. interfaceの用途

| interface | 用途 |
|---|---|
| `gn10_navigation/srv/ComputePath` | 経路計画要求と結果 |
| `gn10_navigation/action/FollowPath` | 経路追従の開始、キャンセル、結果 |
| `gn10_navigation/msg/ControlLease`、`PathVelocity` | 制御権と追従状態 |
| `gn10_pointcloud_localization/msg/LocalizationStatus` | 自己位置推定品質、入力freshness |
| `lidar_perception_system/msg/MovingBucketTrack` | 移動バケットの位置、速度、共分散、信頼度 |
| `field_target_pub/msg/TargetSet` | フィールド目標物の一覧 |
| `robot_port/msg/RobotOperation`、`RobotCommand`、`RobotFeedback`、`BridgeHealth` | ROS-基板間の要求、命令、応答、通信状態 |
| `auto_mode_manager/msg/AutoModeStatus`、`SafetyState`、`ExecutionPath`、`SimulationState` | 自動モード、安全状態、経路実行、シミュレーション状態 |

## 5. 必要ない可能性があるパッケージ・構成

「不要」と断定できるものは、ソースだけではありません。運用プロファイル（実機、シミュレーション、デバッグ）ごとに判断が必要です。

### 5.1 `robot_bringup`内の`robot_debugger`（不要候補）

`robot_bringup`は統合launchを提供する一方、ビルド対象の実ノードは`robot_debugger`です。本番のblue/red統合起動と`robot_debugger`の直接的な接続は確認できません。統合launchだけを使う場合は、`robot_debugger`が不要な可能性があります。

### 5.2 LakibeamとLivoxの同時起動（構成候補）

`Lakibeam_ROS2_Driver`はLaserScan、`livox_ros_driver2`はPointCloud2/独自CustomMsgを扱うため、センサ種類としては重複ではありません。ただし`robot_bringup/launch/blue.launch.py`は両方を同時起動します。実機で一方を使用しないなら、未使用側を統合launchから外せます。

### 5.3 `opponent_tracker`と`lidar_perception_system`の前処理（重複候補）

対象は相手機体と移動バケットで異なるためパッケージ自体の重複ではありません。ただし同じ点群を入力する構成では、点群変換・フィルタリングの計算が重複する可能性があります。

## 6. 現在の問題

### 優先度の高い問題（確認済み）

1. **blue launchのパッケージ名誤り**
   - `robot-bringup/launch/blue.launch.py:17`が`get_package_share_directory('field-target-pub')`を使用する。
   - package.xmlの実名は`field_target_pub`。
   - `robot_bringup blue.launch.py`起動時にパッケージ探索で失敗する可能性が高い。

2. **blue launchが存在しないLivox launchを参照**
   - `robot-bringup/launch/blue.launch.py:61-64`が`livox_ros_driver2/launch/msg_MID360s_launch.py`を参照する。
   - 現在のワークスペース内でこのファイルとlaunchディレクトリの存在を確認できない。
   - LivoxドライバのREADME記載のlaunch名とも一致しない。

3. **`shooter_calculator`依存がワークスペース内にない**
   - `auto-mode-manager/scripts/auto_mode_manager_runtime.py:17-18`が`shooter_calculator.msg`をimportする。
   - `auto-mode-manager/launch/integration_test.launch.py:47-49`も`shooter_calculator`ノードを起動する。
   - ワークスペース内にパッケージがなく、package.xmlにも明示依存がないため、統合テストまたはruntime起動がimport/launchで失敗する可能性がある。

4. **実機自動モードが未実装**
   - `auto-mode-manager/scripts/auto_mode_manager_runtime.py:48-52`は、`simulation`以外の有効モードで`ValueError`を発生させる。
   - 実装上、利用可能なのは`disabled`と`simulation`に限られる。
   - READMEやlaunchが実機運用可能に見える場合、説明と実装を一致させる必要がある。

### 設定・ビルド上の問題（条件付き）

5. **安全監視のtopic名が固定**
   - `navigation_safety_monitor.py:38-43`は`/obstacle_cloud`と`/costmap`を固定購読する。
   - localizationのYAMLで障害物出力topicを変更すると、安全監視が入力を受け取れなくなる。

6. **FollowPathとlegacy pathの二系統**
   - `path_follower_node`はAction `/navigation/follow_path`を通常経路とし、`enable_legacy_path_input=true`なら`/planned_path`も購読する。
   - 両方を有効にした場合、同一追従処理への入力経路が二系統になり、競合要因となる。

7. **Livoxの外部SDK依存**
   - `livox_ros_driver2/CMakeLists.txt:54-61`は`/usr/local/lib/liblivox_lidar_sdk_shared.so`、`livox_lidar_api.h`、PCL、APRを要求する。
   - package.xmlだけではビルド依存が完結せず、SDK未導入環境ではビルドできない。

8. **Realsenseの直接入力はビルド条件付き**
   - `realsense_dust_cloth/CMakeLists.txt:38-69`はCUDA/OpenCVを必須とし、librealsenseは検出時にのみリンクする。
   - `use_direct_realsense=true`でも`HAVE_REALSENSE2`がなければROS画像入力にフォールバックするため、READMEの利用条件を明記すべきである。

## 7. 推奨確認順

1. `robot_bringup/blue.launch.py`の`field_target_pub`名とLivox launch名を修正・実機環境で起動確認する。
2. `shooter_calculator`を外部依存として導入するのか、統合テストから分離するのか決める。
3. 実機モードの実装予定がないなら、launch/READMEで`simulation`限定であることを明示する。
4. 実機プロファイルごとにLakibeam/Livoxの使用センサを選択し、統合launchの同時起動を見直す。
5. localizationのtopic設定と安全監視の固定topicが一致することをlaunchごとに検証する。
