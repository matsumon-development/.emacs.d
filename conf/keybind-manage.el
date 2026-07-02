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
;; Claude Code
;;-----------------------------------------------------------
;; プロジェクトルートでClaude Codeを起動する（定義はconf/package-manage.el）
(bind-key "SPC v c" 'my/run-claude-code evil-normal-state-map)

;; Claude Codeを別フレームに切り出す（定義はconf/package-manage.el）
(bind-key "SPC c f" 'my/claude-code-pop-to-frame evil-normal-state-map)

;; Normalステートで q を押したらウィンドウを閉じる(バッファ・プロセスは残す)。
;; my/claude-code-mode-map経由なので、プレーンなvterm端末には影響しない。
;; quit-windowはdisplay-buffer経由で作られたウィンドウのquit-restoreパラメータに
;; 依存するため、split-windowで直接作ったこのウィンドウには効かない。
;; そのため単純にdelete-windowでウィンドウ自体を閉じる。
(defun my/claude-code-quit-window ()
  "Claude Codeのウィンドウを閉じる(バッファ・プロセスは残す)。"
  (interactive)
  (when (> (count-windows) 1)
    (delete-window)))

(with-eval-after-load 'evil
  (evil-define-key 'normal my/claude-code-mode-map
    "q" #'my/claude-code-quit-window))

;; Insertステートで C-c C-g を押したら、Claude Codeの入力欄をクリアする。
;; プレーンなEscはevilがinsert->normalの切り替えに横取りしてしまい、
;; vtermプロセス(claude)側にESCが届かないため、vterm-send-escapeで
;; evilの状態に関係なく確実にESCを送る。
;; my/claude-code-mode-map経由なので、プレーンなvterm端末には影響しない。
(with-eval-after-load 'evil
  (evil-define-key 'insert my/claude-code-mode-map
    (kbd "C-c C-g") #'vterm-send-escape))

;; Visualステートで選択中のテキストを、ファイルパスと行:列範囲付きで
;; Claude Codeのプロンプトに貼り付ける。
;; 例:
;;   /path/to/file.el L10:R30 ~L20:R2
;;   ```
;;   (選択したテキスト)
;;   ```
;; vterm-send-stringのpaste-p(bracketed paste)を使うので、
;; 複数行になっても改行のたびに送信されず、claude側で複数行入力として扱われる。
(defun my/send-visual-selection-to-claude ()
  "Visualステートで選択中のテキストを、ファイルパスと行:列範囲付きで
Claude Codeのプロンプトに貼り付ける。
対応するClaude Codeバッファが無ければ起動してから送る。"
  (interactive)
  (unless (evil-visual-state-p)
    (user-error "Visualステートで選択してから実行してください"))
  (let* ((beg (region-beginning))
         (end (region-end))
         (text (buffer-substring-no-properties beg end))
         (file (or (buffer-file-name) (buffer-name)))
         (start-line (line-number-at-pos beg))
         (start-col (1+ (save-excursion (goto-char beg) (current-column))))
         (end-line (line-number-at-pos end))
         (end-col (1+ (save-excursion (goto-char end) (current-column))))
         (header (format "%s L%d:R%d ~L%d:R%d"
                          file start-line start-col end-line end-col))
         (payload (format "%s\n```\n%s\n```\n" header text))
         (buffer-name (my/claude-code-buffer-name))
         (already-running (get-buffer buffer-name)))
    (evil-normal-state)
    (my/run-claude-code)
    (if already-running
        (with-current-buffer buffer-name
          (vterm-send-string payload t))
      ;; 起動直後はclaudeの準備ができるまで少し待ってから送る
      (run-at-time 1.5 nil
                   (lambda (buf txt)
                     (when (buffer-live-p buf)
                       (with-current-buffer buf
                         (vterm-send-string txt t))))
                   (get-buffer buffer-name) payload))))

(bind-key "SPC c s" 'my/send-visual-selection-to-claude evil-visual-state-map)
;; Visualステートでは単に c で送れるようにする(Evil標準のchangeコマンドを上書き)
(bind-key "c" 'my/send-visual-selection-to-claude evil-visual-state-map)

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


