// ============================================================
// main.as  -  エントリポイント・ユーザ操作イベント
// ============================================================

// ----------------------------------------------------------------
// 初期化
// ----------------------------------------------------------------

function OnAosoraDefaultSaveData {
	Save.Data.game_log   = [];
	Save.Data.anim_speed = "normal";
}

function OnAosoraLoad {
	TalkTimer.KeyRandomTalkIntervalSeconds = 0;
	game_in_progress                = false;
	game_user_order_req             = "any";
	game_waiting_mode               = null;
	game_waiting_ghost1_name        = null;
	game_waiting_ghost1_displayname = null;
	game_waiting_ghost1_type        = null;
	game_ghost_raiseother_first     = null;
	game_ghost_raiseother_second    = null;
}

// ----------------------------------------------------------------
// 起動・終了
// ----------------------------------------------------------------

function OnBoot {
	return "\0\s[0]" + BuildClearStoneScript() + "うかマンカラへようこそ。";
}

function OnClose {
	if(game_in_progress) {
		GameReset();
	}
	return "\0\s[0]お疲れさまでした。";
}

function OnGhostChanging {
	
	if (Shiori.Reference[0] != "うかマンカラ台") {
		return OnClose();
	}

	// 自分へ切り替え
	if(game_in_progress) {
		GameReset();
		return "\0\s[0]対局を破棄し、ゴーストを再起動します。\w9\w9";
	}
	else {
		return "\0\s[0]ゴーストを再起動します。\w9\w9";
	}
}

function OnGhostChanged {
	
	if (Shiori.Reference[0] != "うかマンカラ台") {
		return OnBoot();
	}

	// 自分から切り替え
	return "\0\s[0]ゴーストを再起動しました。";
}

// ----------------------------------------------------------------
// 選択肢コールバック
// ----------------------------------------------------------------

function OnChoiceSelect {
	return Reflection.Get(Shiori.Reference[0]);
}

// ----------------------------------------------------------------
// ユーザ操作：穴のクリック（手番処理）
// ----------------------------------------------------------------

function OnMouseClick {
	local colName = Shiori.Reference[4];

	// 左クリック以外は無視
	if(Shiori.Reference[5] != 0) {
		return;
	}

	if(!game_in_progress) {
		return;
	}

	// ユーザの手番でなければ無視
	local currentType;
	if(game_turn == "first") {
		currentType = game_first_type;
	} else {
		currentType = game_second_type;
	}
	if(currentType != "user") {
		return;
	}

	// コリジョン名から穴インデックスへ変換
	local holeIdx = CollisionToHoleIndex(colName);
	if(holeIdx == null) {
		return;
	}

	local result = ExecuteMove(holeIdx);
	if(result.result == "error") {
		return;
	}

	local script = "\0";

	// 配布アニメーション（この時点では取り込み前なので lastIdx の石は小穴にいる）
	// 全移動石の事前登録：取り込みがある場合は正面の穴の石も除外対象に含める
	local allMoved = [];
	allMoved.AddRange(result.distributeStones);
	if(result.captureInfo.canCapture) {
		// 正面の穴の石を allMoved に追加（まだ game_stone_hole は更新されていない）
		for(local n = 0; n < 48; n = n + 1) {
			if(game_stone_hole[n] == result.captureInfo.oppHole) {
				allMoved.Add(n);
			}
		}
	}
	PrepareStoneAnim(allMoved);
	script = script + AppendStoneAnimScript(result.distributeStones);

	// 取り込みメッセージ＋取り込み実行＋アニメーション
	local capturedCount = 0;
	local captured = [];
	if(result.captureInfo.canCapture) {
		local cap = ApplyCapture(result.lastIdx, result.captureInfo);
		captured = cap.captured;
		capturedCount = cap.capturedCount;
		script = script + "\0\s[0]\c取り込み！ " + capturedCount + "個の石を獲得しました。";
		script = script + AppendStoneAnimScript(captured);
	}

	// 手番終了処理
	local fin = FinalizeMove(result.bonus);

	if(fin.gameover) {
		if(fin.collectMoved.length > 0) {
			script = script + "\0\s[0]\cゲーム終了！残った石をストアに回収します。";
			script = script + AppendStoneAnimScript(fin.collectMoved);
		}
		local gameResult = GetGameResult();
		script = script + BroadcastGameEnd(gameResult);
		script = script + SaveGameLog(gameResult);
		script = script + BuildGameEndTalk(gameResult);
		GameReset();
		return script;
	}

	script = script + BroadcastStateUpdate(game_turn, fin.bonus);

	// 次が host_ai なら即 AI 手番
	local nextType;
	if(game_turn == "first") {
		nextType = game_first_type;
	} else {
		nextType = game_second_type;
	}
	if(nextType != "user" && nextType != "own_ai") {
		script = script + ExecuteAiTurn();
	} else {
		script = script + BuildTurnTalk(fin.bonus);
	}

	return script;
}

