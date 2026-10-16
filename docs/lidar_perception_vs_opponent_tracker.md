# `LiDAR-Perception-System` と `opponent-tracker` の比較

- 調査日: 2026-10-16
- 対象:
  - `/home/gn10/ros2_ws/src/LiDAR-Perception-System`
  - `/home/gn10/ros2_ws/src/opponent-tracker`
- 調査方法: ノード実装、ヘッダ、設定、launch、README、ROS interfaceを静的に比較

## 1. 結論

| 観点 | `LiDAR-Perception-System` | `opponent-tracker` |
|---|---|---|
| 主目的 | 移動バケツの専用検出・追跡 | 相手機体の検出・追跡と移動バケツ位置の推定 |
| 検出対象 | バケツ本体、またはバケツを支持する下部構造 | 相手機体全体を表す点群クラスタ |
| 入力 | 主に`/livox/lidar`の生点群 | localizationが生成する動的点群。launch設定の既定値は`/dynamic_cloud` |
| 前処理 | CUDAによる座標変換・高さ範囲別グリッド集計 | CPUでPointCloud2を解析し、TFでmapへ変換 |
| 候補抽出 | 連結成分、寸法、円弧形状、固定半径フィット | 空間ハッシュ、近傍探索、BFS連結成分、バウンディングボックス |
| 形状判定 | バケツの半径・点数・円弧・残差 | 相手機体の幅・奥行き・高さ・床接地 |
| 時系列処理 | 4状態ベクトルの線形予測・観測更新、支持部仮説のロック | 5状態カルマンフィルタ、クラスタ対応付け、速度・姿勢平滑化 |
| 欠測時 | 最終観測から既定0.3秒まで`PREDICTED`、その後無効 | missを許容し、最大miss回数を超えると`LOST` |
| 出力 | `MovingBucketTrack`と鮮度検査済み最終topic | 相手姿勢、バケツ照準点、速度、RVizマーカー、任意TF |
| 主な特徴 | 対象専用、高さ分離、GPU、高い観測状態の明示 | 相手ロボットの形状検証、コート制約、位置・速度・向きの提供 |

したがって、両者は同じ「LiDARから動く対象を追跡する」系統に見えるが、代替関係ではない。LPSはバケツの照準対象を得るための専用系、opponent-trackerは相手機体の位置・速度とそのバケツ位置を得るための相手機体追跡系である。

## 2. `LiDAR-Perception-System` の特徴とアルゴリズム

### 2.1 パッケージの役割

`moving_bucket_detector`は、Livox等の`PointCloud2`から移動バケツを検出する。READMEでは、固定バケツ・旗、背景PCD、PCL、KD-tree背景差分を使わず、CUDAと高さ別グリッドを使う専用設計と説明されている。

主な構成は以下である。

```text
/livox/lidar [PointCloud2]
        │
        ▼
moving_bucket_detector
  ├─ CUDAでmap座標への変換とグリッド集計
  ├─ バケツ本体候補の形状フィット
  ├─ 支持部候補の連結成分・時系列追跡
  └─ 4状態の位置・速度推定
        │ /moving_bucket_detector/target_raw
        ▼
track_freshness_guard_node
        │ /moving_bucket_detector/target
        └─ 任意のmap → moving_bucket TF
```

### 2.2 入力検証と座標変換

`moving_bucket_detector`は、設定ファイルから以下を読み込む。

- 入力topic: `/livox/lidar`
- 出力座標系: `map`
- XY範囲: `-5.0 m`から`5.0 m`
- バケツ検出用Z範囲: `1.05 m`から`1.50 m`
- グリッド解像度: `0.08 m`
- 入力データサイズ上限: `8 MiB`

処理前に、`PointCloud2`の幅、高さ、エンディアン、行stride、データサイズ、`FLOAT32`の`x/y/z`フィールドを検証する。時刻に対応するTFが得られない場合はキューで待ち、`tf_wait_s`を超えるとそのフレームを破棄する。

### 2.3 CUDAグリッド集計

1フレームにつき、同じ点群を2回処理する。

1. バケツ本体用のZ範囲
2. 支持部用のZ範囲（`support_min_z`から`support_max_z`）

いずれもmap座標へ変換した後、XYグリッドセルごとに点数と座標和を集計する。自機周辺の`self_radius`または支持部用の`support_self_radius`もグリッド処理時に除外条件として使われる。

この段階では個々の点をPCLの点群構造へ変換せず、固定長のグリッド集計結果を後段へ渡す。そのため、生点群の全探索を繰り返すより、対象範囲内の形状判定に計算を集中できる。

