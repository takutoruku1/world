# 時代ごとの建物拡充ブリーフ

## ユーザー要望(原文)
「章ごとに建てられる建物をふやしたい」

村は自動発展(projects.gd auto_develop が空きスロットに建設)なので、
建物を増やす=各時代の村の見た目と個性が豊かになる。

## やること
1. **data/projects.json** に新規建物を8〜10個追加(時代0〜4に分散)。
   日本チート転生モノの雰囲気に合う名前・説明で。案(変更・追加自由):
   - 時代0: 干し場(食料の保存干し棚。production food 0.5)
   - 時代1: 共同かまど(みんなの炊事場。mood_all +4, production food 0.5)、
     薬草園(production mana 0.5、疫病対策フレーバー)
   - 時代2: 湯屋(お風呂! 日本チートの花形。effects mood_all +8)、
     茶屋(social タグ、production food 0.3)
   - 時代3: 印刷所(production knowledge 1.5)、大市場や劇場系
   - 時代4: 星見台/大聖堂(production mana or knowledge、axis mystic)
   バランス: production は 0.3〜2 程度、max 1〜2、cost は同時代の既存建物並み、
   build_hours は時代0-1: 8-14 / 時代2: 20-40 / 時代3: 40-70 / 時代4: 80-150。
   axis は 1〜4 の控えめな値で3軸に散らす
2. **scripts/location.gd** に新建物の見た目を追加:
   - 既存の KayKit モデル(assets/models/medieval/buildings/<palette>/…)や
     Synty プロップ(_place_synty_model)を再利用してよい
   - 例: 湯屋→tavernモデル+湯気パーティクル、共同かまど→home系+煙、
     干し場→ポール+横木+ぶら下がる食料の手続き生成、
     薬草園→畑風の緑プロット+フェンス
   - _kaykit_building_path の match と _build_visual 系の match に case を足す方式。
     モデルが無い建物は _build_simple_building にフォールバックで良いが、
     色(color)と屋根で差別化すること
3. **scripts/projects.gd** は **POLICIES 定数の projects 配列に新IDを足すことだけ**許可
   (実り=食料系、匠=生産系、星=知識魔素系、森=自然系に振り分け)。他のコード変更禁止
4. 任意: data/cheats.json に湯屋・印刷所のチート追加(形式は既存に倣う)、
   data/thoughts.json に lead_<新ID> の思考を2本ずつ追加

## 制約
- UTF-8で読み書き、apply_patchのみ
- scripts/ は location.gd の見た目追加と projects.gd の POLICIES 配列以外変更禁止
- 検証: `tools\godot\Godot_v4.6.3-stable_mono_win64_console.exe --headless --path . --quit`
  で SCRIPT ERROR ゼロ、続けて `-- --selftest` で SELFTEST OK を確認して報告
