// ============================================================
// game.as  -  カラハ（マンカラ）コアロジック
// ============================================================
//
// 盤面インデックス:
//   0〜5  : 先手の小穴
//   6     : 先手のストア
//   7〜12 : 後手の小穴
//   13    : 後手のストア
//
// ユニット変数（対局中メモリ）:
//   game_board        線形配列[14]  各穴の石数
//   game_stone_hole   線形配列[48]  石nが現在いる穴インデックス
//   game_turn         "first" / "second"
//   game_in_progress  true / false
//   game_first_name   先手プレイヤー名
//   game_second_name  後手プレイヤー名
//   game_first_type   "user" / "own_ai" / "host_ai:easy" / etc.
//   game_second_type  同上
// ============================================================

// 正面の穴インデックス（取り込みルール用）
// 先手 i (0〜5) の正面 = 12 - i
function OppositeHole(i) {
	return 12 - i;
}

// 盤面を初期状態に戻す
function GameInitBoard() {
	game_board = [4,4,4,4,4,4,0,4,4,4,4,4,4,0];

	// 石個体追跡：初期配置
	// 穴0→石0〜3、穴1→石4〜7、…、穴5→石20〜23
	// 穴7→石24〜27、穴8→石28〜31、…、穴12→石44〜47
	// ストア（穴6・13）は初期状態で0個
	game_stone_hole = [];
	local stoneIdx = 0;
	for(local hole = 0; hole <= 5; hole = hole + 1) {
		for(local s = 0; s < 4; s = s + 1) {
			game_stone_hole.Add(hole);
			stoneIdx = stoneIdx + 1;
		}
	}
	for(local hole = 7; hole <= 12; hole = hole + 1) {
		for(local s = 0; s < 4; s = s + 1) {
			game_stone_hole.Add(hole);
			stoneIdx = stoneIdx + 1;
		}
	}
}

// 対局を開始する
// firstType, secondType : "user" / "own_ai" / "host_ai:easy" / "host_ai:normal" / "host_ai:hard"
function GameStart(firstName, secondName, firstType, secondType) {
	GameInitBoard();
	InitStoneCoords();
	game_turn         = "first";
	game_in_progress  = true;
	game_first_name   = firstName;
	game_second_name  = secondName;
	game_first_type   = firstType;
	game_second_type  = secondType;
}

// 対局を終了する（ステータスはクリアしない。ログ保存後に呼ぶこと）
function GameReset() {
	game_in_progress             = false;
	game_ghost_raiseother_first  = null;
	game_ghost_raiseother_second = null;
}

// ----------------------------------------------------------------
// 手番判定ヘルパー
// ----------------------------------------------------------------

// holeIdx が currentTurn プレイヤーの小穴か
function IsOwnHole(holeIdx, currentTurn) {
	if(currentTurn == "first") {
		return holeIdx >= 0 && holeIdx <= 5;
	}
	return holeIdx >= 7 && holeIdx <= 12;
}

// currentTurn プレイヤーのストアインデックス
function StoreIndex(currentTurn) {
	if(currentTurn == "first") {
		return 6;
	}
	return 13;
}

// currentTurn の相手プレイヤー
function OtherTurn(currentTurn) {
	if(currentTurn == "first") {
		return "second";
	}
	return "first";
}

