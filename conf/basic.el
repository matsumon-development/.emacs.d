;;; basic.el --- Emacs本体の基礎設定(フォント・見た目・Dired・バックアップ等) -*- lexical-binding: t; -*-

;;; Commentary:

;; パッケージ依存の薄い、Emacs本体まわりの基礎設定。
;; ネイティブコンパイル・フォント(Cica)・見た目の基本・テキスト編集・Dired・
;; タブ・バックアップ無効化・PATH同期(exec-path-from-shell)をまとめる。

;;; Code:
(require 'cl-lib)

;;----------------------------------------------------------------------------------------
;;                 ネイティブコンパイル
;;----------------------------------------------------------------------------------------
;;初回ネイティブコンパイル時にでる警告をポップアップさせない。Async-native-compile-logには残る
(setq native-comp-async-report-warnings-errors 'silent)

;;----------------------------------------------------------------------------------------
;;                 フォント
;;----------------------------------------------------------------------------------------
;;https://github.com/miiton/Cica/releases
;; darwinは160(=16px)にしている。Cicaは同一サイズなら全角=半角×2になる設計だが、
;; ピクセルサイズが奇数(例: :height 150 → 15px)だと半角の送り幅7.5pxがセル7pxに丸められ、
;; 全角15pxが2×7=14pxに収まらず日英混在の表(org table等)が1pxずつずれる。
;; 偶数pxに落ちる値(140→14px / 160→16px)なら全角がちょうど2セル分になり整列するため160を採用。
(if (display-graphic-p)
    (progn
      (set-face-attribute
       'default nil
       :family "Cica"
       :height
       (cond
        ((eq system-type 'darwin) 160)
        ((eq system-type 'windows-nt) 110)
        ((eq system-type 'gnu/linux) 130)))
      ;;日本語フォント(全角はdefaultと同じCica・同一サイズを継承させ、全角=半角×2を保つ。
      ;; font-specはサイズ指定に:heightを受け付けないため、ここではサイズを指定しない)
      (set-fontset-font
       (frame-parameter nil 'font) 'japanese-jisx0208
       (font-spec :family "Cica"))
      ;; 行間。emacs-mac + Cica の組み合わせでは、行の箱の高さがフォントの
      ;; ピクセルサイズより小さく報告される(160指定で行高12px < グリフ16px、
      ;; とくにdescentが2pxしかない)。そのままだと descender(g/j/p/q/y)や
      ;; 漢字の下端がクリップされ「文字が潰れる」。line-spacingで下方向に余白を
      ;; 足し、行の箱をフォントサイズ以上に広げてクリップを防ぐ(4pxで行高16px=
      ;; ピクセルサイズと一致。もう少しゆとりが欲しければ増やす)。
      (setq-default line-spacing 4)))


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
;; -t で更新時刻順にし、-r は付けない(付けると逆順=古い順になるため)。結果、新しいものが上に来る。
(setq dired-listing-switches
      (if (executable-find "gls")
          "-alth --group-directories-first" ; ディレクトリを先頭にまとめ、サイズを人間が読める単位で、更新の新しい順に表示
        "-alt"))

;; diredを2つのウィンドウで開いている時に、デフォルトの移動orコピー先をもう一方のdiredで開いているディレクトリにする
(setq dired-dwim-target t)

;; パーミッション等の詳細情報を隠し、Finderのようにすっきりした表示にする。( キーでいつでも切替可能
(add-hook 'dired-mode-hook #'dired-hide-details-mode)

;; ただし更新日時だけは表示したい(Finderの「変更日」相当)。
;; dired-hide-details-mode はファイル名の前の詳細列(権限・所有者・サイズ・日時)を
;; 1つの不可視領域としてまとめて隠すため、部分的に日時だけ残すオプションが無い。
;; そこで readin 後に、その不可視領域のうち日時部分の invisible 属性だけを外して可視化する。
;; 日時書式は ls 依存で一定しないため(BSD ls: "Aug  3 23:42" / "Aug  3  2024"、
;; GNU ls --time-style=long-iso: "2026-08-03 14:20")、両方を検出できる正規表現で探す。
(defconst my/dired-modification-time-regexp
  (concat
   ;; GNU ls (long-iso): YYYY-MM-DD HH:MM
   "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}"
   "\\|"
   ;; BSD ls / GNU ls (locale): 月 日 (時刻 or 年)。月名は先頭大文字3字なので
   ;; 小文字始まりの所有者・グループ名や数字のサイズ列とは衝突しない。
   "[A-Z][a-z][a-z] +[0-9]\\{1,2\\} +\\(?:[0-9]\\{2\\}:[0-9]\\{2\\}\\|[0-9]\\{4\\}\\)")
  "Dired の一覧行から更新日時部分を切り出すための正規表現。")

(defun my/dired-reveal-modification-time ()
  "dired-hide-details-mode で隠れる詳細のうち、更新日時だけを再表示する。"
  (when (derived-mode-p 'dired-mode)
    (with-silent-modifications
      (save-excursion
        (goto-char (point-min))
        (while (not (eobp))
          (when (dired-move-to-filename)
            (let ((filename-beg (point)))
              (beginning-of-line)
              ;; bol〜ファイル名の間(=隠された詳細列)から日時だけを探して可視化する
              (when (re-search-forward my/dired-modification-time-regexp
                                       filename-beg t)
                (remove-text-properties (match-beginning 0) (match-end 0)
                                        '(invisible nil)))))
          (forward-line 1))))))
;; dired-insert-set-properties が invisible を付けた後に走らせたいので readin 後フックに置く
(add-hook 'dired-after-readin-hook #'my/dired-reveal-modification-time)

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
  ;; PATH/MANPATH に加え、gptel等が使うAPIキー・接続先もシェルから取り込む。
  ;; GUI起動のEmacsはシェルの環境変数を継承しないため、明示指定しないと
  ;; (getenv ...) が nil になり、これらの変数を参照する設定が動かない。
  (dolist (var '("ANTHROPIC_API_KEY" "GEMINI_API_KEY"
                 "MY_LLM_HOST" "MY_LLM_ENDPOINT"
                 "MY_LLM_MODELS_ENDPOINT" "MY_LLM_API_KEY"))
    (add-to-list 'exec-path-from-shell-variables var))
  (exec-path-from-shell-initialize))

;; 【native-comp補足】emacs-mac は native-comp(libgccjit)を使う。.eln生成後の
;; リンクで gcc のランタイムライブラリ(libemutls_w 等)が必要になるため、
;; libgccjit と同じバージョンの gcc 本体を入れておくこと(`brew install gcc`)。
;; gccが無いと "ld: library 'emutls_w' not found" でnative-compが失敗する。
;; ※ libgccjitはビルド時の絶対パスでgccのlibを解決するため、LIBRARY_PATH等の
;;    環境変数設定は不要(GUI起動でもgccさえ入っていれば動く)。
