;;; mylisp.el --- 既存パッケージに依存しない自作ユーティリティ関数 -*- lexical-binding: t; -*-

;;; Commentary:

;; 既存パッケージに依存しない自作ユーティリティ関数を置く。
;; OS標準アプリでのファイルオープンなど、他ファイルから使う小さな補助関数をまとめる。

;;; Code:

(defun open-default-os-app (filename)
  (shell-command-to-string
   (format "%s %s%s%s"
           (cond
            ((eq system-type 'darwin) "open")
            ((eq system-type 'windows-nt) (format "%s %s" "start" "\"hoge\""))
            ((eq system-type 'gnu/linux) "xdg-open"))
           "\"" filename "\""
           )))

;;----------------------------------------------------------------------------------------
;;                 特定の拡張子をOS標準アプリで開く
;;----------------------------------------------------------------------------------------
;; PDFやOffice系はEmacsで開いても読めないため、OS標準の関連付けアプリへ丸ごと渡す。
;; 以前は find-file-hook で「一度開いてから即kill」していたが、そのフックが走るのは
;; ファイルを全部バッファへ読み込み、normal-mode まで終わった後になる。
;; (auto-mode-alist は .pdf/.docx/.xlsx 等を doc-view-mode-maybe に割り当てているので、
;;  GUIでは doc-view の外部変換が走り出した直後に kill することになっていた)
;; file-name-handler-alist で insert-file-contents を横取りすれば、中身を読む前に
;; 抜けられるため、無駄な読み込みも doc-view の起動も発生しない。

(defvar my/external-app-extensions
  '("docx" "pptx" "xlsx" "xlsm" "xls" "pdf" "boxnote" "drawio")
  "Emacsで開かず、OS標準アプリに渡すファイルの拡張子。")

(defun my/external-app--build-regexp (extensions)
  "EXTENSIONS のいずれかで終わるファイル名にマッチする正規表現を作る。
`file-name-handler-alist' の照合時は `case-fold-search' の値が保証されないため、
.PDF のような大文字表記も正規表現側で許容しておく。"
  (concat "\\.\\(?:"
          (mapconcat
           (lambda (ext)
             (mapconcat (lambda (c)
                          (if (and (>= c ?a) (<= c ?z))
                              (format "[%c%c]" c (upcase c))
                            (regexp-quote (char-to-string c))))
                        ext ""))
           extensions "\\|")
          "\\)\\'"))

(defvar my/external-app-file-regexp
  (my/external-app--build-regexp my/external-app-extensions)
  "OS標準アプリに渡すファイル名にマッチする正規表現。")

(defun my/external-app-file-p (filename)
  "FILENAME が OS標準アプリで開く対象かどうかを返す。"
  (and (stringp filename)
       (string-match-p my/external-app-file-regexp filename)))

(defun my/open-externally-file-handler (operation &rest args)
  "対象拡張子のファイルを、Emacsが中身を読む前に横取りしてOS標準アプリで開く。
それ以外の OPERATION は通常のファイル操作へ委譲する。"
  (if (and (eq operation 'insert-file-contents)
           (nth 1 args)          ;; VISIT非nil = ファイルを訪問する読み込みだけを対象にする
           (display-graphic-p)   ;; ターミナル/daemonでは横取りしない(元の window-system 判定に相当)
           (zerop (buffer-size))) ;; 既存バッファへの挿入やrevertは素通しする
      (let ((file (expand-file-name (car args))))
        ;; Emacsでは開かない=recentfのフックが走らないため、ここで履歴に登録する
        (when (fboundp 'recentf-add-file)
          (recentf-add-file file))
        (open-default-os-app file)
        (kill-buffer (current-buffer))
        ;; find-file 側は insert-file-contents を file-error だけ捕まえる condition-case で
        ;; 囲んでいる。user-error なら握り潰されず、空バッファを残さずコマンドを中断できる
        (user-error "OS標準アプリで開きました: %s" (file-name-nondirectory file)))
    ;; 委譲時は、この関数自身を一時的に無効化して無限再帰を防ぐ(ファイルハンドラの定石)
    (let ((inhibit-file-name-handlers
           (cons #'my/open-externally-file-handler
                 (and (eq inhibit-file-name-operation operation)
                      inhibit-file-name-handlers)))
          (inhibit-file-name-operation operation))
      (apply operation args))))

(add-to-list 'file-name-handler-alist
             (cons my/external-app-file-regexp #'my/open-externally-file-handler))

;; サイズ確認は insert-file-contents より前(find-file-noselect 内)で走るので、
;; 上のハンドラでは抑止できない。どうせEmacsで読まないファイルなので、
;; 大きなpptx等で「本当に開くか」を毎回聞かれないようにする。
(defun my/external-app--skip-size-check (orig size op-type filename &optional offer-raw)
  "OS標準アプリに渡すファイルでは、サイズ確認プロンプトを出さない。"
  (unless (my/external-app-file-p filename)
    (funcall orig size op-type filename offer-raw)))
(advice-add 'abort-if-file-too-large :around #'my/external-app--skip-size-check)


(defun create-boxnote (filename)
  "Create Boxnote"
  (interactive "FNew Boxnote Name: ")
  (let ((template-dir "~/Box/私のBox Notes/template"))
    (let ((chosen-template (completing-read "Select Template: " (cdr (cdr (directory-files template-dir))))))
      (if (not (equal "boxnote" (file-name-extension filename)))
          (prin1 "It is inappropriate extension. \nOnly 'boxnote'")
        (copy-file (format "%s%s%s"  template-dir "/" chosen-template) filename 1)
        (prin1 (format "Creating %s" (file-name-nondirectory filename)))
        (run-at-time 4 nil #'open-default-os-app filename)))))



;;emacsリロード
;;https://tyfkda.github.io/blog/2015/12/24/emacs-reload.html
(defun revert-buffer-no-confirm (&optional force-reverting)
  "Interactive call to revert-buffer. Ignoring the auto-save
 file and not requesting for confirmation. When the current buffer
 is modified, the command refuses to revert it, unless you specify
 the optional argument: force-reverting to true."
  (interactive "P")
  ;;(message "force-reverting value is %s" force-reverting)
  (if (or force-reverting (not (buffer-modified-p)))
      (let ((mm (with-current-buffer (current-buffer)
                  major-mode)))
        (revert-buffer :ignore-auto :noconfirm)
        (with-current-buffer (current-buffer) (funcall mm)))
    (error "The buffer has been modified")))

;; reload buffer
(global-set-key "\M-r" 'revert-buffer-no-confirm)

;;----------------------------------------------------------------------------------------------------
;; クリップボードの画像をPNGファイルに書き出す
;;----------------------------------------------------------------------------------------------------
;; macOSのクリップボードにある画像を、pngpaste等の外部ツールに頼らず標準の osascript
;; だけでPNGとして保存する。AIエージェントへの画像添付(conf/ai-agent.el)と、
;; org-modeへの画像貼り付け(conf/language.el)の両方から使う共通処理。

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

(defun my/clipboard-image-to-file (&optional file)
  "macOSのクリップボードにある画像をPNGとして FILE へ書き出し、そのパスを返す。
FILE(絶対パス)を省略した場合は一時ファイルへ書き出す。
クリップボードに画像が無ければ nil を返す(このときFILEは作られない)。"
  (unless (eq system-type 'darwin)
    (user-error "クリップボード画像の取り込みはmacOSのみ対応です"))
  (let* ((tempp (null file))
         (file (or file (make-temp-file "emacs-clip-" nil ".png")))
         ;; osascript は画像の色空間変換などで stderr に警告
         ;; ("*** Error creating a JP2 color space ...") を出すことがある。
         ;; stdout と混ざると戻り値判定("OK")が崩れるため、stderr は分離して捨てる。
         (result (with-temp-buffer
                   (call-process "osascript" nil (list t nil) nil
                                 "-e" my/clipboard-image-to-png-applescript file)
                   (string-trim (buffer-string)))))
    (if (string= result "OK")
        file
      ;; AppleScriptは画像が無ければファイルを作る前に抜けるので、
      ;; 消すのは make-temp-file が先に作った一時ファイルのときだけでよい。
      (when tempp (ignore-errors (delete-file file)))
      nil)))

;; クリップボードに画像があるかどうかの判定。org-modeの p(貼り付け)のように、
;; 「画像があるときだけ挙動を変えたい」場面から呼ぶ。
;; osascriptの起動は50ms前後かかり、キー1打ごとに払うには重い。クリップボードに
;; テキストが載っているときは画像を貼る用途ではないので、まずEmacs内で完結する
;; テキスト判定で振り分け、テキストが無いときだけosascriptに問い合わせる。

(defconst my/clipboard-has-image-applescript
  (concat
   "try\n"
   "  set pngData to (the clipboard as «class PNGf»)\n"
   "  return \"HASIMAGE\"\n"
   "on error\n"
   "  return \"NOIMAGE\"\n"
   "end try")
  "クリップボードに画像があるかだけを調べるAppleScript(ファイルは作らない)。")

(defun my/clipboard-text-p ()
  "クリップボードに空でないテキストが載っていれば non-nil を返す。"
  (and (display-graphic-p)
       (ignore-errors
         (let ((str (gui-get-selection 'CLIPBOARD 'STRING)))
           (and (stringp str) (not (string-empty-p str)))))))

(defun my/clipboard-image-p ()
  "macOSのクリップボードに画像が載っていれば non-nil を返す。
テキストが載っている場合は(画像も同時に載っていても)テキスト優先で nil を返す。
Excelのセルのように両方載せるアプリがあるが、その場合に貼りたいのは通常テキストのため。"
  (and (eq system-type 'darwin)
       (not (my/clipboard-text-p))
       (string= "HASIMAGE"
                (with-temp-buffer
                  ;; osascriptは色空間の警告をstderrに出すことがあるので分離して捨てる
                  (call-process "osascript" nil (list t nil) nil
                                "-e" my/clipboard-has-image-applescript)
                  (string-trim (buffer-string))))))
