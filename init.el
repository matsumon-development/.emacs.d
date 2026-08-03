;;; init.el --- 最小限のブートストラップ(ロケール・straight.el導入・load-path・conf/*.el読込) -*- lexical-binding: t; -*-

;;; Commentary:

;; 最小限のブートストラップのみを行う。ロケール/文字コード/改行コード設定、
;; straight.elの導入、custom.el読込、load-path設定、conf/*.elの依存順ロードを担う。
;; 個別の機能設定はここには置かず、conf/*.el 側に分割する。

;;; Code:

;;(setq max-specpdl-size 10000)
;;(setq max-lisp-eval-depth 10000)

;;----------------------------------------------------------------------------------------
;;                 ロケール
;;----------------------------------------------------------------------------------------
;; 環境を日本語
;; 文字コードをUTF-8にする
;; 改行コードをLFにする
(set-locale-environment nil)
(set-language-environment "Japanese")
(set-terminal-coding-system 'utf-8-unix)
(set-keyboard-coding-system 'utf-8-unix)
(set-buffer-file-coding-system 'utf-8-unix)
(setq default-buffer-file-coding-system 'utf-8-unix)
(set-default-coding-systems 'utf-8-unix)
(prefer-coding-system 'utf-8-unix)
;;----------------------------------------------------------------------------------------------------
;; パッケージマネージャ
;;----------------------------------------------------------------------------------------------------

;; パッケージマネージャ
;;https://github.com/radian-software/straight.el
;;native-comp-deferred-compilation-deny-listはEmacs30で削除されたため、bootstrapでのネイティブコンパイル時にvoid-variableエラーになる。
;;未定義なら補う
(unless (boundp 'native-comp-deferred-compilation-deny-list)
  (defvar native-comp-deferred-compilation-deny-list nil))
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))
(straight-use-package 'use-package)

;;----------------------------------------------------------------------------------------------------
;; transient / magit の static-when 自己修復
;;----------------------------------------------------------------------------------------------------
;; transient の Package-Requires が特殊な複数行形式のため straight が依存(compat)を nil と
;; 誤認し、compat 抜きで byte-compile してしまう。すると compat 由来のマクロ static-when が
;; .elc に未展開で残り、起動時に "Invalid function: static-when" と magit 系の generic-function
;; 衝突(transient--init-suffix-key ...)を起こす。Emacs のバージョン切替で straight が再ビルド
;; する度に再発するため、magit/transient をロードする前にここで検出して依存込みで再コンパイルする。
(defun my/repair-static-when-elc ()
  "transient/magit の .elc に未展開の `static-when' が残っていたら、依存込みで再コンパイルする。"
  (let* ((build (expand-file-name "straight/build/" user-emacs-directory))
         (probes '("transient/transient.elc" "magit/magit-base.elc"))
         (broken (seq-some
                  (lambda (rel)
                    (let ((elc (expand-file-name rel build)))
                      (and (file-exists-p elc)
                           (with-temp-buffer
                             (insert-file-contents-literally elc)
                             (search-forward "static-when" nil t)))))
                  probes)))
    (when broken
      (message "[init] transient/magit の static-when 未展開を検出。再コンパイルします...")
      ;; 各パッケージの require が確実に解決するよう、全 build サブディレクトリを load-path に足す
      (dolist (dir (directory-files build t "\\`[^.]"))
        (when (file-directory-p dir) (add-to-list 'load-path dir)))
      ;; マクロ提供元を先に読み込んでおく(static-when 等の展開に必要)
      (dolist (feat '(compat cond-let llama)) (ignore-errors (require feat)))
      (dolist (pkg '("transient" "magit" "magit-section" "git-commit"
                     "with-editor" "git-gutter-plus"))
        (let ((dir (expand-file-name pkg build)))
          (when (file-directory-p dir)
            (dolist (el (directory-files dir t "\\.el\\'"))
              (ignore-errors (byte-compile-file el)))))))))
(my/repair-static-when-elc)

;;; custom-file
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))


;;----------------------------------------------------------------------------------------------------
;; ロードパス
;;----------------------------------------------------------------------------------------------------

;;load-pathを追加する関数を定義
(defun add-to-load-path (&rest paths)
  (let (path)
    (dolist (path paths paths)
      (let ((default-directory
              (expand-file-name (concat user-emacs-directory path))))
        (add-to-list 'load-path default-directory)
        (if (fboundp 'normal-top-level-add-subdirs-to-load-path)
            (normal-top-level-add-subdirs-to-load-path))))))

(add-to-load-path "elisp" "conf" "public_repos")

(load "basic")
(load "package-manage")
(load "ai-agent")
(load "language")
(load "mylisp")
(load "keybind-manage")