// ----------------------------------------------------------------
// 石の配布
// ----------------------------------------------------------------
// 戻り値：{ lastIdx: 最後に置いた穴, orderedStones: 配布順の石インデックス配列 }
function DistributeStones(holeIdx, currentTurn) {
	local stones = game_board[holeIdx];
	game_board[holeIdx] = 0;

	local enemyStore = StoreIndex(OtherTurn(currentTurn));
	local cur = holeIdx;

	// この穴にいる石をランダムな順に集める
	local movingStones = [];
	for(local n = 0; n < 48; n = n + 1) {
		if(game_stone_hole[n] == holeIdx) {
			movingStones.Add(n);
		}
	}
	// Fisher-Yates シャッフル
	for(local i = movingStones.length - 1; i > 0; i = i - 1) {
		local j = Random.GetIndex(0, i + 1);
		local tmp = movingStones[i];
		movingStones[i] = movingStones[j];
		movingStones[j] = tmp;
	}

	// 配布順に石を置き、その順番を orderedStones に記録
	local orderedStones = [];
	for(local i = 0; i < stones; i = i + 1) {
		cur = (cur + 1) % 14;
		// 相手のストアはスキップ
		if(cur == enemyStore) {
			cur = (cur + 1) % 14;
		}
		game_board[cur] = game_board[cur] + 1;
		game_stone_hole[movingStones[i]] = cur;
		orderedStones.Add(movingStones[i]);
	}

	return { lastIdx: cur, orderedStones: orderedStones };
}

// ----------------------------------------------------------------
// 取り込みルール
// ----------------------------------------------------------------

// 取り込みが発生するか判定のみ行う（盤面・stone_hole は変更しない）
// 戻り値: { canCapture, oppHole } （oppHole: 正面の穴インデックス）
function CheckCapture(lastIdx, currentTurn) {
	if(!IsOwnHole(lastIdx, currentTurn)) {
		return { canCapture: false, oppHole: -1 };
	}
	if(game_board[lastIdx] != 1) {
		return { canCapture: false, oppHole: -1 };
	}
	local oppHole;
	if(currentTurn == "first") {
		oppHole = OppositeHole(lastIdx);
	} else {
		oppHole = 12 - lastIdx;
		if(oppHole < 0 || oppHole > 5) {
			return { canCapture: false, oppHole: -1 };
		}
	}
	if(game_board[oppHole] <= 0) {
		return { canCapture: false, oppHole: -1 };
	}
	return { canCapture: true, oppHole: oppHole };
}

// 取り込みを実行する（CheckCapture で canCapture==true のとき呼ぶ）
// 戻り値：取り込みで移動した石インデックスの配列
function ExecuteCapture(lastIdx, oppHole, currentTurn) {
	local captured = [];
	local myStore = StoreIndex(currentTurn);
	game_board[myStore] = game_board[myStore] + game_board[lastIdx] + game_board[oppHole];
	game_board[lastIdx] = 0;
	game_board[oppHole] = 0;
	for(local n = 0; n < 48; n = n + 1) {
		if(game_stone_hole[n] == lastIdx || game_stone_hole[n] == oppHole) {
			game_stone_hole[n] = myStore;
			captured.Add(n);
		}
	}
	return captured;
}

// ----------------------------------------------------------------
// ゲーム終了チェック
// ----------------------------------------------------------------
// どちらかの全小穴が空なら true
function IsGameOver() {
	local firstEmpty = true;
	for(local i = 0; i <= 5; i = i + 1) {
		if(game_board[i] > 0) {
			firstEmpty = false;
			break;
		}
	}
	if(firstEmpty) {
		return true;
	}

	local secondEmpty = true;
	for(local i = 7; i <= 12; i = i + 1) {
		if(game_board[i] > 0) {
			secondEmpty = false;
			break;
		}
	}
	return secondEmpty;
}

// 残石を各ストアへ回収してゲームを終わらせる
// outMoved : 移動した石インデックスを追加する配列（呼び出し元から渡す）
function CollectRemainingStones(outMoved) {
	for(local i = 0; i <= 5; i = i + 1) {
		game_board[6] = game_board[6] + game_board[i];
		game_board[i] = 0;
	}
	for(local i = 7; i <= 12; i = i + 1) {
		game_board[13] = game_board[13] + game_board[i];
		game_board[i] = 0;
	}
	// 石個体を各ストアへ移動
	for(local n = 0; n < 48; n = n + 1) {
		local h = game_stone_hole[n];
		if(h >= 0 && h <= 5) {
			game_stone_hole[n] = 6;
			outMoved.Add(n);
		} else if(h >= 7 && h <= 12) {
			game_stone_hole[n] = 13;
			outMoved.Add(n);
		}
	}
}

