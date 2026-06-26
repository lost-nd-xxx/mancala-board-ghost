// ============================================================
// game_event.as  -  対応ゴーストからの raiseother 受信イベント
// ============================================================
//
// 受信イベント一覧（台ゴースト側）:
//   OnMancalaRequestGame  対局リクエスト
//   OnMancalaMove         手番操作
//   OnMancalaResign       投了
//
// Shiori.Reference:
//   OnMancalaRequestGame : [0]=ゴースト名  [1]=AI種別  [2]=先後希望
//   OnMancalaMove        : [0]=穴インデックス
//   OnMancalaResign      : なし
//
// 送信元ゴースト名は Shiori.Reference[0]（RequestGame）または
// Shiori.Headers["Sender"] で取得する。
// ※ OnMancalaMove / OnMancalaResign では送信元を
//    game_first_name / game_second_name と照合して判別する。
// ============================================================

// ----------------------------------------------------------------
// 先後決定ヘルパー
// ----------------------------------------------------------------
// req1 / req2 : "first" / "second" / "any"
// 戻り値 : { first: req1側の名前, second: req2側の名前,
//            firstType: ..., secondType: ... }
function DecideOrder(name1, type1, req1, name2, type2, req2) {
	local name1IsFirst;

	if(req1 == "first" && req2 == "second") {
		name1IsFirst = true;
	} else if(req1 == "second" && req2 == "first") {
		name1IsFirst = false;
	} else if(req1 == "first" && req2 != "second") {
		name1IsFirst = true;
	} else if(req1 == "second" && req2 != "first") {
		name1IsFirst = false;
	} else if(req2 == "first" && req1 != "second") {
		name1IsFirst = false;
	} else if(req2 == "second" && req1 != "first") {
		name1IsFirst = true;
	} else {
		// first vs first / second vs second / any vs any → ランダム
		name1IsFirst = (Random.GetIndex(0, 2) == 0);
	}

	if(name1IsFirst) {
		return { firstName: name1, firstType: type1, secondName: name2, secondType: type2 };
	}
	return { firstName: name2, firstType: type2, secondName: name1, secondType: type1 };
}

// ----------------------------------------------------------------
// 対応ゴーストが1人の場合の先後決定
// （ユーザ側の希望は対局開始UIで別途取得するため、
//   ここでは台側をユーザとして扱い "any" を渡す）
// ----------------------------------------------------------------