### 2.4 バケツ本体の候補抽出

`extract_candidates()`は、グリッド上で次の処理を行う。

1. 点数が2以上のセルを8近傍で連結成分化する。
2. 成分の総点数とセル数を確認する。
3. XY方向のサイズを`0.12 m`以上`0.65 m`以下に制限する。
4. セル平均位置から初期中心を作る。
5. バケツ半径`0.1365 m`に対して、ロバスト重み付きの固定半径フィットを最大10回行う。
6. 各セルの角度から観測円弧を計算する。
7. 円弧長、半径フィット残差、点数から候補スコアを計算する。
8. 最大8候補に絞る。

候補は以下の条件を満たす必要がある。

- 点数: `18`点以上
- セル数: `5`以上
- 半径フィット残差: `0.055 m`以下
- 円弧span: `1.2 rad`以上

追跡中は予測位置から`0.4 m`以内、かつ残差`0.035 m`以下の候補だけを直接観測候補として採用する。これは、毎フレーム別の円形物体へ追跡対象が切り替わることを抑えるためである。

### 2.5 支持部候補の抽出とロック

バケツ本体が見えない場合は、`SupportTracker`が低いZ範囲の連結成分を調べる。

1. グリッドを8近傍の連結成分へ分割する。
2. 点数を`20`点以上`1000`点以下にする。
3. XYサイズを`0.20 m`以上`1.15 m`以下にする。
4. 既知の固定設備（`desk_`、`bucket_`、`flag_`のTF）付近を除外する。
5. 既存仮説の予測位置へ距離ゲート付きで対応付ける。
6. 対応した仮説の速度を観測差分で更新する。
7. 4ヒット以上かつ累積移動量が`0.25 m`を超えた仮説を移動対象としてロックする。

支持部から採用した場合、XYは支持部の中心、Zは設定値`support_target_z=1.2 m`を使う。つまり、`SUPPORT_INFERRED`のZは直接測ったバケツ中心ではなく、支持部からの推定値である。

### 2.6 時系列推定と鮮度

検出ノードは状態を`[x, y, vx, vy]`で保持し、一定速度モデルで予測する。観測があれば2次元位置観測として共分散付きで更新する。支持部推定は直接観測より大きい観測分散を与える。

`MovingBucketTrack.msg`の`observation_mode`は次の4種類である。

- `NONE`: 有効な観測・予測なし
- `DIRECT`: バケツ形状を直接観測
- `SUPPORT_INFERRED`: 支持部から推定
- `PREDICTED`: 新しい観測なしで短時間予測

確認ヒット数に達した追跡は、最後の観測から既定`0.3 s`まで予測を有効とする。GPU検出ノードの出力はrawであり、`track_freshness_guard_node`が入力時刻、追跡時刻、最終観測時刻、有限値、共分散、重複時刻を検査する。古い結果や入力停止時には`valid=false`を公開する。

### 2.7 出力

- `/moving_bucket_detector/target_raw`
  - 型: `lidar_perception_system/msg/MovingBucketTrack`
  - GPU検出直後の結果
- `/moving_bucket_detector/target`
  - 型: `lidar_perception_system/msg/MovingBucketTrack`
  - 鮮度検査済みの最終結果
- `/moving_bucket_detector/diagnostics`
  - 入力数、処理数、TF待ち超過、キュー破棄、処理時間など
- `map -> moving_bucket`
  - 鮮度監視ノードが必要時に公開

## 3. `opponent-tracker` の特徴とアルゴリズム

### 3.1 パッケージの役割

`opponent_tracker_node`は、localizationパッケージが静的地図との差分として生成した動的点群から、相手機体の点群クラスタを抽出する。

```text
/dynamic_cloud [PointCloud2]
        │
        ▼
opponent_tracker_node
  ├─ TFでmapへ変換
  ├─ 自機コート外・固定障害物・自機近傍を除外
  ├─ 空間ハッシュ + BFSでクラスタ化
  ├─ 相手機体の寸法・床接地を検証
  ├─ 高いZ範囲からバケツ中心を抽出
  └─ 5状態カルマンフィルタで相手を追跡
        ├─ /opponent_robot/pose
        ├─ /opponent_robot/bucket_target
        ├─ /opponent_robot/velocity
        └─ /opponent_robot/markers
```

### 3.2 動的点群の前提

`opponent-tracker`自身は背景差分を行わない。入力は`gn10_pointcloud_localization`が生成する動的点群であり、静的地図との差分処理は上流ノードの責務である。

実装上の入力topicには注意が必要である。