// コリジョン名 → 盤面インデックス変換
function CollisionToHoleIndex(colName) {
	if(colName == "hole_f0") { return 0; }
	if(colName == "hole_f1") { return 1; }
	if(colName == "hole_f2") { return 2; }
	if(colName == "hole_f3") { return 3; }
	if(colName == "hole_f4") { return 4; }
	if(colName == "hole_f5") { return 5; }
	if(colName == "hole_s0") { return 7; }
	if(colName == "hole_s1") { return 8; }
	if(colName == "hole_s2") { return 9; }
	if(colName == "hole_s3") { return 10; }
	if(colName == "hole_s4") { return 11; }
	if(colName == "hole_s5") { return 12; }
	return null;
}

// ----------------------------------------------------------------
// tooltip：穴にホバーしたときの石数表示
// ----------------------------------------------------------------

function tooltip {
	local colName = Shiori.Reference[4];
	local holeIdx = CollisionToHoleIndex(colName);
	if(holeIdx == null) {
		if(colName == "store_f") { holeIdx = 6; }
		else if(colName == "store_s") { holeIdx = 13; }
	}
	if(holeIdx == null || !game_in_progress) {
		return;
	}
	return game_board[holeIdx] + "個";
}

// ----------------------------------------------------------------
// ダブルクリック：メインメニュー
// ----------------------------------------------------------------

function OnMouseDoubleClick {
	// 右クリックは無視
	if(Shiori.Reference[5] != 0) {
		return;
	}
	if(game_in_progress) {
		return OnMancalaInGameMenu();
	}
	return OnMancalaMainMenu();
}

// 対局中メニュー
// ・ユーザが参加者なら「投了」を出す
// ・「試合を中断する」はどのパターンでも常に出す（無効試合）
function OnMancalaInGameMenu {
	local userIsPlayer = (game_first_type == "user" || game_second_type == "user");
	local script = "\0\s[0]\_q対局中です。\n\n";
	if(userIsPlayer) {
		script = script + "\![*]\q[投了する,OnMancalaResignMenu]\n";
	}
	script = script + "\![*]\q[試合を中断する,OnMancalaAbortMenu]";
	script = script + "\n\![*]\q[閉じる　,OnMancalaMenuClose]";
	return script;
}

// 試合中断確認（ゴースト vs ゴースト観戦時）
talk OnMancalaAbortMenu {
	\0\s[0]\_qこの試合を中断しますか？
	（無効試合として終了します）

	\![*]\q[中断する,OnMancalaUserAbort]
	\![*]\q[やめる　,OnMancalaMenuClose]
}

// ユーザ操作による試合中断（無効試合）
function OnMancalaUserAbort {
	if(!game_in_progress) {
		return "\0\s[0]対局中ではありません。";
	}
	local script = "\0";
	script = script + BuildClearStoneScript();
	script = script + CancelTurnTimer();
	script = script + BroadcastGameVoid();
	script = script + "\0\s[0]\c試合を中断しました。無効試合とします。";
	GameReset();
	return script;
}

