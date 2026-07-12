# 有料アセット全面適用ラウンド (for Codex)

統合制約(シミュ本体不変・U.load_model/load_texture_file使用・Label3D fixed_size禁止・カメラ操作不変・UTF-8読み・apply_patchのみ)継続。

購入済みアセットがGLB変換済みで配置されている:
- `assets/models/synty/` — POLYGON Knights Pack (騎士/兵士キャラ、モジュール城・教会・家、武器、旗など789モデル+テクスチャ)。メインアトラスは Textures フォルダ内を確認して特定すること
- `assets/models/dmason/hero/` — mesh/CharacterBaseMesh.glb (Face1-5/Hair1-7/Cloth1-9/Shoe/Belt/Hat/Helm等の全パーツ入り、名前で表示切替) + anim/*.glb (生活アニメ) + texture/PolyArt.png
- `assets/models/dmason/monster/` — Meshes/Character/*Mesh.glb (Bat/Dragon/EvilMage/Golem/MonsterPlant/Orc/Skeleton/Slime/Spider/TurtleShell) + Animations/<種>/*.glb + Textures/Albedo.png

**重要な既存機構**(そのまま使うこと):
- FBX由来GLBはテクスチャ未埋め込み → `MeshInstance3D.material_override` に StandardMaterial3D(albedo_texture=アトラス, roughness=1.0) を適用する
- アニメーションGLBは1テイク入り。`main._merge_take_anim(model, anim_path, name)` で移植できる(agent._build_dmason_hero_model も参考)
- 主人公は既に dmason 勇者で構築済み(agent.gd)。触らないこと

## 1. 村人を勇者パーツで多様化(最優先)

villagers の `_build_kaykit_person_model` を dmason ベースに置き換え:
- id.hash() で Face1-5 / Hair1-7 / Cloth1-9 / Shoe1-6 / Belt1-3 を組み合わせ、髪は複数の茶/黒/金系ティント
- 職業で味付け: 農夫系(farm/forest職)=Hat1-3のどれか、知識系(school/library)=なし、兵系(barracks职)=Helm+ShoulderPad
- アニメは主人公と同じ DM_HERO_ANIMS 相当(agent側の定数を村人でも使えるよう一般化してよい。ただしシミュのロジックは不変)
- 高さは villager 1.35 / hero 1.5 の既存比率を維持

## 2. 建物をSynty Knightsのモジュールで格上げ

`location.gd` のモデル割り当てで、Syntyに良い物がある建物は差し替え:
- castle → モジュール城(壁+塔+門を2-4ピース組み)
- barracks/archeryrange → Synty同等物があれば差し替え
- church系(祠の上位/寺院系があれば) → Synty教会
- hut/house → Synty家(KayKitと雰囲気比較して良い方を採用。色替え規則は維持)
- 無い物(風車・水車・井戸など)はKayKitのまま
- 完成建物の周囲プロップに Synty の旗・武器ラック等を混ぜる

## 3. イベントの敵をモンスターで多様化

- monster_raid: era0-1=Slime/Spider、era2-3=Orc/Skeleton、era4+=Golem/EvilMage を2-4体(既存の骸骨演出機構 _spawn_skeleton_raid を一般化してよい。表示層のみ)
- war_attack: 敵兵を Synty Knights の敵色キャラに(既存 _spawn_war_band を差し替え)
- 全て Albedo.png / Syntyアトラスの material_override を忘れずに

## 4. その他の改善(気づき次第、表示層のみで)

- 祭り中の村人 Cheer は dmason の Victory_noWeapon に置換可
- タイトル後のプロローグ中も主人公モデルが正しく見えるか確認
- 会話ダイアログの上に重なる白い表示物(ユーザー報告)がないか --shot 系で確認し、あればレイヤー/描画順を修正

## 検証

tools\godot\Godot_v4.6.3-stable_mono_win64_console.exe で (1)--quit SCRIPT ERRORなし (2)--selftest OK (3)--shot/--shot-day/--shot-night 目視(村人の多様さ・建物・テクスチャ適用)。コミットしない。
