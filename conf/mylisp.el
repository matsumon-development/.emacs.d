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

;;特定の拡張子を別アプリで開く
(add-hook 'find-file-hook
          '(lambda()
             (let ((x 'nil) (buffer (buffer-name)))
               (if (eq system-type 'windows-nt)
                   (setq default-process-coding-system '(utf-8 . japanese-shift-jis)))
               (unless (equal window-system 'nil)
                 (dolist (ext '("docx" "pptx" "xlsx" "xlsm" "xls" "pdf" "boxnote" "drawio"))
                   (when (equal ext (file-name-extension (buffer-file-name)))
                     (setq x 't)))
                 (cond ((eq x 't)
                        (open-default-os-app (buffer-file-name))
                        (previous-buffer)
                        (kill-buffer buffer)))))))


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
