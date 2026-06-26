// ============================================================
// draw.as  -  石アニメーション更新
// ============================================================
//
// 穴座標は _workspace/shell/ellipse_rects.txt の値をそのまま使用。
// 石画像サイズ 20x20 のため、各穴の配置可能矩形は
//   x: TopLeft.x + 10  〜  BotRight.x - 10
//   y: TopLeft.y + 10  〜  BotRight.y - 10
//
// 穴インデックス対応:
//   0〜5  : 先手小穴
//   6     : 先手ストア
//   7〜12 : 後手小穴
//   13    : 後手ストア
// ============================================================

// 穴ごとの配置可能矩形（石左上端の移動可能範囲）
// 楕円内接矩形の左上をそのまま使い、右下に石直径20pxのマージンを取る
// 石左上端がこの範囲に収まれば石全体が楕円内接矩形内に収まる
local HOLE_RECT = [
	[130, 190, 153, 230],  //  0: 先手小穴0
	[210, 191, 233, 230],  //  1: 先手小穴1
	[290, 191, 312, 230],  //  2: 先手小穴2
	[369, 190, 393, 230],  //  3: 先手小穴3
	[449, 190, 471, 230],  //  4: 先手小穴4
	[528, 190, 552, 230],  //  5: 先手小穴5
	[607,  83, 633, 208],  //  6: 先手ストア
	[528,  62, 552, 104],  //  7: 後手小穴0
	[449,  62, 473, 104],  //  8: 後手小穴1
	[370,  62, 393, 104],  //  9: 後手小穴2
	[290,  63, 313, 104],  // 10: 後手小穴3
	[210,  63, 233, 104],  // 11: 後手小穴4
	[129,  62, 153, 104],  // 12: 後手小穴5
	[ 45,  83,  73, 208],  // 13: 後手ストア
];

// 石の初期位置（surfaces.txt で画面外に配置されている座標）
local STONE_BASE_X = 0;
local STONE_BASE_Y = 320;

// 各石の現在座標（ユニット変数）
// game_stone_x[n] / game_stone_y[n] : 石nの現在の絶対座標

// 衝突回避パラメータ
local COLLISION_DIST = 20;   // この距離未満は重なりとみなす（石サイズ20px基準）
local COLLISION_TRIES = 4;   // 最大試行回数

// ----------------------------------------------------------------
// 石48個の座標を更新するさくらスクリプトを生成して返す
// game_stone_hole[n] を参照して石nがいる穴を特定し、
// その穴の矩形内で衝突回避しながらランダムに配置する。
// COLLISION_TRIES 回試行して回避できなければ重なりを許容する。
// ----------------------------------------------------------------

// 確定済み石座標を穴ごとに保持する連想配列
// placed_x[holeIdx] / placed_y[holeIdx] : 各穴の配置済み座標リスト
local placed_x = {};
local placed_y = {};

// 穴の配置済みリストを初期化（全石の現在座標を登録）
function ClearPlacedStones() {
	placed_x = {};
	placed_y = {};
	for(local i = 0; i < 14; i = i + 1) {
		placed_x[i] = [];
		placed_y[i] = [];
	}
}

// 移動していない石の現在座標を placed に登録する
// movedStones : 移動した石のインデックス配列（これらは登録しない）
function RegisterUnmovedStones(movedStones) {
	ClearPlacedStones();
	for(local n = 0; n < 48; n = n + 1) {
		// 移動した石かどうか確認
		local isMoved = false;
		foreach(local m in movedStones) {
			if(m == n) {
				isMoved = true;
				break;
			}
		}
		if(!isMoved) {
			local holeIdx = game_stone_hole[n];
			placed_x[holeIdx].Add(game_stone_x[n]);
			placed_y[holeIdx].Add(game_stone_y[n]);
		}
	}
}

// (cx,cy) が穴holeIdx の配置済み石と衝突しないか判定
function HasCollision(holeIdx, cx, cy) {
	local xs = placed_x[holeIdx];
	local ys = placed_y[holeIdx];
	local count = xs.length;
	for(local i = 0; i < count; i = i + 1) {
		local dx = cx - xs[i];
		local dy = cy - ys[i];
		// 距離の二乗で比較（平方根不要）
		if(dx * dx + dy * dy < COLLISION_DIST * COLLISION_DIST) {
			return true;
		}
	}
	return false;
}

// 石座標の永続配列を初期化（対局開始時に呼ぶ）
function InitStoneCoords() {
	game_stone_x = [];
	game_stone_y = [];
	for(local i = 0; i < 48; i = i + 1) {
		game_stone_x.Add(STONE_BASE_X);
		game_stone_y.Add(STONE_BASE_Y);
	}
}

