;;; ai-client.el --- AIのJSONストリームをEmacs側で受けるクライアント -*- lexical-binding: t; -*-

;;; Commentary:

;; AIの応答を「端末画面」ではなく「構造化イベント」としてEmacsへ取り込むための層。
;;
;; conf/ai-agent.el のCLI統合(claude/agy/bob)は、TUIをvtermで動かしてEmacsは
;; ただの端末になる方式で、画面にはANSIエスケープ付きの文字しか来ない。そのため
;; Emacs側は「いま何が起きたか」を知れず、セッションを読むには
;; my/claude-code-show-session のように後からディスクのJSONLを読み直すしかなかった。
;;
;; ここでは逆に、最初から機械可読なストリームを受ける。扱う提供側は3つ。
;;   - claude CLI … stream-json(1行が1個のJSONオブジェクト)
;;   - Gemini API … SSE("data: " 行の中身がJSON)。:streamGenerateContent?alt=sse
;;   - MyLLM      … SSE。独自のOpenAI互換API(MY_LLM_*)
;; 違うのは「行からJSONを取り出す方法」と「JSONの形」だけなので、その2つだけを
;; 差し替え可能にし(リーダ + 正規化関数)、以降の描画・操作は共通にする。
;; なおストリーミングの指定方法は提供側でまったく違う。Geminiはメソッドを変え
;; (:generateContent → :streamGenerateContent)、OpenAI互換はエンドポイントを
;; 変えずbodyに "stream": true を入れる。claude CLIは --output-format で指定する。
;;
;;   プロセス出力 → リーダ(行→JSON) → 正規化関数(JSON→イベント) → 描画 / フック
;;
;; 正規化後のイベントはplistで、種別は次の7つに限る。提供側が増えても描画は変えない。
;;   (:type text        :text STR)
;;   (:type thinking    :text STR)
;;   (:type tool-call   :id STR :name STR :input ALIST)
;;   (:type tool-result :id STR :error BOOL :text STR)
;;   (:type done        :info ALIST)
;;   (:type error       :message STR)
;;   (:type other       :label STR :text STR :raw OBJ)  ; 上記以外。捨てずに1行で残す
;;
;; ツール呼び出しの承認や実行は描画とは別の関心事なので、ここでは行わず
;; my/ai-stream-event-functions(フック)を通す。
;;
;; gptel(ai-agent.el 第6節)とは棲み分けている。単発のチャット・リライトは
;; gptelの方が良く出来ているのでそのまま使い、こちらは「エージェントの動きを
;; Emacs側で受けて描く」用途だけを持つ。
;;
;; init.el では mylisp の後に読み込む(表示位置の決定に
;; my/display-buffer-by-monitor-orientation を、起動ディレクトリに
;; my/ai-agent-project-root を使うため)。

;;; Code:

