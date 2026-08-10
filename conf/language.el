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
  ;; markdown-command(C-c C-c v 等が使う変換コマンド)は既定の "markdown" のまま。
  ;; 以前はWindows時代のpandoc.exeを絶対パス指定していたが、macOSでは存在せず
  ;; 常に失敗していたため削除した。プレビューは下の grip-mode に任せる。
  :mode
  ("\\.markdown\\'" . markdown-mode)
  ("\\.md\\'" . gfm-mode)
  )

;; GFM(GitHub風)プレビュー。旧 markdown-preview-mode から乗り換え。
;; 旧設定は upstream が2022年で更新停止しているうえ、CSS/JSをCDNから http:// で
;; 読んでいたためオフラインでは崩れ、mixed contentでブロックもされ得た。
(use-package grip-mode
  :straight t
  :defer    t
  :custom
  ;; バックエンドは go-grip を明示指定する('auto だと環境次第で素のgripを掴む)。
  ;; 素のgrip(Python)はレンダリングをGitHub APIに投げるので、書きかけの文章が
  ;; 外部送信されるうえレート制限(60回/時)もかかる。go-gripは完全ローカルで動き、
  ;; mermaid・数式(MathJax)・シンタックスハイライトのJS/CSSを自前で同梱するため
  ;; オフラインでもそのまま描画できる。
  (grip-command 'go-grip)
  ;; このEmacsは XWIDGETS 付きでビルドされているので、外部ブラウザではなく
  ;; Emacs内のwebkitバッファにプレビューを出す。
  ;; xwidget無しのビルドに移ったらnilにする(既定のブラウザで開くようになる)。
  (grip-preview-in-webkit t)
  ;; 保存しなくても編集内容を反映させる。go-gripはローカル処理で軽いので有効化して問題ない。
  (grip-real-time-refresh t)
  :config
  ;; プレビューは編集中のウィンドウを分割せず、独立したフレームに出す。
  ;; 別モニタへ移したり、透過させた編集フレームの背後に置いたりしたいので、
  ;; 同一フレーム内の分割ではなくフレームを分ける必要がある。
  ;;
  ;; display-buffer-alist をバッファ名で引っ掛ける方法は使えない。
  ;; xwidgetのセッションバッファは xwidget-webkit--create-new-session-buffer で
  ;; 一旦「元バッファ名」(例 memo.md<2>)で作られ、*xwidget-webkit: …* への改名は
  ;; ページ読込後の xwidget-webkit-callback まで起きないため、表示を決める
  ;; pop-to-buffer の時点ではまだ目的の名前になっていない。
  ;; そこで grip--browse-url の呼び出し全体を包み、その間だけ表示先を強制する。
  ;; display-buffer-overriding-action は display-buffer-alist より優先される。
  (defun my/grip-preview-in-own-frame (fn url)
    "gripのプレビュー(FN URL)を専用フレームに表示する。"
    (let ((display-buffer-overriding-action
           '((display-buffer-reuse-window display-buffer-pop-up-frame)
             ;; 新フレームを作ってもフォーカスと選択フレームは編集側に残す。
             ;; 書きながら背後でプレビューが更新される状態にしたいため。
             (inhibit-switch-frame . t)
             ;; 編集フレーム側のウィンドウを再利用させない(分割に戻ってしまうため)。
             (inhibit-same-window . t)
             ;; ウィンドウをバッファ専用にしておくと、grip-mode をoffにして
             ;; xwidgetバッファがkillされたときにフレームごと片付く。
             (dedicated . t)
             (reusable-frames . visible)
             (pop-up-frame-parameters
              . ((name . "grip preview")
                 (width . 100)
                 (height . 48)
                 ;; 生成時にフォーカスを奪わせない
                 (no-focus-on-map . t))))))
      (funcall fn url)))
  (advice-add 'grip--browse-url :around #'my/grip-preview-in-own-frame)

  ;; プレビューの地色を白系(light)に固定する。
  ;; go-grip v0.9.2 にテーマ指定のCLIフラグは無く、grip-theme も mdopen 専用なので
  ;; Emacs側からは指定できない。配色は github-markdown-{light,dark}.css を
  ;; prefers-color-scheme のメディアクエリで出し分ける作りで、地色は
  ;; light=#ffffff / dark=#0d1117。xwidgetのWebKitが暗いと判定すると暗くなる。
  ;; ただし theme-switch.js は localStorage の "go-grip-theme" を
  ;; prefers-color-scheme より優先するので、そこへ light を書き込んで上書きする。
  (defconst my/grip--force-light-js
    (concat
     "(function(){"
     "var l=document.getElementById('theme-light'),"
     "d=document.getElementById('theme-dark'),"
     "lh=document.getElementById('highlight-light'),"
     "dh=document.getElementById('highlight-dark');"
     ;; go-grip以外のページでは該当要素が無いので、何もせず抜ける
     "if(!l||!d){return;}"
     "try{localStorage.setItem('go-grip-theme','light');}catch(e){}"
     "l.media='all';d.media='not all';"
     "if(lh){lh.media='all';}if(dh){dh.media='not all';}"
     "document.body.setAttribute('data-theme','light');"
     ;; トグルボタンの表示も light 側に合わせておく
     "var b=document.getElementById('theme-toggle');"
     "if(b){var i=b.querySelector('.theme-toggle-icon');"
     "if(i){i.textContent='\\u2600';}b.title='Theme: Light';}"
     "})();")
    "go-gripのプレビューを強制的にlightテーマにするJavaScript。")

  (defun my/grip--force-light-theme (xwidget &rest _)
    "XWIDGET の読込完了時に、gripのプレビューをlightテーマへ固定する。"
    ;; ページ読込が完了してからでないとDOMが無いので、load-finished のみ対象にする。
    (when (and (listp last-input-event)
               (equal (nth 3 last-input-event) "load-finished")
               ;; grip のプレビュー(ローカルサーバ)以外は触らない
               (string-prefix-p (format "http://%s:" grip-preview-host)
                                (or (xwidget-webkit-uri xwidget) "")))
      (xwidget-webkit-execute-script xwidget my/grip--force-light-js)))
  (advice-add 'xwidget-webkit-callback :after #'my/grip--force-light-theme)
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
