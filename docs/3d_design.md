# 「箱庭の神」3D化デザイン

## ルック方針

あたたかいローポリ箱庭。地面、建物、住人、動物は外部アセットを使わず、BoxMesh / CylinderMesh / SphereMesh / CapsuleMesh / TorusMesh / SurfaceTool で構築する。昼は素朴な村、夕方は金色、夜は青いフォグと魔法光が目立つ見た目にする。

カメラは神視点の斜め見下ろし。UI は既存 CanvasLayer を維持し、3D ビューの上に重ねる。

## 座標変換

シミュレーション座標は既存の 2D Vector2 のまま維持する。表示用 3D 座標への変換は `main.gd` に集約する。

- `Vector2(x, y)` → `Vector3((x - 490) * 0.08, height, (y - 380) * 0.08)`
- クリック判定は Camera3D のレイを地面 `y = 0` に落とし、逆変換した 2D 座標で既存の住人選択距離判定を行う
- `global_position` を使う移動、距離、仕事割当は変更しない

## シーン構成

- `Main(Node2D)`
  - `View3D(Node3D)`: 3D 表示の親
  - `Camera3D`: 斜め見下ろしカメラ
  - `DirectionalLight3D`: 太陽
  - `OmniLight3D`: 夜の祠と村の補助光
  - `WorldEnvironment`: 空色、フォグ、アンビエント
  - 既存の `Terrain` / `Town` / `Agents` / `Animals`: シミュレーション座標を保持する Node2D
  - 既存の `DialogueUI` / `UILayer`: 2D HUD

## メッシュレシピ

### 地形

- 草原: 大きな PlaneMesh
- 川: 曲線点列を太い低い BoxMesh セグメントでつなぎ、水色の発光を少し足す
- 北西の山: 円錐状 CylinderMesh と雪冠
- 森: 幹 CylinderMesh と葉 SphereMesh / Cone 風 CylinderMesh の集合
- 岩場: 灰色 SphereMesh を低く潰した岩

### 建物

- 共通: `color` と `size` を footprint と基調色に使う
- 建設中: 土台、足場、部分的に伸びる躯体、上部の進捗バー
- 小屋・学校・診療所: 箱の壁と SurfaceTool の切妻屋根
- 畑: 畝の列と苗
- 鍛冶場: 煙突と炉の発光
- 魔導の塔: 円柱塔、円錐屋根、紫の発光球
- 世界樹: 太い幹と複数の樹冠
- 大機関: 円柱・輪・発光コアで機械的に見せる
- 大魔法陣: TorusMesh の輪、柱、発光素材

### 住人・動物

- 住人: CapsuleMesh の胴体、SphereMesh の頭、Label3D の日本語名
- 主人公: 金色のラベル、頭上の光輪、少し大きいシルエット
- 選択: 足元の TorusMesh リング
- 吹き出し: Billboard の Label3D と白い PlaneMesh
- 鹿: 細い脚、胴体、枝角
- 犬: 低い胴体、尾
- 鶏: 丸い体、くちばし、とさか
- 山羊: 角とあごひげ

## ライティング

`CanvasModulate` は使わず、時刻から太陽色、環境光、フォグ色、夜の補助光を補間する。夜は青紫に寄せ、祠・魔法系建物の発光が見えるようにする。