talk OnMancalaMainMenu {
	\0\s[0]\_qマンカラへようこそ。

	\![*]\q[対局を始める　　　　,OnMancalaStartMenu]
	\![*]\q[ゴーストと対戦　　　,OnMancalaGhostMenu]
	\![*]\q[ゴーストvsゴースト　,OnMancalaGhostVsGhostMenu]
	\![*]\q[ルール説明　　　　　,OnMancalaRuleMenu]
	\![*]\q[演出速度変更　　　　,OnMancalaSpeedMenu]
	\![*]\q[対戦ログ　　　　　　,OnMancalaGameLog]

	\![*]\q[閉じる　　　　　　　,OnMancalaMenuClose]
}

// ----------------------------------------------------------------
// 対戦ログ表示
// ----------------------------------------------------------------

function OnMancalaGameLog {
	local logs = Save.Data.game_log;
	if(logs == null || logs.length == 0) {
		return "\0\s[0]\_q対戦ログはまだありません。\n\n\![*]\q[戻る,OnMancalaMainMenu]";
	}

	local script = "\0\s[0]\b[2]\![set,autoscroll,disable]\_q【対戦ログ】（最新{logs.length}件） \![*]\q[戻る　,OnMancalaMainMenu] \![*]\q[閉じる,OnMancalaMenuClose]\n\n";

	// 新しい順に表示
	local i = logs.length - 1;
	while(i >= 0) {
		local rec = logs[i];
		local firstName  = GetDisplayName(rec.first_type,  rec.first_name);
		local secondName = GetDisplayName(rec.second_type, rec.second_name);
		local resultStr;
		if(rec.result == "first_win")  { resultStr = firstName + " 勝利"; }
		else if(rec.result == "second_win") { resultStr = secondName + " 勝利"; }
		else { resultStr = "引き分け"; }
		script = script + rec.date + "\n";
		script = script + "先手：" + firstName + "(" + rec.first_store + "石) vs 後手：" + secondName + "(" + rec.second_store + "石)\n";
		script = script + "結果：" + resultStr + "\n\n";
		i = i - 1;
	}

	if(logs.length>=7) {
		script = script + "\![*]\q[戻る　,OnMancalaMainMenu] \![*]\q[閉じる,OnMancalaMenuClose]";
	}
	return script;
}

// ----------------------------------------------------------------
// ルール説明
// ----------------------------------------------------------------

talk OnMancalaRuleMenu {
	\0\s[1]\b[2]\_q【マンカラ カラハのルール】
	盤面は14の穴からなります。
	先手（下段）と後手（上段）がそれぞれ小穴6つとストア1つを持ちます。
	
	【手番】
	自分の小穴を1つ選び、石を全て取り出して
	反時計回りに1個ずつ配ります。
	（相手のストアは飛ばします）
	
	\![*]\q[次へ　,OnMancalaRuleMenu2]

	\![*]\q[閉じる,OnMancalaMenuClose]
}

talk OnMancalaRuleMenu2 {
	\0\s[2]\b[2]\_q【特殊ルール】
	■連続手番
	最後の石が自分のストアに入ったら、もう一度手番を得ます。
	
	■取り込み
	最後の石が自分の空の小穴に入り、
	正面の相手の穴に石があるとき、
	両方の石を全て自分のストアに取り込みます。
	
	\![*]\q[次へ　,OnMancalaRuleMenu3]
	\![*]\q[前へ　,OnMancalaRuleMenu]

	\![*]\q[閉じる,OnMancalaMenuClose]
}