// 石1個の目標座標を決定して placed・game_stone_x/y に登録し、オフセットコマンドを返す
function PlaceOneStone(n, holeIdx) {
	local rect   = HOLE_RECT[holeIdx];
	local x1     = rect[0];
	local y1     = rect[1];
	local x2     = rect[2];
	local y2     = rect[3];
	local rangeX = x2 - x1;
	local rangeY = y2 - y1;

	local sx = x1 + Random.GetIndex(0, rangeX);
	local sy = y1 + Random.GetIndex(0, rangeY);

	// 衝突回避：最大 COLLISION_TRIES 回試行
	for(local t = 0; t < COLLISION_TRIES; t = t + 1) {
		local cx = x1 + Random.GetIndex(0, rangeX);
		local cy = y1 + Random.GetIndex(0, rangeY);
		if(!HasCollision(holeIdx, cx, cy)) {
			sx = cx;
			sy = cy;
			break;
		}
	}

	placed_x[holeIdx].Add(sx);
	placed_y[holeIdx].Add(sy);
	game_stone_x[n] = sx;
	game_stone_y[n] = sy;

	local ox = sx - STONE_BASE_X;
	local oy = sy - STONE_BASE_Y;
	return "\![anim,offset,stone" + n + "," + ox + "," + oy + "]";
}

// 石48個を1石ずつ100msウェイト付きで更新するさくらスクリプトを返す
// 初回配置用（全石・ウェイトなし）
function BuildStoneAnimScriptNoWait() {
	local script = "";
	ClearPlacedStones();

	for(local n = 0; n < 48; n = n + 1) {
		local holeIdx = game_stone_hole[n];
		script = script + PlaceOneStone(n, holeIdx);
	}

	return script;
}

// 演出速度（ms）を返す。Save.Data.anim_speed の値に応じて切り替え。
// "none":0  "fast":200  "normal":500（デフォルト）
function GetAnimWait() {
	local sp = Save.Data.anim_speed;
	if(sp == null) { Save.Data.anim_speed = "normal"; return 500; }
	if(sp == "none") { return 0; }
	if(sp == "fast") { return 200; }
	if(sp == "slow") { return 600; }
	return 500;
}

// ms ミリ秒を anim_speed に応じてスケールし、"\_w[N]" タグを返す。
// none のときは空文字列を返す。
function ScaleWait(ms) {
	local sp = Save.Data.anim_speed;
	if(sp == "none") { return ""; }
	if(sp == "fast") { return "\_w[" + (ms * 2 / 5) + "]"; }
	if(sp == "slow") { return "\_w[" + (ms * 1.2).Round() + "]"; }
	return "\_w[" + ms + "]";
}

// 手番開始時に一度だけ呼ぶ。移動しない石を placed に登録して衝突判定を準備する。
// allMovedStones : この手番で移動する全石のインデックス配列
function PrepareStoneAnim(allMovedStones) {
	RegisterUnmovedStones(allMovedStones);
}

// PrepareStoneAnim の後に呼ぶ。targetStones をアニメーションするスクリプトを返す。
// 配置した石は placed に追加されるため、続けて呼べば衝突判定が引き継がれる。
function AppendStoneAnimScript(targetStones) {
	local script = "";
	local wait = GetAnimWait();
	foreach(local n in targetStones) {
		local holeIdx = game_stone_hole[n];
		if(wait > 0) {
			script = script + PlaceOneStone(n, holeIdx) + "\_w[" + wait + "]";
		} else {
			script = script + PlaceOneStone(n, holeIdx);
		}
	}
	return script;
}

// 後方互換用ラッパー（allMoved == targetStones の場合）
function BuildStoneAnimScript(movedStones) {
	PrepareStoneAnim(movedStones);
	return AppendStoneAnimScript(movedStones);
}

// 石1個の保存座標 game_stone_x/y[n] を、乱数を引かずそのまま再送する。
// 既に確定済みの座標を画面へ再反映するだけなので、穴内のランダム配置は変わらない。
function ReassertOneStone(n) {
	local ox = game_stone_x[n] - STONE_BASE_X;
	local oy = game_stone_y[n] - STONE_BASE_Y;
	return "\![anim,offset,stone" + n + "," + ox + "," + oy + "]";
}

// 全48石を保存座標のまま再送するスクリプトを返す。
// 手番末尾・終了時に一度流すことで、途中で取りこぼされた \![anim] があっても
// 最終的に全石が game_stone_x/y（＝game_stone_hole に対応する確定座標）へ補正される。
// 乱数を引かないため、アナログなランダム配置は保たれる。
function BuildStoneRefreshScript() {
	local script = "";
	for(local n = 0; n < 48; n = n + 1) {
		script = script + ReassertOneStone(n);
	}
	return script;
}

// 全石を画面外に戻すスクリプトを返す（対局終了・リセット時）
function BuildClearStoneScript() {
	local script = "";
	for(local i = 0; i < 48; i = i + 1) {
		script = script + "\![anim,offset,stone" + i + ",0,0]";
	}
	return script;
}
