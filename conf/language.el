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
  ;; 新規ファイルにはタイトル行を入れておく(関数はこのファイルの下で定義)
  :hook (org-mode . my/org-new-file-insert-title)
  :config
  ;; #+TITLE: の値だけを大きくする(関数はこのファイルの下で定義)
  (my/org-enlarge-document-title)
  ;; ワークフローは TODO(未着手) → WIP(着手中) → DONE。
  ;; 自分の手を離れて止まっているものは WAIT、やらずに終えたものは CANCELED に落とす。
  ;; "|" の右側が完了状態なので、CANCELED も完了扱い(残タスクとして数えられない)。
  ;; 括弧内は C-c C-t から1文字で選ぶためのキー(大文字小文字で区別するので W と w は別)。
  (setq org-todo-keywords
        '((sequence "TODO(t)" "WIP(w)" "WAIT(W)" "|" "DONE(d)" "CANCELED(c)")))
  ;; 色はテーマ固有の色名ではなく、error/warning/success といった意味付きのfaceから
  ;; 継承する。SPC t c で明るいテーマに切り替えてもそのテーマの色に追従させるため。
  (setq org-todo-keyword-faces
        '(("TODO"     . (:inherit error :weight bold))
          ("WIP"      . (:inherit warning :weight bold))
          ("WAIT"     . (:inherit font-lock-comment-face :weight bold))
          ("DONE"     . (:inherit success :weight bold))
          ("CANCELED" . (:inherit shadow :weight bold :strike-through t))))
  ;; 貼り付けた画像を毎回トグルせず見られるよう、ファイルを開いた時点から
  ;; 画像リンクをインライン表示する(既定はnilで、C-c C-x C-v を押すまで出ない)。
  (setq org-startup-with-inline-images t)
  ;; スクリーンショットは実寸だと画面を埋めてしまうので、表示幅を600pxに抑える。
  ;; リンクごとに変えたいときは #+ATTR_ORG: :width ... を書けばそちらが優先される。
  (setq org-image-actual-width '(600)))

;;----------------------------------------------------------------------------------------------------
;; org-mode: 新規ファイルに #+TITLE: を入れる
;;----------------------------------------------------------------------------------------------------
;; org-modeのバッファは capture や org-src など「ファイルを持たないもの」もあるため、
;; 「ファイルを訪問していて」「そのファイルがまだ無く」「中身が空」の3条件で
;; 新規作成時だけに絞る(既存ファイルの中身を触らないようにするため)。

(defun my/org-new-file-insert-title ()
  "新規に作ったorgファイルの先頭に、ファイル名をタイトルとして入れる。"
  (when (and buffer-file-name
             (not (file-exists-p buffer-file-name))
             (zerop (buffer-size)))
    (insert (format "#+TITLE: %s\n\n" (file-name-base buffer-file-name)))
    ;; すぐ本文を書き始められるよう、カーソルはタイトルの下(空行)に置く
    (goto-char (point-max))))

;;----------------------------------------------------------------------------------------------------
;; org-mode: #+TITLE: の文字を大きくする
;;----------------------------------------------------------------------------------------------------
;; 大きくなるのは "#+TITLE:" の後ろの値だけ。先頭の "#+TITLE:" 自体は
;; org-document-info-keyword という別のfaceなので等倍のまま。

(defvar my/org-document-title-height 1.6
  "#+TITLE: の値を表示するときの拡大率(defaultフェイスに対する相対値)。
絶対サイズではなく相対値にして、フォントサイズを変えても比率が保たれるようにする。")

(defun my/org-enlarge-document-title (&rest _)
  "org-document-title に高さだけを足す。
custom側(:custom-face / custom-set-faces)で指定すると face 全体を差し替えることになり、
テーマが与えている色や太さまで落ちてしまう。ここでは :height だけを上書きしたいので
set-face-attribute を使う。ただしテーマを読み込むと属性は計算し直されて元に戻るため、
enable-theme-functions からも呼んでテーマ切替(SPC t c)に追従させる。"
  (when (facep 'org-document-title)
    (set-face-attribute 'org-document-title nil
                        :height my/org-document-title-height)))

;; org読み込み前はfaceがまだ無いので、ここでは登録だけしておく(上のuse-packageの
;; :configで初回適用し、以降はテーマを切り替えるたびに再適用される)。
(add-hook 'enable-theme-functions #'my/org-enlarge-document-title)

;; 見出し・TODO・タグ・日付・表・#+begin_srcブロックまで、org全体の見た目を今風にする。
;; 以前は org-bullets(見出しの記号だけを差し替えるパッケージ)を使っていたが、
;; 見た目を一新するため置き換えた。
(use-package org-modern
  :straight t
  :after org
  :hook (org-mode . org-modern-mode)
  :custom
  ;; 見出しの記号は、折り畳み状態が分かるインジケータ(▶/▼)にする。
  ;; 従来のように記号を並べたいときは 'replace にして org-modern-replace-stars を使う。
  (org-modern-star 'fold)
  ;; TODOキーワードはラベル表示になり、色は org-modern-todo-faces から取られる
  ;; (この経路では org-todo-keyword-faces は参照されない)。テーマに追従させたいので
  ;; ここでも意味付きのfaceから継承する。既定の org-modern-todo が :inverse-video で
  ;; 「文字色をラベルの背景色にする」作りなので、それに合わせて :inverse-video を付ける。
  (org-modern-todo-faces
   '(("TODO"     . (:inherit error :weight semibold :inverse-video t))
     ("WIP"      . (:inherit warning :weight semibold :inverse-video t))
     ("WAIT"     . (:inherit font-lock-comment-face :weight semibold :inverse-video t))
     ("DONE"     . (:inherit success :weight semibold :inverse-video t))
     ("CANCELED" . (:inherit shadow :weight semibold :inverse-video t))))
  :config
  ;; タグはラベルとして見出し直後に置きたいので、org側の桁揃え(空白詰め)を止める。
  ;; 揃えたままだとラベルが右端へ飛んで読みにくくなる(org-modernのREADME推奨設定)。
  (setq org-auto-align-tags nil)
  (setq org-tags-column 0)
  ;; 折り畳んだ見出しの省略記号(既定の "..." より収まりがよい)
  (setq org-ellipsis "…"))

;;----------------------------------------------------------------------------------------------------
;; org-mode: クリップボードの画像を「貼り付け」る
;;----------------------------------------------------------------------------------------------------
;; クリップボードの画像をorgファイルと同じディレクトリにPNGとして保存し、
;; その相対パスへのリンクを挿入してインライン表示する(貼り付けたように見せる)。
;; org 9.7の org-yank-media が同等のことをするが、Emacs 29.4 同梱のorgは 9.6 系で
;; ハンドラ自体が無いため、ここでは自前のコマンドを用意する。
;; クリップボード→PNG の書き出しは my/clipboard-image-to-file(conf/mylisp.el)。

(defun my/org--unique-image-file (dir base)
  "DIR の中で BASE.png が空いていればそのパスを、埋まっていれば連番を足したパスを返す。
同じ秒に2枚貼っても、既存の画像を上書きしないようにするため。"
  (let ((file (expand-file-name (concat base ".png") dir))
        (n 1))
    (while (file-exists-p file)
      (setq file (expand-file-name (format "%s-%d.png" base n) dir)
            n (1+ n)))
    file))

(defun my/org-insert-clipboard-image (&optional name)
  "クリップボードの画像をPNGで保存し、リンクを挿入してインライン表示する。
保存先はorgファイルと同じディレクトリ(ファイル未保存のバッファでは
`default-directory')。ファイル名は「orgのファイル名-日時.png」を自動生成するが、
C-u 付きで呼ぶと NAME を尋ねる(拡張子は不要)。"
  (interactive
   (list (when current-prefix-arg
           (read-string "画像のファイル名(拡張子なし): "))))
  (unless (derived-mode-p 'org-mode)
    (user-error "org-modeのバッファではありません"))
  (let* ((dir (if buffer-file-name
                  (file-name-directory buffer-file-name)
                default-directory))
         (base (or (and name (not (string-empty-p (string-trim name)))
                        (string-trim name))
                   (format "%s-%s"
                           (if buffer-file-name
                               (file-name-base buffer-file-name)
                             "clipboard")
                           (format-time-string "%Y%m%d-%H%M%S"))))
         (file (my/org--unique-image-file dir base)))
    (unless (my/clipboard-image-to-file file)
      (user-error "クリップボードに画像がありません"))
    ;; 画像は前後に空行を置いて、1枚ずつ独立した段落にする。
    ;; 表示幅の #+ATTR_ORG は段落単位で効くため、同じ段落に2枚並べてしまうと
    ;; 片方だけサイズを変えられなくなる(my/org-image-enlarge 等が効く単位に合わせる)。
    (let ((start (point)))
      (unless (bolp) (insert "\n"))
      (unless (save-excursion (forward-line -1) (looking-at-p "^[ \t]*$"))
        (insert "\n"))
      (insert (format "[[file:%s]]\n" (file-relative-name file dir)))
      (unless (looking-at-p "^[ \t]*$")
        (save-excursion (insert "\n")))
      ;; 挿入した範囲だけを再描画する(バッファ全体を走査しないので大きなファイルでも軽い)
      (org-display-inline-images nil t start (point)))
    (message "画像を保存: %s" (file-relative-name file dir))))

;;----------------------------------------------------------------------------------------------------
;; org-mode: カーソル位置の画像の表示サイズを変える
;;----------------------------------------------------------------------------------------------------
;; リンクを含む段落に #+ATTR_ORG: :width を付け外しして、インライン表示の幅だけを変える
;; (画像ファイル自体は加工しない)。幅の求め方は org 本体の実装に合わせてあるので、
;; org-image-actual-width の既定値(このファイル上部)ともそのまま整合する。

(defvar my/org-image-resize-step 1.25
  "画像を1回拡大/縮小するときの倍率。")

(defvar my/org-image-min-width 50
  "拡大/縮小で下回らない表示幅(px)。縮めすぎて画像を見失わないようにするため。")

(defconst my/org-image-attr-width-re
  "^[ \t]*#\\+attr_.*?: +.*?\\(:width +\\(\\S-+\\)\\)"
  "段落に付いた #+ATTR_*: :width を拾う正規表現。
グループ1が \":width 300\" 全体、グループ2が数値部分。
どの #+ATTR_* でも効く点は org 本体(org-display-inline-image--width)と同じ。")

(defun my/org-image--link-here ()
  "カーソル位置ちょうどにある画像ファイルリンクのorg要素を返す(無ければnil)。"
  (let ((ctx (org-element-context)))
    (and (eq (org-element-type ctx) 'link)
         (equal (org-element-property :type ctx) "file")
         (image-supported-file-p (org-element-property :path ctx))
         ctx)))

(defun my/org-image--link-at-point ()
  "カーソル位置、無ければその行にある画像ファイルリンクのorg要素を返す。
インライン表示中はリンク全体が画像に置き換わっているので、
行のどこにカーソルがあっても掴めるようにしている。"
  (or (my/org-image--link-here)
      (save-excursion
        (beginning-of-line)
        (when (re-search-forward org-link-any-re (line-end-position) t)
          (goto-char (match-beginning 0))
          (my/org-image--link-here)))))

(defun my/org-image--current-width (link)
  "LINK の現在の表示幅(px)を返す。
ATTRにも org-image-actual-width にも幅指定が無ければ、画像の実寸を返す。
org-display-inline-image--width はorg内部の関数だが、表示幅の決定を
org本体と同じ規則で行いたいのでそのまま使う。"
  (let ((w (org-display-inline-image--width link)))
    (if (numberp w)
        (round w)
      (car (image-size (create-image
                        (expand-file-name (org-element-property :path link)))
                       t)))))

(defun my/org-image--set-attr-width (link width)
  "LINK を含む段落の #+ATTR_ORG: :width を WIDTH(px)にする。
WIDTH が nil なら幅指定を取り除き、org-image-actual-width の既定に戻す。"
  (let* ((par (org-element-lineage link '(paragraph)))
         (case-fold-search t))
    (unless par
      (user-error "この画像には #+ATTR を付けられません(段落の中にありません)"))
    (save-excursion
      (goto-char (org-element-property :begin par))
      (if (re-search-forward my/org-image-attr-width-re
                             (org-element-property :post-affiliated par) t)
          (if width
              (replace-match (number-to-string width) t t nil 2)
            (replace-match "" t t nil 1)
            ;; 他の属性が並ぶ行では、消した箇所の前後で空白が二重になるので詰める
            (when (and (eq (char-before) ?\s) (looking-at-p " "))
              (delete-char 1))
            ;; 幅指定しか無かった行は、空の #+ATTR_ORG: が残るので行ごと消す
            (when (save-excursion
                    (beginning-of-line)
                    (looking-at-p "^[ \t]*#\\+attr_[^:]*:[ \t]*$"))
              (delete-region (line-beginning-position)
                             (min (point-max) (1+ (line-end-position))))))
        (when width
          ;; 段落本文の直前(既存の #+ATTR_* 等の後ろ)に新しく1行足す
          (goto-char (org-element-property :post-affiliated par))
          (insert (format "#+ATTR_ORG: :width %d\n" width)))))))

(defun my/org-image--redisplay ()
  "カーソル位置の段落のインライン画像を、いまの幅指定で表示し直す。
org-display-inline-images は refresh 付きでも既存オーバーレイを作り直さず
画像キャッシュを流すだけなので、幅を変えるには一度消してから表示する。"
  (let* ((link (my/org-image--link-at-point))
         (par (and link (org-element-lineage link '(paragraph))))
         (beg (if par (org-element-property :begin par) (line-beginning-position)))
         (end (if par (org-element-property :end par) (line-end-position))))
    (org-remove-inline-images beg end)
    (org-display-inline-images nil t beg end)))

(defvar my/org-image-resize-map
  (let ((map (make-sparse-keymap)))
    (define-key map "+" #'my/org-image-enlarge)
    (define-key map "=" #'my/org-image-enlarge) ; Shiftを押さずに拡大できるように
    (define-key map "-" #'my/org-image-shrink)
    map)
  "拡大/縮小の直後だけ有効になる一時キーマップ。+ / - を連打して詰められる。")

(defun my/org-image--resize (factor)
  "カーソル位置の画像の表示幅を FACTOR 倍にして、その場で表示し直す。"
  (unless (derived-mode-p 'org-mode)
    (user-error "org-modeのバッファではありません"))
  (let* ((link (or (my/org-image--link-at-point)
                   (user-error "カーソル位置に画像リンクがありません")))
         (new (max my/org-image-min-width
                   (round (* (my/org-image--current-width link) factor)))))
    (my/org-image--set-attr-width link new)
    (my/org-image--redisplay)
    ;; 続けて + / - を押すだけで調整できるようにする
    (set-transient-map my/org-image-resize-map t)
    (message "画像の表示幅: %dpx (+ / - で調整)" new)))

(defun my/org-image-enlarge ()
  "カーソル位置の画像の表示を `my/org-image-resize-step' 倍に拡大する。"
  (interactive)
  (my/org-image--resize my/org-image-resize-step))

(defun my/org-image-shrink ()
  "カーソル位置の画像の表示を `my/org-image-resize-step' 分の1に縮小する。"
  (interactive)
  (my/org-image--resize (/ 1.0 my/org-image-resize-step)))

(defun my/org-image-set-width (width)
  "カーソル位置の画像の表示幅(px)を WIDTH に設定する。
空入力なら幅指定を消して、org-image-actual-width の既定に戻す。"
  (interactive
   (list (let ((s (string-trim (read-string "表示幅(px、空入力で既定に戻す): "))))
           (cond ((string-empty-p s) nil)
                 ((> (string-to-number s) 0) (round (string-to-number s)))
                 (t (user-error "正の数を入力してください"))))))
  (unless (derived-mode-p 'org-mode)
    (user-error "org-modeのバッファではありません"))
  (let ((link (or (my/org-image--link-at-point)
                  (user-error "カーソル位置に画像リンクがありません"))))
    (my/org-image--set-attr-width link width)
    (my/org-image--redisplay)
    (set-transient-map my/org-image-resize-map t)
    (message (if width "画像の表示幅: %spx (+ / - で調整)" "画像の表示幅を既定に戻しました")
             width)))




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
