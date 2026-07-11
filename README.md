# 箱庭の神 (Hakoniwa no Kami)

魔法のある異世界で、**神となって主人公「アシタ」を導き**、何もない村を現代社会まで発展させるシミュレーション。Godot 4 / GDScript製。

## 遊び方

- 主人公アシタは**毎朝 祠で祈り**ます。そこであなた(神)が選択肢を選び、
  **行動**(畑を拓く、祭りをする…)・**魔法**(恵みの雨、鍛鉄の炎…)・**方針**を授けます
- 村人と動物は自律的に暮らします。山で山菜を採り、川で水を汲む原始の暮らしから始まり、
  選んだ道によって **機械 / 自然 / 神秘** の3系統に文明が分岐します
- 選択を誤ると**戦禍・魔力の淀み・飢餓**で村が滅ぶこともあります(バッドエンド3種+グッドエンド4種)
- 住人をクリックすると様子が見られます。右パネルで村の状態・年代記・魔法を確認。
  Space=一時停止、右上ボタンで倍速

## 起動

```powershell
& "C:\Users\takut\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine.Mono_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64_console.exe" --path d:\dev\world
```

またはGodotエディタでプロジェクトを開いて F5。

## 開発向け

- パース/起動チェック: `<godot> --headless --path . --quit`
- 自己テスト(12ゲーム日を自動プレイ): `<godot> --headless --path . -- --selftest`
- スクリーンショット: `<godot> --path . -- --shot` → `shot.png`

## 構成

- `scripts/` — ロジック。`main.gd`が構成ルート。シミュレーションは全て「ゲーム内分」で駆動
- `data/` — 時代・魔法・プロジェクト・イベント・セリフはすべてJSON。行を足すだけで内容を増やせる
- `scenes/main.tscn` — 唯一のシーン(5行)。ノードは全てコードで構築

## 将来の3D化について

シミュレーション本体(world/clock/events/magic/projects と住人の行動ロジック)は描画から分離してある。
3D化するときは `terrain.gd / location.gd / agent.gd / animal.gd` の描画部分(_drawとLabel)を
Node3D+メッシュに置き換え、Vector2座標をXZ平面へ写せばよい。対話UI・パネル類はそのまま使える。
