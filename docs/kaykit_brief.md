# KayKit CC0アセット統合ブリーフ (for Codex) — 3D品質の大幅アップ

`assets/models/` にKayKit(CC0)のGLTF/GLBを配置済み。これらでプロシージャル造形を置き換え、見た目を製品級に引き上げる。
統合制約(シミュ本体不変・Label3D fixed_size禁止・カメラ操作不変・UTF-8読み・apply_patchのみ)継続。

## 0. ランタイムモデルローダー(最初に作る・全ての土台)

**エディタのインポートは使えない**。実行時読み込み必須:
```gdscript
# util.gd に追加(検証済みの動作方式):
static var _model_cache := {}
static func load_model(res_path: String) -> Node3D:
    if not _model_cache.has(res_path):
        var doc := GLTFDocument.new()
        var state := GLTFState.new()
        if doc.append_from_file(res_path, state) != OK:
            _model_cache[res_path] = null
        else:
            _model_cache[res_path] = doc.generate_scene(state)
    var proto = _model_cache[res_path]
    return null if proto == null else proto.duplicate()
```
モデルが無い/読めない場合は**既存のプロシージャル造形にフォールバック**すること(全箇所)。

## 1. 建物の置き換え (`assets/models/medieval/buildings/<色>/building_*.gltf`)

マッピング(推奨、判断で調整可):
hut→home_A/home_B交互 / well→well / woodcamp→lumbermill / forge→blacksmith / market→market / quarry→mine / granary→grain(neutralフォルダ) / shrine→church / school→church以外なら home_B 大きめ or tavern / pen→fence_wood+家畜の柵で表現(neutralのfence) / wall→wall_straight / stable→home_A+fence など。
- **色バリエーションの演出**: 建設時の優勢軸で色を選ぶ — tech優勢=red、nature=green、mystic=blue、初期/中立=yellowかneutral。**村の見た目が選んだ道に染まっていく**
- スケール調整必須: モデルのAABBを測り、既存の footprint (`fp`) に収まるよう `scale` を決める共通ヘルパーを作る
- ラベル/バッジ/クリック選択/stand位置は既存のまま
- 該当モデルが無い建物(祈りの岩・野営地・世界樹・大機関・大魔法陣・grove・mage_tower等)は**現行プロシージャルを維持**

## 2. 建設中表現

`neutral/building_stage_A/B/C.gltf` を進捗0-33% / 33-66% / 66-100%で切り替え(+既存の進捗バー維持)。scaffoldingモデルも活用可。

## 3. 山と地形装飾

- 「山」サイト → `decoration/nature/mountain_B_grass_trees.gltf`(または良さげな山)に置き換え。麓の採集広場は平地のまま
- `hills_*` をマップ外周の遠景に数個
- `cloud_big/small` を空にゆっくり流す(2-4個、ゆったり移動)
- 伐採可能な木 → decoration/nature 内の木モデルに置き換え(**clear_trees_rect の仕組み=木の親Node3Dをqueue_free は維持**)。種類・大きさをばらす

## 4. キャラクター置き換え (`assets/models/characters/*.glb`)

Barbarian / Knight / Mage / Rogue / Rogue_Hooded(リグ+アニメ75種入り)。
- 村人: Rogue / Barbarian / Rogue_Hooded / Mage をid hashで割り当て(Mageは低頻度)
- アシタ: 立ち絵(茶髪・クリーム服)に最も近いものを選び、金の選択リング・ラベルで特別感維持
- **状態→アニメ対応**(AnimationPlayer.play、ループ設定に注意):
  - MOVING→Walking_A(またはB/C個体差) / WORKING・LEADING→Use_Item か Interact のループ / SLEEPING→Lie_Idle / PRAYING→Sit_Floor_Idle / TRAINING→Spellcasting / EATING→Sit_Floor_Idle / FREE→Idle / 会話中→Idle+たまにCheer
  - 移動方向への回頭は既存ロジック流用
- 既存の釣り竿・斧の小道具表現は新モデルに合わせて維持・調整
- スケール: 既存キャラの身長(~1.4ワールド単位)に合わせる
- 動物はモデルが無いので現行プロシージャル維持

## 5. パフォーマンス

- モデルはキャッシュ+duplicate()(ローダーが担保)。木~240本で重い場合は本数調整かMultiMesh化(任意)
- 検証時にFPSが大きく落ちていないこと(RTX 3060 Laptop)

## 検証

tools\godot\Godot_v4.6.3-stable_mono_win64_console.exe で (1)--quit SCRIPT ERRORなし (2)--selftest OK (3)--shot/--shot-day/--shot-night を撮り、**建物・キャラ・山・雲が正しく表示されアニメが動くか自分の目で確認**。うまくいかないモデルはフォールバックで隠さず直すこと。コミットしない。