- launchの既定値: `/dynamic_cloud`
- `config/opponent_tracker_params.yaml`: `/dynamic_points`
- C++のパラメータ既定値: `/dynamic_points`
- READMEとlocalizationの出力: `/dynamic_cloud`

launchで`input_topic`を明示すれば実行時に統一できるが、設定ファイルだけで起動する場合はtopic不一致になる可能性がある。

### 3.3 TF変換とフィルタ

点群の`x/y/z`と任意の`intensity`フィールドを読み、各点をmap座標へ変換する。指定時刻のTFが取れなければ、短い待ち時間の後に最新TFへフォールバックする。

その後、以下を除外する。

- フィールド範囲外
- 相手コート外
- 中央障壁・柱などの既知固定障害物内
- 自機位置から`0.90 m`未満のクラスタ

相手コートは、固定値`side_a`、`side_b`、または自機のY座標と中央境界から反対側を推定する`auto`で決める。

### 3.4 空間ハッシュとクラスタリング

`ClusterExtractor`は次の処理を行う。

1. 点を`0.08 m`ボクセルの空間ハッシュへ格納する。
2. `cluster_tolerance`以内のボクセル近傍を探索する。
3. BFSでユークリッド距離に基づく連結成分を作る。
4. 点数が`min_cluster_size`未満、または`max_cluster_size`超過の成分を破棄する。
5. 残った成分について重心、軸平行バウンディングボックス、寸法を計算する。

デフォルトのC++値はクラスタ結合距離`0.35 m`だが、設定YAMLには`0.20 m`が記載されている。実際にどの値が使われるかはROSパラメータ読み込み結果に依存する。

### 3.5 相手機体の幾何検証

クラスタを相手機体と認めるには、次の条件を満たす必要がある。

- 幅: `0.20 m`から`1.30 m`
- 奥行き: `0.20 m`から`1.30 m`
- 高さ: `0.30 m`から`2.20 m`
- 最低点Z: `0.25 m`以下

最後の条件は、床に接地した相手機体を残し、浮遊物や上方の物体を除外するためのものである。

### 3.6 バケツ中心の抽出

相手機体クラスタ内から`1.15 m`から`2.15 m`の点だけを集め、その平均をバケツ中心とする。5点以上あれば`has_bucket=true`、信頼度`1.0`となる。

5点未満の場合は、バウンディングボックス上面付近を代替位置にして`has_bucket=false`、信頼度`0.7`とする。このため、opponent-trackerのバケツ位置は、バケツ専用形状を直接フィットした位置ではなく、相手機体クラスタから得た高い位置の推定である。

### 3.7 クラスタ選択とカルマン追跡

検出クラスタが複数ある場合は、次の方針で1つを選ぶ。

- 追跡中: 予測位置から最も近く、`max_association_dist`以内のクラスタ
- 未追跡・未確定: 点数、バケツ検出の有無、クラスタ体積を加点した候補

`KalmanTracker2D`の状態は概念的に`[x, y, vx, vy, bucket_z]`である。

1. 一定速度モデルで位置・速度を予測する。
2. 観測した相手機体重心のXYとバケツ中心Zを測定値として更新する。
3. 位置、速度、バケツZの共分散を更新する。
4. 次元を指数移動平均で平滑化する。
5. 移動中は速度方向からヘディングを求め、角度を平滑化する。
6. 停止時はLiDAR重心揺れによる微小速度を0にする。
7. フィールド境界、固定障害物、最大速度`2.5 m/s`を制約する。

観測が欠けた場合は`markMissed()`でcoastingへ移行し、最大miss回数を超えると`LOST`となる。LPSの`PREDICTED`のような有効トラックtopicを短時間継続して出す処理とは異なり、opponent-trackerは確認済み状態の間だけ結果を公開する。

### 3.8 出力

- `/opponent_robot/pose`
  - 型: `geometry_msgs/msg/PoseStamped`
  - 相手機体中心のXYと推定ヘディング
- `/opponent_robot/bucket_target`
  - 型: `geometry_msgs/msg/PointStamped`
  - 相手バケツの照準位置
- `/opponent_robot/velocity`
  - 型: `geometry_msgs/msg/TwistStamped`
  - 相手機体のXY速度
- `/opponent_robot/markers`
  - 型: `visualization_msgs/msg/MarkerArray`
  - 相手機体・バケツの可視化
- `/our_robot/markers`
  - 型: `visualization_msgs/msg/MarkerArray`
  - 自機位置・姿勢の可視化
- `map -> opponent_robot`
- `map -> opponent_bucket`
  - `publish_tf=true`の場合に公開

