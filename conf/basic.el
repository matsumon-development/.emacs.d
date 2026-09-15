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

(defun my/dired-quit-window ()
  "Diredバッファを閉じる。ウィンドウが複数開いていれば、そのウィンドウも閉じる。
1つしかウィンドウが無い場合はバッファを閉じるだけ(唯一のウィンドウは消せないため)。"
  (interactive)
  (let ((win (selected-window)))
    (kill-current-buffer)
    ;; kill後もそのウィンドウが生きていて、かつフレームに複数ウィンドウがあれば閉じる
    (when (and (window-live-p win) (not (one-window-p)))
      (delete-window win))))

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
(setq delete-by-moving-to-trash t)
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
      ;; Emacsで開かない=find-file-hookが走らないため、recentfには何も記録されない。
      ;; PDF・Office系をdiredから開いた場合も履歴に残るよう、ここで明示的に登録する
      (when (fboundp 'recentf-add-file)
        (recentf-add-file file))
      (call-process "open" nil 0 nil file)))

  ;; カーソル位置のファイルをFinderで表示(選択状態)する。ブラウザへのドラッグ&ドロップなど
  ;; Emacsが対応していない操作をFinder側に橋渡しするために使う
  (defun dired-reveal-in-finder ()
    "Reveal the file at point in Dired within macOS Finder."
    (interactive)
    (call-process "open" nil 0 nil "-R" (dired-get-filename))))

