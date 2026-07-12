# テクスチャ多様化ブリーフ (for Codex)

新しいタイルテクスチャ10種を生成済み: `assets/textures/` の tex_cobble(石畳) / tex_flowers(花畑) / tex_plaster(漆喰) / tex_gravel(砂利) / tex_crops(作物の列) / tex_cloth(布・赤クリーム縞) / tex_metal(真鍮金属板) / tex_moss_stone(苔石) / tex_dark_planks(黒木材) / tex_sand(砂)。

これらを使って世界の質感の多様性を上げる。割当は君のデザイン判断だが、例:
- 広場 → tex_cobble、道になりそうな場所や祠の周り → tex_gravel/tex_moss_stone
- 畑の作付け面 → tex_crops、学び舎/診療所の壁 → tex_plaster
- 市場の屋台 → tex_cloth、大機関/鍛冶場の一部 → tex_metal
- 川辺 → tex_sand、古い建物・城壁 → tex_moss_stone、木こり場 → tex_dark_planks
- 地面の草原に tex_flowers のパッチを数カ所(単調さ回避)

制約(継続): シミュ本体・data/*.json不変。画像読込は U.load_texture_file のみ。Label3Dのfixed_size禁止・カラー絵文字禁止。カメラ操作変更禁止。UTF-8読み(化けたらパッチに使わない)。編集はapply_patchのみ。
検証: tools\godot\Godot_v4.6.3-stable_mono_win64_console.exe で --quit にSCRIPT ERRORなし / --selftest OK / --shot-day と --shot-night を自分の目で確認。コミットしない。