talk OnMancalaRuleMenu3 {
	\0\s[3]\b[2]\_q【ゲーム終了】
	どちらかの小穴が全て空になったらゲーム終了。
	残った石は持ち主のストアに入ります。
	ストアの石が多い方の勝ちです。同数は引き分け。
	
	\![*]\q[対局を始める,OnMancalaStartMenu]
	\![*]\q[前へ　　　　,OnMancalaRuleMenu2]

	\![*]\q[閉じる　　　,OnMancalaMenuClose]
}

// ----------------------------------------------------------------
// 対局開始UI（ユーザ vs host_ai）
// ----------------------------------------------------------------

talk OnMancalaStartMenu {
	\0\s[0]\_q対局を始めます。
	先手と後手、どちらを希望しますか？

	\![*]\q[先手　　　,OnMancalaUserSelectFirst]
	\![*]\q[後手　　　,OnMancalaUserSelectSecond]
	\![*]\q[どちらでも,OnMancalaUserSelectAny]
	\![*]\q[やめる　　,OnMancalaMenuClose]
}

function OnMancalaUserSelectFirst {
	game_user_order_req = "first";
	return OnMancalaSelectDifficulty();
}

function OnMancalaUserSelectSecond {
	game_user_order_req = "second";
	return OnMancalaSelectDifficulty();
}

function OnMancalaUserSelectAny {
	game_user_order_req = "any";
	return OnMancalaSelectDifficulty();
}

talk OnMancalaSelectDifficulty {
	\0\s[0]\_q難易度を選んでください。

	\![*]\q[かんたん　,OnMancalaStartVsAiEasy]
	\![*]\q[ふつう　　,OnMancalaStartVsAiNormal]
	\![*]\q[むずかしい,OnMancalaStartVsAiHard]
	\![*]\q[やめる　　,OnMancalaMenuClose]
}

function OnMancalaStartVsAiEasy   { return StartVsAi("host_ai:easy"); }
function OnMancalaStartVsAiNormal { return StartVsAi("host_ai:normal"); }
function OnMancalaStartVsAiHard   { return StartVsAi("host_ai:hard"); }

// ユーザ vs 台AI の対局開始
function StartVsAi(aiType) {
	if(game_in_progress) {
		return "\0\s[0]対局中です。";
	}

	local aiName;
	if(aiType == "host_ai:easy")   { aiName = "COM:かんたん"; }
	else if(aiType == "host_ai:normal") { aiName = "COM:ふつう"; }
	else { aiName = "COM:むずかしい"; }

	local order = DecideOrder(
		"ユーザ", "user", game_user_order_req,
		aiName,   aiType, "any"
	);

	GameStart(order.firstName, order.secondName, order.firstType, order.secondType);

	local script = "\0";
	script = script + BuildStoneAnimScriptNoWait();

	// 先手が host_ai なら即 AI 手番、そうでなければ手番トーク
	if(game_first_type != "user" && game_first_type != "own_ai") {
		script = script + ExecuteAiTurn();
	} else {
		script = script + BuildTurnTalk(false);
	}

	return script;
}

// ユーザ vs ユーザの対局開始
function OnMancalaStartVsUser {
	if(game_in_progress) {
		return "\0\s[0]対局中です。";
	}
	GameStart("先手プレイヤー", "後手プレイヤー", "user", "user");
	local script = "\0";
	script = script + BuildStoneAnimScriptNoWait();
	return script;
}

// ----------------------------------------------------------------
// 演出速度設定
// ----------------------------------------------------------------

function GetAnimSpeedLabel() {
	local sp = Save.Data.anim_speed;
	if(sp == null)   { return "普通"; }
	if(sp == "none") { return "ノーウェイト"; }
	if(sp == "fast") { return "速い"; }
	if(sp == "slow") { return "ゆっくり"; }
	return "普通";
}