;; カーソル行(またはマークしたファイル)のフルパスをクリップボードへ入れる。
;; 素の dired にも dired-copy-filename-as-kill (w) があり 0 w で絶対パスを取れるが、
;; 毎回数引数を打つ必要があり、うっかり素の w を押すと相対パスが入る。
;; パスを他のアプリへ渡す用途では絶対パスしか使わないので、専用のキーを用意する。
;; kill-new は select-enable-clipboard が非nil(既定t)ならOSのクリップボードにも送る。
;; パスのクォートは my/quote-path-for-shell(conf/mylisp.el)と共有する。mylisp.el は
;; このファイルより後に読まれるが、呼ぶのは実行時なので問題ない。
(defun my/dired-copy-full-path ()
  "Diredのカーソル行、またはマークしたファイルのフルパスをクリップボードへコピーする。
複数ある場合は改行区切りで連結する。"
  (interactive)
  (let* ((files (or (dired-get-marked-files)
                    (user-error "コピーするファイルがありません")))
         (text (mapconcat #'my/quote-path-for-shell files "\n")))
    (kill-new text)
    (message "コピーしました: %s"
             (if (cdr files)
                 (format "%d件 (先頭: %s)" (length files)
                         (my/quote-path-for-shell (car files)))
               text))))


;;----------------------------------------------------------------------------------------
;;                 Dired プレビュー
;;----------------------------------------------------------------------------------------
;; カーソル行のファイルを隣のウィンドウに表示する(Finderのプレビュー相当)。
;; 既定はONで、M-x my/dired-preview-mode (diredでは P) でいつでも切れる。
;; キーバインドは keybind-manage.el 側。

(defvar my/dired-preview-extensions
  '("png" "jpg" "jpeg" "gif" "webp" "tif" "tiff" "svg" "heic" "bmp" "xpm" "xbm" "pbm")
  "diredでプレビューするファイルの拡張子(小文字で書く)。
ここに挙げたものだけを開くので、PDFやOffice系を外部アプリへ渡す設定
(conf/mylisp.el)を誤って踏むことはない。増やすときは、その形式をEmacsが
表示できるか(`image-type-available-p' など)を確かめること。")

(defvar my/dired-preview-max-file-size (* 30 1024 1024)
  "プレビューするファイルサイズの上限(バイト)。
カーソルを動かすたびに読み込むので、巨大なファイルで固まらないよう制限する。")

(defvar my/dired-preview--buffers nil
  "プレビューのために開いたバッファ。自分で開いたものだけを後で片付けるため覚えておく。")

(defvar my/dired-preview--last-file nil
  "直近にプレビューしたファイル。同じ行に留まっている間の再読み込みを避ける。")

(defconst my/dired-preview--placeholder-name " *dired preview*"
  "プレビュー対象外のときに表示するバッファ名。先頭の空白はバッファ一覧に出さないため。")

(defun my/dired-preview--split-side ()
  "プレビュー用ウィンドウを作る向きを返す。
モニターが横長なら \\='right(左右に並べる)、縦長なら \\='below(上下に積む)。
`frame-monitor-attributes' は現在のフレームが載っているモニターを見るので、
マルチモニター環境でフレームを移すと、その都度その画面に合った向きになる。"
  (let* ((attrs (frame-monitor-attributes))
         (geom (or (alist-get 'workarea attrs) (alist-get 'geometry attrs)))
         (width (nth 2 geom))
         (height (nth 3 geom)))
    (if (and (numberp width) (numberp height) (< width height))
        'below
      'right)))

(defun my/dired-preview--previewable-p (file)
  "FILEがプレビュー対象かどうかを返す。"
  (and file
       (file-regular-p file)
       (let ((ext (file-name-extension file)))
         (and ext (member (downcase ext) my/dired-preview-extensions)))
       (let ((size (file-attribute-size (file-attributes file))))
         (and size (<= size my/dired-preview-max-file-size)))))

(defun my/dired-preview--get-window ()
  "プレビュー用ウィンドウを返す。無ければnil。"
  (seq-find (lambda (win) (window-parameter win 'my/dired-preview))
            (window-list (selected-frame) 'no-minibuf)))

(defun my/dired-preview--placeholder-buffer (file)
  "プレビュー対象外のときに見せるバッファを返す。
対象外のたびにウィンドウを閉じると、行を移すだけで分割が出入りして落ち着かないので、
ウィンドウは残したまま中身だけ差し替える。"
  (let ((buf (get-buffer-create my/dired-preview--placeholder-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (if file
                    (format "プレビュー対象外: %s\n" (file-name-nondirectory file))
                  "プレビューできる行がありません\n")))
      (setq buffer-read-only t))
    buf))

(defun my/dired-preview--buffer (file)
  "FILEのプレビュー用バッファを返す。
既に開いているバッファがあればそれを使い(片付けの対象にしない)、
無ければ自分で開いて、あとで片付けられるよう覚えておく。"
  (or (get-file-buffer file)
      (progn
        (require 'recentf nil t)
        ;; カーソルを動かすたびに履歴へ積まれるのを防ぐ
        (let* ((recentf-exclude '(".*"))
               (buf (find-file-noselect file)))
          (push buf my/dired-preview--buffers)
          buf))))

(defun my/dired-preview--show (buf)
  "BUFをプレビュー用ウィンドウに表示する。ウィンドウが無ければ作る。"
  (let ((win (my/dired-preview--get-window)))
    (unless (window-live-p win)
      (setq win (split-window (selected-window) nil (my/dired-preview--split-side)))
      (set-window-parameter win 'my/dired-preview t))
    (set-window-buffer win buf)
    win))

(defun my/dired-preview--cleanup ()
  "プレビュー用ウィンドウを閉じ、このために開いたバッファを片付ける。"
  (let ((win (my/dired-preview--get-window)))
    (when (and (window-live-p win) (not (one-window-p)))
      (delete-window win)))
  (dolist (buf my/dired-preview--buffers)
    (when (buffer-live-p buf) (kill-buffer buf)))
  (setq my/dired-preview--buffers nil
        my/dired-preview--last-file nil))

(defun my/dired-preview--update ()
  "カーソル行に応じてプレビューを更新する。`post-command-hook' から呼ぶ。"
  (cond
   ;; dired上にいる間だけ更新する
   ((derived-mode-p 'dired-mode)
    (let ((file (ignore-errors (dired-get-filename nil t))))
      (unless (equal file my/dired-preview--last-file)
        (setq my/dired-preview--last-file file)
        (if (my/dired-preview--previewable-p file)
            (my/dired-preview--show (my/dired-preview--buffer file))
          (when (my/dired-preview--get-window)
            (my/dired-preview--show (my/dired-preview--placeholder-buffer file)))))))
   ;; diredから離れたら後片付けする。ただしプレビューのウィンドウを自分で選んで
   ;; 画像をスクロールしている最中は、消してしまわないよう除外する
   ((and (my/dired-preview--get-window)
         (not (eq (selected-window) (my/dired-preview--get-window))))
    (my/dired-preview--cleanup))))

(define-minor-mode my/dired-preview-mode
  "diredでカーソル行のファイルを隣のウィンドウにプレビューする。"
  :global t
  :lighter " DPrev"
  (if my/dired-preview-mode
      (add-hook 'post-command-hook #'my/dired-preview--update)
    (remove-hook 'post-command-hook #'my/dired-preview--update)
    (my/dired-preview--cleanup)))

;; 既定はON。diredを開いた時点から効く。
(my/dired-preview-mode 1)

;; dired を閉じるときにプレビューも畳む。my/dired-quit-window は
;; post-command-hook が走る前にウィンドウ構成を変えるので、ここで明示的に片付ける。
;; (無名lambdaで足すと後から remove できないので、名前を付けておく)
(defun my/dired-preview--before-quit (&rest _)
  "dired を閉じる前にプレビューを片付ける。"
  (when my/dired-preview-mode (my/dired-preview--cleanup)))

(advice-add 'my/dired-quit-window :before #'my/dired-preview--before-quit)


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
