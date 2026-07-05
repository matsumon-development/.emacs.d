;;ファイル操作系
(bind-key "SPC f f" 'find-file evil-normal-state-map)
(bind-key "SPC f s" 'save-buffer evil-normal-state-map)
(bind-key "SPC f r" 'counsel-recentf evil-normal-state-map)
(bind-key "SPC f c" 'copy-file evil-normal-state-map)


;;終了
(bind-key "SPC q R" 'restart-emacs evil-normal-state-map)
(bind-key "SPC q q" 'kill-emacs evil-normal-state-map)


;;バッファー系
(bind-key "SPC b d" 'kill-current-buffer evil-normal-state-map)
(bind-key "SPC b x" 'kill-buffer-and-window evil-normal-state-map)
(bind-key "SPC b b" 'switch-to-buffer evil-normal-state-map)
(bind-key "SPC b n" 'next-buffer evil-normal-state-map)
(bind-key "SPC b p" 'switch-to-prev-buffer evil-normal-state-map)


;;ディレイド
;; dired-modeはevil-set-initial-stateでemacs-stateに固定している(package-manage.el)ため、
;; evilに邪魔されず素のdired-mode-mapへのbind-keyがそのまま効く。
(with-eval-after-load 'dired
  (bind-key "C-b" 'switch-to-buffer dired-mode-map)
  (bind-key "RET" 'dired-find-alternate-file dired-mode-map)
  (bind-key "a"   'dired-find-file dired-mode-map)
  (bind-key "q"   'kill-current-buffer dired-mode-map)
  (bind-key "i"   'dired-subtree-insert dired-mode-map)
  (bind-key "I"   'dired-subtree-remove dired-mode-map)
  ;; Finder/rangerのように、h=親ディレクトリへ、l=開く、で1ペインのまま素早く移動する
  ;; (lはネイティブでは dired-do-redisplay だが、Finder的な移動を優先する)
  (bind-key "h" 'dired-up-directory dired-mode-map)
  (bind-key "l" 'dired-find-alternate-file dired-mode-map)
  ;; 現在diredで開いているフォルダをカレントディレクトリとして、vtermでターミナルを開く
  ;; (dired-do-touchを上書きするが、Finder代替の運用ではタッチよりターミナル起動を優先する)
  (bind-key "T" 'my/run-vterm-current-dir dired-mode-map)
  (when (eq system-type 'darwin)
    (bind-key "O" 'dired-open-with-default-app dired-mode-map)
    (bind-key "F" 'dired-reveal-in-finder dired-mode-map))
  (when (and window-system (eq system-type 'windows-nt))
    (bind-key "F"
              '(lambda ()
                 (interactive)
                 (shell-command-to-string (format "start RUNDLL32.EXE shell32.dll,OpenAs_RunDLL %s" (file-name-nondirectory (dired-get-file-for-visit)))))
              dired-mode-map)))


;;Magit
(bind-key "SPC g s"  'magit-status evil-normal-state-map)
(with-eval-after-load 'magit
  (bind-key "q"  'kill-current-buffer magit-status-mode-map)
  (bind-key "q"  'kill-current-buffer magit-log-mode-map)
  (bind-key "q"  'kill-current-buffer magit-diff-mode-map)
  (bind-key "q"  'kill-current-buffer magit-process-mode-map))

;;eaf-git
(bind-key "SPC e g s"  'eaf-open-git evil-normal-state-map)


;;window系
(bind-key "SPC w d" 'delete-window evil-normal-state-map)
(bind-key "SPC w w" 'other-window evil-normal-state-map)
(bind-key "SPC w -" 'split-window-below evil-normal-state-map)
(bind-key "SPC w /" 'split-window-right evil-normal-state-map)

;;移動系
(bind-key "C-h" 'delete-backward-char)

;;シェル
(bind-key "SPC !" 'shell-command evil-normal-state-map)

;;関数呼び出し
(bind-key "SPC SPC" 'execute-extended-command evil-normal-state-map)


;;tab-bar-mode
(cond ((>= emacs-major-version 27)
       (bind-key "C-; C-c" 'tab-new global-map)
       (bind-key "C-; c" 'tab-new global-map)
       (bind-key "C-; n" 'tab-next global-map)
       (bind-key "C-; C-n" 'tab-next global-map)
       (bind-key "C-<tab>" 'tab-next global-map)
       (bind-key "C-; k" 'tab-close global-map)
       (bind-key "C-; C-k" 'tab-close global-map)
       (bind-key "C-; C-f" 'find-file-other-tab global-map)
       (bind-key "C-; f" 'find-file-other-tab global-map)))


;; ウィンドウのテーマのサイクル
(bind-key "SPC t c" 'theme-cycle evil-normal-state-map)

;; ウィンドウの透過の切り替え
(which-key-add-key-based-replacements "SPC t t" "transparency-config")
(bind-key "SPC t t t" 'cycle-transparency evil-normal-state-map)

(bind-key "SPC t t ESC"
          '(lambda(lev)
             (interactive "sTransparent Level:" )
             (cl-typecase (string-to-number lev)
               ((number 1 100)
                (set-frame-parameter nil 'alpha (string-to-number lev)))
               (t (message "Input Error: 1~100の範囲で指定してください"))
               ))
          evil-normal-state-map)
(which-key-add-key-based-replacements "SPC t t ESC" "set-transparency-level")


;;rainbow-modeの切り替え
(bind-key "SPC t c" 'rainbow-mode evil-normal-state-map)

;;行の折り返しON/OFF
(bind-key "SPC t x t" 'toggle-truncate-lines evil-normal-state-map)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;自作
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(bind-key "SPC f R"
          '(lambda(new-name)
             (interactive "sNew name: ")
             (let ((name (buffer-name)) (filename (buffer-file-name)))
               (if (not filename)
                   (message "Buffer '%s' is not visiting a file!" name)
                 (if (get-buffer new-name)
                     (message "A buffer named '%s' already exists!" new-name)
                   (rename-file filename new-name 1)
                   (rename-buffer new-name)
                   (set-visited-file-name new-name)
                   (set-buffer-modified-p nil)
                   (message "renamed")))))
          evil-normal-state-map)
(which-key-add-key-based-replacements "SPC f R" "rename file")

;;-----------------------------------------------------------
;; ファイルのショートカット
;;-----------------------------------------------------------
(bind-key "SPC f e d"
          '(lambda()
             (interactive)
             (switch-to-buffer
              (find-file-noselect "~/.emacs.d/conf/basic.el")))
          evil-normal-state-map)
(which-key-add-key-based-replacements "SPC f e d" "open-basic-config")

(bind-key "SPC f e p"
      '(lambda()
         (interactive)
         (switch-to-buffer
          (find-file-noselect "~/.emacs.d/conf/package-manage.el")))
      evil-normal-state-map)
(which-key-add-key-based-replacements "SPC f e p" "open-pakage-manage-config")


(bind-key "SPC f e k"
          '(lambda()
             (interactive)
             (switch-to-buffer
              (find-file-noselect "~/.emacs.d/conf/keybind-manage.el")))
          evil-normal-state-map)
(which-key-add-key-based-replacements "SPC f e k" "open-keybind-manage-config")

(bind-key "SPC f e l"
          '(lambda()
             (interactive)
             (switch-to-buffer
              (find-file-noselect "~/.emacs.d/conf/language.el")))
          evil-normal-state-map)
(which-key-add-key-based-replacements "SPC f e l" "open-language-config")

(bind-key "SPC f e a"
          '(lambda()
             (interactive)
             (switch-to-buffer
              (find-file-noselect "~/.emacs.d/conf/ai-agent.el")))
          evil-normal-state-map)
(which-key-add-key-based-replacements "SPC f e a" "open-aiagent-config")

;;-----------------------------------------------------------
;; その他
;;-----------------------------------------------------------



;;今開いているバッファのファイルをクリップボードに貼り付ける
;;https://qiita.com/ShingoFukuyama/items/8f1d3342180d42ad9f78
(bind-key "C-c C-c p"
          '(lambda()
             (interactive)
             (let ((file-path buffer-file-name)
                   (dir-path default-directory))
               (cond (file-path
                      (kill-new (expand-file-name file-path))
                      (message "This file path is on the clipboard!"))
                     (dir-path
                      (kill-new (expand-file-name dir-path))
                      (message "This directory path is on the clipboard!"))
                     (t
                      (error-message-string "Fail to get path name."))))))

;;-----------------------------------------------------------
;; vterm
;;-----------------------------------------------------------
;; 現在のファイルバッファのディレクトリで、通常のターミナルを開く（定義はconf/package-manage.el）
(bind-key "SPC v s" 'my/run-vterm-current-dir evil-normal-state-map)

;;-----------------------------------------------------------
;; AI Agents (claude / agy / bob)
;; コマンド本体は conf/ai-agent.el 側。ここではキーバインドのみ。
;;-----------------------------------------------------------
(which-key-add-key-based-replacements "SPC a" "AI Agents")
(bind-key "SPC a g" 'my/run-agy evil-normal-state-map)
(bind-key "SPC a c" 'my/run-claude-code evil-normal-state-map)
(bind-key "SPC a b" 'my/run-bob evil-normal-state-map)
;; SPC a f: 今ウィンドウに表示中のAIエージェントを別フレームへ切り出す /
;; SPC a w: 別フレームから元のフレームの分割へ戻す。
;; どのエージェントかは表示中のバッファから自動判定するので、エージェントごとに
;; キーを分けず、1つのキーで扱える(コマンド本体は conf/ai-agent.el)。
(bind-key "SPC a f" 'my/ai-agent-pop-displayed-to-frame evil-normal-state-map)
(bind-key "SPC a w" 'my/ai-agent-dock-displayed-to-window evil-normal-state-map)
(bind-key "SPC a a" 'my/run-ai-tool-prompt evil-normal-state-map)
;; SPC a s: 現在のプロジェクトのClaude Codeセッション全文を専用バッファで表示。
;; claudeはvtermに過去分が残らないので、~/.claude/projectsのトランスクリプトから復元する。
(bind-key "SPC a s" 'my/claude-code-show-session evil-normal-state-map)
(which-key-add-key-based-replacements "SPC a f" "pop-to-frame")
(which-key-add-key-based-replacements "SPC a w" "back-to-window")
(which-key-add-key-based-replacements "SPC a s" "claude-session")

;; 各AIエージェントのバッファ内キーバインド。
;;   q        … ウィンドウを閉じる(バッファ・プロセスは残す)
;;   C-c C-g … 入力欄をクリア(ESC送信)
;;   C-c C-w … 別フレームから元のフレームの分割ウィンドウへ戻す
;;             (別フレーム側のバッファでそのまま押せるよう normal/insert 両方に束縛)
;; ai-agent.el の my/ai-agents レジストリに登録された全モードマップへ一括束縛するので、
;; エージェントを増やしても、ここを触らずに自動で対応できる。
(with-eval-after-load 'evil
  (dolist (agent my/ai-agents)
    (let ((mode-map (symbol-value (plist-get (cdr agent) :mode-map))))
      (evil-define-key 'normal mode-map "q" #'my/ai-tool-quit-window)
      (evil-define-key 'insert mode-map (kbd "C-c C-g") #'vterm-send-escape)
      (evil-define-key 'normal mode-map (kbd "C-c C-w") #'my/ai-agent-back-to-window)
      (evil-define-key 'insert mode-map (kbd "C-c C-w") #'my/ai-agent-back-to-window))))

;; Visualステートの選択テキストをAIへ送る(本体は my/send-visual-selection-to-ai)。
;;   c / SPC a s s … デフォルトのAIツール(SPC a a で切替)へ
;;   SPC a s c/g/b … claude / agy / bob を明示指定
(which-key-add-key-based-replacements "SPC a s" "send-selection-to-ai")
(bind-key "SPC a s s" 'my/send-visual-selection-to-ai evil-visual-state-map)
(bind-key "SPC a s c"
          (lambda () (interactive) (my/send-visual-selection-to-ai "claude"))
          evil-visual-state-map)
(bind-key "SPC a s g"
          (lambda () (interactive) (my/send-visual-selection-to-ai "agy"))
          evil-visual-state-map)
(bind-key "SPC a s b"
          (lambda () (interactive) (my/send-visual-selection-to-ai "bob"))
          evil-visual-state-map)
;; Visualステートでは単に c でデフォルトのAIツールへ送る(Evil標準のchangeを上書き)。
(bind-key "c" 'my/send-visual-selection-to-ai evil-visual-state-map)

;;-----------------------------------------------------------
;; vterm
;;-----------------------------------------------------------
;; Shift+Enterで送信せずに改行だけ入れる（claude codeなどの複数行入力用）。
;; 改行を送るたびにウィンドウを少しずつ広げ（my/vterm-window-max-ratioを上限）、
;; 通常のEnterで送信したら初期サイズに戻す。
;; vterm-mode-mapはvtermパッケージが実際にロードされるまで存在しないため、
;; with-eval-after-loadで遅延させる。
(with-eval-after-load 'vterm
  (defvar-local my/vterm-input-line-count 0
    "Shift+Enterで増やした、未送信の入力行数（改行数）。")

  (defun my/vterm--target-height ()
    "現在の入力行数を反映した、vtermウィンドウのあるべき高さ(行数)を返す。"
    (let* ((frame-h (frame-height))
           (base (max 1 (round (* frame-h my/vterm-window-ratio))))
           (max-h (round (* frame-h my/vterm-window-max-ratio))))
      (min max-h (+ base my/vterm-input-line-count))))

  (defun my/vterm-resize-to-fit-input ()
    "入力行数に応じてvtermウィンドウの高さを調整する。
上下分割(below/above)のときだけ有効。左右分割は既に全高なので対象外。"
    (let ((win (get-buffer-window)))
      (when (and (window-live-p win) (not (window-full-height-p win)))
        (ignore-errors
          (window-resize win (- (my/vterm--target-height) (window-total-height win)))))))

  (defun my/vterm-send-newline ()
    "vtermのプロンプトで、行を確定せずに改行だけを送る(\\+Enter相当)。
入力の改行が増えるたびにウィンドウを広げる。"
    (interactive)
    (vterm-send-string "\\")
    (vterm-send-return)
    (setq my/vterm-input-line-count (1+ my/vterm-input-line-count))
    (my/vterm-resize-to-fit-input))

  (defun my/vterm-submit-and-shrink ()
    "通常のEnterで送信し、入力行数カウントをリセットしてウィンドウを初期サイズに戻す。"
    (interactive)
    (setq my/vterm-input-line-count 0)
    (call-interactively #'vterm-send-return)
    (my/vterm-resize-to-fit-input))

  (define-key vterm-mode-map (kbd "S-<return>") #'my/vterm-send-newline)
  (define-key vterm-mode-map [return] #'my/vterm-submit-and-shrink)
  (define-key vterm-mode-map (kbd "RET") #'my/vterm-submit-and-shrink))