talk OnMancalaSpeedMenu {
	\0\s[0]\_q演出速度を選んでください。
	現在の設定：{GetAnimSpeedLabel()}

	\![*]\q[ノーウェイト,OnMancalaSpeedNone]
	\![*]\q[速い　　　　,OnMancalaSpeedFast]
	\![*]\q[普通　　　　,OnMancalaSpeedNormal]
	\![*]\q[ゆっくり　　,OnMancalaSpeedSlow]

	\![*]\q[戻る　　　　,OnMancalaMainMenu]
}

function OnMancalaSpeedNone {
	Save.Data.anim_speed = "none";
	return OnMancalaSpeedMenu();
}
function OnMancalaSpeedFast {
	Save.Data.anim_speed = "fast";
	return OnMancalaSpeedMenu();
}
function OnMancalaSpeedNormal {
	Save.Data.anim_speed = "normal";
	return OnMancalaSpeedMenu();
}
function OnMancalaSpeedSlow {
	Save.Data.anim_speed = "slow";
	return OnMancalaSpeedMenu();
}

// ----------------------------------------------------------------
// ゴーストと対戦（ユーザ参加）
// ----------------------------------------------------------------

talk OnMancalaGhostMenu {
	\0\s[0]\_qゴーストとの対戦を待機します。
	先手と後手、どちらを希望しますか？

	\![*]\q[先手　　　,OnMancalaGhostWaitFirst]
	\![*]\q[後手　　　,OnMancalaGhostWaitSecond]
	\![*]\q[どちらでも,OnMancalaGhostWaitAny]
	\![*]\q[やめる　　,OnMancalaMenuClose]
}

function OnMancalaGhostWaitFirst  { game_user_order_req = "first";  return StartWaitingForGhost("user_vs_ghost"); }
function OnMancalaGhostWaitSecond { game_user_order_req = "second"; return StartWaitingForGhost("user_vs_ghost"); }
function OnMancalaGhostWaitAny    { game_user_order_req = "any";    return StartWaitingForGhost("user_vs_ghost"); }

// ----------------------------------------------------------------
// ゴーストvsゴースト（観戦）
// ----------------------------------------------------------------

talk OnMancalaGhostVsGhostMenu {
	\0\s[0]\_qゴースト同士の対戦を待機します。
	ゴーストが2体集まると対局を開始します。

	\![*]\q[待機開始,OnMancalaGhostVsGhostStart]
	\![*]\q[やめる　,OnMancalaMenuClose]
}

function OnMancalaGhostVsGhostStart { return StartWaitingForGhost("ghost_vs_ghost"); }

// 待機開始共通処理
function StartWaitingForGhost(mode) {
	if(game_in_progress) {
		return "\0\s[0]対局中です。";
	}
	game_waiting_mode        = mode;
	game_waiting_ghost1_name = null;
	game_waiting_ghost1_type = null;
	local modeStr;
	if(mode == "ghost_vs_ghost") {
		modeStr = "ゴーストvsゴースト";
	} else {
		modeStr = "ユーザvsゴースト";
	}
	return "\0\s[0]\_q【" + modeStr + "】\nゴーストからのリクエストを待っています...\![set,balloontimeout,-1]"
		+ "\n\n\![*]\q[キャンセル,OnMancalaWaitCancel]";
}

function OnMancalaWaitCancel {
	game_waiting_mode        = null;
	game_waiting_ghost1_name = null;
	game_waiting_ghost1_type = null;
	return "\0\s[0]待機をキャンセルしました。";
}

// ----------------------------------------------------------------
// ユーザ投了
// ----------------------------------------------------------------

talk OnMancalaResignMenu {
	\0\s[0]\_q投了しますか？

	\![*]\q[投了する,OnMancalaUserResign]
	\![*]\q[やめる　,OnMancalaMenuClose]
}

