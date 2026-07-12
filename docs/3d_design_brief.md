# 3D化デザインブリーフ (for Codex)

## ⚠ 最重要: Windowsでの文字コード(必読)

このリポジトリのファイルはすべて **UTF-8(BOMなし)** で、日本語を含む。Windows PowerShell 5.1 の既定設定では日本語が文字化けする。

- ファイルを読むときは、**毎回コマンドの冒頭で**次を実行してから読むこと:
  `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8; Get-Content -Raw -Encoding utf8 <path>`
- ファイルの新規作成・編集は **apply_patch のみ**を使うこと。PowerShellの `Set-Content` / `Out-File` / `echo >` で書いてはならない(エンコーディングが壊れる)
- 日本語が「縺ゅ→」のように化けて見えたら、それは読み方の誤り。**化けた文字列を理解・編集・パッチの文脈行に使ってはならない**。正しい読み方で読み直すこと

「箱庭の神」の見た目を2D記号表現から**3D**に置き換える。**デザイン(アートディレクションと3D表現の設計・実装)はあなた(Codex)に一任する**。ただし以下の統合制約は厳守すること。

## 世界観
魔法のある異世界。何もない原始の村(祠・小屋・山・川)から始まり、機械/自然/神秘の3系統に分岐しながら現代都市まで発展する。神視点で箱庭を見下ろして眺めるゲーム。あたたかく、素朴で、夜は幻想的な雰囲気を目指してほしい。

## 厳守する統合制約

1. **シミュレーション本体を変えない**: `scripts/{clock,world,events,magic,projects,chronicle}.gd` と `data/*.json` の挙動・データ形式は一切変更しない(バグ修正も不要)。`agent/protagonist/animal` の行動ロジック(スケジュール、欲求、移動、生産)も変えない — 変更してよいのは**描画・表示に関する部分のみ**
2. **座標系**: シミュレーションは既存の2Dマップ座標(x: 0..980, y: 40..720 のVector2)のまま動かし続ける。3D表示への変換は表示層のみで行う(推奨: `(x, y) → Vector3(x, 0, y) × スケール係数`)。`global_position` を使うロジック(移動、距離判定、クリック選択)が壊れないよう、変換ヘルパーを1箇所に集約すること
3. **HUD/対話UIは2Dのまま**: `ui.gd`(CanvasLayer HUD)と `dialogue_ui.gd`(神対話ウィンドウ)は現状維持。3Dビューの上にそのまま重ねる
4. **アセット禁止**: 外部モデル・テクスチャ・画像・プラグイン不可。ジオメトリはすべてプロシージャル(BoxMesh, CylinderMesh, SphereMesh, CapsuleMesh, PrismMesh, PlaneMesh, TorusMesh, SurfaceTool, CSG可)。GDScriptのみ、C#不可
5. **ノードはコードで構築**: 新しい.tscnを増やさない(既存の5行 main.tscn のみ)。既存方針どおり全ノードを `new()` + `add_child()` で構築
6. **機能を落とさない**:
   - 建物: 種類ごとに見た目が変わる(既存の `color` / `size` データを活用)。**建設中**の表現と進捗が見えること。時代が進むと村が発展して見えること
   - 住人: 名前ラベル(日本語、Label3D等)、主人公は特別に見えること、選択リングに相当する表現、吹き出し(会話テキスト、日本語)
   - 動物: 鹿・犬・鶏・山羊が判別できる簡易造形
   - 昼夜サイクル: 現在は CanvasModulate(`main.gd` の `_update_tint`)。DirectionalLight3D + Environment 等の3D手法に置き換えてよい
   - クリックで住人選択(カメラからのレイキャスト等で `main._select` に接続)
   - カメラ: 見下ろし系で、マウスでパン・ズーム(+可能なら回転)ができること
7. **検証コマンドが通ること**(必ず全部実行して確認する):
   - 起動チェック: `& "C:\Users\takut\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine.Mono_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64_console.exe" --headless --path d:\dev\world --quit` (SCRIPT ERRORが出ないこと)
   - 自己テスト: 同exeで `--headless --path d:\dev\world -- --selftest` が `SELFTEST OK` / exit 0
   - スクショ: 同exeで `--path d:\dev\world -- --shot` が shot.png を保存して正常終了(3Dビューが写ること)
8. **日本語フォント**: ゲーム内テキストは日本語。Label3D等でも `scripts/util.gd` の `U.jp_font()`(SystemFont)を使うこと

## あなたに任せるデザイン判断(自由領域)

- 全体のルック(ローポリ/フラットシェーディング等)、パレット、フォグ、ライティング設計
- 地形の造形(草原、川の水表現、北西の山と森、岩場)
- 建物ごとの造形レシピ(祠、小屋、畑、鍛冶場、魔導の塔、世界樹、大機関、大魔法陣 など全種)
- 住人・動物のキャラクター造形と歩行の見せ方
- カメラの初期アングルと操作感
- 夜・夕暮れの空気感、時代が進んだときの見た目の変化

## 進め方

1. まず `docs/3d_design.md` にデザインドキュメント(ルック方針、メッシュレシピ、シーン構成、座標変換方針)を書く
2. その後に実装。既存の `terrain.gd / location.gd / agent.gd / protagonist.gd / animal.gd / bubble.gd / main.gd(表示部分)` を3D表現に置き換える
3. こまめに起動チェックを回し、最後に上記7の3コマンドを全部通す
4. 変更はワーキングツリーに残したままでよい(コミットは不要。レビュー後にこちらで行う)
