// ============================================================
// protocol.as  -  対応ゴーストへの raiseother 送信まとめ
// ============================================================
//
// 全関数はさくらスクリプト文字列を返す。
// 呼び出し元（main.as）が return や文字列連結で使用すること。
//
// 送信先ゴースト名は game_first_name / game_second_name から取得する。
// プレイヤー種別が "user" の場合は raiseother を送信しない（空文字を返す）。
// ============================================================

// ----------------------------------------------------------------
// 内部ヘルパー
// ----------------------------------------------------------------

// perspective（"first"/"second"）の相手ゴースト名を返す
function GetOpponentName(perspective) {
	if(perspective == "first") {
		return game_second_name;
	}
	return game_first_name;
}

// perspective のプレイヤー種別を返す
function GetPlayerType(perspective) {
	if(perspective == "first") {
		return game_first_type;
	}
	return game_second_type;
}

// raiseother 送信に使うゴースト名（題名）を返す
// OnMancalaRequestGame 経由で参加したゴーストには playerType に関わらず送信する
// game_ghost_raiseother_first/second が null なら送信不要（user/host_ai のみの対局）
function GetRaiseotherName(perspective) {
	if(perspective == "first") {
		return game_ghost_raiseother_first;
	}
	return game_ghost_raiseother_second;
}

// raiseother コマンドを1行生成する（引数は可変なので文字列で受け取る）
// args : "r0,r1,r2" のようにカンマ区切りで渡す
function MakeRaiseother(targetName, eventName, args) {
	if(args == "" || args == null) {
		return "\![raiseother," + targetName + "," + eventName + "]";
	}
	return "\![raiseother," + targetName + "," + eventName + "," + args + "]";
}

// ----------------------------------------------------------------
// OnMancalaGameStart  -  先後通知＋対戦相手情報
// ----------------------------------------------------------------
// perspective    : 送信先から見た先後 ("first" / "second")
// oppDisplayName : 送信先から見た相手の呼び名
// oppGhostName   : 送信先から見た相手のゴースト名（raiseother名。相手が人間/台AIなら ""）
function SendGameStart(targetName, perspective, oppDisplayName, oppGhostName) {
	local dq = `"`;
	local name = oppGhostName;
	if(name == null) { name = ""; }
	local args = perspective + "," + dq + oppDisplayName + dq + "," + dq + name + dq;
	return MakeRaiseother(targetName, "OnMancalaGameStart", args);
}

// 両プレイヤーへ先後通知を送る（raiseother対象のゴーストのみ）
function BroadcastGameStart() {
	local script = "";
	local rn1 = GetRaiseotherName("first");
	local rn2 = GetRaiseotherName("second");
	// 先手への通知：相手は後手
	if(rn1 != null) {
		script = script + SendGameStart(rn1, "first", game_second_name, game_ghost_raiseother_second);
	}
	// 後手への通知：相手は先手
	if(rn2 != null) {
		script = script + SendGameStart(rn2, "second", game_first_name, game_ghost_raiseother_first);
	}
	return script;
}

// ----------------------------------------------------------------
// OnMancalaStateUpdate  -  盤面状態通知
// ----------------------------------------------------------------
// turnStatus : "your_turn" / "your_bonus_turn" / "opponent_turn" / "opponent_bonus_turn"
function SendStateUpdate(targetName, boardStr, turnStatus, advantage) {
	local dq = `"`;
	local args = dq + boardStr + dq + "," + turnStatus + "," + advantage;
	return MakeRaiseother(targetName, "OnMancalaStateUpdate", args);
}

// 手番処理後に両プレイヤーへ盤面を通知する
// activeTurn  : 今まさに手番を持つプレイヤー ("first" / "second")
// isBonus     : 連続手番か否か
function BroadcastStateUpdate(activeTurn, isBonus) {
	local script  = "";
	local boardStr = SerializeBoard();

	// 先手への通知
	local rn1 = GetRaiseotherName("first");
	if(rn1 != null) {
		local turnStatus1;
		if(activeTurn == "first") {
			if(isBonus) { turnStatus1 = "your_bonus_turn"; } else { turnStatus1 = "your_turn"; }
		} else {
			if(isBonus) { turnStatus1 = "opponent_bonus_turn"; } else { turnStatus1 = "opponent_turn"; }
		}
		script = script + SendStateUpdate(rn1, boardStr, turnStatus1, GetAdvantage("first"));
	}

	// 後手への通知
	local rn2 = GetRaiseotherName("second");
	if(rn2 != null) {
		local turnStatus2;
		if(activeTurn == "second") {
			if(isBonus) { turnStatus2 = "your_bonus_turn"; } else { turnStatus2 = "your_turn"; }
		} else {
			if(isBonus) { turnStatus2 = "opponent_bonus_turn"; } else { turnStatus2 = "opponent_turn"; }
		}
		script = script + SendStateUpdate(rn2, boardStr, turnStatus2, GetAdvantage("second"));
	}

	return script;
}

// ----------------------------------------------------------------
// OnMancalaGameEnd  -  ゲーム終了通知
// ----------------------------------------------------------------
function SendGameEnd(targetName, resultFromTheirView, boardStr) {
	local dq = `"`;
	local args = resultFromTheirView + "," + dq + boardStr + dq;
	return MakeRaiseother(targetName, "OnMancalaGameEnd", args);
}

// 両プレイヤーへゲーム終了を通知する
// gameResult : "first_win" / "second_win" / "draw"
function BroadcastGameEnd(gameResult) {
	local script   = "";
	local boardStr = SerializeBoard();

	local rn1 = GetRaiseotherName("first");
	if(rn1 != null) {
		local r1;
		if(gameResult == "first_win") { r1 = "win"; } else if(gameResult == "second_win") { r1 = "lose"; } else { r1 = "draw"; }
		script = script + SendGameEnd(rn1, r1, boardStr);
	}

	local rn2 = GetRaiseotherName("second");
	if(rn2 != null) {
		local r2;
		if(gameResult == "second_win") { r2 = "win"; } else if(gameResult == "first_win") { r2 = "lose"; } else { r2 = "draw"; }
		script = script + SendGameEnd(rn2, r2, boardStr);
	}

	return script;
}

// ----------------------------------------------------------------
// OnMancalaGameVoid  -  無効試合通知（タイムアウト・投了による中断）
// ----------------------------------------------------------------
function BroadcastGameVoid() {
	local script = "";
	local rn1 = GetRaiseotherName("first");
	local rn2 = GetRaiseotherName("second");
	if(rn1 != null) { script = script + MakeRaiseother(rn1, "OnMancalaGameVoid", ""); }
	if(rn2 != null) { script = script + MakeRaiseother(rn2, "OnMancalaGameVoid", ""); }
	return script;
}

// ----------------------------------------------------------------
// OnMancalaError  -  エラー通知（送信元ゴーストへのみ）
// ----------------------------------------------------------------
// errorCode : "invalid_move" / "not_your_turn" / "game_not_started" /
//             "game_in_progress" / "not_your_game" / "not_waiting"
function SendError(targetName, errorCode) {
	return MakeRaiseother(targetName, "OnMancalaError", errorCode);
}
