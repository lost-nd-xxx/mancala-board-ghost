// ============================================================
// ai.as  -  台ゴーストAI
// ============================================================
//
// 難易度:
//   easy   : 空でない自分の小穴からランダムに選択
//   normal : 1手先評価（自ストア増加量が最大になる手を選択）
//   hard   : Minimax（深さ4、連続手番考慮）
//
// 全関数は game_board を直接変更せず、コピーを使って計算する。
// ============================================================

// ----------------------------------------------------------------
// 共通ヘルパー：盤面コピー
// ----------------------------------------------------------------
function CopyBoard(board) {
	local copy = [];
	for(local i = 0; i < 14; i = i + 1) {
		copy.Add(board[i]);
	}
	return copy;
}

// ----------------------------------------------------------------
// 盤面コピー上でカラハの1手を実行する
// 戻り値（連想配列）:
//   board : 更新後の盤面配列
//   bonus : 連続手番か否か（true/false）
//   gameover : ゲーム終了か否か
// ----------------------------------------------------------------
function SimulateMove(board, holeIdx, currentTurn) {
	local b = CopyBoard(board);

	local enemyStore;
	local myStore;
	if(currentTurn == "first") {
		myStore    = 6;
		enemyStore = 13;
	} else {
		myStore    = 13;
		enemyStore = 6;
	}

	local stones = b[holeIdx];
	b[holeIdx] = 0;
	local cur = holeIdx;

	for(local i = 0; i < stones; i = i + 1) {
		cur = (cur + 1) % 14;
		if(cur == enemyStore) {
			cur = (cur + 1) % 14;
		}
		b[cur] = b[cur] + 1;
	}

	// 取り込み判定
	if(currentTurn == "first") {
		if(cur >= 0 && cur <= 5 && b[cur] == 1) {
			local opp = 12 - cur;
			if(b[opp] > 0) {
				b[6] = b[6] + b[cur] + b[opp];
				b[cur] = 0;
				b[opp] = 0;
			}
		}
	} else {
		if(cur >= 7 && cur <= 12 && b[cur] == 1) {
			local firstIdx = 12 - cur;
			if(firstIdx >= 0 && firstIdx <= 5 && b[firstIdx] > 0) {
				b[13] = b[13] + b[cur] + b[firstIdx];
				b[cur] = 0;
				b[firstIdx] = 0;
			}
		}
	}

	// ゲーム終了チェック・残石回収
	local gameover = SimIsGameOver(b);
	if(gameover) {
		for(local i = 0; i <= 5; i = i + 1) {
			b[6] = b[6] + b[i];
			b[i] = 0;
		}
		for(local i = 7; i <= 12; i = i + 1) {
			b[13] = b[13] + b[i];
			b[i] = 0;
		}
	}

	local bonus = (cur == myStore) && !gameover;
	return { board: b, bonus: bonus, gameover: gameover };
}

function SimIsGameOver(board) {
	local firstEmpty = true;
	for(local i = 0; i <= 5; i = i + 1) {
		if(board[i] > 0) {
			firstEmpty = false;
			break;
		}
	}
	if(firstEmpty) {
		return true;
	}
	local secondEmpty = true;
	for(local i = 7; i <= 12; i = i + 1) {
		if(board[i] > 0) {
			secondEmpty = false;
			break;
		}
	}
	return secondEmpty;
}

// currentTurn の有効手リストを返す（穴インデックスの配列）
function GetValidMoves(board, currentTurn) {
	local moves = [];
	if(currentTurn == "first") {
		for(local i = 0; i <= 5; i = i + 1) {
			if(board[i] > 0) {
				moves.Add(i);
			}
		}
	} else {
		for(local i = 7; i <= 12; i = i + 1) {
			if(board[i] > 0) {
				moves.Add(i);
			}
		}
	}
	return moves;
}

// ----------------------------------------------------------------
// Easy AI
// ----------------------------------------------------------------
function AiSelectEasy(currentTurn) {
	local moves = GetValidMoves(game_board, currentTurn);
	return Random.Select(moves);
}