// ----------------------------------------------------------------
// OnMancalaRequestGame
// R0: ゴースト名（題名。raiseotherで使う方）
// R1: 呼び名（手番表示などで使う名前）
// R2: AI種別
// R3: 先後希望
// ----------------------------------------------------------------
function OnMancalaRequestGame {
	local senderName  = Shiori.Reference[0];  // raiseother 送信先に使う名前
	local displayName = Shiori.Reference[1];  // 手番等の表示に使う名前
	local aiType      = Shiori.Reference[2];
	local orderReq    = Shiori.Reference[3];

	// 呼び名が省略された場合はゴースト名で代用
	if(displayName == null || displayName == "") {
		displayName = senderName;
	}

	// 対局中は受け付けない
	if(game_in_progress) {
		return SendError(senderName, "game_in_progress");
	}

	// 待機中でなければ受け付けない
	if(game_waiting_mode == null) {
		return SendError(senderName, "not_waiting");
	}

	local script = "";

	if(game_waiting_mode == "user_vs_ghost") {
		// ユーザ vs ゴースト：1体で対局開始
		game_waiting_mode = null;
		local userReq = game_user_order_req;
		if(userReq == null || userReq == "") { userReq = "any"; }

		local order = DecideOrder(
			"ユーザ", "user", userReq,
			displayName, aiType, orderReq
		);
		if(order.firstName == displayName) {
			// ゴーストが先手
			game_ghost_raiseother_first  = senderName;
			game_ghost_raiseother_second = null;
		} else {
			// ゴーストが後手
			game_ghost_raiseother_first  = null;
			game_ghost_raiseother_second = senderName;
		}
		GameStart(order.firstName, order.secondName, order.firstType, order.secondType);
		script = script + BuildStoneAnimScriptNoWait();
		script = script + BroadcastGameStart();
		script = script + BuildGameStartTalk();
		script = script + BroadcastStateUpdate("first", false);
		if(game_first_type == "user" || game_first_type == "own_ai") {
			script = script + BuildTurnTalk(false);
		} else {
			script = script + ExecuteAiTurn();
		}

	} else if(game_waiting_mode == "ghost_vs_ghost") {
		if(game_waiting_ghost1_name == null) {
			// 1体目を記録して引き続き待機
			game_waiting_ghost1_name        = senderName;
			game_waiting_ghost1_displayname = displayName;
			game_waiting_ghost1_type        = aiType;
			script = script + "\0\s[0]\_q\_?" + displayName + "\_?が参加を申請しました。\nもう1体のゴーストを待っています...\![set,balloontimeout,-1]"
				+ "\n\n\![*]\q[キャンセル,OnMancalaWaitCancel]";
		} else {
			// 2体目で対局開始（ゴースト vs ゴースト）
			game_waiting_mode = null;
			local name1        = game_waiting_ghost1_name;
			local dname1       = game_waiting_ghost1_displayname;
			local type1        = game_waiting_ghost1_type;
			game_waiting_ghost1_name        = null;
			game_waiting_ghost1_displayname = null;
			game_waiting_ghost1_type        = null;

			local order = DecideOrder(
				dname1, type1, "any",
				displayName, aiType, orderReq
			);
			if(order.firstName == dname1) {
				game_ghost_raiseother_first  = name1;
				game_ghost_raiseother_second = senderName;
			} else {
				game_ghost_raiseother_first  = senderName;
				game_ghost_raiseother_second = name1;
			}
			GameStart(order.firstName, order.secondName, order.firstType, order.secondType);
			script = script + BuildStoneAnimScriptNoWait();
			script = script + BroadcastGameStart();
			script = script + BuildGameStartTalk();
			script = script + BroadcastStateUpdate("first", false);
			// 先手が台AI(host_ai)なら台が着手、own_ai なら相手ゴーストの着手を待つ
			if(game_first_type == "user" || game_first_type == "own_ai") {
				script = script + BuildTurnTalk(false);
			} else {
				script = script + ExecuteAiTurn();
			}
		}
	}

	return script;
}

// ----------------------------------------------------------------
// OnMancalaMove
// R0: ゴースト名（OnMancalaRequestGame の R0 と同じ名前）
// R1: 穴インデックス
// ----------------------------------------------------------------
function OnMancalaMove {
	local senderName = Shiori.Reference[0];
	// 数値化：蒼空では「文字列+数値」は連結、「文字列*数値」はNaNになるため
	// 明示的に .ToNumber() を使う
	local holeIdx    = Shiori.Reference[1].ToNumber();

	if(!game_in_progress) {
		return SendError(senderName, "game_not_started");
	}

	// 送信元が参加者か確認（raiseother名で照合）
	if(senderName != game_ghost_raiseother_first && senderName != game_ghost_raiseother_second) {
		return SendError(senderName, "not_your_game");
	}

	// 送信元の先後を判定
	local senderTurn;
	if(senderName == game_ghost_raiseother_first) {
		senderTurn = "first";
	} else {
		senderTurn = "second";
	}

	// 手番確認
	if(senderTurn != game_turn) {
		return SendError(senderName, "not_your_turn");
	}

	local result = ExecuteMove(holeIdx);

	if(result.result == "error") {
		return SendError(senderName, result.error);
	}

	// タイムアウトタイマーをキャンセル
	local script = CancelTurnTimer();

	local allMoved = [];
	allMoved.AddRange(result.distributeStones);
	if(result.captureInfo.canCapture) {
		for(local n = 0; n < 48; n = n + 1) {
			if(game_stone_hole[n] == result.captureInfo.oppHole) {
				allMoved.Add(n);
			}
		}
	}
	PrepareStoneAnim(allMoved);
	script = script + AppendStoneAnimScript(result.distributeStones);

	if(result.captureInfo.canCapture) {
		local cap = ApplyCapture(result.lastIdx, result.captureInfo);
		script = script + "\0\s[0]\c取り込み！ " + cap.capturedCount + "個の石を獲得しました。";
		script = script + AppendStoneAnimScript(cap.captured) + ScaleWait(2000);
	}

	local fin = FinalizeMove(result.bonus);

	if(fin.gameover) {
		if(fin.collectMoved.length > 0) {
			script = script + "\0\s[0]\cゲーム終了！残った石をストアに回収します。";
			script = script + AppendStoneAnimScript(fin.collectMoved) + ScaleWait(2000);
		}
		// 取りこぼし補正：全石を確定座標へ再反映してから終了通知
		script = script + BuildStoneRefreshScript();
		local gameResult = GetGameResult();
		script = script + BroadcastGameEnd(gameResult);
		script = script + SaveGameLog(gameResult);
		script = script + BuildGameEndTalk(gameResult);
		GameReset();
		return script;
	}

	script = script + BroadcastStateUpdate(game_turn, fin.bonus);

	// 次の手番が host_ai なら即座にAI手番を実行、そうでなければ手番トーク
	local currentType;
	if(game_turn == "first") {
		currentType = game_first_type;
	} else {
		currentType = game_second_type;
	}
	if(currentType != "user" && currentType != "own_ai") {
		script = script + ExecuteAiTurn();
	} else {
		// 取りこぼし補正：相手（非AI）へ手番が渡る前に全石を確定座標へ再反映
		script = script + BuildStoneRefreshScript();
		script = script + BuildTurnTalk(fin.bonus);
	}

	return script;
}

