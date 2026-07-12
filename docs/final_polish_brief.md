# 仕上げ演出ラウンド (for Codex)

統合制約(シミュ本体不変・U.load_model/load_texture_file使用・Label3D fixed_size禁止・カメラ操作不変・UTF-8読み・apply_patchのみ)継続。

## 1. 新しい建物のモデル割り当て(プロジェクト追加済み・モデル名ほぼ一致)

type id → KayKitモデル: tavern→building_tavern / windmill→building_windmill / watermill→building_watermill / tower→building_tower_A(+base) / barracks→building_barracks / archeryrange→building_archeryrange / castle→building_castle / stable→適当な納屋風(home_B+fence等)。軸色ルール(tech=red/nature=green/mystic=blue/中立=yellow)は既存の仕組みに合わせる。スケールは既存ヘルパーで。

## 2. 川の装飾

- `neutral/building_bridge_A or B` を川の中流に1本架ける(見た目のみ、渡れなくてよい)
- `decoration/nature/waterlily_A/B`・`waterplant_A/B/C` を川沿いに10個ほど散らす
- 水車小屋(watermill)が建つ場合の設置は通常の格子でよい

## 3. 村のプロップ密度

`medieval/decoration/props/`(26種: 樽・荷車・木箱など)を、**建物が完成するたびにその周囲に1-2個**ランダム配置(人口/建物数が増えるほど村がにぎやかに見える)。過密にならないよう建物あたり最大2個。

## 4. 骸骨の魔物(スケルトン)

`assets/models/skeletons/Skeleton_{Minion,Warrior,Rogue,Mage}.glb`(アニメ付き)。
**monster_raid イベントが発生した朝**(main.request_prayer で event_id=="monster_raid" の convo を開いた時に演出フックを追加してよい — 表示層のみ)、マップ北の森の際に骸骨3-4体を出現させ、ゆっくりうろつかせ、2ゲーム時間で霧散(fade out)させる。Idle/Walkアニメ使用。シミュには一切影響しないこと。

## 5. 収穫祭の演出

main.festival_active() / main.festival_site が実装済み。祭りの間、会場に:
- 色とりどりの光の粒(GPUParticles3D)や提灯風の光
- 集まった村人が時々 Cheer アニメ
祭り終了で消える。

## 6. 初心者向けヘルプ

画面右上(速度ボタンの左)に「？」ボタン → 全画面ヘルプオーバーレイ(クリックで閉じる):
- カメラ: 左ドラッグ=回転 / 右ドラッグ=移動 / ホイール=ズーム / Space=一時停止
- 村人や動物をクリック=様子を見る
- 毎朝アシタが祈る→選択肢で導く / 左上=いまの目標(ミッション) / 右パネルのタブ説明
デザインは既存テーマと調和させる。

## 7. フォント確認

UIフォントを Kiwi Maru(assets/fonts, util.jp_font経由)に切替済み。スクショで文字化け・レイアウト崩れがないか確認し、崩れる箇所はサイズ調整。

## 検証

tools\godot\Godot_v4.6.3-stable_mono_win64_console.exe で (1)--quit SCRIPT ERRORなし (2)--selftest OK (3)--shot/--shot-day/--shot-night 目視(新建物・橋・プロップ・フォント)。コミットしない。
