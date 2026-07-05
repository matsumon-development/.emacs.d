;;common-lisp
(require 'cl-lib)

;;----------------------------------------------------------------------------------------
;;                 ネイティブコンパイル
;;----------------------------------------------------------------------------------------
;;初回ネイティブコンパイル時にでる警告をポップアップさせない。Async-native-compile-logには残る
(setq native-comp-async-report-warnings-errors 'silent)

;;----------------------------------------------------------------------------------------
;;                 フォント
;;----------------------------------------------------------------------------------------
;;https://github.com/yuru7/HackGen/releases
(if (display-graphic-p)
    (progn
      (set-face-attribute
       'default nil
       :family "HackGenNerd"
       :height
       (cond
        ((eq system-type 'darwin) 140)
        ((eq system-type 'windows-nt) 110)
        ((eq system-type 'gnu/linux) 130)))
      ;;日本語フォント
      (set-fontset-font
       (frame-parameter nil 'font) 'japanese-jisx0208
       (font-spec
        :family "HackGenNerd"
        :height
        (cond
         ((eq system-type 'darwin) 140)
         ((eq system-type 'windows-nt) 110)
         ((eq system-type 'gnu/linux) 130))))))


;;----------------------------------------------------------------------------------------
;;                 エディタの見た目 基本
;;----------------------------------------------------------------------------------------

(global-display-line-numbers-mode t) ; 行番号を有効にする
(setq ring-bell-function 'ignore)    ; エラー音を鳴らなくする
(setq inhibit-splash-screen t)       ; splash screenを無効にする
(electric-pair-mode 1)               ; 自動閉じ括弧
(tool-bar-mode -1)                   ; ツールバーを非表示
(menu-bar-mode -1)                   ; メニューバーを非表示
(when (fboundp 'scroll-bar-mode)
  (scroll-bar-mode -1))                ; スクロールバーを非表示
(setq initial-scratch-message "")    ; scratchの初期メッセージ消去
(fset 'yes-or-no-p 'y-or-n-p)        ; "yes or no" の選択を "y or n" にする
(global-hl-line-mode 1)              ; カーソル行をハイライト

;;空白を可視化する
(use-package whitespace
  :custom-face
  (whitespace-tab ((nil (:foreground "LightSkyBlue"))))
  (whitespace-space ((t (:foreground "#505050"))))
  :custom
  (whitespace-style '(
                      face           ; faceで可視化
                      trailing       ; 行末
                      tabs           ; タブ
                      spaces         ; スペース
                      empty          ; 先頭/末尾の空行
                      space-mark     ; 表示のマッピング
                      tab-mark
                      ))
  (whitespace-display-mappings          ;文字変更
   '(
     ;;(newline-mark ?\n [?$ ?\n])    ; 改行記号
     (space-mark ?\u3000 [?□])       ; 全角スペース
     (space-mark ?\u0020 [?\xB7])     ; 半角スペース
     (tab-mark ?\t [?\xBB ?\t])       ;タブ文字
     ))
  (whitespace-space-regexp "\\([\x0020\x3000]+\\)" ) ;半角スペースと全角スペースを可視化する
  :init (global-whitespace-mode 1)
  )

;;emcsを格子状にしようと思ったらイマイチだった
;;(custom-set-faces
;; '(default ((t :box(:line-width 1 :color "#282928" :style nil)))))


;;タイトルバーに時計を表示
(when (window-system)
  (setq display-time-string-forms
        '(
          (format "%s %s %s" dayname monthname day)
          (format "  %s:%s" 24-hours minutes))
        frame-title-format '( "\x231a " display-time-string))
  (display-time)
  )


;;----------------------------------------------------------------------------------------
;;                 テキストエディット
;;----------------------------------------------------------------------------------------

(add-hook 'after-save-hook 'delete-trailing-whitespace)                     ; 保存直後に行末の空白を削除
(add-hook 'after-save-hook '(lambda() (untabify (point-min) (point-max))))  ; 保存直後にタブをスペースに変換
(setq require-final-newline t)                                              ; ファイルの最終行に空行が挿入される

;;----------------------------------------------------------------------------------------
;;                 Dired
;;----------------------------------------------------------------------------------------
(defun dired-open-in-accordance-with-situation ()
  (interactive)
  (let ((file (dired-get-filename)))
    (if (file-directory-p file)
        (dired-find-alternate-file)
      (dired-find-file))))


(put 'dired-find-alternate-file 'disabled nil) ; dired-find-alternate-file の有効化

;; GNU ls (coreutils) があれば使う。macOS標準のBSD lsには無い --group-directories-first 等が使える
(when (executable-find "gls")
  (setq insert-directory-program "gls"))
(setq dired-listing-switches
      (if (executable-find "gls")
          "-alrth --group-directories-first" ; ディレクトリを先頭にまとめ、サイズを人間が読める単位で表示
        "-alrt"))

;; diredを2つのウィンドウで開いている時に、デフォルトの移動orコピー先をもう一方のdiredで開いているディレクトリにする
(setq dired-dwim-target t)

;; パーミッション等の詳細情報を隠し、Finderのようにすっきりした表示にする。( キーでいつでも切替可能
(add-hook 'dired-mode-hook #'dired-hide-details-mode)

;; 削除はFinderと同じくゴミ箱に移動する(誤delete対策)。macOS 14+ 標準の`trash`コマンドを利用
(setq delete-by-moving-files-to-trash t)
(when (and (eq system-type 'darwin) (executable-find "trash"))
  (defun system-move-file-to-trash (file)
    "macOS標準の`trash`コマンドでFILEをゴミ箱に移動する。"
    (call-process "trash" nil nil nil file)))

;; Finderのダブルクリックと同様、カーソル位置(またはマークした)ファイルをOS標準の関連付けアプリで開く
(when (eq system-type 'darwin)
  (defun dired-open-with-default-app ()
    "Open the file(s) at point in Dired with the macOS default application."
    (interactive)
    (dolist (file (dired-get-marked-files))
      (call-process "open" nil 0 nil file)))

  ;; カーソル位置のファイルをFinderで表示(選択状態)する。ブラウザへのドラッグ&ドロップなど
  ;; Emacsが対応していない操作をFinder側に橋渡しするために使う
  (defun dired-reveal-in-finder ()
    "Reveal the file at point in Dired within macOS Finder."
    (interactive)
    (call-process "open" nil 0 nil "-R" (dired-get-filename))))


;;----------------------------------------------------------------------------------------
;;                 タブ
;;----------------------------------------------------------------------------------------
(if (>= emacs-major-version 27)
    (tab-bar-mode t))


;;----------------------------------------------------------------------------------------
;;                 おまじない
;;----------------------------------------------------------------------------------------
;;; *.~ とかのバックアップファイルを作らない
(setq make-backup-files nil)
(setq backup-inhibited t)
;;; .#* とかのバックアップファイルを作らない
(setq auto-save-default nil)

;; macOSのGUIアプリ(Emacs.app、emacs --daemon等)はターミナルのシェルを経由しないため、
;; .zshrc等で設定したPATH(fnmのnpmシム、~/.go/bin等)を引き継がない。
;; eglotなどが言語サーバーの実行ファイルを見つけられるよう、shellのPATHを同期する。
(use-package exec-path-from-shell
  :straight t
  :if (memq window-system '(mac ns))
  :config
  (exec-path-from-shell-initialize))
