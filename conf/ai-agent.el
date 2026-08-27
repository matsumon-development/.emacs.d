;;; ai-agent.el --- AIエージェント関連の設定 -*- lexical-binding: t; -*-

;;; Commentary:

;; プロジェクトルートで各種AIエージェントCLIを vterm 上で起動する設定と、
;; gptel (エディタ一体型のインライン書き換え & チャット) の設定をまとめたファイル。
;;   - Claude Code (claude)
;;   - Antigravity CLI (agy)
;;   - IBM Bob (bob)   https://bob.ibm.com/docs/shell
;;
;; vterm 本体の設定と共通ヘルパー(my/vterm-get-or-create / my/vterm-pop-to-buffer-oriented
;; など)は package-manage.el 側の (use-package vterm ...) にある。ここの各コマンドは
;; それらに依存するため、vterm を実際に使う関数の先頭で (require 'vterm) して依存を
;; 明示する(vterm は :commands で遅延ロードされるので、起動時ではなく実行時に読み込む)。
;; init.el では package-manage の直後に (load "ai-agent") で読み込む。

;;; Code:

(require 'cl-lib)   ; my/define-ai-agent マクロで cl-defmacro / &key を使う

;; =====================================================================
;; 1. AIエージェント共通処理 (claude / agy / bob)
;; =====================================================================
;; claude・agy・bob はいずれも「プロジェクトルートで CLI を vterm 起動し、
;; 専用マイナーモードで識別する」という同じ構造を持つ。共通処理をここにまとめ、
;; 各エージェント固有の値(コマンド名・lighter・フレーム名)だけを
;; my/define-ai-agent マクロに渡して一式を生成する。

;; vc-root-dirはファイル自体がVCに追跡されている場合しか使えないため、
;; .gitの存在だけでルートを判定できるproject-currentを使う
(defun my/ai-agent-project-root ()
  "現在のプロジェクトルートを返す(project.elが検出できない場合はdefault-directory)。"
  (let ((proj (project-current)))
    (expand-file-name (if proj (project-root proj) default-directory))))

(defun my/ai-agent--send-startup (buf project-root command)
  "BUF(vterm)でPROJECT-ROOTへcdしてCOMMANDを起動する文字列を送る。"
  (with-current-buffer buf
    (vterm-send-string
     (format "cd %s && %s\n" (shell-quote-argument project-root) command))))

;; AIエージェントのバッファも、素の端末と同じくemacs-stateのまま扱う
;; (vterm-modeの初期ステート設定はconf/package-manage.el)。claude/agy/bobはESCや
;; C-a/C-r等を多用するTUIなので、evilに横取りさせず端末へそのまま渡すのが目的。
;; スクロールバックをvi操作で読みたいときは C-z で normal-state に入る。
(defun my/ai-agent-run (command mode-fn buffer-name-fn)
  "COMMANDをvtermで起動(既存バッファがあれば再利用)し、MODE-FNを有効化する。
BUFFER-NAME-FN はプロジェクトルートを受け取りバッファ名を返す関数。"
  (require 'vterm)
  (let* ((project-root (my/ai-agent-project-root))
         (buffer-name (funcall buffer-name-fn project-root))
         (existed (get-buffer buffer-name))
         (buf (my/vterm-get-or-create buffer-name #'my/vterm-pop-to-buffer-oriented)))
    (with-current-buffer buf
      (funcall mode-fn 1))
    (unless existed
      (my/ai-agent--send-startup buf project-root command))))

(defun my/ai-agent-pop-to-frame (command mode-fn buffer-name-fn frame-name)
  "COMMANDのバッファを別フレーム(FRAME-NAME)に切り出す。
すでに他のフレームで表示されていればそのフレームを選択するだけにする。
現在のフレームでウィンドウ分割表示されていれば、そのウィンドウは閉じる。
別フレームに出すだけなので、現在のフレームでの分割表示(split-window)は行わない。"
  (require 'vterm)
  (let* ((project-root (my/ai-agent-project-root))
         (buffer-name (funcall buffer-name-fn project-root))
         (existed (get-buffer buffer-name))
         (other-frame-win
          (and existed
               (seq-find (lambda (win) (not (eq (window-frame win) (selected-frame))))
                         (get-buffer-window-list existed nil t)))))
    (if other-frame-win
        (progn
          (select-frame-set-input-focus (window-frame other-frame-win))
          (select-window other-frame-win))
      (let* ((current-frame-win
              (and existed
                   (seq-find (lambda (win) (eq (window-frame win) (selected-frame)))
                             (get-buffer-window-list existed nil t))))
             ;; 現在のフレームがすでにこのバッファ専用(唯一のウィンドウ)になっているか
             (frame-dedicated-p
              (and current-frame-win
                   (= (length (window-list (selected-frame))) 1))))
        (if frame-dedicated-p
            ;; すでに専用フレームでそのまま表示されているだけなので何もしない
            (select-window current-frame-win)
          (let (buf)
            (if existed
                (setq buf existed)
              (setq buf (generate-new-buffer buffer-name))
              (with-current-buffer buf
                (vterm-mode)))
            (with-current-buffer buf
              (funcall mode-fn 1))
            (unless existed
              (my/ai-agent--send-startup buf project-root command))
            ;; 現在のフレームで分割表示されていれば、そのウィンドウだけ閉じる
            (dolist (win (get-buffer-window-list buf nil t))
              (when (eq (window-frame win) (selected-frame))
                (delete-window win)))
            (select-frame-set-input-focus (make-frame (list (cons 'name frame-name))))
            (switch-to-buffer buf)))))))

(defun my/ai-agent--dock-to-window (buffer-name-fn frame-name)
  "FRAME-NAMEで別フレームに切り出したAIバッファを、元のフレームの分割ウィンドウに戻す。
BUFFER-NAME-FN はバッファ名を返す関数。
名前がFRAME-NAMEの専用フレームを探し、別の可視フレームで
my/vterm-pop-to-buffer-oriented により分割表示してから、専用フレームを削除する。
my/ai-agent-pop-to-frame の逆操作。"
  (require 'vterm)
  (let* ((buffer-name (funcall buffer-name-fn))
         (buf (get-buffer buffer-name)))
    (unless buf
      (user-error "%s のバッファがありません" buffer-name))
    (let* ((dedicated-frame
            (seq-find (lambda (fr) (equal (frame-parameter fr 'name) frame-name))
                      (frame-list)))
           ;; 戻し先: 専用フレーム以外の可視フレーム(通常はメインフレーム)
           (target-frame
            (seq-find (lambda (fr)
                        (and (frame-visible-p fr)
                             (not (eq fr dedicated-frame))))
                      (frame-list))))
      (unless dedicated-frame
        (user-error "別フレーム(%s)に切り出されていません" frame-name))
      (unless target-frame
        (user-error "戻し先のフレームがありません"))
      ;; 戻し先フレームを選択し、そこで分割表示する。
      ;; すでにそのフレームで表示済みなら、新たに分割せずそのウィンドウを選ぶ。
      (select-frame-set-input-focus target-frame)
      (let ((existing (seq-find (lambda (win) (eq (window-frame win) target-frame))
                                (get-buffer-window-list buf nil t))))
        (if existing
            (select-window existing)
          (my/vterm-pop-to-buffer-oriented buf)))
      ;; 切り出し用の専用フレームはもう不要なので閉じる。
      (when (frame-live-p dedicated-frame)
        (delete-frame dedicated-frame)))))

(defvar my/ai-agents nil
  "定義済みAIエージェントのalist。
キーはコマンド名(文字列、例: \"claude\")、値は各種関数/シンボルを持つplist。
plistのキー: :run :buffer-name :pop-to-frame :back-to-window
             :frame-name :mode :mode-map。
my/define-ai-agent が呼ばれるたびに登録される。")

(defun my/ai-agent-get (tool)
  "TOOL(コマンド名文字列、例: \"claude\")に対応するエージェントplistを返す。
未登録ならnil。"
  (cdr (assoc tool my/ai-agents)))

(cl-defmacro my/define-ai-agent (stem &key command lighter frame-name)
  "AIエージェント(vterm CLI起動)一式を定義する。
STEM       関数/モード名の語幹シンボル (例: claude-code, agy, bob)。
COMMAND    vtermで起動するCLIコマンド文字列 (例: \"claude\")。
LIGHTER    モードラインの表示 (例: \" Claude\")。
FRAME-NAME 別フレームに切り出す際のフレーム名 (例: \"Claude Code\")。

以下を生成する:
  my/STEM-mode          識別用マイナーモード
  my/STEM-buffer-name    プロジェクト別バッファ名
  my/run-STEM            起動(既存があれば再利用)コマンド
  my/STEM-pop-to-frame   別フレームへ切り出すコマンド
  my/STEM-back-to-window 別フレームから元のフレームの分割へ戻すコマンド
また COMMAND をキーに my/ai-agents へ登録する。"
  (let* ((name        (symbol-name stem))
         (mode-sym    (intern (format "my/%s-mode" name)))
         (mode-map-sym (intern (format "my/%s-mode-map" name)))
         (bufname-sym (intern (format "my/%s-buffer-name" name)))
         (run-sym     (intern (format "my/run-%s" name)))
         (frame-sym   (intern (format "my/%s-pop-to-frame" name)))
         (back-sym    (intern (format "my/%s-back-to-window" name))))
    `(progn
       ;; プレーンなvterm端末(my/run-vterm-current-dir)と区別し、
       ;; 固有のキーバインドやフックはこのモード経由で追加する。
       (define-minor-mode ,mode-sym
         ,(format "%s をvtermでやりとりしているバッファであることを示すマイナーモード。" command)
         :lighter ,lighter
         :keymap (make-sparse-keymap))
       (defun ,bufname-sym (&optional project-root)
         ,(format "PROJECT-ROOT(省略時は現在のプロジェクトルート)に対応する%sバッファ名を返す。" command)
         (let* ((root (or project-root (my/ai-agent-project-root)))
                (project-name (file-name-nondirectory (directory-file-name root))))
           (format ,(format "*%s:%%s*" name) project-name)))
       (defun ,run-sym ()
         ,(format "現在のプロジェクトルートで %s を起動します。" command)
         (interactive)
         (my/ai-agent-run ,command #',mode-sym #',bufname-sym))
       (defun ,frame-sym ()
         ,(format "現在のプロジェクトの%sバッファを別フレームに切り出す。
詳細は my/ai-agent-pop-to-frame を参照。" command)
         (interactive)
         (my/ai-agent-pop-to-frame ,command #',mode-sym #',bufname-sym ,frame-name))
       (defun ,back-sym ()
         ,(format "現在のプロジェクトの%sバッファを、別フレームから元のフレームの分割に戻す。
詳細は my/ai-agent--dock-to-window を参照。" command)
         (interactive)
         (my/ai-agent--dock-to-window #',bufname-sym ,frame-name))
       ;; コマンド名をキーにレジストリへ登録(重複登録時は上書き)。
       ;; キーバインドや共通処理側は my/ai-agents を辿ることで
       ;; エージェントを増やしても自動的に対応できる。
       (setq my/ai-agents
             (cons (cons ,command (list :command         ,command
                                        :run            #',run-sym
                                        :buffer-name     #',bufname-sym
                                        :pop-to-frame    #',frame-sym
                                        :back-to-window  #',back-sym
                                        :frame-name      ,frame-name
                                        :mode            ',mode-sym
                                        :mode-map        ',mode-map-sym))
                   (assoc-delete-all ,command my/ai-agents))))))

(my/define-ai-agent claude-code
  :command "claude" :lighter " Claude" :frame-name "Claude Code")

(my/define-ai-agent agy
  :command "agy" :lighter " Agy" :frame-name "Antigravity")

;; IBM Bob (bob)   https://bob.ibm.com/docs/shell
(my/define-ai-agent bob
  :command "bob" :lighter " Bob" :frame-name "Bob")

;; =====================================================================
;; 2. AIエージェントのバッファ操作 / 選択テキスト送信
;; =====================================================================
;; キーバインド(keybind-manage.el)から呼ぶコマンド本体。keybind側には
;; ロジックを置かず、束縛だけを書けるようにここへ実処理をまとめる。

;; Normalステートで q を押したらウィンドウを閉じる(バッファ・プロセスは残す)。
;; my/STEM-mode-map 経由で束縛するので、プレーンなvterm端末には影響しない。
;; quit-windowはdisplay-buffer経由で作られたウィンドウのquit-restoreパラメータに
;; 依存するため、split-windowで直接作ったこのウィンドウには効かない。
;; そのため単純にdelete-windowでウィンドウ自体を閉じる。
(defun my/ai-tool-quit-window ()
  "AIツールのウィンドウを閉じる(バッファ・プロセスは残す)。"
  (interactive)
  (when (> (count-windows) 1)
    (delete-window)))

(defun my/ai-agent-current ()
  "現在のバッファで有効なAIエージェントのplistを返す。無ければnil。
my/STEM-mode マイナーモードが有効かどうかで判定する。"
  (seq-some (lambda (agent)
              (let ((mode (plist-get (cdr agent) :mode)))
                (and (boundp mode) (symbol-value mode) (cdr agent))))
            my/ai-agents))

(defun my/ai-agent-back-to-window ()
  "現在のAIエージェントバッファを、別フレームから元のフレームの分割に戻す。
どのエージェントかは有効なマイナーモードから自動判定するので、
別フレーム側のバッファ内で実行すればよい。"
  (interactive)
  (let ((agent (or (my/ai-agent-current)
                   (user-error "AIエージェントのバッファではありません"))))
    (my/ai-agent--dock-to-window (plist-get agent :buffer-name)
                                 (plist-get agent :frame-name))))

;; 「どのエージェントか」を指定せず、今ウィンドウに表示されているAIエージェントを
;; 対象にする統合コマンド。keybind側は SPC a f / SPC a w の2つだけで済む。
(defun my/ai-agent-displayed-in-frame (&optional frame)
  "FRAME(省略時は選択フレーム)のウィンドウに表示されているAIエージェントのplistを返す。
無ければnil。各ウィンドウのバッファで my/STEM-mode が有効かどうかで判定する。"
  (seq-some (lambda (win)
              (with-current-buffer (window-buffer win)
                (my/ai-agent-current)))
            (window-list (or frame (selected-frame)))))

(defun my/ai-agent-displayed ()
  "今表示中のAIエージェントのplistを返す。無ければnil。
選択フレームを優先し、そこに無ければ全フレームのウィンドウを探す
(別フレームに切り出した状態から戻す場合に対応)。"
  (or (my/ai-agent-displayed-in-frame (selected-frame))
      (seq-some #'my/ai-agent-displayed-in-frame (frame-list))))

(defun my/ai-agent-pop-displayed-to-frame ()
  "今ウィンドウに表示されているAIエージェントを別フレームに切り出す。
どのエージェントかは表示中のバッファから自動判定するので、
エージェントごとにキーを分ける必要はない。"
  (interactive)
  (let ((agent (or (my/ai-agent-displayed)
                   (user-error "ウィンドウにAIエージェントが表示されていません"))))
    (funcall (plist-get agent :pop-to-frame))))

(defun my/ai-agent-dock-displayed-to-window ()
  "別フレームに切り出したAIエージェントを、元のフレームの分割に戻す。
どのエージェントかは表示中のバッファから自動判定する。
my/ai-agent-pop-displayed-to-frame の逆操作。"
  (interactive)
  (let ((agent (or (my/ai-agent-displayed)
                   (user-error "AIエージェントが表示されていません"))))
    (funcall (plist-get agent :back-to-window))))

;; エージェントのバッファ内では Normal ステートの q(my/ai-tool-quit-window)で
;; ウィンドウを閉じられるが、以下は「エージェント以外のウィンドウにいるまま」
;; 別ウィンドウで開いているエージェントを片付けるためのコマンド。
;; 全フレームのウィンドウを走査し、エージェント(my/STEM-mode)を表示している
;; ウィンドウを対象にする。
(defun my/ai-agent--displayed-windows ()
  "全フレームで、AIエージェントのバッファを表示しているウィンドウのリストを返す。"
  (seq-filter (lambda (win)
                (with-current-buffer (window-buffer win)
                  (my/ai-agent-current)))
              (cl-mapcan #'window-list (frame-list))))

(defun my/ai-agent-quit-displayed-window ()
  "表示中のAIエージェントのウィンドウを閉じる(バッファ・プロセスは残す)。
エージェント以外のウィンドウにいるまま、別ウィンドウのエージェントを片付ける用途。
(エージェントのバッファ内なら Normal ステートの q でも閉じられる。)"
  (interactive)
  (let ((wins (or (my/ai-agent--displayed-windows)
                  (user-error "AIエージェントが表示されていません"))))
    (dolist (win wins)
      ;; フレーム唯一のウィンドウは delete-window できないので残す。
      (when (and (window-live-p win)
                 (> (length (window-list (window-frame win))) 1))
        (delete-window win)))))

(defun my/ai-agent-kill-displayed-buffer ()
  "表示中のAIエージェントのウィンドウを閉じ、さらにバッファも削除する(vtermプロセスも終了)。
vtermは実行中プロセスを持つため通常killでは確認を求められるが、明示的な
「閉じる」操作なので kill-buffer-query-functions を無効化して一発で閉じる。"
  (interactive)
  (let ((wins (or (my/ai-agent--displayed-windows)
                  (user-error "AIエージェントが表示されていません"))))
    (dolist (win wins)
      (let ((buf (window-buffer win)))
        (when (and (window-live-p win)
                   (> (length (window-list (window-frame win))) 1))
          (delete-window win))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buf))))))

;; =====================================================================
;; 3. Claude Code セッション全文の表示
;; =====================================================================
;; claudeの対話UIは画面を再描画する方式のため、vtermのスクロールバックには
;; 過去のやり取りが積まれない(表示は画面の縦サイズぶんに収まる)。ただし会話は
;; claude自身が ~/.claude/projects/<スラッグ>/<セッションUUID>.jsonl に全文を
;; 保存しているので、その最新ファイルを整形して専用バッファに表示する。
;;   スラッグ規則: プロジェクトルートのパス中の / と . をすべて - に置換したもの。
;;     例: /Users/kensei/.emacs.d → -Users-kensei--emacs-d

(defvar my/claude-projects-dir (expand-file-name "~/.claude/projects/")
  "Claude Code がセッションのトランスクリプト(JSONL)を保存するディレクトリ。")

(define-minor-mode my/claude-session-mode
  "Claude Codeセッション全文表示バッファ(*claude-session:...*)であることを示すモード。
normalステートで q を押すと閉じられるよう、キーバインドはこのマップ経由で束縛する
(keybind-manage.el / evil-define-key)。"
  :lighter " ClaudeSession"
  :keymap (make-sparse-keymap))

(defun my/claude-session-quit ()
  "セッション表示バッファを閉じる(バッファをkillし、分割していればウィンドウも閉じる)。"
  (interactive)
  (let ((buf (current-buffer)))
    (when (> (count-windows) 1)
      (delete-window))
    (kill-buffer buf)))

(defun my/claude-code--project-slug (project-root)
  "PROJECT-ROOT を Claude Code のトランスクリプトディレクトリ名(スラッグ)に変換する。
パス中の / と . をすべて - に置換する。"
  (replace-regexp-in-string "[/.]" "-" (directory-file-name project-root)))

(defun my/claude-code--latest-transcript (project-root)
  "PROJECT-ROOT に対応する最新の(最終更新が新しい)トランスクリプトファイルを返す。
無ければnil。起動中のセッションは書き込みが続くので通常これが現在のセッション。"
  (let* ((dir (expand-file-name (my/claude-code--project-slug project-root)
                                my/claude-projects-dir))
         (files (and (file-directory-p dir)
                     (directory-files dir t "\\.jsonl\\'"))))
    (car (sort files
               (lambda (a b)
                 (time-less-p (file-attribute-modification-time (file-attributes b))
                              (file-attribute-modification-time (file-attributes a))))))))

(defun my/claude-code--render-content (content)
  "メッセージのcontent(文字列またはブロックのベクタ)を読みやすいテキストにして返す。"
  (cond
   ((null content) "")
   ((stringp content) content)
   ((vectorp content)
    ;; 空ブロック(内容が保存されていないthinking等)は空文字になるので取り除く。
    (mapconcat #'identity
               (seq-remove #'string-empty-p
                           (mapcar #'my/claude-code--render-block content))
               "\n"))
   (t (format "%s" content))))

(defun my/claude-code--blockquote (text)
  "TEXT の各行頭に \"> \" を付け、Markdownの引用(blockquote)にして返す。
thinking や tool_result のように「本文だが控えめに見せたい」ものに使う。"
  (mapconcat (lambda (l) (if (string-empty-p l) ">" (concat "> " l)))
             (split-string text "\n") "\n"))

(defun my/claude-code--render-block (block)
  "content内の1ブロック(hash-table)をMarkdownに整形して返す。text/thinking/tool_use/tool_result対応。
内容が無いブロックは空文字を返す(呼び出し側で除去する)。gfm-view-modeで整形表示する前提で、
見出しは ## 、コマンド/結果はコードブロックや引用で表す。"
  (if (not (hash-table-p block))
      (format "%s" block)
    (let ((type (gethash "type" block)))
      (cond
       ((equal type "text") (or (gethash "text" block) ""))
       ((equal type "thinking")
        ;; Claude Codeはthinking本文を保存しない場合がある(type/signatureのみ)。
        ;; 中身が空なら見出しごと出さない。あるときは引用で控えめに表示。
        (let ((tt (or (gethash "thinking" block) "")))
          (if (string-empty-p (string-trim tt)) ""
            (concat "> 💭 *thinking*\n>\n" (my/claude-code--blockquote tt)))))
       ((equal type "tool_use")
        ;; ターミナルの ⏺ 記法に寄せる。ファイルパスはインラインコード、コマンドや
        ;; 入力JSONはフェンス付きコードブロックにして、gfm側で着色・整形させる。
        ;; (Edit系の変更内容は後続の tool_result 側で ```diff として表示する)
        (let* ((name (gethash "name" block))
               (input (gethash "input" block))
               (fp (and (hash-table-p input) (gethash "file_path" input)))
               (cmd (and (hash-table-p input) (gethash "command" input))))
          (cond
           (fp  (format "⏺ **%s** `%s`" name fp))
           (cmd (format "⏺ **%s**\n```sh\n%s\n```" name cmd))
           (input (format "⏺ **%s**\n```json\n%s\n```" name
                          (or (ignore-errors (json-serialize input)) "")))
           (t (format "⏺ **%s**" name)))))
       ((equal type "tool_result")
        (let ((c (string-trim
                  (my/claude-code--render-content (gethash "content" block)))))
          (if (string-empty-p c) "" (my/claude-code--blockquote c))))
       ((equal type "image") "🖼 *image*")
       (t "")))))

(defun my/claude-code--render-patch (patch)
  "structuredPatch(ハンクのベクタ)を プレーンな unified diff 文字列にして返す。
各ハンクは oldStart/oldLines/newStart/newLines/lines を持ち、
lines の各行頭は 空白(文脈) / +(追加) / -(削除)。
着色は手動propertizeせず、呼び出し側で ```diff フェンスに入れて
gfm-view-mode(markdown-fontify-code-blocks-natively)に色付けさせる。"
  (mapconcat
   (lambda (hunk)
     (concat
      (format "@@ -%s,%s +%s,%s @@"
              (gethash "oldStart" hunk) (gethash "oldLines" hunk)
              (gethash "newStart" hunk) (gethash "newLines" hunk))
      "\n"
      (mapconcat #'identity (gethash "lines" hunk) "\n")))
   patch "\n"))

(defun my/claude-code-show-session ()
  "現在のプロジェクトの Claude Code セッション全文を専用バッファに整形表示する。
claudeの対話UIではvtermに過去分が残らないため、~/.claude/projects 以下の
最新トランスクリプト(JSONL)を読み、user/assistant のやり取りを時系列で表示する。"
  (interactive)
  (let* ((root (my/ai-agent-project-root))
         (file (or (my/claude-code--latest-transcript root)
                   (user-error "このプロジェクトのClaude Codeトランスクリプトが見つかりません: %s" root)))
         (bufname (format "*claude-session:%s*"
                          (file-name-nondirectory (directory-file-name root))))
         (lines (with-temp-buffer
                  (insert-file-contents file)
                  (split-string (buffer-string) "\n" t)))
         (out (get-buffer-create bufname)))
    (with-current-buffer out
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "# Claude Code session\n\n`%s`\n" file))
        (dolist (line lines)
          (condition-case nil
              (let* ((obj (json-parse-string line :object-type 'hash-table :array-type 'array))
                     (type (gethash "type" obj))
                     (msg (gethash "message" obj))
                     (tur (gethash "toolUseResult" obj))
                     (patch (and (hash-table-p tur) (gethash "structuredPatch" tur))))
                (cond
                 ;; Edit/MultiEdit の結果は tool_result の文言ではなく ```diff で表示する。
                 ((and patch (> (length patch) 0))
                  (insert (format "\n⏺ **Edit** `%s`\n```diff\n%s\n```\n"
                                  (or (gethash "filePath" tur) "")
                                  (my/claude-code--render-patch patch))))
                 ((hash-table-p msg)
                  ;; 役割ヘッダはターミナルに寄せて ▌ You / ● Claude とし、Markdown見出し
                  ;; (##)にすることで gfm-view-mode 側で大きく・区切り明瞭に表示させる。
                  (let* ((role (or (gethash "role" msg) type "?"))
                         (head (cond ((equal role "user") "## ▌ You")
                                     ((equal role "assistant") "## ● Claude")
                                     (t (format "## %s" (upcase role)))))
                         (text (string-trim
                                (my/claude-code--render-content (gethash "content" msg)))))
                    (unless (string-empty-p text)
                      (insert (format "\n%s\n\n%s\n" head text)))))
                 ((equal type "summary")
                  (insert (format "\n## 📄 Summary\n\n%s\n" (or (gethash "summary" obj) ""))))))
            (error nil))))
      (goto-char (point-min))
      ;; Markdownとして「整形表示」する。見出しスケーリング・コードブロックの
      ;; ネイティブ着色を有効にしてから gfm-view-mode(読み取り専用GFM)にし、
      ;; マークアップ記号(## ** ` など)を隠して素の見た目に近づける。
      (require 'markdown-mode)  ; 下記defcustomを先に定義させ、free variable警告も防ぐ
      (setq markdown-header-scaling t
            markdown-fontify-code-blocks-natively t)
      (gfm-view-mode)
      (when (fboundp 'markdown-toggle-markup-hiding)
        (markdown-toggle-markup-hiding 1))
      (my/claude-session-mode 1))
    (pop-to-buffer out)))

;; normalステートで q を押したら閉じる(バッファをkillしウィンドウも閉じる)。
;; view-modeやevil-normal-state-mapのqより優先させるため、マイナーモードマップに
;; evil-define-keyで束縛する。
(with-eval-after-load 'evil
  (evil-define-key 'normal my/claude-session-mode-map "q" #'my/claude-session-quit))

;; Visualステートで選択中のテキストを、ファイルパスと行:列範囲付きで
;; AIエージェント(claude / agy / bob)のプロンプトに貼り付ける。
;; 例:
;;   /path/to/file.el L10:R30 ~L20:R2
;;   ```
;;   (選択したテキスト)
;;   ```
;; vterm-send-stringのpaste-p(bracketed paste)を使うので、
;; 複数行になっても改行のたびに送信されず、エージェント側で複数行入力として扱われる。
;; 送り先はデフォルトのAIツール(my/get-default-ai-tool)。SPC a a で切り替えられる。
(defun my/ai--visual-selection-payload ()
  "Visualステートの選択範囲を、ファイルパス+行:列範囲付きのペイロード文字列にして返す。
Visualステートでなければエラー。整形例:
  /path/to/file.el L10:R30 ~L20:R2
  ```
  (選択したテキスト)
  ```
region-beginning/end を読むので、evilステートを変える前に呼ぶこと。"
  (unless (evil-visual-state-p)
    (user-error "Visualステートで選択してから実行してください"))
  (let* ((beg (region-beginning))
         (end (region-end))
         (text (buffer-substring-no-properties beg end))
         (file (or (buffer-file-name) (buffer-name)))
         (start-line (line-number-at-pos beg))
         (start-col (1+ (save-excursion (goto-char beg) (current-column))))
         (end-line (line-number-at-pos end))
         (end-col (1+ (save-excursion (goto-char end) (current-column)))))
    (format "%s L%d:R%d ~L%d:R%d\n```\n%s\n```\n"
            file start-line start-col end-line end-col text)))

(defun my/send-visual-selection-to-ai (&optional tool)
  "Visualステートで選択中のテキストを、ファイルパスと行:列範囲付きで
AIエージェントのプロンプトに貼り付ける。
TOOL(コマンド名文字列)省略時はデフォルトのAIツールに送る。
対応するバッファが無ければ起動してから送る。"
  (interactive)
  (let* ((payload (my/ai--visual-selection-payload))
         (tool (or tool (my/get-default-ai-tool)))
         (agent (or (my/ai-agent-get tool)
                    (user-error "未対応のAIツールです: %s" tool)))
         (run-fn (plist-get agent :run))
         (bufname-fn (plist-get agent :buffer-name))
         (buffer-name (funcall bufname-fn))
         (already-running (get-buffer buffer-name)))
    (evil-normal-state)
    (funcall run-fn)
    (if already-running
        (with-current-buffer buffer-name
          (vterm-send-string payload t))
      ;; 起動直後はエージェントの準備ができるまで少し待ってから送る
      (run-at-time 1.5 nil
                   (lambda (buf txt)
                     (when (buffer-live-p buf)
                       (with-current-buffer buf
                         (vterm-send-string txt t))))
                   (get-buffer buffer-name) payload))))

;; ---------------------------------------------------------------------
;; 選択範囲を「外部ターミナルの tmux ペイン」へ送る(vtermを使わない経路)
;; ---------------------------------------------------------------------
;; Emacs内蔵のvtermではなく、Ghostty等のターミナル内で tmux 実行中の
;; claude/agy/bob へ、選択範囲を送りたい場合に使う。GhosttyはAppleScript制御を
;; 持たないため、ターミナルemulatorに依存しない tmux を仲介役にする。
;; 送信は `tmux load-buffer`(ペイロードをpaste-bufferへ)+ `paste-buffer -p`
;; (bracketed paste)で行う。bracketed pasteにより複数行が「1回の貼り付け」
;; として扱われ、行ごとに実行/送信されない(vterm側の paste-p と同じ狙い)。
(defvar my/ai-tmux-target "claude"
  "選択範囲プロンプトの送信先 tmux ターゲット。
セッション名(例: \"claude\")か、session:window.pane 形式(例: \"claude:0.1\")。
Ghostty等で `tmux new -s claude` してから claude を起動しておく運用を想定。")

(defvar my/ai-tmux-send-enter nil
  "非nilなら貼り付け後に Enter を送って即送信する。
nil(既定)なら貼り付けのみで、送信するかは対象側で手動確認する。")

(defun my/ai-agent--tmux-session-exists-p (session)
  "tmux セッション SESSION が存在すれば非nilを返す(tmux未起動なら nil)。"
  (and (executable-find "tmux")
       (zerop (call-process "tmux" nil nil nil "has-session" "-t" session))))

(defun my/ai--tmux-send-text (session text &optional send-enter enter-delay)
  "TEXT を tmux セッション SESSION へ bracketed paste で送る。
load-buffer(stdin)で paste-buffer に読み込み、paste-buffer -p(bracketed paste)で
貼り付ける。複数行は「1回の貼り付け」として渡り、行ごとに実行/送信されない。
SEND-ENTER が非nilなら最後に Enter を送って送信する。
ENTER-DELAY(秒)が指定されれば、ペースト後 Enter を送る前にその時間だけ待つ
(claude が貼り付けた画像パスを添付として認識する猶予。間を置かないと Enter が
添付処理に吸われて送信されないことがある)。"
  (unless (executable-find "tmux")
    (user-error "tmux が見つかりません。brew install tmux を実行してください"))
  (with-temp-buffer
    (insert text)
    (unless (zerop (call-process-region (point-min) (point-max)
                                        "tmux" nil nil nil "load-buffer" "-"))
      (user-error "tmux load-buffer に失敗しました(tmux は起動していますか?)")))
  (unless (zerop (call-process "tmux" nil nil nil
                               "paste-buffer" "-d" "-p" "-t" session))
    (user-error "tmux paste-buffer に失敗(対象 \"%s\" は起動中ですか? tmux ls で確認)" session))
  (when send-enter
    (when (and enter-delay (> enter-delay 0)) (sleep-for enter-delay))
    (call-process "tmux" nil nil nil "send-keys" "-t" session "Enter")))

(defun my/send-visual-selection-to-tmux ()
  "Visualステートの選択範囲を、tmux ペイン(`my/ai-tmux-target')へ送る。
vterm を経由せず、外部ターミナルで tmux 実行中のエージェントへ bracketed paste する。
ペイロード整形は vterm 版と共通(`my/ai--visual-selection-payload')。"
  (interactive)
  (let ((payload (my/ai--visual-selection-payload))
        (target my/ai-tmux-target))
    ;; 送信先の存在を先に確認し、tmux未起動やセッション名違いを弾く。
    (unless (my/ai-agent--tmux-session-exists-p target)
      (user-error "tmux ターゲット \"%s\" が見つかりません。Ghosttyで `tmux new -s %s` してから claude 等を起動してください(送信先は my/ai-tmux-target で変更可)"
                  target target))
    (evil-normal-state)
    (my/ai--tmux-send-text target payload my/ai-tmux-send-enter)
    (message "tmux[%s] に選択範囲を送信しました%s"
             target (if my/ai-tmux-send-enter "(Enter送信)" ""))))

;; ---------------------------------------------------------------------
;; SPC a c: claude を vterm と tmux(外部Ghostty)のどちらで起動するか選ぶ
;; ---------------------------------------------------------------------
;; vterm … 従来どおりEmacs内のvtermバッファで起動。
;; tmux  … 新しいGhosttyウィンドウを開き、その中でtmuxセッション+claudeを起動する。
;;         セッション名はエージェントのバッファ名(例 *claude-code:proj*)を整形した
;;         もの(claude-code-proj)。起動後は SPC a s t の送信先もそのセッションに合わせる。
(defun my/ai-agent--tmux-session-name (buffer-name)
  "BUFFER-NAME(バッファ名文字列)から tmux セッション名を作る。
tmux で使えない/紛らわしい文字(前後の *、および : . 空白)を除去/ - に置換する。
例: \"*claude-code:myproj*\" -> \"claude-code-myproj\"。"
  (let ((raw (replace-regexp-in-string "\\`\\*+\\|\\*+\\'" "" buffer-name)))
    (replace-regexp-in-string "[:.[:space:]]+" "-" raw)))

(defvar my/ai-tmux-ghostty-window-size '(100 . 30)
  "tmux 起動で開く Ghostty ウィンドウのサイズ (幅列 . 高行)。
Ghostty の --window-width / --window-height(グリッドの列数・行数)に渡す。
nil ならサイズ指定せず Ghostty の既定に任せる。")

(defun my/ai-agent--tmux-ghostty-position ()
  "Ghostty を開くモニターの左上ピクセル座標 (X . Y) を返す(非GUIなら nil)。
モニターが複数なら Emacs のいるモニターとは別のモニター、1枚ならそのモニターの左上。
Ghostty の --window-position-x/y はプライマリモニター左上原点なので、
Emacs の geometry(同じ原点)の左上をそのまま渡す。"
  (when (display-graphic-p)
    (let* ((monitors (display-monitor-attributes-list))
           (cur (frame-monitor-attributes))
           (target (if (<= (length monitors) 1)
                       cur
                     (or (seq-find (lambda (m) (not (equal (alist-get 'workarea m)
                                                           (alist-get 'workarea cur))))
                                   monitors)
                         cur))))
      (pcase-let ((`(,x ,y ,_w ,_h) (alist-get 'geometry target)))
        (cons x y)))))

(defun my/ai-agent-run-in-tmux (command bufname-fn)
  "COMMAND(例 \"claude\")を、外部Ghostty上のtmuxセッションで起動する。
セッション名は BUFNAME-FN のバッファ名を整形したもの(`my/ai-agent--tmux-session-name')。
`open -na Ghostty.app --args -e tmux new-session -A -s <session> -c <root>'
の要領で新しいGhosttyウィンドウを開き、その中で tmux セッション+コマンドを立ち上げる
(-A なので同名セッションが既にあれば再利用する)。起動したセッション名を
`my/ai-tmux-target' にセットし、以後 `SPC a s t' の送信先をそのセッションに合わせる。
ウィンドウは対象モニター(複数時は Emacs と別モニター)の左上に置く。Emacs には触らない。"
  (unless (executable-find "tmux")
    (user-error "tmux が見つかりません。brew install tmux を実行してください"))
  (let* ((root (my/ai-agent-project-root))
         (session (my/ai-agent--tmux-session-name (funcall bufname-fn root)))
         (pos (my/ai-agent--tmux-ghostty-position))
         (size my/ai-tmux-ghostty-window-size)
         ;; --window-position/width/height は -e より前に置く。
         (win-args (append
                    (when pos
                      (list (format "--window-position-x=%d" (car pos))
                            (format "--window-position-y=%d" (cdr pos))))
                    (when size
                      (list (format "--window-width=%d" (car size))
                            (format "--window-height=%d" (cdr size)))))))
    ;; -c でプロジェクトルートを起動ディレクトリに指定する。open(launchd)経由で
    ;; 起動するプロセスの作業ディレクトリはHOMEになるため、指定しないと claude が
    ;; HOMEで立ち上がってしまう(vterm版が cd しているのと同じ意図)。
    ;; (open -g だと -n の新規インスタンスが起動しないため使えない)
    (apply #'call-process "open" nil nil nil
           "-na" "Ghostty.app" "--args"
           (append win-args
                   (list "-e" "tmux" "new-session" "-A" "-s" session "-c" root command)))
    ;; open は Ghostty を前面化してフォーカスを奪う。少し待ってウィンドウが出そろってから
    ;; Emacs を再アクティブ化してフォーカスを戻す(Emacs で作業を続けられるように)。
    (let ((frame (selected-frame)))
      (run-at-time 0.8 nil
                   (lambda ()
                     (when (frame-live-p frame)
                       (select-frame-set-input-focus frame)))))
    (setq my/ai-tmux-target session)
    (message "Ghosttyでtmuxセッション \"%s\"(%s)を起動しました(SPC a s t の送信先も設定)"
             session root)))

(defun my/run-claude-code-choose ()
  "claude を vterm と tmux(外部Ghostty)のどちらで起動するか選んで実行する。
既定は vterm。tmux を選ぶと新しいGhosttyウィンドウで tmux セッションとして起動する。"
  (interactive)
  (let ((choice (completing-read "Claudeの起動方法: " '("vterm" "tmux")
                                 nil t nil nil "vterm")))
    (cond
     ((string= choice "vterm") (my/run-claude-code))
     ((string= choice "tmux")
      (my/ai-agent-run-in-tmux "claude" #'my/claude-code-buffer-name)))))

;; =====================================================================
;; 4. デフォルトAIツールのプロンプト起動
;; =====================================================================
(defvar my/ai-default-tool-file (expand-file-name ".default-ai-tool" user-emacs-directory)
  "デフォルトのAIツールを保存するファイルのパス")

(defun my/get-default-ai-tool ()
  "保存されているデフォルトのAIツールを取得する。デフォルトはagy。"
  (if (file-exists-p my/ai-default-tool-file)
      (with-temp-buffer
        (insert-file-contents my/ai-default-tool-file)
        (string-trim (buffer-string)))
    "agy"))

(defun my/set-default-ai-tool (tool)
  "デフォルトのAIツールをファイルに保存する。"
  (with-temp-file my/ai-default-tool-file
    (insert tool)))

(defun my/run-ai-tool-prompt ()
  "AIツールを選択して起動する。Enterを押した場合はデフォルトのツールを起動する。"
  (interactive)
  (let* ((default-tool (my/get-default-ai-tool))
         (choices '("agy" "claude" "bob"))
         (prompt (format "Select AI tool (default %s): " default-tool))
         (selected (completing-read prompt choices nil t nil nil default-tool)))
    (when (not (string= selected default-tool))
      (my/set-default-ai-tool selected))
    (cond
     ((string= selected "agy") (my/run-agy))
     ((string= selected "claude") (my/run-claude-code))
     ((string= selected "bob") (my/run-bob)))))

;; =====================================================================
;; 5. AIエージェントへ送るプロンプトの編集バッファ (compose)
;; =====================================================================
;; vtermのプロンプト欄は編集操作(カーソル移動・範囲削除・貼り付け)が効きにくく、
;; 長い/複数行のプロンプトを打ちづらい。そこで通常のEmacsバッファでプロンプトを
;; 編集し、C-c C-c で対象エージェントのvtermへ一括送信してバッファ・ウィンドウを
;; 閉じる「編集専用バッファ」を用意する(git commitメッセージ編集に近い発想)。
;; 送信は bracketed paste + Return で、既存の my/send-visual-selection-to-ai と揃える。

(defvar my/ai-compose-buffer-name "*ai-compose*"
  "AIエージェント向けプロンプト編集バッファの名前。")

(defvar-local my/ai-compose-target nil
  "このコンポーズバッファの送信先。`my/ai-compose--resolve-target' が返す指定子。
  (:tmux . SESSION) … 外部ターミナルの tmux セッションへ送る
  (:vterm . BUFFER) … Emacs内のエージェントvtermバッファへ送る")

(defvar-local my/ai-compose--preview-buffers nil
  "このコンポーズで開いた画像プレビューバッファのリスト。閉じる際にまとめて片付ける。")

(define-minor-mode my/ai-compose-mode
  "AIエージェントへ送るプロンプトを編集する専用バッファであることを示すマイナーモード。
送信(C-c C-c)・中止(C-c C-k / q)のキーバインドは keybind-manage.el で束縛する。"
  :lighter " AICompose"
  :keymap (make-sparse-keymap))

(defun my/ai-compose--resolve-target ()
  "コンポーズの送信先を解決して指定子を返す。
対象エージェントは 現在バッファ → 表示中 → デフォルトツール の順で決める。
そのエージェント/プロジェクトについて次の順で解決する:
  1) tmux セッションが既に在れば (:tmux . SESSION)(vtermは開かない)
  2) vterm バッファが既に在れば (:vterm . BUFFER)
  3) どちらも起動していなければ、tmux と vterm のどちらで起動するか尋ね
     (ポップアップは tmux を先頭に・既定も tmux)、選んだ方を起動して指定子を返す。"
  (let* ((agent (or (my/ai-agent-current) (my/ai-agent-displayed)
                    (my/ai-agent-get (my/get-default-ai-tool))
                    (user-error "対象のAIエージェントを特定できません")))
         (command    (plist-get agent :command))
         (bufname-fn (plist-get agent :buffer-name))
         (root       (my/ai-agent-project-root))
         (session    (my/ai-agent--tmux-session-name (funcall bufname-fn root))))
    (cond
     ;; 1) tmux セッションが既にある → tmux優先(vtermは開かない)
     ((my/ai-agent--tmux-session-exists-p session)
      (cons :tmux session))
     ;; 2) vterm が既に起動している → それを使う
     ((get-buffer (funcall bufname-fn root))
      (cons :vterm (get-buffer (funcall bufname-fn root))))
     ;; 3) どちらも未起動 → 起動方法を確認(tmuxを先頭・既定に)して起動する
     (t
      (let ((choice (completing-read
                     (format "%s の起動方法(未起動): " command)
                     '("tmux" "vterm") nil t nil nil "tmux")))
        (if (string= choice "tmux")
            (progn (my/ai-agent-run-in-tmux command bufname-fn)
                   (cons :tmux session))
          (funcall (plist-get agent :run))
          (cons :vterm (get-buffer (funcall bufname-fn root)))))))))

(defun my/ai-agent-compose ()
  "AIエージェントへ送るプロンプトを専用バッファで編集する。
vtermのプロンプト欄は打ちづらいため、通常バッファで入力し C-c C-c で送信する。
送信先はプロジェクトの claude 用 tmux セッションが在ればそれ(vtermは開かない)、
無ければ現在/表示中のエージェント、それも無ければデフォルトツール(必要なら起動)。"
  (interactive)
  (let ((target (my/ai-compose--resolve-target))
        (buf (get-buffer-create my/ai-compose-buffer-name)))
    (with-current-buffer buf
      (erase-buffer)
      ;; major-mode設定でローカル変数が消えるので、送信先の記録は最後に行う
      (text-mode)
      (my/ai-compose-mode 1)
      (setq my/ai-compose-target target))
    ;; 小さなvtermウィンドウ等から呼ぶと選択中ウィンドウの分割に失敗するため、
    ;; my/vterm-pop-to-buffer-oriented(選択ウィンドウを分割)は使わず、
    ;; フレーム最下部に十分な高さのウィンドウを確保して表示・選択する。
    (pop-to-buffer buf '((display-buffer-at-bottom)
                         (window-height . 0.3)))
    ;; すぐ入力できるようinsertステートにする
    (when (fboundp 'evil-insert-state) (evil-insert-state)))
  (message "C-c C-c で送信 / C-c C-k で中止"))

(defun my/ai-agent-compose--close ()
  "コンポーズバッファとそのウィンドウを閉じる(送信/中止の共通後処理)。"
  (let ((buf (current-buffer))
        (previews my/ai-compose--preview-buffers))
    ;; 画像プレビューのウィンドウとバッファを片付ける。
    ;; ※ プレビューを閉じても一時PNGファイル自体は消さない。送信直後にclaudeが
    ;;   そのパスを読むため、ファイルはOSの一時領域の掃除に任せる。
    (dolist (pbuf previews)
      (when (buffer-live-p pbuf)
        (dolist (win (get-buffer-window-list pbuf nil t))
          (when (window-live-p win) (ignore-errors (delete-window win))))
        (kill-buffer pbuf)))
    (when (> (count-windows) 1)
      (delete-window))
    (kill-buffer buf)))

(defvar my/ai-compose-send-delay 0.4
  "compose送信時、bracketed paste から Enter を送るまでの待ち時間(秒)。
claude は貼り付けた画像パスを画像添付として認識する処理に少し時間がかかり、
間を置かずに Enter を送ると Enter が添付処理に吸われて送信されないことがある。
そこでペースト後わずかに待ってから Enter を送る。0 にすると待たない。")

(defun my/ai-agent-compose-send ()
  "コンポーズバッファの内容を送信先へ送り、バッファとウィンドウを閉じる。
送信先(`my/ai-compose-target')が tmux セッションならそこへ bracketed paste + Enter で送る。
vtermバッファならそのvtermへ送る。"
  (interactive)
  (unless (bound-and-true-p my/ai-compose-mode)
    (user-error "コンポーズバッファではありません"))
  (let ((target my/ai-compose-target)
        (text (string-trim (buffer-substring-no-properties (point-min) (point-max)))))
    (when (string-empty-p text)
      (user-error "送信する内容がありません"))
    (pcase target
      (`(:tmux . ,session)
       (unless (my/ai-agent--tmux-session-exists-p session)
         (user-error "tmuxセッション \"%s\" がありません(閉じられた可能性)" session))
       ;; bracketed paste + Enter で、複数行を1入力として渡してから送信する
       ;; (画像パス添付の認識を待つため Enter 前に my/ai-compose-send-delay 秒待つ)
       (my/ai--tmux-send-text session text t my/ai-compose-send-delay))
      (`(:vterm . ,buffer)
       (unless (buffer-live-p buffer)
         (user-error "送信先のAIエージェントバッファがありません"))
       (with-current-buffer buffer
         ;; bracketed pasteで複数行も途中送信されず1入力として渡し、最後にReturnで送信する
         (vterm-send-string text t)
         ;; claudeが画像パスを添付として認識する猶予。間を置かないとReturnが吸われる
         (when (> my/ai-compose-send-delay 0)
           (sit-for my/ai-compose-send-delay))
         (vterm-send-return)))
      (_ (user-error "送信先が解決できません")))
    (my/ai-agent-compose--close)))

(defun my/ai-agent-compose-abort ()
  "コンポーズを中止し、バッファとウィンドウを閉じる(送信しない)。"
  (interactive)
  (my/ai-agent-compose--close))

;; --- クリップボード画像の添付(compose用) ---------------------------------
;; vterm/tmux 上の Claude Code には画像バイナリを直接貼り付けられないが、画像の
;; ファイルパスをプロンプトに渡せば Claude Code がそのパスの画像を読み込む。
;; そこでクリップボードの画像をPNGに保存し、そのパスを compose バッファへ挿入する。
;; 送信(C-c C-c)すると通常テキストと同様にパスが claude へ渡り、画像が読み込まれる。
;; pngpaste 等の外部導入に依存せず、macOS標準の osascript だけで完結させる。
(defconst my/clipboard-image-to-png-applescript
  (concat
   "on run argv\n"
   "  try\n"
   "    set pngData to (the clipboard as «class PNGf»)\n"
   "  on error\n"
   "    return \"NOIMAGE\"\n"
   "  end try\n"
   "  set f to open for access (POSIX file (item 1 of argv)) with write permission\n"
   "  set eof f to 0\n"
   "  write pngData to f\n"
   "  close access f\n"
   "  return \"OK\"\n"
   "end run")
  "クリップボード画像をPNGとして引数のパスへ書き出すAppleScript。画像が無ければ NOIMAGE を返す。")

(defun my/clipboard-image-to-file ()
  "macOSのクリップボードにある画像をPNGで一時ファイルへ書き出し、そのパスを返す。
クリップボードに画像が無ければ nil を返す。"
  (unless (eq system-type 'darwin)
    (user-error "クリップボード画像の取り込みはmacOSのみ対応です"))
  (let* ((file (make-temp-file "claude-clip-" nil ".png"))
         ;; osascript は画像の色空間変換などで stderr に警告
         ;; ("*** Error creating a JP2 color space ...") を出すことがある。
         ;; stdout と混ざると戻り値判定("OK")が崩れるため、stderr は分離して捨てる。
         (result (with-temp-buffer
                   (call-process "osascript" nil (list t nil) nil
                                 "-e" my/clipboard-image-to-png-applescript file)
                   (string-trim (buffer-string)))))
    (if (string= result "OK")
        file
      (ignore-errors (delete-file file))
      nil)))

(defun my/ai-compose--preview-image (file)
  "FILE の画像を compose ウィンドウの隣(右側)に表示する(フォーカスは移さない)。
表示したバッファを返す。"
  (let* ((buf (find-file-noselect file))
         (win (display-buffer
               buf '((display-buffer-in-direction)
                     (direction . right)
                     (window-width . 0.5)))))
    (when (window-live-p win)
      ;; ウィンドウが割り当たった状態でウィンドウ幅に合わせて縮小表示する
      (with-selected-window win
        (when (derived-mode-p 'image-mode)
          (setq-local image-auto-resize 'fit-window)
          (ignore-errors (image-toggle-display-image)))))
    buf))

(defun my/ai-compose-insert-image ()
  "クリップボードの画像をPNGに保存し、そのパスを compose バッファへ挿入する。
あわせて、その画像を compose ウィンドウの隣に別ウィンドウでプレビュー表示する。
送信すると Claude Code 等がそのパスの画像を読み込む。"
  (interactive)
  (unless (bound-and-true-p my/ai-compose-mode)
    (user-error "コンポーズバッファではありません"))
  (let ((file (my/clipboard-image-to-file)))
    (unless file
      (user-error "クリップボードに画像がありません"))
    ;; 直前が行頭/空白でなければ、区切りの空白を1つ入れてから挿入する
    (unless (or (bolp) (memq (char-before) '(?\s ?\t ?\n)))
      (insert " "))
    (insert file " ")
    ;; 隣のウィンドウにプレビューを出し、閉じるとき片付けられるよう記録しておく
    (let ((pbuf (my/ai-compose--preview-image file)))
      (when (buffer-live-p pbuf)
        (push pbuf my/ai-compose--preview-buffers)))
    (message "画像を添付: %s" file)))

(defun my/send-visual-selection-to-compose ()
  "Visualステートで選択中のテキストを、ファイルパスと行:列範囲付きで
ai-composeバッファへ挿入する(vtermのプロンプトへ直接送るのではなく編集バッファへ集める)。
既にai-composeバッファが開いていればそのカーソル位置に挿入し、
無ければ新規にai-composeを開いて挿入する。"
  (interactive)
  (let ((payload (my/ai--visual-selection-payload))
        (existing (get-buffer my/ai-compose-buffer-name)))
    (evil-normal-state)
    (if existing
        ;; 既に開いている: そのウィンドウを選び(表示されていなければ表示し)、
        ;; そのバッファのカーソル位置(point)に挿入する。
        (progn
          (let ((win (get-buffer-window existing t)))
            (if win
                (progn (select-frame-set-input-focus (window-frame win))
                       (select-window win))
              (pop-to-buffer existing)))
          (insert payload))
      ;; 無ければ新規にai-composeを開き(空バッファの先頭)、そこへ挿入する。
      (my/ai-agent-compose)
      (insert payload))))

;; =====================================================================
;; 6. gptel 設定（エディタ一体型インライン書き換え & チャット用）
;; =====================================================================
(use-package gptel
  :straight t
  :commands (gptel gptel-menu)
  :init
  ;; 環境変数からAPIキーを取得
  (setq gptel-api-key (lambda () (getenv "ANTHROPIC_API_KEY")))
  :config
  ;; Anthropic Claudeをデフォルトに設定
  (setq gptel-backend (gptel-make-anthropic "Claude"
                        :key gptel-api-key
                        :stream t))
  ;; 好みに応じて sonnet などを指定
  (setq gptel-model 'claude-3-5-sonnet-latest)

  ;; Google Gemini も併用登録する。
  ;; gptel-make-gemini はバックエンドを登録するだけで、デフォルト(Claude)は上書きしない。
  ;; gptel-menu の Model からいつでも Gemini(flash/pro)へ切り替えられる。
  ;; APIキーは Claude と分けて GEMINI_API_KEY から取得する(Google AI Studio で発行)。
  (gptel-make-gemini "Gemini"
    :key (lambda () (getenv "GEMINI_API_KEY"))
    :stream t
    ;; 高速・低コストの flash と高性能の pro の両方を選べるようにしておく
    :models '(gemini-2.5-flash gemini-2.5-pro))

  ;; 独自のOpenAI互換API(SSE対応)を併用登録する。
  ;; FQDN・パス・APIキーはすべて環境変数から取得し、git には値を残さない。
  ;;   MY_LLM_HOST     : FQDNのみ(スキーム https:// は付けない)
  ;;   MY_LLM_ENDPOINT : チャットのパス
  ;;   MY_LLM_API_KEY  : Bearerトークン
  ;;   MY_LLM_MODELS_ENDPOINT : モデル一覧APIのパス
  ;; モデル名は固定せず、モデル一覧API(下記 refresh コマンド)から動的に取得する。
  (defvar my/gptel-myllm-backend nil
    "独自OpenAI互換APIのgptelバックエンド。モデル一覧を後から差し替えるため保持する。")

  (defun my/gptel-myllm-refresh-models ()
    "独自APIのモデル一覧を取得し、gptelバックエンド \"MyLLM\" の選択肢へ反映する。
一覧エンドポイントは環境変数 MY_LLM_MODELS_ENDPOINT から取得する。
レスポンスは OpenAI 互換の2形式に対応する。
  1. 裸のJSON配列        : [{\"id\": …}, …]
  2. dataラッパー付き     : {\"object\": \"list\", \"data\": [{\"id\": …}, …]}
各要素の id をモデル名(シンボル)として扱う。"
    (interactive)
    (let* ((host (getenv "MY_LLM_HOST"))
           (key  (getenv "MY_LLM_API_KEY"))
           (path (getenv "MY_LLM_MODELS_ENDPOINT"))
           (url  (format "https://%s%s" host path))
           (url-request-method "GET")
           (url-request-extra-headers
            `(("Authorization" . ,(concat "Bearer " key)))))
      (unless (and host key path my/gptel-myllm-backend)
        (user-error "MY_LLM_HOST / MY_LLM_API_KEY / MY_LLM_MODELS_ENDPOINT が未設定か、バックエンド未登録です"))
      (with-current-buffer (url-retrieve-synchronously url t t 30)
        (goto-char (point-min))
        (re-search-forward "\r?\n\r?\n") ; HTTPヘッダとボディの境界まで進める
        (let* ((json (json-parse-buffer :array-type 'list :object-type 'alist))
               ;; OpenAI標準は {"object":"list","data":[…]} 形式。トップレベルが
               ;; その形なら data を取り出し、裸の配列ならそのまま使う。
               (items (or (alist-get 'data json) json))
               ;; id が無い/文字列でない要素は握りつぶさず除外する
               ;; (intern に nil が渡ると stringp エラーで一覧が丸ごと落ちるため)。
               (models (delq nil
                             (mapcar (lambda (m)
                                       (let ((id (and (consp m) (alist-get 'id m))))
                                         (and (stringp id) (intern id))))
                                     items))))
          (kill-buffer)
          ;; models スロットへ書き戻す。setf の gv エキスパンダは gptel(struct定義)
          ;; がロード済みの時にしか展開できず、遅延ロード(:commands)+部分再評価だと
          ;; \(setf gptel-backend-models\) が void になる。ロード状態に依存しないよう
          ;; record のスロット位置を実行時に求めて aset で直接書き込む。
          (require 'cl-lib)
          (aset my/gptel-myllm-backend
                (cl-struct-slot-offset 'gptel-backend 'models)
                models)
          (message "MyLLM: %d 個のモデルを取得しました" (length models))
          models))))

  ;; MY_LLM_HOST が無ければ登録自体をスキップ(未設定マシンでの読込エラー回避)。
  (when (getenv "MY_LLM_HOST")
    (setq my/gptel-myllm-backend
          (gptel-make-openai "MyLLM"                       ; gptel-menu の表示名
            :host (getenv "MY_LLM_HOST")
            :endpoint (getenv "MY_LLM_ENDPOINT")
            :key (lambda () (getenv "MY_LLM_API_KEY"))     ; Authorization: Bearer を自動付与
            :stream t                                      ; SSE対応
            :models nil))                                  ; 一覧は下記で動的取得
    ;; gptel初回ロード時に1回だけモデル一覧を取得。失敗してもgptelの読込は妨げない。
    (ignore-errors (my/gptel-myllm-refresh-models)))

  ;; gptelのバッファをポップアップではなく通常のバッファとして扱いやすくする設定
  (setq gptel-default-mode 'markdown-mode))

;; =====================================================================
;; 7. whisper 設定（音声入力・ローカルでの文字起こし）
;; =====================================================================
;; whisper.el はマイク音声を ffmpeg で録音し、whisper.cpp でローカル文字起こしして
;; 現在のポイントにテキストを挿入する。C-S-w(Ctrl+Shift+w)で録音開始/終了をトグルする
;; (whisper-run 自体が「録音してなければ開始／録音中なら停止して文字起こし」のトグル)。
;; 初回起動時は whisper-install-directory 以下に whisper.cpp を git clone して
;; CMake でビルドし、指定モデル(下記)をダウンロードするため、少し時間がかかる。
;;   前提: ffmpeg / cmake / C++コンパイラ / git (いずれも導入済み前提)。
;;   whisper.el 自体は MELPA に無いため straight の git レシピで取得する。
;;   キーバインド(C-S-w)は思想どおり keybind-manage.el 側に置く。
(use-package whisper
  :straight (whisper :type git :host github :repo "natrys/whisper.el" :branch "master")
  :commands (whisper-run)
  :config
  (setq whisper-install-directory (expand-file-name ".cache/" user-emacs-directory) ; 本体とモデルの保存先(.cache/whisper.cpp/)
        whisper-language "ja"           ; 日本語に固定
        whisper-model "large-v3-turbo"  ; Turboモデル(約1.5GB)。まず動作確認するなら "base" が軽い
        whisper-translate nil           ; 英語への翻訳はオフ
        whisper-return-cursor 'start)   ; 入力後、カーソルを挿入テキストの先頭に戻す

  ;; --- macOS: 録音デバイス(avfoundation)の指定 ---
  (setq whisper--ffmpeg-input-device ":default")

  ;; --- macOS: マイク使用許可 ---
  ;; 上記デバイスを設定した上で初めて録音を試みると、macOS がマイク許可を求める。
  ;; Emacs はマイクへ初アクセスするまで「システム設定 → プライバシーとセキュリティ
  ;;  → マイク」に現れないため、リストに出ないのは正常。録音実行時に許可すること。
  )