(require 'cl-lib)   ; my/ai-stream-start で cl-defun / &key を使う

;; =====================================================================
;; 1. 設定値
;; =====================================================================

(defvar my/ai-stream-buffer-name "*ai-stream*"
  "正規化したイベントを描画するバッファ名。")

(defvar my/ai-stream-stderr-buffer-name " *ai-stream-stderr*"
  "コマンドのエラー出力をためるバッファ名。
JSONストリームに混ざると行の解釈が壊れるので、標準出力とは必ず分ける。
先頭が空白なのは、バッファ一覧に出さないため。")

(defvar my/ai-stream-max-tool-result-lines 10
  "ツールの実行結果を描画するときに表示する最大行数。
超えた分は行数だけ知らせて省略する(ビルドログ等でバッファが埋まるのを防ぐ)。")

(defvar my/ai-stream-max-value-width 160
  "ツールの引数・結果の1行を描画するときの最大幅(文字)。")

(defvar my/ai-stream-event-functions nil
  "正規化イベントごとに呼ばれるフック。各関数はイベント(plist)を1つ受け取る。
ツール呼び出しの承認やツール自体の実行は、描画とは別の関心事なのでここに足す。
Gemini のように functionCall を自分で実行して返す必要がある提供側では、
このフックから実行して functionResponse を組み立てることになる。")

(defvar my/ai-stream-claude-program "claude"
  "claude CLI の実行ファイル名(PATH上)。")

(defvar my/ai-stream-claude-args '("--output-format" "stream-json" "--verbose")
  "claude を stream-json で動かすときの固定引数。
stream-json は --print(-p)と併用したときだけ有効なので、-p は
`my/ai-stream-claude' 側で必ず付ける。--verbose も必須で、無いと
\"When using --print, --output-format=stream-json requires --verbose\" で
起動に失敗する(そのため system/rate_limit_event 等の管理イベントも必ず流れてくる)。")

(defvar my/ai-stream-gemini-model "gemini-flash-latest"
  "`my/ai-stream-gemini' が使うGeminiのモデル名。
gptel側の既定(ai-agent.el)と揃えてあるが、こちらはgptelのモデル選択とは独立。")

(defvar my/ai-stream-myllm-sse-models
  '("\\`gemini-.+-flash\\'"
    "\\`claude-haiku-"
    "\\`claude-sonnet-"
    "\\`claude-opus-")
  "MyLLM(独自のOpenAI互換API)でSSEが使えるモデル名の正規表現。
サーバ側の対応が次のものに限られるため、ここで絞る。
  gemini-*-flash / claude-haiku-* / claude-sonnet-* / claude-opus-*
対応していないモデルに stream:true を投げるとSSEではない応答が返り、
\"data:\" 行が1つも来ないまま何も表示されずに終わってしまう。それを
起動前に弾くのが目的。
版の数字を含めないのは、サーバ側で日々版が上がるため(gemini-3.6-flash →
gemini-3.7-flash 等。接続先はおそらくAmazon Bedrock経由で、ゲートウェイ側が
モデルIDを付け替えている)。新しい版が出ても、ここを直さずに通る形にしておく。")

(defvar my/ai-stream-myllm-model nil
  "`my/ai-stream-myllm' が使うモデル名、または名前の一部(正規表現)。
nilなら環境変数 MY_LLM_FAST_MODEL、それも無ければ実行時の選択に任せる。
MyLLMのモデル一覧はマシンごとに違うので、設定ファイルに固定値を書かない
(ai-agent.el が MY_LLM_FAST_MODEL を使っているのと同じ考え方)。
完全一致ではなく部分一致で扱うのは、サーバ側のモデルが日々版を上げるため
(例: gemini-3.6-flash → gemini-3.7-flash)。完全一致で持つと版が上がった日から
存在しないモデルを指すことになるので、\"gemini\" のように版を含めない形で
書いておけば追随できる。")

(defvar my/ai-stream--state nil
  "ストリーム1本ぶんの作業用ハッシュ表。filter/sentinelが動的に束縛する。
正規化関数は原則チャンク1件だけを見れば済むが、OpenAI互換のツール呼び出しは
引数が複数チャンクに割れて届くため、そこだけ途中の状態を持つ必要がある。
提供側ごとに引数を増やさず、必要な正規化関数だけがこれを使う。")

(defvar-local my/ai-stream--process nil
  "このバッファへ描画中のプロセス(無ければnil)。")

(defvar-local my/ai-stream--last-type nil
  "直前に描画したイベント種別。本文と思考の区切りを入れる判定に使う。")

;; =====================================================================
;; 2. リーダ: 1行からJSON本文を取り出す
;; =====================================================================
;; 2系統の違いはここだけに閉じ込める。プロセス出力は行の途中で切れて届くので、
;; 未完の末尾はプロセスに持ち越す(1チャンク=1行とは限らない)。

(defun my/ai-stream--take-lines (proc chunk)
  "PROCに持ち越した断片とCHUNKを繋ぎ、完成した行だけをリストで返す。
末尾の未完部分はPROCへ持ち越す。"
  (let* ((pending (concat (process-get proc 'my/ai-pending) chunk))
         (lines (split-string pending "\n")))
    ;; split-string の最後の要素は改行で終わっていない部分(末尾が改行なら "")
    (process-put proc 'my/ai-pending (car (last lines)))
    (butlast lines)))

(defun my/ai-stream--payload (line reader)
  "LINEから、READERに応じてJSON本文の文字列を取り出す。
読み飛ばす行ならnil、ストリーム終端の合図なら \\='done を返す。
READERは次の2つ。
  stream-json … 1行がそのまま1個のJSONオブジェクト
  sse         … \"data:\" 行の中身だけがJSON。event:/id:/コメント(:)/空行は無視"
  (let ((line (string-trim-right line "\r")))
    (pcase reader
      ('stream-json
       (let ((s (string-trim line)))
         (unless (string-empty-p s) s)))
      ('sse
       (when (string-prefix-p "data:" line)
         (let ((s (string-trim (substring line 5))))
           (cond ((string-empty-p s) nil)
                 ;; OpenAI互換サーバ向けの終端合図。Geminiは送ってこないが、
                 ;; 同じリーダを独自エンドポイントにも使えるよう解釈しておく。
                 ((equal s "[DONE]") 'done)
                 (t s)))))
      (_ (error "未知のリーダ種別: %s" reader)))))

(defun my/ai-stream--line-to-events (line reader normalizer)
  "LINEを正規化イベントのリストにする。読み飛ばす行ならnilを返す。
JSONが壊れていても描画を止めず、errorイベントとして見せる
(ストリームは途中で切れることがあり、1行の失敗で以降を捨てたくない)。"
  (let ((payload (my/ai-stream--payload line reader)))
    (cond
     ((null payload) nil)
     ;; [DONE] で終わる実装では finish_reason が来ないことがあるので、
     ;; ここでも溜まっているツール呼び出しを吐き出しておく(無ければ何もしない)。
     ((eq payload 'done)
      (append (my/ai-stream--openai-flush-tool-calls)
              (list (list :type 'done :info nil))))
     (t
      (condition-case err
          (funcall normalizer
                   (json-parse-string payload
                                      :object-type 'alist :array-type 'list
                                      :null-object nil :false-object nil))
        (error
         (list (list :type 'error
                     :message (format "JSONの解釈に失敗: %s / %s"
                                      (error-message-string err)
                                      (truncate-string-to-width payload 120 nil nil t))))))))))

;; =====================================================================
;; 3. 正規化: 提供側のJSONを共通イベントへ
;; =====================================================================

(defun my/ai-stream--content-to-string (content)
  "ツール結果のCONTENT(文字列、またはブロックのリスト)を文字列にする。"
  (cond
   ((stringp content) content)
   ((listp content)
    (mapconcat (lambda (block)
                 (or (and (consp block) (alist-get 'text block))
                     (format "%S" block)))
               content "\n"))
   (t (format "%S" content))))

;; --- claude CLI (--output-format stream-json) ---
;; 封筒は system / assistant / user / result の4種で、中身は message.content の
;; ブロック列。ブロックのキー名(text / thinking / tool_use の input / tool_result の
;; tool_use_id・is_error)は、~/.claude/projects 配下の実データで確認したもの。

(defun my/ai-stream--claude-block (block)
  "claudeのcontentブロックBLOCKを正規化イベントにする。"
  (pcase (and (consp block) (alist-get 'type block))
    ("text"
     (let ((s (alist-get 'text block)))
       (and (stringp s) (not (string-empty-p s)) (list :type 'text :text s))))
    ("thinking"
     (let ((s (alist-get 'thinking block)))
       (and (stringp s) (not (string-empty-p s)) (list :type 'thinking :text s))))
    ("tool_use"
     (list :type 'tool-call
           :id (alist-get 'id block)
           :name (alist-get 'name block)
           :input (alist-get 'input block)))
    ("tool_result"
     (list :type 'tool-result
           :id (alist-get 'tool_use_id block)
           :error (and (alist-get 'is_error block) t)
           :text (my/ai-stream--content-to-string (alist-get 'content block))))
    (other (list :type 'other :label (or other "block") :raw block))))

(defun my/ai-stream--normalize-claude (obj)
  "claude CLI の stream-json 1件OBJを正規化イベントのリストにする。"
  (pcase (alist-get 'type obj)
    ((or "assistant" "user")
     (let ((content (alist-get 'content (alist-get 'message obj))))
       (cond
        ((stringp content) (list (list :type 'text :text content)))
        ((listp content) (delq nil (mapcar #'my/ai-stream--claude-block content)))
        (t nil))))
    ("result" (list (list :type 'done :info obj)))
    ;; --verbose が必須な都合で、本題と関係ない管理イベントが毎回必ず流れてくる。
    ;; 捨てはしないが、生のJSONを出すと画面を占領するので要点だけに畳む。
    ("system"
     (list (list :type 'other :label "system"
                 :text (format "%s" (or (alist-get 'subtype obj) ""))
                 :raw obj)))
    ("rate_limit_event"
     (let ((info (alist-get 'rate_limit_info obj)))
       (list (list :type 'other :label "rate_limit"
                   :text (format "%s (%s)"
                                 (or (alist-get 'status info) "?")
                                 (or (alist-get 'rateLimitType info) "?"))
                   :raw obj))))
    (other (list (list :type 'other :label (or other "?") :raw obj)))))

;; --- Gemini API (:streamGenerateContent?alt=sse) ---
;; 本文も思考も candidates[0].content.parts[] に入り、思考側には thought:true が
;; 付く(本文との区別はこのフラグだけ)。finishReason が付いた時点でターンの終わり。

(defun my/ai-stream--gemini-part (part)
  "Geminiのpart(PART)を正規化イベントにする。"
  (let ((text (alist-get 'text part))
        (call (alist-get 'functionCall part)))
    (cond
     (call (list :type 'tool-call
                 :id (or (alist-get 'id call) (alist-get 'id part))
                 :name (alist-get 'name call)
                 :input (alist-get 'args call)))
     ((and (stringp text) (not (string-empty-p text)))
      ;; :false-object nil で読んでいるので、thought:false は nil になる
      (list :type (if (alist-get 'thought part) 'thinking 'text) :text text))
     ;; thoughtSignature だけを運ぶ part(text が "")が実際に混ざる。これは
     ;; 会話を続けるときに思考を復元するための控えで、表示するものを持たない。
     ;; 見せても邪魔になるだけなので読み飛ばす。
     ((alist-get 'thoughtSignature part) nil)
     (t (list :type 'other :label "part" :raw part)))))

(defun my/ai-stream--parse-json-or-string (text)
  "TEXT(JSON文字列)をalistにして返す。JSONとして読めなければ文字列のまま返す。"
  (if (or (null text) (string-empty-p text))
      nil
    (condition-case nil
        (json-parse-string text :object-type 'alist :array-type 'list
                           :null-object nil :false-object nil)
      (error text))))

(defun my/ai-stream--normalize-gemini (obj)
  "Gemini の SSE 1件OBJを正規化イベントのリストにする。"
  (let* ((cand (car (alist-get 'candidates obj)))
         (parts (alist-get 'parts (alist-get 'content cand)))
         (finish (alist-get 'finishReason cand))
         ;; promptFeedback.blockReason は安全フィルタでの拒否。本文が来ないので
         ;; 黙って終わったように見えてしまうため、errorとして明示する。
         (blocked (alist-get 'blockReason (alist-get 'promptFeedback obj))))
    (append
     (delq nil (mapcar #'my/ai-stream--gemini-part parts))
     (when blocked
       (list (list :type 'error :message (format "リクエストが拒否されました: %s" blocked))))
     (when finish (list (list :type 'done :info obj))))))

;; --- OpenAI互換API (MyLLM) ---
;; SSEの枠(data: 行)はGeminiと同じなのでリーダは \='sse を共用でき、違うのは中身の形。
;; 本文は choices[0].delta.content に差分で届く。
;;
;; 厄介なのはツール呼び出し。claude/Geminiは1イベントに引数まで揃って来るのに対し、
;; OpenAI互換は delta.tool_calls の function.arguments が「JSON文字列の断片」として
;; 複数チャンクに割れて届く。そのため index ごとに溜め、finish_reason(または[DONE])が
;; 来た時点で1件の tool-call イベントにまとめる。溜め場は `my/ai-stream--state'。

(defun my/ai-stream--openai-stash-tool-calls (calls)
  "delta.tool_callsのCALLSを、indexごとに `my/ai-stream--state' へ溜める。
id・nameは最初のチャンクにだけ入り、以降は arguments の断片だけが届くため、
既に拾ったものを消さないように既存値で埋め戻す。"
  (when (hash-table-p my/ai-stream--state)
    (dolist (call calls)
      (let* ((idx (or (alist-get 'index call) 0))
             (key (format "tool-call-%s" idx))
             (acc (gethash key my/ai-stream--state))
             (fn (alist-get 'function call)))
        (puthash key
                 (list :index idx
                       :id (or (alist-get 'id call) (plist-get acc :id))
                       :name (or (alist-get 'name fn) (plist-get acc :name))
                       :args (concat (plist-get acc :args) (alist-get 'arguments fn)))
                 my/ai-stream--state)))))

(defun my/ai-stream--openai-flush-tool-calls ()
  "溜めたツール呼び出しを tool-call イベントのリストにし、溜め場を空にする。
溜まっていなければnilを返すので、他の提供側から呼んでも無害。"
  (when (hash-table-p my/ai-stream--state)
    (let (accs)
      (maphash (lambda (key acc)
                 (when (string-prefix-p "tool-call-" key)
                   (push acc accs)
                   (remhash key my/ai-stream--state)))
               my/ai-stream--state)
      (mapcar (lambda (acc)
                (list :type 'tool-call
                      :id (plist-get acc :id)
                      :name (plist-get acc :name)
                      ;; argumentsはJSON文字列。ストリームが途中で切れていれば
                      ;; 読めないので、その場合は文字列のまま見せる(黙って捨てない)。
                      :input (my/ai-stream--parse-json-or-string (plist-get acc :args))))
              ;; 並列呼び出しのときは index 順に並べる(ハッシュの順は不定)
              (sort accs (lambda (a b) (< (plist-get a :index) (plist-get b :index))))))))

(defun my/ai-stream--normalize-openai (obj)
  "OpenAI互換のチャンクOBJを正規化イベントのリストにする。"
  (let* ((err (alist-get 'error obj))
         (choice (car (alist-get 'choices obj)))
         ;; stream:true が効かず非ストリームの応答が返ってきた場合も拾えるよう、
         ;; delta が無ければ message を見る。
         (delta (or (alist-get 'delta choice) (alist-get 'message choice)))
         (finish (alist-get 'finish_reason choice))
         (content (alist-get 'content delta))
         ;; 思考の持ち方はOpenAI互換の仕様外で実装依存。reasoning_content か
         ;; reasoning のどちらかが使われることが多いので両方見る。無ければ思考なし。
         (reasoning (or (alist-get 'reasoning_content delta) (alist-get 'reasoning delta)))
         (calls (alist-get 'tool_calls delta))
         events)
    (when err
      (push (list :type 'error
                  :message (format "%s" (or (alist-get 'message err) err)))
            events))
    (when (and (stringp reasoning) (not (string-empty-p reasoning)))
      (push (list :type 'thinking :text reasoning) events))
    (when (and (stringp content) (not (string-empty-p content)))
      (push (list :type 'text :text content) events))
    (when calls (my/ai-stream--openai-stash-tool-calls calls))
    (append (nreverse events)
            (when finish
              (append (my/ai-stream--openai-flush-tool-calls)
                      (list (list :type 'done :info obj)))))))

;; =====================================================================
;; 4. 描画
;; =====================================================================

(defvar my/ai-stream-mode-map
  (let ((map (make-sparse-keymap)))
    ;; special-mode 由来の q(quit-window)・g はそのまま使う。
    (define-key map (kbd "TAB") #'my/ai-stream-toggle-thinking)
    (define-key map (kbd "C-c C-k") #'my/ai-stream-abort)
    map)
  "`my/ai-stream-mode' のキーマップ。
evil側の割り当ては conf/keybind-manage.el にある。")

(define-derived-mode my/ai-stream-mode special-mode "AI-Stream"
  "AIのJSONストリームを正規化して表示するモード。"
  (setq-local truncate-lines nil)
  ;; 思考(thinking)は既定で畳む。テキストプロパティ invisible に付けた
  ;; シンボルを可視性リストから出し入れすることで開閉する。
  (add-to-invisibility-spec 'my/ai-thinking))

(defun my/ai-stream-toggle-thinking ()
  "思考(thinking)の表示/非表示を切り替える。"
  (interactive)
  (if (memq 'my/ai-thinking buffer-invisibility-spec)
      (remove-from-invisibility-spec 'my/ai-thinking)
    (add-to-invisibility-spec 'my/ai-thinking))
  (message "思考: %s" (if (memq 'my/ai-thinking buffer-invisibility-spec) "非表示" "表示")))

(defun my/ai-stream--one-line (string &optional width)
  "STRINGを1行に畳み、WIDTH(既定 `my/ai-stream-max-value-width')で切る。"
  (let ((s (replace-regexp-in-string "[\n\r]+" " ⏎ " (format "%s" string))))
    (truncate-string-to-width s (or width my/ai-stream-max-value-width) nil nil t)))

(defun my/ai-stream--append (buffer string &optional props)
  "BUFFERの末尾へSTRINGを追記し、PROPSをテキストプロパティとして付ける。
末尾を見ているウィンドウは追従させる(途中を読んでいるウィンドウは動かさない)。"
  (when (and (buffer-live-p buffer) (stringp string) (not (string-empty-p string)))
    (with-current-buffer buffer
      (let* ((inhibit-read-only t)
             (follow (seq-filter (lambda (w) (>= (window-point w) (point-max)))
                                 (get-buffer-window-list buffer nil t))))
        (save-excursion
          (goto-char (point-max))
          (let ((start (point)))
            (insert string)
            (when props (add-text-properties start (point) props))))
        (dolist (w follow) (set-window-point w (point-max)))))))

(defun my/ai-stream--section (buffer type header)
  "BUFFERで、直前と種別が変わったときだけ区切りとHEADERを入れる。
本文と思考は細かく分割されて届くので、チャンクごとに見出しを出さないための判定。"
  (with-current-buffer buffer
    (unless (eq my/ai-stream--last-type type)
      (my/ai-stream--append buffer (my/ai-stream--separator))
      (when header (my/ai-stream--append buffer header))
      (setq my/ai-stream--last-type type))))

(defun my/ai-stream--separator ()
  "いまのバッファ末尾に足すべき区切り文字列を返す。
本文は改行で終わらずに届くことが多いので、行を閉じてから空行を1つ作る
(先頭では何も足さない)。"
  (cond ((= (point-max) 1) "")
        ((eq (char-before (point-max)) ?\n) "\n")
        (t "\n\n")))

(defun my/ai-stream--block-start (buffer)
  "BUFFERで、1件ごとに独立して描くイベントの前に区切りを入れる。"
  (with-current-buffer buffer
    (my/ai-stream--append buffer (my/ai-stream--separator))
    ;; 次が本文・思考でも必ず見出しから描き直させる
    (setq my/ai-stream--last-type nil)))

(defun my/ai-stream--format-input (input)
  "ツールの引数INPUT(alist)を、1キー1行に整形する。"
  (cond
   ((null input) "")
   ((and (consp input) (consp (car input)))
    (mapconcat (lambda (kv)
                 (format "    %s: %s\n" (car kv) (my/ai-stream--one-line (cdr kv))))
               input ""))
   (t (format "    %s\n" (my/ai-stream--one-line input)))))

(defun my/ai-stream--format-result (text)
  "ツールの実行結果TEXTを、行数を抑えて整形する。"
  (let* ((lines (split-string (string-trim-right (or text "")) "\n"))
         (total (length lines))
         (shown (seq-take lines my/ai-stream-max-tool-result-lines)))
    (concat
     (mapconcat (lambda (l) (format "    %s\n" (my/ai-stream--one-line l))) shown "")
     (when (> total my/ai-stream-max-tool-result-lines)
       (format "    … 他 %d 行\n" (- total my/ai-stream-max-tool-result-lines))))))

(defun my/ai-stream--format-done (info)
  "完了イベントの付随情報INFOを1行にまとめる。
claudeのresultイベントとGeminiの最終チャンクで持つ項目が違うため、
あるものだけを拾う(無い項目で落ちないようにする)。"
  (let* ((usage (alist-get 'usageMetadata info))
         (cand (car (alist-get 'candidates info)))
         (choice (car (alist-get 'choices info)))
         (parts (delq nil
                      (list
                       (when-let* ((v (alist-get 'subtype info))) (format "%s" v))
                       (when-let* ((v (alist-get 'finishReason cand))) (format "%s" v))
                       (when-let* ((v (alist-get 'finish_reason choice))) (format "%s" v))
                       (when-let* ((v (alist-get 'num_turns info))) (format "%s turns" v))
                       (when-let* ((v (alist-get 'total_cost_usd info))) (format "$%.4f" v))
                       (when-let* ((v (alist-get 'duration_ms info)))
                         (format "%.1fs" (/ v 1000.0)))
                       (when-let* ((v (alist-get 'totalTokenCount usage)))
                         (format "%s tokens" v))
                       (when-let* ((v (alist-get 'total_tokens (alist-get 'usage info))))
                         (format "%s tokens" v))))))
    (if parts (string-join parts " / ") "")))

(defun my/ai-stream--render (buffer event)
  "正規化イベントEVENTをBUFFERへ描く。"
  (when (buffer-live-p buffer)
    (let ((type (plist-get event :type)))
      (pcase type
        ('text
         (my/ai-stream--section buffer type nil)
         (my/ai-stream--append buffer (plist-get event :text)))
        ('thinking
         (my/ai-stream--section
          buffer type (propertize "⋯ 思考 (TABで開閉)\n" 'face 'shadow))
         ;; 本文は invisible プロパティで畳んでおく(見出しだけ見える)
         (my/ai-stream--append buffer (concat (plist-get event :text) "\n")
                               '(invisible my/ai-thinking face shadow)))
        ('tool-call
         (my/ai-stream--block-start buffer)
         (my/ai-stream--append buffer (format "▶ %s\n" (or (plist-get event :name) "?"))
                               '(face font-lock-function-name-face))
         (my/ai-stream--append buffer (my/ai-stream--format-input (plist-get event :input))
                               '(face shadow)))
        ('tool-result
         (my/ai-stream--block-start buffer)
         (my/ai-stream--append buffer
                               (if (plist-get event :error) "✗ 結果(エラー)\n" "✓ 結果\n")
                               (if (plist-get event :error) '(face error) '(face success)))
         (my/ai-stream--append buffer (my/ai-stream--format-result (plist-get event :text))
                               '(face shadow)))
        ('done
         (my/ai-stream--block-start buffer)
         (my/ai-stream--append
          buffer (format "── 完了 %s\n" (my/ai-stream--format-done (plist-get event :info)))
          '(face shadow)))
        ('error
         (my/ai-stream--block-start buffer)
         (my/ai-stream--append buffer (format "!! %s\n" (plist-get event :message))
                               '(face error)))
        ('other
         ;; 知らない種別も落とさず1行で残す(提供側の仕様変更に気付けるように)。
         ;; 正規化側が要約(:text)を付けていればそれを使い、無ければ生のJSONを畳む。
         (my/ai-stream--block-start buffer)
         (my/ai-stream--append
          buffer (format "· %s: %s\n"
                         (plist-get event :label)
                         (my/ai-stream--one-line
                          (or (plist-get event :text)
                              (format "%S" (plist-get event :raw)))))
          '(face shadow)))
        (_ nil)))))

;; =====================================================================
;; 5. プロセス起動
;; =====================================================================

(defun my/ai-stream--prepare-buffer (name header)
  "描画先バッファNAMEを用意して返す。HEADERがあれば先頭に書く。"
  (let ((buf (get-buffer-create name)))
    (with-current-buffer buf
      (when (and my/ai-stream--process (process-live-p my/ai-stream--process))
        (user-error "まだ実行中です(C-c C-k で中止)"))
      (unless (derived-mode-p 'my/ai-stream-mode)
        (my/ai-stream-mode))
      (let ((inhibit-read-only t))
        (erase-buffer))
      (setq my/ai-stream--last-type nil)
      (when header
        (my/ai-stream--append buf (concat header "\n") '(face font-lock-keyword-face))))
    buf))

(defun my/ai-stream--display (buffer)
  "BUFFERを表示する。既存ウィンドウを再利用し、無ければモニターの向きに合わせて分割する。
gptelの表示設定(ai-agent.el)と同じ考え方だが、こちらは出力を眺めるだけなので
フォーカスは移さない(入力中の編集を邪魔しない)。"
  (display-buffer buffer
                  '((display-buffer-reuse-window
                     my/display-buffer-by-monitor-orientation))))

(defun my/ai-stream--filter (proc chunk)
  "PROCの出力CHUNKを行に切り、イベントへ正規化して描画とフックに回す。"
  (let ((buf (process-get proc 'my/ai-buffer))
        ;; チャンクをまたぐ蓄積(OpenAI互換のツール呼び出し)のための溜め場。
        ;; 正規化関数の引数を増やさずに渡すため動的束縛にする。
        (my/ai-stream--state (process-get proc 'my/ai-state)))
    (dolist (line (my/ai-stream--take-lines proc chunk))
      (dolist (event (my/ai-stream--line-to-events
                      line
                      (process-get proc 'my/ai-reader)
                      (process-get proc 'my/ai-normalizer)))
        (my/ai-stream--render buf event)
        ;; 承認・ツール実行はここから。描画の失敗で以降のイベントを落とさないよう
        ;; フック側のエラーは握って知らせるだけにする。
        (condition-case err
            (run-hook-with-args 'my/ai-stream-event-functions event)
          (error (message "my/ai-stream-event-functions でエラー: %s"
                          (error-message-string err))))))))

(defun my/ai-stream--sentinel (proc _event)
  "PROCの終了を描画先バッファへ知らせる。"
  (unless (process-live-p proc)
    (let ((buf (process-get proc 'my/ai-buffer))
          (status (process-exit-status proc))
          (my/ai-stream--state (process-get proc 'my/ai-state)))
      ;; 改行で終わらずに切れた最後の1行も捨てずに処理する
      (let ((rest (process-get proc 'my/ai-pending)))
        (when (and rest (not (string-empty-p (string-trim rest))))
          (dolist (event (my/ai-stream--line-to-events
                          rest
                          (process-get proc 'my/ai-reader)
                          (process-get proc 'my/ai-normalizer)))
            (my/ai-stream--render buf event))))
      (unless (zerop status)
        (my/ai-stream--render
         buf (list :type 'error
                   :message (format "プロセスが異常終了しました(status %s)。詳細は %s"
                                    status my/ai-stream-stderr-buffer-name))))
      (when (buffer-live-p buf)
        (with-current-buffer buf (setq my/ai-stream--process nil))))))

(cl-defun my/ai-stream-start (&key command reader normalizer stdin header
                                   (name "ai-stream")
                                   (buffer my/ai-stream-buffer-name)
                                   (directory default-directory))
  "COMMANDを起動し、その標準出力をJSONストリームとして読んでバッファへ描く。
READERは \\='stream-json か \\='sse、NORMALIZERはJSON1件をイベントのリストに
する関数。STDINがあれば標準入力へ送ってEOFを送る(APIキーをコマンドライン引数に
置かず、psに見せないため)。起動したプロセスを返す。"
  (let* ((buf (my/ai-stream--prepare-buffer buffer header))
         (stderr (get-buffer-create my/ai-stream-stderr-buffer-name))
         (default-directory directory)
         proc)
    (with-current-buffer stderr (let ((inhibit-read-only t)) (erase-buffer)))
    (setq proc (make-process
                :name name
                ;; 出力は:filterで自分で捌くので、バッファには溜めない
                :buffer nil
                :command command
                :connection-type 'pipe
                :noquery t
                :stderr stderr
                :filter #'my/ai-stream--filter
                :sentinel #'my/ai-stream--sentinel))
    ;; :stderr にバッファを渡すとEmacsが内部でパイププロセスを作り、その既定の
    ;; sentinel が "Process ... finished" をバッファへ書き込む。エラー出力に
    ;; 混ざると読みにくいので黙らせる。
    (when-let* ((pipe (get-buffer-process stderr)))
      (set-process-sentinel pipe #'ignore))
    (process-put proc 'my/ai-buffer buf)
    (process-put proc 'my/ai-reader reader)
    (process-put proc 'my/ai-normalizer normalizer)
    (process-put proc 'my/ai-pending "")
    (process-put proc 'my/ai-state (make-hash-table :test 'equal))
    (with-current-buffer buf (setq my/ai-stream--process proc))
    ;; stdinは渡す場合も渡さない場合も必ず閉じる。閉じないとコマンド側が
    ;; パイプからの入力を待ってしまう(claudeは3秒待って警告を出す)。
    (when stdin (process-send-string proc stdin))
    (process-send-eof proc)
    (my/ai-stream--display buf)
    proc))

(defun my/ai-stream-abort ()
  "実行中のストリームを中止する。"
  (interactive)
  (let ((buf (get-buffer my/ai-stream-buffer-name)))
    (if-let* ((proc (and buf (buffer-local-value 'my/ai-stream--process buf)))
              ((process-live-p proc)))
        (progn (interrupt-process proc)
               (message "ストリームを中止しました"))
      (message "実行中のストリームはありません"))))

;; =====================================================================
;; 6. 提供側ごとのエントリ
;; =====================================================================

(defun my/ai-stream-claude (prompt)
  "PROMPTをclaude CLIへ投げ、stream-jsonの出力をEmacs側で描画する。
vtermのTUIを介さないので、ツール呼び出しも結果もイベントとして受け取れる。
プロジェクトルートで動かす(my/ai-agent-project-root は conf/ai-agent.el)。"
  (interactive (list (read-string "claude: ")))
  (my/ai-stream-start
   :name "ai-stream-claude"
   :command (append (list my/ai-stream-claude-program "-p" prompt)
                    my/ai-stream-claude-args)
   :reader 'stream-json
   :normalizer #'my/ai-stream--normalize-claude
   :directory (my/ai-agent-project-root)
   :header (format "claude: %s" (my/ai-stream--one-line prompt 200))))

(defun my/ai-stream--curl-escape (string)
  "STRINGをcurlの設定記法の二重引用符内に置ける形にする。
curlの設定ファイルは値の中の \\ と \" をエスケープで解釈するため、その2文字だけ逃がす。"
  (replace-regexp-in-string "[\\\"]" (lambda (m) (concat "\\" m)) string t t))

(defun my/ai-stream--curl-config (url headers body)
  "URL・HEADERS(alist)・BODY(文字列)から、curlへ標準入力で渡す設定を作る。
APIキーをコマンドライン引数に置かないのが目的(psの出力に鍵が出ないようにする。
ai-agent.el の my/gptel--auth-ok-p と同じ方針)。"
  (concat
   "silent\n"         ; 進捗表示を出さない(JSONストリームに混ざらないように)
   "show-error\n"     ; ただしエラーは残す(stderr側へ出る)
   "no-buffer\n"      ; -N 相当。これが無いとcurlが溜め込んで逐次表示にならない
   "fail-with-body\n" ; HTTPエラー時も本文(エラーJSON)を出しつつ、終了コードで知らせる
   (format "url = \"%s\"\n" (my/ai-stream--curl-escape url))
   (mapconcat (lambda (h)
                (format "header = \"%s: %s\"\n" (car h) (my/ai-stream--curl-escape (cdr h))))
              headers "")
   (format "data = \"%s\"\n" (my/ai-stream--curl-escape body))))

(defun my/ai-stream--env (name)
  "環境変数NAMEの値を返す。未設定または空文字ならnilを返す。"
  (let ((v (getenv name)))
    (and v (not (string-empty-p v)) v)))

(defun my/ai-stream--gemini-config (model prompt)
  "Gemini の SSE エンドポイントを叩くcurl設定(文字列)を作る。
Geminiはbodyのフラグではなくメソッド(:streamGenerateContent)と alt=sse で
ストリーミングを指定する。"
  (let ((key (my/ai-stream--env "GEMINI_API_KEY")))
    (unless key (user-error "GEMINI_API_KEY が設定されていません"))
    (my/ai-stream--curl-config
     (format "https://generativelanguage.googleapis.com/v1beta/models/%s:streamGenerateContent?alt=sse"
             model)
     `(("x-goog-api-key" . ,key)
       ("Content-Type" . "application/json"))
     (json-serialize
      `((contents . [((role . "user") (parts . [((text . ,prompt))]))]))))))

(defun my/ai-stream-gemini (prompt)
  "PROMPTをGemini APIへ投げ、SSEの出力をEmacs側で描画する。
モデルは `my/ai-stream-gemini-model'。"
  (interactive (list (read-string "Gemini: ")))
  (let ((curl (executable-find "curl")))
    (unless curl (user-error "curl が見つかりません"))
    (my/ai-stream-start
     :name "ai-stream-gemini"
     ;; 設定は標準入力から読ませる(URL・ヘッダ・本文を引数に出さない)
     :command (list curl "--config" "-")
     :reader 'sse
     :normalizer #'my/ai-stream--normalize-gemini
     :stdin (my/ai-stream--gemini-config my/ai-stream-gemini-model prompt)
     :header (format "Gemini (%s): %s"
                     my/ai-stream-gemini-model (my/ai-stream--one-line prompt 200)))))

(defun my/ai-stream-myllm-sse-model-p (model)
  "MODELがMyLLMでSSEを使えるモデルなら非nilを返す。"
  (seq-some (lambda (re) (string-match-p re model)) my/ai-stream-myllm-sse-models))

(defun my/ai-stream--myllm-models ()
  "MyLLMのモデル一覧のうち、SSEが使えるものだけを返す。
一覧はgptelのMyLLMバックエンド(ai-agent.elが起動時に取得して保持している)から借りる。
ai-clientはgptelに依存しない作りなので、無ければnilを返して手入力に落とす。"
  ;; bound-and-true-p にしているのは、gptel側が無い環境(MY_LLM_*未設定など)で
  ;; 未定義変数の参照にならないようにするため。
  (when-let* ((backend (bound-and-true-p my/gptel-myllm-backend))
              ((fboundp 'gptel-backend-models)))
    (seq-filter #'my/ai-stream-myllm-sse-model-p
                (mapcar (lambda (m) (format "%s" (if (consp m) (car m) m)))
                        (gptel-backend-models backend)))))

(defun my/ai-stream--myllm-resolve-model (want candidates)
  "WANT(モデル名または名前の一部)に一致するモデルをCANDIDATESから探して返す。
無ければnilを返す。完全一致ではなく部分一致で引き当てるのは、サーバ側のモデルが
日々版を上げるため(ai-agent.el の MY_LLM_FAST_MODEL の扱いと同じ)。"
  (seq-find (lambda (m) (ignore-errors (string-match-p want m))) candidates))

(defun my/ai-stream--myllm-read-model ()
  "MyLLMで使うモデル名を決めて返す。SSE非対応のモデルならエラーにする。"
  (let* ((candidates (my/ai-stream--myllm-models))
         (want (or my/ai-stream-myllm-model
                   (my/ai-stream--env "MY_LLM_FAST_MODEL")))
         (model
          (cond
           ;; 設定があり一覧も取れている → 一覧から引き当てる。これで版の更新に追随する。
           ((and want candidates)
            (or (my/ai-stream--myllm-resolve-model want candidates)
                ;; 一致しないのは、版が上がって名前が変わったか綴り間違い。
                ;; 黙って別のモデルに落とさず、知らせてから選ばせる。
                (progn
                  (message "MyLLM: \"%s\" に一致するSSE対応モデルがありません(候補: %s)。一覧が古いときは M-x my/gptel-myllm-refresh-models"
                           want (string-join (seq-take candidates 8) " "))
                  (completing-read "MyLLM model: " candidates nil t))))
           ;; 一覧が取れない(gptelのMyLLMバックエンド未登録)→ 設定値をそのまま使う
           (want want)
           (candidates (completing-read "MyLLM model: " candidates nil t))
           (t (read-string "MyLLM model: ")))))
    (unless (my/ai-stream-myllm-sse-model-p model)
      (user-error "%s はMyLLMのSSE対応モデルではありません(対応: gemini-*-flash / claude-haiku-* / claude-sonnet-* / claude-opus-*)。単発の問い合わせなら gptel を使ってください"
                  model))
    model))

(defun my/ai-stream--myllm-config (model prompt)
  "MyLLM(独自のOpenAI互換API)を叩くcurl設定(文字列)を作る。
このAPIはGeminiのようにメソッドやパスでストリーミングを指定するのではなく、
エンドポイントは同じままbodyに \"stream\": true を入れるとSSEになる。"
  (let ((host (my/ai-stream--env "MY_LLM_HOST"))
        (path (my/ai-stream--env "MY_LLM_ENDPOINT"))
        (key  (my/ai-stream--env "MY_LLM_API_KEY")))
    (unless (and host path key)
      (user-error "MY_LLM_HOST / MY_LLM_ENDPOINT / MY_LLM_API_KEY が未設定です"))
    (my/ai-stream--curl-config
     (format "https://%s%s" host path)
     `(("Authorization" . ,(concat "Bearer " key))
       ("Content-Type" . "application/json"))
     (json-serialize
      `((model . ,model)
        ;; ここが独自APIの肝。URLは非ストリームと同じで、このフラグだけでSSEになる。
        (stream . t)
        (messages . [((role . "user") (content . ,prompt))]))))))

(defun my/ai-stream-myllm (prompt)
  "PROMPTを独自のOpenAI互換API(MY_LLM_*)へ投げ、SSEの出力をEmacs側で描画する。
モデルは `my/ai-stream-myllm-model'、未設定なら MY_LLM_FAST_MODEL、
それも無ければ実行時に選ぶ。SSE非対応のモデルは起動前に弾く。"
  (interactive (list (read-string "MyLLM: ")))
  (let ((curl (executable-find "curl"))
        (model (my/ai-stream--myllm-read-model)))
    (unless curl (user-error "curl が見つかりません"))
    (my/ai-stream-start
     :name "ai-stream-myllm"
     :command (list curl "--config" "-")
     :reader 'sse
     :normalizer #'my/ai-stream--normalize-openai
     :stdin (my/ai-stream--myllm-config model prompt)
     :header (format "MyLLM (%s): %s" model (my/ai-stream--one-line prompt 200)))))

(provide 'ai-client)
;;; ai-client.el ends here
