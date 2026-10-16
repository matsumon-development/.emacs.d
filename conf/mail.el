;;; mail.el --- メール(mu4e)の設定 -*- lexical-binding: t; -*-

;;; Commentary:

;; マウスを使わずEmacs内でメールを読み書きするための mu4e の設定。
;;
;; 他のパッケージと違い、mu4e の elisp は MELPA ではなく検索エンジン本体である
;; `mu' コマンドに同梱されて配布される。elisp とバイナリのバージョンが食い違うと
;; 動かないため、straight.el では管理せず Homebrew の mu を正とし、
;; `:straight nil' + mu の導入先を load-path に足す形で読み込む
;; (このリポジトリで lockfile による固定から外れる唯一の例外)。
;;
;; 外部コマンドの前提(いずれも brew で導入。詳細は README.org の「メール(mu4e)」):
;;   - mu     : メールのインデックス/検索エンジン + mu4e の elisp 同梱
;;   - isync  : mbsync コマンド。IMAP <-> ローカルMaildir の同期(受信側)
;;   - msmtp  : 送信(SMTP)。パスワードはmacOSキーチェーンから取り出す
;;
;; mu が入っていない環境(別マシン・初期セットアップ直後)でも起動時にエラーに
;; ならないよう、mu4e の elisp が見つかったときだけ設定を有効にする。
;; init.el では mylisp の後、keybind-manage の前に (load "mail") で読み込む。

;;; Code:

(require 'seq)

;; =====================================================================
;; 1. 個人設定(環境変数から受け取る)
;; =====================================================================
;; このリポジトリはGitHubで公開しているため、メールアドレス等の個人情報は
;; ファイルに直接書かず環境変数から受け取る(gptelのAPIキーと同じ方針)。
;;   export MY_MAIL_ADDRESS="you@gmail.com"
;;   export MY_MAIL_FULL_NAME="Your Name"   ; 省略時は user-full-name
(defvar my/mail-address (getenv "MY_MAIL_ADDRESS")
  "送信元メールアドレス。未設定ならmu4eの送信設定は既定値のまま。")

(defvar my/mail-full-name (or (getenv "MY_MAIL_FULL_NAME") user-full-name)
  "メールのFromに出す表示名。")

;; ローカルMaildirのルート。mbsync側(~/.mbsyncrc の MaildirStore)と揃えること。
;; フォルダ名はmbsyncのチャンネル定義で英語に寄せている(Gmailのフォルダ名は
;; アカウントの言語設定で変わり、日本語だとパスに全角が混ざって扱いづらいため)。
(defvar my/mail-maildir (expand-file-name "~/Mail")
  "mbsyncが同期先にするMaildirのルート。")

;; =====================================================================
;; 2. mu4e の elisp を探す
;; =====================================================================
;; mu4e は mu 本体に同梱されるので、mu の実行ファイルから導入先を逆算する。
;; Homebrew は share/emacs/site-lisp/mu/mu4e に置くが、ディストリによっては
;; share/emacs/site-lisp/mu4e 直下のこともあるため両方を候補にする。
(defun my/mu4e--locate-load-path ()
  "mu に同梱された mu4e の elisp ディレクトリを返す(見つからなければnil)。"
  (let* ((mu (executable-find "mu"))
         ;; symlink実体(Cellar配下)と、symlink経由のprefixの両方から候補を作る
         (prefixes (when mu
                     (mapcar (lambda (path)
                               ;; .../bin/mu -> ...
                               (file-name-directory
                                (directory-file-name (file-name-directory path))))
                             (list mu (file-truename mu))))))
    (seq-find
     #'file-directory-p
     (delete-dups
      (append
       (mapcan (lambda (prefix)
                 (list (expand-file-name "share/emacs/site-lisp/mu/mu4e" prefix)
                       (expand-file-name "share/emacs/site-lisp/mu4e" prefix)))
               prefixes)
       ;; PATHが通っていないGUI起動時のフォールバック
       '("/opt/homebrew/share/emacs/site-lisp/mu/mu4e"
         "/usr/local/share/emacs/site-lisp/mu/mu4e"))))))

(defvar my/mu4e-load-path (my/mu4e--locate-load-path)
  "mu4e の elisp ディレクトリ。nil なら mu 未導入とみなし設定を読み込まない。")