// ----------------------------------------------------------------
// Normal AI  -  1手先評価
// ----------------------------------------------------------------
function AiSelectNormal(currentTurn) {
	local moves = GetValidMoves(game_board, currentTurn);
	local myStore;
	if(currentTurn == "first") {
		myStore = 6;
	} else {
		myStore = 13;
	}

	local bestMove  = moves[0];
	local bestScore = -999;

	foreach(local move in moves) {
		local sim = SimulateMove(game_board, move, currentTurn);
		local score = sim.board[myStore];
		// 連続手番ボーナス
		if(sim.bonus) {
			score = score + 3;
		}
		if(score > bestScore) {
			bestScore = score;
			bestMove  = move;
		}
	}

	return bestMove;
}

// ----------------------------------------------------------------
// Hard AI  -  Minimax（深さ3）
// ----------------------------------------------------------------
local MINIMAX_DEPTH = 3;

// 評価関数：先手有利をプラスで返す
function Evaluate(board) {
	return board[6] - board[13];
}

// Minimax 本体
// maximizing : true = 先手の番、false = 後手の番
function Minimax(board, depth, maximizing) {
	if(depth == 0 || SimIsGameOver(board)) {
		return Evaluate(board);
	}

	local currentTurn;
	if(maximizing) {
		currentTurn = "first";
	} else {
		currentTurn = "second";
	}

	local moves = GetValidMoves(board, currentTurn);
	if(moves.length == 0) {
		return Evaluate(board);
	}

	if(maximizing) {
		local best = -9999;
		foreach(local move in moves) {
			local sim = SimulateMove(board, move, currentTurn);
			local nextMaximizing;
			if(sim.bonus) {
				nextMaximizing = true;
			} else {
				nextMaximizing = false;
			}
			local val = Minimax(sim.board, depth - 1, nextMaximizing);
			if(val > best) {
				best = val;
			}
		}
		return best;
	} else {
		local best = 9999;
		foreach(local move in moves) {
			local sim = SimulateMove(board, move, currentTurn);
			local nextMaximizing;
			if(sim.bonus) {
				nextMaximizing = false;
			} else {
				nextMaximizing = true;
			}
			local val = Minimax(sim.board, depth - 1, nextMaximizing);
			if(val < best) {
				best = val;
			}
		}
		return best;
	}
}

function AiSelectHard(currentTurn) {
	local moves = GetValidMoves(game_board, currentTurn);
	local maximizing = (currentTurn == "first");

	local bestMove  = moves[0];
	local bestScore;
	if(maximizing) {
		bestScore = -9999;
	} else {
		bestScore = 9999;
	}

	foreach(local move in moves) {
		local sim = SimulateMove(game_board, move, currentTurn);
		local nextMaximizing;
		if(sim.bonus) {
			nextMaximizing = maximizing;
		} else {
			nextMaximizing = !maximizing;
		}
		local val = Minimax(sim.board, MINIMAX_DEPTH - 1, nextMaximizing);
		if(maximizing) {
			if(val > bestScore) {
				bestScore = val;
				bestMove  = move;
			}
		} else {
			if(val < bestScore) {
				bestScore = val;
				bestMove  = move;
			}
		}
	}

	return bestMove;
}

// ----------------------------------------------------------------
// 統合エントリポイント
// ----------------------------------------------------------------
// playerType : "host_ai:easy" / "host_ai:normal" / "host_ai:hard"
// currentTurn: "first" / "second"
// 戻り値: 選択した穴インデックス
function AiSelectMove(playerType, currentTurn) {
	if(playerType == "host_ai:easy") {
		return AiSelectEasy(currentTurn);
	}
	if(playerType == "host_ai:normal") {
		return AiSelectNormal(currentTurn);
	}
	if(playerType == "host_ai:hard") {
		return AiSelectHard(currentTurn);
	}
	// フォールバック
	return AiSelectEasy(currentTurn);
}