// 勝敗を返す。"first_win" / "second_win" / "draw"
function GetGameResult() {
	if(game_board[6] > game_board[13]) {
		return "first_win";
	}
	if(game_board[13] > game_board[6]) {
		return "second_win";
	}
	return "draw";
}

// ----------------------------------------------------------------
// メインの手番処理
// ----------------------------------------------------------------
// 戻り値（連想配列）:
//   result           : "ok" / "error"
//   error            : エラー種別（resultがerrorのとき）
//   distributeStones : 配布した石のインデックス配列（配布順）
//   captureInfo      : { canCapture, oppHole } 取り込み判定結果
//                      canCapture==true のとき、呼び出し側が ApplyCapture を呼ぶ
//   bonus            : true（連続手番）/ false  ※取り込み実行後に確定
//   gameover         : ※ApplyCapture / FinalizeMove 呼び出し後に確定
function ExecuteMove(holeIdx) {
	if(!game_in_progress) {
		return { result: "error", error: "game_not_started" };
	}
	if(!IsOwnHole(holeIdx, game_turn)) {
		return { result: "error", error: "invalid_move" };
	}
	if(game_board[holeIdx] <= 0) {
		return { result: "error", error: "invalid_move" };
	}

	local myStore = StoreIndex(game_turn);

	// 石を配布（配布順の石リストを受け取る）
	local dist = DistributeStones(holeIdx, game_turn);
	local lastIdx = dist.lastIdx;
	local distributeStones = dist.orderedStones;

	// 取り込み判定（盤面は変更しない）
	local captureInfo = CheckCapture(lastIdx, game_turn);

	local bonus = (lastIdx == myStore);

	return { result: "ok", distributeStones: distributeStones,
	         captureInfo: captureInfo, bonus: bonus, lastIdx: lastIdx };
}

// 取り込みを実行して結果を返す
// lastIdx : ExecuteMove の戻り値の lastIdx
// captureInfo : ExecuteMove の戻り値の captureInfo
// 戻り値: { captured, capturedCount }
function ApplyCapture(lastIdx, captureInfo) {
	local captured = ExecuteCapture(lastIdx, captureInfo.oppHole, game_turn);
	return { captured: captured, capturedCount: captured.length };
}

// 手番を終了させる（取り込み・アニメーション完了後に呼ぶ）
// 戻り値: { gameover, bonus, collectMoved }
function FinalizeMove(bonus) {
	if(IsGameOver()) {
		local collectMoved = [];
		CollectRemainingStones(collectMoved);
		game_in_progress = false;
		return { gameover: true, bonus: false, collectMoved: collectMoved };
	}
	if(!bonus) {
		game_turn = OtherTurn(game_turn);
	}
	return { gameover: false, bonus: bonus, collectMoved: [] };
}

// ----------------------------------------------------------------
// 盤面シリアライズ
// ----------------------------------------------------------------
// "4,4,4,4,4,4,0,4,4,4,4,4,4,0" 形式で返す
function SerializeBoard() {
	local s = "";
	for(local i = 0; i < 14; i = i + 1) {
		if(i > 0) {
			s = s + ",";
		}
		s = s + game_board[i];
	}
	return s;
}

// ----------------------------------------------------------------
// 優勢情報
// ----------------------------------------------------------------
// "winning" / "losing" / "even"  （対応ゴーストから見た判定）
function GetAdvantage(perspective) {
	local myStore;
	local enemyStore;
	if(perspective == "first") {
		myStore    = game_board[6];
		enemyStore = game_board[13];
	} else {
		myStore    = game_board[13];
		enemyStore = game_board[6];
	}
	local diff = myStore - enemyStore;
	if(diff >= 3) {
		return "winning";
	}
	if(diff <= -3) {
		return "losing";
	}
	return "even";
}