(when my/mu4e-load-path
  (add-to-list 'load-path my/mu4e-load-path))

;; =====================================================================
;; 3. mu4e 本体
;; =====================================================================
(use-package mu4e
  :straight nil ; elispはmu本体に同梱されるためstraight管理外(Commentary参照)
  :if my/mu4e-load-path
  ;; 起動時には読まない。キーバインド(keybind-manage.el)から呼ばれたときに読み込む。
  :commands (mu4e mu4e-compose-new mu4e-search mu4e-update-mail-and-index)
  :init
  ;; evilのキー操作をmu4eの各バッファ(main/headers/view/compose)にも効かせる。
  ;; evil-collection-init の対象は package-manage.el 側でまとめているが、mu4eは
  ;; mu未導入の環境ではそもそも使えないオプション扱いなので、ここで完結させる。
  (with-eval-after-load 'evil-collection
    (evil-collection-init 'mu4e))
  :custom
  ;; --- 受信 ---
  ;; 受信はEmacsからではなくmbsyncに任せる(Emacsをブロックしない・CLIでも同じ結果)
  (mu4e-get-mail-command "mbsync -a")
  (mu4e-update-interval (* 5 60))
  ;; mbsyncはファイル名のUIDを書き換えるため、mu4e側も移動時に名前を変える必要がある
  ;; (nilのままだとmbsyncが同期の度に重複メールを作る)
  (mu4e-change-filenames-when-moving t)
  ;; 自動更新のたびに「Indexing...」がエコーエリアへ出るのを抑える
  (mu4e-hide-index-messages t)
  (mu4e-headers-auto-update t)
  ;; --- フォルダ(mbsyncのチャンネル名に合わせる。README.orgの.mbsyncrc参照) ---
  (mu4e-drafts-folder "/gmail/drafts")
  (mu4e-sent-folder   "/gmail/sent")
  (mu4e-trash-folder  "/gmail/trash")
  ;; アーカイブ(refile)先。Gmailの「すべてのメール」に対応させる
  (mu4e-refile-folder "/gmail/archive")
  (mu4e-attachment-dir (expand-file-name "~/Downloads"))
  ;; --- 表示 ---
  ;; 日付は年月日を省略せず、一覧の桁を固定して目で追いやすくする
  (mu4e-headers-date-format "%Y-%m-%d %H:%M")
  (mu4e-headers-fields '((:human-date . 18)
                         (:flags      . 6)
                         (:from       . 26)
                         (:subject    . nil)))
  ;; Nerdフォント(Cica)を使っているので装飾文字はそのまま出せる
  (mu4e-use-fancy-chars t)
  (mu4e-view-show-images t)
  (mu4e-view-show-addresses t)
  ;; qで確認を挟まない(誤爆してもインデックスは壊れない)
  (mu4e-confirm-quit nil)
  ;; --- 作成 ---
  (mu4e-compose-dont-reply-to-self t)
  (mu4e-compose-complete-addresses t)
  ;; 過去に自分が送った相手だけを補完候補にする(MLやnoreplyで候補が埋まるのを防ぐ)
  (mu4e-compose-complete-only-personal t)
  ;; --- 検索 ---
  ;; ジャンプ先(jキー)。mbsyncのローカルフォルダ名と揃える
  (mu4e-maildir-shortcuts '((:maildir "/gmail/inbox"   :key ?i :name "受信トレイ")
                            (:maildir "/gmail/sent"    :key ?s :name "送信済み")
                            (:maildir "/gmail/drafts"  :key ?d :name "下書き")
                            (:maildir "/gmail/archive" :key ?a :name "アーカイブ")
                            (:maildir "/gmail/trash"   :key ?t :name "ゴミ箱")))
  (mu4e-bookmarks '((:name "未読" :query "flag:unread AND NOT flag:trashed" :key ?u)
                    (:name "今日" :query "date:today..now" :key ?t)
                    (:name "今週" :query "date:7d..now" :key ?w)
                    (:name "添付あり" :query "mime:application/* AND NOT flag:trashed" :key ?a)
                    (:name "下書き" :query "flag:draft" :key ?d)))
  :config
  ;; C-x m など、Emacs標準のメール作成もmu4eへ寄せる
  (setq mail-user-agent 'mu4e-user-agent)
  (when my/mail-address
    (setq user-mail-address my/mail-address))
  (when my/mail-full-name
    (setq user-full-name my/mail-full-name))

  ;; Gmailは送信時にサーバ側で「送信済み」へ控えを残すため、ローカルにも保存すると
  ;; 二重になる。mu4e 1.12前後で扱いが変わった変数なので、ある場合だけ設定する。
  (when (boundp 'mu4e-sent-messages-behavior)
    (setq mu4e-sent-messages-behavior 'delete))

  ;; macOSの通知センターへ新着を出す(mu4e 1.12以降)
  (when (boundp 'mu4e-notification-support)
    (setq mu4e-notification-support t))

  ;; 送信はmsmtpに委譲する。Emacsにパスワードを持たせず、msmtp側の passwordeval
  ;; 経由でmacOSキーチェーンから取り出せるのが利点(~/.msmtprc はREADME参照)。
  ;; msmtpが無い環境ではEmacs標準のsmtpmailにフォールバックする。
  (if (executable-find "msmtp")
      (setq message-send-mail-function #'message-send-mail-with-sendmail
            sendmail-program (executable-find "msmtp")
            ;; msmtpは -f の解釈が独自なので、Message側から渡させない
            message-sendmail-f-is-evil t
            ;; Fromヘッダからアカウントを選ばせる(複数アカウントに備える)
            message-sendmail-extra-arguments '("--read-envelope-from"))
    (setq message-send-mail-function #'smtpmail-send-it))

  ;; 送信バッファはウィンドウごと消す(メール作成後にバッファが残らないように)
  (setq message-kill-buffer-on-exit t)

  ;; init.elで日本語環境にしているため、Gnus/Message側の既定では本文が
  ;; ISO-2022-JPで送られる(mm-coding-system-prioritiesが日本語環境で
  ;; '(iso-8859-1 iso-2022-jp utf-8) になる)。今どきの相手にはUTF-8が無難なので
  ;; 優先順位を入れ替える。絵文字や機種依存文字が化けるのも防げる。
  (with-eval-after-load 'mm-util
    (setq mm-coding-system-priorities '(utf-8 iso-8859-1 iso-2022-jp)))

  ;; 日本語は単語間に空白が無く format=flowed の再折り返しと相性が悪いため使わない。
  ;; 代わりに作成バッファでは見た目の折り返し(visual-line)だけを効かせる。
  (add-hook 'mu4e-compose-mode-hook #'turn-off-auto-fill)
  (add-hook 'mu4e-compose-mode-hook #'visual-line-mode))