function OnMancalaUserResign {
	if(!game_in_progress) {
		return "\0\s[0]対局中ではありません。";
	}
	// ユーザの手番でなくても投了できる
	local userTurn;
	if(game_first_type == "user") {
		userTurn = "first";
	} else if(game_second_type == "user") {
		userTurn = "second";
	} else {
		return "\0\s[0]あなたはこの対局の参加者ではありません。";
	}
	local gameResult;
	if(userTurn == "first") {
		gameResult = "second_win";
	} else {
		gameResult = "first_win";
	}
	local script = "\0\s[0]\c投了しました。\n";
	script = script + BuildClearStoneScript();
	script = script + BroadcastGameEnd(gameResult);
	script = script + SaveGameLog(gameResult);
	script = script + "\![timerraise,0,1,OnMancalaTurnTimeout]";
	script = script + BuildGameEndTalk(gameResult);
	GameReset();
	return script;
}

// ----------------------------------------------------------------
// タイムアウト（own_ai が5分以内に OnMancalaMove を送らなかった場合）
// ----------------------------------------------------------------

function StartTurnTimer() {
	// own_ai の手番のときのみタイマーをセット
	local currentType;
	if(game_turn == "first") {
		currentType = game_first_type;
	} else {
		currentType = game_second_type;
	}
	if(currentType == "own_ai") {
		return "\![timerraise,300000,1,OnMancalaTurnTimeout]";
	}
	return "";
}

function CancelTurnTimer() {
	return "\![timerraise,0,1,OnMancalaTurnTimeout]";
}

function OnMancalaTurnTimeout {
	if(!game_in_progress) {
		return;
	}
	// タイムアウトしたプレイヤー名を取得
	local timedOutName = GetCurrentTurnDisplayName();
	local script = "\0";
	script = script + BuildClearStoneScript();
	script = script + BroadcastGameVoid();
	script = script + BuildGameVoidTalk(timedOutName);
	GameReset();
	return script;
}

function BuildGameVoidTalk(timedOutName) {
	return "\0\s[0]\c\_?" + timedOutName + "\_?が応答しなかったため、試合を無効とします。";
}

talk OnMancalaMenuClose {
	\0\s[0]またいつでもどうぞ。
}

// ----------------------------------------------------------------
// プレイヤー表示名
// ----------------------------------------------------------------

// playerType と name からバルーン表示用の名前を返す
function GetDisplayName(playerType, name) {
	if(playerType == "user") { return "ユーザ"; }
	// host_ai / own_ai はいずれもゴーストの呼び名をそのまま使う
	return name;
}

// 現在手番のプレイヤー表示名を返す
function GetCurrentTurnDisplayName() {
	if(game_turn == "first") {
		return GetDisplayName(game_first_type, game_first_name);
	}
	return GetDisplayName(game_second_type, game_second_name);
}

// 手番トーク（石アニメーション後に続けて返す）
// isBonus: 連続手番かどうか
function BuildTurnTalk(isBonus) {
	local name = "\_?" + GetCurrentTurnDisplayName() + "\_?";
	local msg;
	if(isBonus) {
		msg = name + "の連続手番です。\n待機中...\![set,balloontimeout,-1]";
	} else {
		msg = name + "の手番です。\n待機中...\![set,balloontimeout,-1]";
	}
	return "\0\s[0]\c" + msg + StartTurnTimer();
}

// ----------------------------------------------------------------
// 対局終了トーク
// ----------------------------------------------------------------

function BuildGameEndTalk(gameResult) {
	local firstName  = "\_?" + GetDisplayName(game_first_type,  game_first_name) + "\_?";
	local secondName = "\_?" + GetDisplayName(game_second_type, game_second_name) + "\_?";
	if(gameResult == "first_win") {
		return "\0\s[0]\c先手 " + firstName + " の勝ち、\n後手 " + secondName + " の負けです。";
	}
	if(gameResult == "second_win") {
		return "\0\s[0]\c後手 " + secondName + " の勝ち、\n先手 " + firstName + " の負けです。";
	}
	return "\0\s[0]\c引き分けです。\n先手 " + firstName + " ・ 後手 " + secondName;
}
