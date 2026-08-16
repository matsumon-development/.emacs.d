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
;; CSVを「表」として読むための設定。
(defvar-local my/csv--hidden-header-overlay nil
  "見出し行(本文1行目)を隠すためのオーバーレイ。")

(defun my/csv--sync-hidden-header-row (&rest _)
  "ヘッダー行の有効/無効に合わせて、本文1行目の表示を切り替える。
`csv-header-line' は1行目を複製してヘッダー行に出すだけで本文の1行目は
そのまま残るため、何もしないとファイル先頭で同じ行が二重に見える。
そこでヘッダー行が有効な間だけ、本文側の1行目をオーバーレイで隠す。
隠すとヘッダー文字列の計算が1行ずれるので、その回避は
`my/csv--header-string-ignore-hidden-row' が担当する。"
  (cond
   ((and header-line-format (not my/csv--hidden-header-overlay))
    ;; csv-align-mode が buffer-invisibility-spec をリスト化するので、
    ;; 素の t に頼らず専用シンボルを登録して確実に隠す。
    (add-to-invisibility-spec 'my/csv-header-row)
    (save-excursion
      (goto-char (point-min))
      (setq my/csv--hidden-header-overlay
            ;; 改行まで含めないと、隠したあとに空行が残る。
            (make-overlay (point-min) (min (point-max) (1+ (line-end-position)))))
      (overlay-put my/csv--hidden-header-overlay 'invisible 'my/csv-header-row)))
   ((and (not header-line-format) my/csv--hidden-header-overlay)
    (delete-overlay my/csv--hidden-header-overlay)
    (setq my/csv--hidden-header-overlay nil))))

(defun my/csv--header-string-ignore-hidden-row (fn &rest args)
  "ヘッダー文字列の計算中だけ1行目の隠蔽を解いて FN を ARGS で呼ぶ。
`csv--compute-header-string' は `move-to-column' で横スクロール位置に
合わせるが、move-to-column は不可視テキストを飛び越して進むため、
1行目を隠したままだと2行目を読んでしまい、見出しが1行ずれる。
`csv-align-mode' が使う csv-truncate は残す必要があるので、
`buffer-invisibility-spec' 全体ではなく自前のシンボルだけ取り除く。"
  (let ((buffer-invisibility-spec
         (remq 'my/csv-header-row buffer-invisibility-spec)))
    (apply fn args)))

;; 処理の順番に意味があるので、:hook を並べず1つの関数にまとめる
;; (use-packageの:hookはadd-hookで先頭に積まれるため、書いた順と実行順が逆になる)。
(defun my/csv-view-setup ()
  "CSV/TSVバッファを表として読みやすくする。"
  ;; 桁揃えの前に区切り文字を確定させる。中身から推測するので
  ;; カンマ以外(TAB・セミコロン)のファイルもそのまま開ける。
  (csv-guess-set-separator)
  ;; 折り返すと行と列の対応が崩れて表に見えなくなるので、はみ出した分は切る。
  (setq-local truncate-lines t)
  ;; 1行目を見出しとしてヘッダー行に固定する。スクロールしても列名が見える。
  ;; csv-header-line はトグルなので、二重に呼んで解除しないよう確認する。
  ;; 本文側1行目の隠蔽は csv-header-line への advice が引き受ける。
  (unless header-line-format
    (csv-header-line))
  ;; 列の桁揃え。バッファの中身は書き換えず表示だけ変える方式で、
  ;; jit-lockにより画面に見えている範囲だけ処理するため大きなファイルでも重くない。
  (csv-align-mode 1))

(use-package csv-mode
  :straight t
  :defer    t
  :mode     (("\\.csv\\'" . csv-mode)
             ("\\.tsv\\'" . tsv-mode))
  :custom
  ;; 文字列は左寄せ・数値は右寄せ。数字の桁が縦に揃って比較しやすくなる。
  (csv-align-style 'auto)
  ;; 1列が極端に長いと後続の列が画面外へ押し出されるので上限を設ける。
  (csv-align-max-width 60)
  :hook
  ((csv-mode . my/csv-view-setup))
  :config
  ;; M-x csv-header-line で手動トグルしたときも隠蔽が追従するよう、
  ;; setup 側で呼ぶのではなく csv-header-line 自体に足しておく。
  (advice-add 'csv-header-line :after #'my/csv--sync-hidden-header-row)
  (advice-add 'csv--compute-header-string :around
              #'my/csv--header-string-ignore-hidden-row))

;; 列ごとに文字色を変えて、隣の列との境目を見分けやすくする。
;; MELPAには無いのでGitHubから直接取得する。
(defun my/rainbow-csv-maybe-enable ()
  "CSVでのみ rainbow-csv を有効にする。
tsv-mode では有効にしない。TSVは引用符を使わない仕様のため
tsv-mode が `csv-field-quotes' を nil にするが、rainbow-csv は
その中身を正規表現の文字クラスへそのまま埋める実装になっており、
空だと \"[]\" という不正な正規表現になって invalid-regexp で落ちるため。"
  (when csv-field-quotes
    (rainbow-csv-mode 1)))

(use-package rainbow-csv
  :straight (rainbow-csv :type git :host github :repo "emacs-vs/rainbow-csv")
  :defer    t
  ;; tsv-mode は csv-mode から派生していて csv-mode-hook も走るので、
  ;; フックは csv-mode 側に付けたうえで上の関数で選り分ける。
  :hook     ((csv-mode . my/rainbow-csv-maybe-enable)))


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
  ;; typescript-modeはJSXを解釈できないが、grammar未導入の間も.tsx/.jsxを
  ;; 開けるよう暫定で割り当てておく(grammarがあれば下でtsx-ts-modeに上書きする)。
  :mode     (("\\.ts\\'"      . typescript-mode)
             ("\\.[jt]sx\\'"  . typescript-mode))
  )


;;            TypeScript/JSX の tree-sitter モード
;; .tsx はJSXを含むため、typescript-mode(.ts用)では字下げもハイライトも崩れる。
;; Emacs 29内蔵のtree-sitterモード(tsx-ts-mode / typescript-ts-mode)なら正しく扱え、
;; VSCodeと同じ typescript-language-server にeglotがそのまま繋がる
;; (eglot-server-programs に登録済みで、tsxは languageId=typescriptreact になる)。
;; grammarは各自のマシンでビルドする必要があるため、未導入の環境では
;; 上のtypescript-modeのまま動くようにしてある。
(defvar my/treesit-language-sources
  '((typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
    (tsx        "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
    (css        "https://github.com/tree-sitter/tree-sitter-css"))
  "`my/treesit-install-grammars' で取得するtree-sitterのgrammar一覧。")

(defun my/treesit-install-grammars ()
  "未導入のtree-sitter grammarをまとめてビルド・インストールする。
Cコンパイラとgitが必要。実行後にEmacsを再起動すると各ts-modeが有効になる。"
  (interactive)
  (unless (treesit-available-p)
    (user-error "このEmacsはtree-sitterに対応していません"))
  (setq treesit-language-source-alist my/treesit-language-sources)
  (dolist (src my/treesit-language-sources)
    (unless (treesit-language-available-p (car src))
      (treesit-install-language-grammar (car src))))
  (message "tree-sitter grammarの導入が完了しました。Emacsを再起動してください"))

;; grammarが入っているものだけts-modeへ切り替える。auto-mode-alistは先頭から
;; 探索されるので、後から add-to-list したこちらが上のtypescript-modeより優先される。
(when (and (fboundp 'treesit-available-p) (treesit-available-p))
  (setq treesit-language-source-alist my/treesit-language-sources)
  (when (treesit-language-available-p 'tsx)
    (add-to-list 'auto-mode-alist '("\\.[jt]sx\\'" . tsx-ts-mode)))
  (when (treesit-language-available-p 'typescript)
    (add-to-list 'auto-mode-alist '("\\.ts\\'" . typescript-ts-mode))))


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
;;   CSS/SCSS  : vscode-css-language-server (npm install -g vscode-langservers-extracted)
(use-package eglot
  :defer t
  :hook ((python-mode        . eglot-ensure)
         (typescript-mode    . eglot-ensure)
         ;; tree-sitter版のTS/TSX。tsserverはVSCodeと同じものを使う
         (typescript-ts-mode . eglot-ensure)
         (tsx-ts-mode        . eglot-ensure)
         ;; CSS/SCSSもVSCodeと同じ vscode-css-language-server に繋ぐ
         (css-mode           . eglot-ensure)
         (scss-mode          . eglot-ensure)
         (go-mode            . eglot-ensure)
         (rust-mode          . eglot-ensure)
         (sh-mode            . eglot-ensure)))

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
;; フォーマッタ(保存時の自動整形)
;;----------------------------------------------------------------------------------------------------
;; VSCodeの"Format on Save"相当。apheleiaは外部フォーマッタを非同期で走らせ、
;; カーソル位置とスクロール位置を保ったまま結果を反映するので保存が引っかからない。
;; どのモードでどのフォーマッタを使うかはapheleia-mode-alistに既定が揃っている
;; (TypeScript/TSX/CSS/SCSS/JSON=prettier、Python=black など)。
;; フォーマッタ本体は別途インストールが必要:
;;   prettier (npm install -g prettier。プロジェクトのnode_modules配下があればそちらが優先される)
(use-package apheleia
  :straight t
  :hook (after-init . apheleia-global-mode)
  :config
  ;; Goは既存の gofmt-before-save(gofmt-commandにgoimportsを指定)に任せる。
  ;; apheleiaのgo-mode既定はgofmtでimport整理が入らないうえ、二重に整形が走るため外す。
  (setf (alist-get 'go-mode apheleia-mode-alist nil t) nil))


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