// ----------------------------------------------------------------
// OnMancalaResign
// R0: ゴースト名（OnMancalaRequestGame の R0 と同じ名前）
// ----------------------------------------------------------------
function OnMancalaResign {
	local senderName = Shiori.Reference[0];

	if(!game_in_progress) {
		return SendError(senderName, "game_not_started");
	}

	if(senderName != game_ghost_raiseother_first && senderName != game_ghost_raiseother_second) {
		return SendError(senderName, "not_your_game");
	}

	// 投了した側が負け
	local gameResult;
	if(senderName == game_ghost_raiseother_first) {
		gameResult = "second_win";
	} else {
		gameResult = "first_win";
	}

	// 残石は回収せずそのまま終了
	game_in_progress = false;

	local script = "";
	script = script + BroadcastGameEnd(gameResult);
	script = script + SaveGameLog(gameResult);
	GameReset();
	return script;
}

// ----------------------------------------------------------------
// 対局開始演出トークを返す
// 「対局開始。先手：〇〇、後手：◇◇」を表示し、初手通知との間に間を作る。
// OnMancalaGameStart と直後の OnMancalaStateUpdate が近接して届く構造的問題を
// 緩和する役割も兼ねる（受信側がGameStartを処理する猶予を作る）。
// ----------------------------------------------------------------
function BuildGameStartTalk() {
	local firstName  = "\_?" + GetDisplayName(game_first_type,  game_first_name)  + "\_?";
	local secondName = "\_?" + GetDisplayName(game_second_type, game_second_name) + "\_?";
	return "\0\s[0]\c対局開始。\n先手：" + firstName + "\n後手：" + secondName + ScaleWait(5000);
}

