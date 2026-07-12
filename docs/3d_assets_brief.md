# 生成アセット組み込みブリーフ (for Codex)

gpt-image-2 で生成したアセット一式を3Dワールドと UI に組み込む。**どう美しく貼るかのデザイン判断は任せる**。従来の統合制約(シミュ本体・data/*.json 不変、検証3コマンド、UTF-8読み取り、apply_patchのみ)はすべて継続。

## ⚠ 技術上の最重要事項

このプロジェクトは**Godotエディタで一度も開かれていない**ため、`load("res://...png")` は使えない(インポート済みリソースが存在しない)。
画像の読み込みは必ず `scripts/util.gd` の **`U.load_texture_file(res_path)`**(実行時にImage.load_from_fileで読む。無ければnull)を使うこと。
すべての画像は**ファイルが無くても動く**フォールバック(現在の単色マテリアル/絵文字)を残すこと。

## アセットと用途

### 1. タイルテクスチャ `assets/textures/` (1024x1024, シームレス)
StandardMaterial3D の albedo_texture に貼る。uv1_scale やトリプラナーの使い分けは任せる。
- tex_grass → 地面の草原プレーン
- tex_soil → 畑の土
- tex_stone → 石系建物(石切り場・城壁・診療所など)と祠の石壁
- tex_wood → 木の壁(小屋・木こり場・学び舎など)
- tex_thatch → わら屋根(小屋など)
- tex_roof_tile → 瓦屋根(祠・塔など上位建物)
- tex_water → 川(可能ならUVオフセットをゆっくり動かして流れを表現)
- tex_rock → 山・岩
- tex_bark / tex_leaves → 木の幹と樹冠
建物種ごとの割当は君のデザイン判断で(既存の色調と調和させ、albedo_color を乗算して色バリエーションを保つのが推奨)。

### 2. 空パノラマ `assets/sky/` (1536x1024, equirectangular風)
- sky_dawn / sky_day / sky_dusk / sky_night
Environment を BG_SKY + PanoramaSkyMaterial に変更し、時刻(main.gd の `_update_tint` が持つ時間帯係数)に応じて切替・ブレンドする。切替がパキッと目立たない工夫(フェード、エネルギー補間など)は任せる。既存のフォグ・太陽光・夜光との整合も調整すること。

### 3. UIアイコン `assets/icons/` (透過PNG)
- icon_food / icon_wood / icon_stone / icon_metal / icon_mana / icon_knowledge
ui.gd のトップバー資源チップの絵文字を 16〜20px のアイコン画像+数値ラベルに置き換える(TextureRect + Label のHBox)。ツールチップは維持。ファイルが無い資源は絵文字のまま。

### 4. イベントカットイン `assets/illustrations/cutin_<event_id>.png` (1536x1024)
dialogue_ui.gd を拡張: open() に渡される convo に `event_id` キーがある場合(events.gd 実装済み)、
`res://assets/illustrations/cutin_<event_id>.png` が存在すれば対話ウィンドウ上部に横長のカットイン(高さ~120px、KEEP_ASPECT_COVERED+クリップ)を表示する。無ければ従来表示。
※ main.gd の request_prayer が dialogue_ui.open に convo の text/choices しか渡していない場合は、open の引数に convo 全体 or event_id を追加してよい(呼び出し側も併せて修正)。

## 注意

- `scripts/ui.gd` には最近こちらで追加した show_title()(タイトル画面)と ending_art(エンディングイラスト表示)がある。**壊さないこと**。タイトル画面と統一感のあるデザイン調整は歓迎
- 検証: tools\godot\Godot_v4.6.3-stable_mono_win64_console.exe で (1)起動チェック --quit にSCRIPT ERRORなし (2) -- --selftest が SELFTEST OK (3) -- --shot でスクショを撮り、昼と夜の見た目を自分で確認して調整
- コミットはしない