## 4. 差異の詳細

### 4.1 検出対象の違い

LPSはバケツの半径・円弧を直接検証するため、バケツ本体の部分点群を対象にできる。バケツが見えない場合は、動いている支持部をロックし、Zだけを設定値で補う。

opponent-trackerは相手機体全体のクラスタ形状を先に検証する。バケツは相手機体クラスタの高い位置の点から抽出するため、相手機体クラスタが成立しない場合はバケツだけを独立検出できない。

### 4.2 入力データの違い

LPSは生のLivox点群を自らmapへ変換し、高さ範囲を分けて集計する。

opponent-trackerは、上流のlocalizationが背景差分した動的点群を受け取る。従って、静的障害物の除去と動的点群の品質はlocalizationの設定・出力に依存する。

### 4.3 追跡モデルの違い

LPSは4状態の位置・速度推定に対象専用の候補スコアと支持部仮説ロックを組み合わせる。観測の出所を`DIRECT`、`SUPPORT_INFERRED`、`PREDICTED`として明示できる。

opponent-trackerは5状態のカルマンフィルタで、相手機体の位置・速度・バケツZを同時に平滑化する。ヘディング、寸法、固定障害物・フィールド境界制約まで出力推定へ反映する。

### 4.4 信頼性と失敗時挙動の違い

LPSは入力・TF・計算キュー・結果の鮮度を独立監視する。GPU計算が停止してもguardが期限到来を検知し、`valid=false`を公開できる。

opponent-trackerはコールバック内でTF、クラスタ検出、カルマン更新を完結する。TFが取得できない場合やクラスタが無い場合はそのフレームを処理できず、trackerのmissカウンタが進む。入力topic不一致や上流動的点群の欠落は、検出前段で解決する必要がある。

## 5. 共通点

- ROS 2 C++ノードである。
- `PointCloud2`を入力とする。
- TFを用いてmap座標系で処理する。
- 自機周辺または既知固定物を候補から除外する。
- 点群を単一フレームだけでなく時系列追跡する。
- RViz向けの可視化を提供する。
- Eigenを使った幾何・状態推定処理を含む。

## 6. 運用上の注意と現在確認できる不整合

### 6.1 `opponent-tracker`の入力topic表記が統一されていない

localizationの出力、README、launch、テストの一部は`/dynamic_cloud`を使う。一方、C++既定値、設定YAML、別のテストスクリプトは`/dynamic_points`を使う。

推奨対応は、実際のシステム出力である`/dynamic_cloud`を標準名に統一し、設定・C++既定値・テストを同じ名前へ揃えることである。現時点でもlaunch引数`input_topic:=/dynamic_cloud`を明示すれば接続できる。

### 6.2 2つのパッケージは同じ入力を共有し得るが、出力は競合しない

両方を同じ動的点群系へ接続することは可能だが、出力topicが異なる。

- LPS: `/moving_bucket_detector/*`
- opponent-tracker: `/opponent_robot/*`

そのため、topic名の直接衝突はない。ただし、opponent-trackerが必要とする相手機体クラスタと、LPSが必要とするバケツ形状を別々に処理するので、同じ点群を入力するとCPU/GPU処理負荷が重複する可能性がある。

### 6.3 推定対象の使い分け

- 射出・照準のために移動バケツの観測状態、鮮度、直接観測か推定かを厳密に扱う場合: LPS
- 相手機体の位置、速度、進行方向、相手バケツの概略位置が必要な場合: opponent-tracker
- 相手機体が見えず、バケツだけが見えるケース: LPSの方が設計上適している
- 相手機体の形状全体を利用して安定追跡したい場合: opponent-tracker

## 7. 主要な参照ファイル

- LPS検出: `LiDAR-Perception-System/src/moving_bucket_detector.cpp`
- LPS支持部追跡: `LiDAR-Perception-System/include/lidar_perception_system/support_candidates.hpp`
- LPS鮮度監視: `LiDAR-Perception-System/src/track_freshness_guard_node.cpp`
- LPS設定: `LiDAR-Perception-System/config/moving_bucket.json`
- LPS interface: `LiDAR-Perception-System/msg/MovingBucketTrack.msg`
- 相手クラスタ抽出: `opponent-tracker/src/cluster_extractor.cpp`
- 相手追跡ノード: `opponent-tracker/src/opponent_tracker_node.cpp`
- 相手カルマンフィルタ: `opponent-tracker/src/kalman_tracker_2d.cpp`
- 相手設定: `opponent-tracker/config/opponent_tracker_params.yaml`
