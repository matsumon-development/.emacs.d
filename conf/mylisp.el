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
