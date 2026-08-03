;;; language.el --- プログラミング言語・マークアップ/データ形式の設定 -*- lexical-binding: t; -*-

;;; Commentary:

;; プログラミング言語・マークアップ/データ形式のメジャーモードと、
;; 言語サーバ(eglot)・Lint の設定をまとめる。

;;; Code:

;;----------------------------------------------------------------------------------------------------
;; パッケージで追加のマークアップ言語
;;----------------------------------------------------------------------------------------------------

(use-package org
  :defer t
  :mode(("\\.org\\'" . org-mode))
  :config
  (setq org-todo-keywords '((sequence "TODO(t)" "WIP(w)" "|" "DONE(d)"))))
(use-package org-bullets
  :after org
  :straight t
  :custom (org-bullets-bullet-list '("" "" "" "" "" "" "" "" "" ""))
  :hook (org-mode . org-bullets-mode))




(use-package markdown-mode
  :straight t
  :defer    t
  :custom
  (markdown-fontify-code-blocks-natively t) ;;コードブロックのハイライト
  (markdown-command "~/AppData/Local/Pandoc/pandoc.exe -s --self-contained -t html5 -c http://thomasf.github.io/solarized-css/solarized-light.min.css")
  :mode
  ("\\.markdown\\'" . markdown-mode)
  ("\\.md\\'" . gfm-mode)
  )
(use-package markdown-preview-mode
  :straight (markdown-preview-mode :type git :host github :repo "ancane/markdown-preview-mode")
  :defer    t
  :custom
  (markdown-preview-stylesheets (list "http://thomasf.github.io/solarized-css/solarized-light.min.css"))
  (markdown-preview-javascript (list "http://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.6.0/highlight.min.js"))
  (markdown-preview-script-onupdate "hljs.highlightAll();")
  )

;;----------------------------------------------------------------------------------------------------
;; パッケージで追加のデータファイル形式
;;----------------------------------------------------------------------------------------------------

;;            json
(use-package json-mode
  :straight t
  :defer    t
  :mode     (("\\.json\\'" . json-mode)))


;;            csv
(use-package csv-mode
  :straight t
  :defer    t
  :mode     (("\\.csv\\'" . csv-mode)))


(use-package ttl-mode
  :straight t
  :defer    t
  :mode     (("\\.ttl\\'" . ttl-mode)))


;;            YAML
(use-package yaml-mode
  :straight t
  :defer    t
  :hook     (yaml-mode . (lambda () (electric-indent-local-mode -1)))
  :mode
  ("\\.yaml\\'" . yaml-mode)
  ("\\.yml\\'" . yaml-mode))


;;            Dockerfile
(use-package dockerfile-mode
  :straight t
  :defer    t
  :hook     (dockerfile-mode . (lambda () (electric-indent-local-mode -1)))
  :mode (
         ("Dockerfile\\'" . dockerfile-mode)
         ("\\.Dockerfile'" . dockerfile-mode)))


;;            docker-compose
(use-package docker-compose-mode
  :straight t
  :defer    t
  :hook
  (docker-compose-mode . (lambda ()  (electric-indent-local-mode -1)))
  :mode (("docker-compose\\.yml\\'" . docker-compose-mode)
         ("docker-compose\\.yaml\\'" . docker-compose-mode)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; パッケージで追加のプログラミング言語
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;            PowerShell
(use-package powershell
  :straight t
  :defer    t
  :mode     ("\\.ps1\\'" . powershell-mode)
  )


;;            TypeScript
(use-package typescript-mode
  :straight t
  :defer    t
  :custom   (typescript-indent-level 2)
  :mode     ("\\.ts\\'" . typescript-mode)
  )


;;            C#
(use-package csharp-mode
  :straight t
  :defer    t
  :mode     ("\\.cs\\'" . csharp-mode))


;;            Go言語
(use-package go-mode
  :straight t
  :defer    t
  :commands go-mode
  :custom   (gofmt-command "goimports")
  :hook     (before-save . gofmt-before-save)
  :mode     ("\\.go\\'" . go-mode))


;;            Rust
(use-package rust-mode
  :straight t
  :defer    t
  :mode     ("\\.rs\\'" . rust-mode))


;;            Scala
(use-package scala-mode
  :straight t
  :defer t
  :mode (("\\.scala\\'" . scala-mode)))


;;            Groovy
(use-package groovy-mode
  :straight t
  :defer t
  :mode (("\\.groovy\\'" . groovy-mode)
         ("\\.gradle\\'" . groovy-mode)))


;;            Jenkinsfile
(use-package jenkinsfile-mode
  :straight t
  :defer t
  :mode (("Jenkinsfile\\'" . jenkinsfile-mode)))



;;----------------------------------------------------------------------------------------------------
;; 言語サーバ(eglot)
;;----------------------------------------------------------------------------------------------------
;; Emacs30に標準搭載のeglotに一本化する。対応する各言語サーバーは別途インストールが必要。
;;   Python    : pyright        (npm install -g pyright)
;;   TypeScript: typescript-language-server, typescript (npm install -g typescript typescript-language-server)
;;   Go        : gopls          (go install golang.org/x/tools/gopls@latest)
;;   Rust      : rust-analyzer  (rustup component add rust-analyzer)
;;   Shell     : bash-language-server (npm install -g bash-language-server)
(use-package eglot
  :defer t
  :hook ((python-mode     . eglot-ensure)
         (typescript-mode . eglot-ensure)
         (go-mode         . eglot-ensure)
         (rust-mode       . eglot-ensure)
         (sh-mode         . eglot-ensure)))

;; lsp-mode/lsp-pyrightはeglotとの比較用に残しているが、自動起動フックは外している。
;; 試したい場合はバッファ内で (require 'lsp-pyright) や M-x lsp-deferred を手動実行する。
(use-package lsp-mode
  :straight t
  :defer    t
  :commands (lsp lsp-deferred)
  :custom
  ((lsp-keymap-prefix "M-l")
   (lsp-signature-auto-activate '(:on-trigger-char :after-completion :on-server-request))
   (lsp-idle-delay 1.0)
   (lsp-semantic-tokens-enable t)
   (lsp-completion-provider :none) ;; ★補完にcorfuを使用する
   )
  :hook (lsp-mode . lsp-enable-which-key-integration))

(use-package lsp-pyright
  :straight t
  :defer    t)


;;----------------------------------------------------------------------------------------------------
;; Lint
;;----------------------------------------------------------------------------------------------------

;; Set up a mode for JSON based templates

(define-derived-mode cfn-json-mode js-mode
  "CFN-JSON"
  "Simple mode to edit CloudFormation template in JSON format."
  (setq js-indent-level 2))

(add-to-list 'magic-mode-alist
             '("\\({\n *\\)? *[\"']AWSTemplateFormatVersion" . cfn-json-mode))

;; Set up a mode for YAML based templates if yaml-mode is installed
;; Get yaml-mode here https://github.com/yoshiki/yaml-mode
(when (featurep 'yaml-mode)

  (define-derived-mode cfn-yaml-mode yaml-mode
    "CFN-YAML"
    "Simple mode to edit CloudFormation template in YAML format.")

  (add-to-list 'magic-mode-alist
               '("\\(---\n\\)?AWSTemplateFormatVersion:" . cfn-yaml-mode)))

;; Set up cfn-lint integration if flycheck is installed
;; Get flycheck here https://www.flycheck.org/
(when (featurep 'flycheck)
  (flycheck-define-checker cfn-lint
    "AWS CloudFormation linter using cfn-lint.

Install cfn-lint first: pip install cfn-lint

See `https://github.com/aws-cloudformation/cfn-python-lint'."

    :command ("cfn-lint" "-f" "parseable" source)
    :error-patterns ((warning line-start (file-name) ":" line ":" column
                              ":" (one-or-more digit) ":" (one-or-more digit) ":"
                              (id "W" (one-or-more digit)) ":" (message) line-end)
                     (error line-start (file-name) ":" line ":" column
                            ":" (one-or-more digit) ":" (one-or-more digit) ":"
                            (id "E" (one-or-more digit)) ":" (message) line-end))
    :modes (cfn-json-mode cfn-yaml-mode))

  (add-to-list 'flycheck-checkers 'cfn-lint)
  (add-hook 'cfn-json-mode-hook 'flycheck-mode)
  (add-hook 'cfn-yaml-mode-hook 'flycheck-mode))





;;----------------------------------------------------------------------------------------------------
;; インデントとタブサイズ
;;----------------------------------------------------------------------------------------------------

;;タブサイズ
(add-hook 'prog-mode-hook #'(lambda() (setq tab-width 4)))


;;自動インデントの設定
(use-package aggressive-indent
  :straight t
  :init (global-aggressive-indent-mode 1)
  :config
  (electric-indent-local-mode -1)
  (add-to-list 'aggressive-indent-excluded-modes 'python-mode)
  (add-to-list 'aggressive-indent-excluded-modes 'js-mode)
  (add-to-list 'aggressive-indent-excluded-modes 'typescript-mode)
  (add-to-list 'aggressive-indent-excluded-modes 'markdown-mode)
  (add-to-list 'aggressive-indent-excluded-modes 'org-mode)
  (add-to-list 'aggressive-indent-excluded-modes 'scala-mode          )
  (add-to-list 'aggressive-indent-excluded-modes 'yaml-mode           )
  (add-to-list 'aggressive-indent-excluded-modes 'dockerfile-mode   )
  (add-to-list 'aggressive-indent-excluded-modes 'docker-compose-mode)
  (add-to-list 'aggressive-indent-excluded-modes 'csv-mode           )
  (add-to-list 'aggressive-indent-excluded-modes 'ttl-mode           )
  )