// ----------------------------------------------------------------
// host_ai の手番を連続手番が続く限り実行し、さくらスクリプトを返す
// ----------------------------------------------------------------
function ExecuteAiTurn() {
	local script = "";
	local isBonus = false;  // 最初の手番は連続手番ではない

	local continueAi = true;
	while(continueAi && game_in_progress) {
		local currentType;
		if(game_turn == "first") {
			currentType = game_first_type;
		} else {
			currentType = game_second_type;
		}

		// own_ai またはユーザの手番になったら停止
		if(currentType == "user" || currentType == "own_ai") {
			continueAi = false;
			break;
		}

		// 思考中トーク（演出）
		local currentName;
		if(game_turn == "first") { currentName = game_first_name; } else { currentName = game_second_name; }
		local thinkName = "\_?" + GetDisplayName(currentType, currentName) + "\_?";
		// 手番が「host_aiで委任した対応ゴースト」なら台は代理着手なので「待機中...」、
		// 台AIと対戦（raiseother名がnull）なら台自身が考えるので「思考中...」とする。
		local waitWord;
		if(GetRaiseotherName(game_turn) != null) {
			waitWord = "待機中...";
		} else {
			waitWord = "思考中...";
		}
		local thinkMsg;
		if(isBonus) {
			thinkMsg = thinkName + "の連続手番です。\n" + waitWord;
		} else {
			thinkMsg = thinkName + "の手番です。\n" + waitWord;
		}
		script = script + "\0\s[0]\c" + thinkMsg + ScaleWait(5000);

		local holeIdx = AiSelectMove(currentType, game_turn);
		local result  = ExecuteMove(holeIdx);

		local allMoved = [];
		allMoved.AddRange(result.distributeStones);
		if(result.captureInfo.canCapture) {
			for(local n = 0; n < 48; n = n + 1) {
				if(game_stone_hole[n] == result.captureInfo.oppHole) {
					allMoved.Add(n);
				}
			}
		}
		PrepareStoneAnim(allMoved);

		script = script + "\n手を決定。石を動かしています...";
		script = script + AppendStoneAnimScript(result.distributeStones);

		if(result.captureInfo.canCapture) {
			local cap = ApplyCapture(result.lastIdx, result.captureInfo);
			script = script + "\0\s[0]\c取り込み！ " + cap.capturedCount + "個の石を獲得しました。";
			script = script + AppendStoneAnimScript(cap.captured);
		}

		local fin = FinalizeMove(result.bonus);

		if(fin.gameover) {
			if(fin.collectMoved.length > 0) {
				script = script + "\0\s[0]\cゲーム終了！残った石をストアに回収します。";
				script = script + AppendStoneAnimScript(fin.collectMoved);
			}
			// 取りこぼし補正：全石を確定座標へ再反映してから終了通知
			script = script + BuildStoneRefreshScript();
			local gameResult = GetGameResult();
			script = script + BroadcastGameEnd(gameResult);
			script = script + SaveGameLog(gameResult);
			script = script + BuildGameEndTalk(gameResult);
			GameReset();
			continueAi = false;
		} else {
			isBonus = fin.bonus;
			script = script + BroadcastStateUpdate(game_turn, fin.bonus);
			// 連続手番でも相手（non-ai）の番になったら停止して手番トーク
			if(!fin.bonus) {
				local nextType;
				if(game_turn == "first") {
					nextType = game_first_type;
				} else {
					nextType = game_second_type;
				}
				if(nextType == "user" || nextType == "own_ai") {
					// 取りこぼし補正：相手（非AI）へ手番が渡る前に全石を確定座標へ再反映
					script = script + BuildStoneRefreshScript();
					script = script + BuildTurnTalk(false);
					continueAi = false;
				}
			}
		}
	}

	script = script + ScaleWait(5000);
	return script;
}

// ----------------------------------------------------------------
// 対局ログ保存（仕様書 7.2）
// ----------------------------------------------------------------
function SaveGameLog(gameResult) {
	if(Save.Data.game_log == null) {
		Save.Data.game_log = [];
	}

	local month  = Time.GetNowMonth();
	local day    = Time.GetNowDate();
	local hour   = Time.GetNowHour();
	local minute = Time.GetNowMinute();
	if(month  < 10) { month  = "0" + month; }
	if(day    < 10) { day    = "0" + day; }
	if(hour   < 10) { hour   = "0" + hour; }
	if(minute < 10) { minute = "0" + minute; }

	local record = {
		date:         Time.GetNowYear() + "-" + month + "-" + day + " " + hour + ":" + minute,
		first_name:   game_first_name,
		second_name:  game_second_name,
		first_type:   game_first_type,
		second_type:  game_second_type,
		result:       gameResult,
		first_store:  game_board[6],
		second_store: game_board[13]
	};

	Save.Data.game_log.Add(record);

	// 最新20件を超えたら古いものを削除
	while(Save.Data.game_log.length > 20) {
		Save.Data.game_log.Remove(Save.Data.game_log[0]);
	}

	return "";
}
