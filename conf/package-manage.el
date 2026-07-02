;;----------------------------------------------------------------------------------------
;;                 テキストエディット
;;----------------------------------------------------------------------------------------

;;vimにする
(use-package evil
  :straight t
  :init
  (setq evil-want-keybinding nil) ; evil-collection使用のため、evilロード前にnilにする
  (evil-mode 1)
  :config
  (setq evil-emacs-state-cursor    '("#E74C3C" box))
  (setq evil-normal-state-cursor   '("#2ECC71" box))
  (setq evil-visual-state-cursor   '("#E67E22" box))
  (setq evil-insert-state-cursor   '("#E74C3C" bar))
  (setq evil-replace-state-cursor  '("#E74C3C" bar))
  (setq evil-operator-state-cursor '("#E74C3C" hollow)))




;;----------------------------------------------------------------------------------------
;;                 エディタの見た目
;;----------------------------------------------------------------------------------------

;;テーマ
(use-package doom-themes
  :straight t
  :custom
  (doom-themes-enable-italic t)
  (doom-themes-enable-bold t)
  :custom-face
  (doom-modeline-bar ((t (:background "#6272a4"))))   ;;一番左の色
  :config
  (doom-themes-neotree-config)
  (doom-themes-org-config)
  (setq my-themes '(doom-dracula doom-wilmersdorf  doom-solarized-light))
  (setq curr-theme my-themes)
  (load-theme 'doom-wilmersdorf t)
  (defun theme-cycle ()
    (interactive)
    (disable-theme (car curr-theme))
    (setq curr-theme (cdr curr-theme))
    (if (null curr-theme) (setq curr-theme my-themes))
    (load-theme (car curr-theme) t)
    (message "%s" (car curr-theme)))
  (load-theme (car curr-theme) t)
  )


;;モードライン
(use-package doom-modeline
  :straight t
  :after doom-themes
  :custom
  (doom-modeline-buffer-file-name-style 'truncate-with-project)
  (doom-modeline-icon t)
  (doom-modeline-major-mode-icon t)
  (doom-modeline-major-mode-color-icon t)
  (doom-modeline-minor-modes nil)
  (doom-modeline-enable-word-count t)
  (doom-modeline-buffer-encoding t)
  (doom-modeline-indent-info t)
  (doom-modeline-lsp t)
  :hook
  (after-init . doom-modeline-mode)
  :after (evil)
  :config
  (line-number-mode t)
  (column-number-mode t)
  (display-time-mode t)
  (doom-modeline-def-segment evil-state
    "The current evil state.  Requires `evil-mode' to be enabled."
    (when (bound-and-true-p evil-local-mode)
      (s-trim-right (evil-state-property evil-state :tag t))))
  (setq evil-normal-state-tag   (propertize "[N]" 'face '((:background "DodgerBlue2" :foreground "white"))))
  (setq evil-emacs-state-tag    (propertize "[E]" 'face '((:background "MediumOrchid1" :foreground "white"))))
  (setq evil-insert-state-tag   (propertize "[I]" 'face '((:background "ForestGreen") :foreground "white")))
  (setq evil-visual-state-tag   (propertize "[V]" 'face '((:background "LightSteelBlue4" :foreground "white"))))
  (setq evil-motion-state-tag   (propertize "[M]" 'doom-modeline-evil-motion-state '((:background "blue") :foreground "white")))
  (setq evil-operator-state-tag (propertize "[O]" 'doom-modeline-evil-operator-state '((:background "purple") :foreground "white")))
  (doom-modeline-def-modeline
    'main
    '(bar window-number evil-state matches buffer-info remote-host buffer-position  parrot selection-info)
    '(misc-info persp-name github debug minor-modes input-method buffer-encoding major-mode process vcs checker))
  )




;;imenuとneotreeのモードラインを非表示にする
(use-package hide-mode-line
  :straight t
  :hook
  ((treemacs-mode neotree-mode imenu-list-minor-mode ) . hide-mode-line-mode))





;;対応する括弧の色を合わせる
(use-package rainbow-delimiters
  :straight t
  :hook
  (prog-mode . rainbow-delimiters-mode)
  :custom
  (rainbow-delimiters-outermost-only-face-count 1)
  :custom-face
  (rainbow-delimiters-depth-1-face ((t (:foreground "#9a4040"))))
  (rainbow-delimiters-depth-2-face ((t (:foreground "#ff5e5e"))))
  (rainbow-delimiters-depth-3-face ((t (:foreground "#ffaa77"))))
  (rainbow-delimiters-depth-4-face ((t (:foreground "#dddd77"))))
  (rainbow-delimiters-depth-5-face ((t (:foreground "#80ee80"))))
  (rainbow-delimiters-depth-6-face ((t (:foreground "#66bbff"))))
  (rainbow-delimiters-depth-7-face ((t (:foreground "#da6bda"))))
  (rainbow-delimiters-depth-8-face ((t (:foreground "#afafaf"))))
  (rainbow-delimiters-depth-9-face ((t (:foreground "#f0f0f0"))))
  :config
  (show-paren-mode t)                                             ; 対応する括弧を 光らせる
  (set-face-background 'show-paren-match "GhostWhite")            ; 対応する括弧のバックグラウンドを白色にする
  )




;;インデントのスペースに色をつける
(use-package highlight-indent-guides
  :straight t
  :diminish
  :hook
  ((prog-mode yaml-mode) . highlight-indent-guides-mode)
  :custom
  (highlight-indent-guides-auto-enabled nil)
  (highlight-indent-guides-responsive t)
  (highlight-indent-guides-method 'fill)
  :custom-face
  (highlight-indent-guides-even-face       ((t (:background "#1F3466" :foreground "#505050"))))
  (highlight-indent-guides-odd-face        ((t (:background "#00464A" :foreground "#505050"))))
  (highlight-indent-guides-top-even-face   ((t (:background "#1F3466" :foreground "#505050"))))
  (highlight-indent-guides-top-odd-face    ((t (:background "#00464A" :foreground "#505050"))))
  (highlight-indent-guides-stack-even-face ((t (:background "#1F3466" :foreground "#505050"))))
  (highlight-indent-guides-stack-odd-face  ((t (:background "#00464A" :foreground "#505050"))))
  )





;;ペーストなど目立たせる
(use-package volatile-highlights
  :straight t
  :diminish
  :hook
  (after-init . volatile-highlights-mode)
  :custom-face
  (vhl/default-face ((nil (:foreground "#FF3333" :background "#FFCDCD")))))




;;アイコンの追加
(use-package all-the-icons-ivy
  :straight t
  :if (display-graphic-p)
  :init (add-hook 'after-init-hook 'all-the-icons-ivy-setup))

(use-package ivy-rich
  :straight t
  :if       (display-graphic-p)
  :after    (ivy)
  :init     (ivy-rich-mode 1)
  :custom
  (ivy-rich-path-style 'abbrev)
  (ivy-virtual-abbreviate 'full)
  :config (setcdr (assq t ivy-format-functions-alist) #'ivy-format-function-line))

(use-package all-the-icons-ivy-rich
  :straight t
  :if       (display-graphic-p)
  :init     (all-the-icons-ivy-rich-mode 1)
  :custom
  (all-the-icons-ivy-rich-icon-size 1.0)
  (inhibit-compacting-font-caches t))

(use-package all-the-icons
  :straight (all-the-icons :type git :host github :repo "domtronn/all-the-icons.el")
  :if       (display-graphic-p)
  :custom   (all-the-icons-scale-factor 1.0))

(use-package all-the-icons-dired
  :straight t
  :if       (display-graphic-p)
  :hook     (dired-mode . all-the-icons-dired-mode))


;;色コードを記入した文字のバックグラウンド色をその色にする
(use-package rainbow-mode
  :straight t
  :commands (rainbow-mode)
  :hook     ((css-mode html-mode web-mode emacs-lisp-mode) . rainbow-mode))


;;ウィンドウを透けさせる
(use-package cycle-frame-transparency
  :straight (cycle-frame-transparency :type git :host github :repo "blue0513/cycle-frame-transparency")
  :custom   (cft--trasparent 90))



;;----------------------------------------------------------------------------------------
;;                 別ウィンドウの設定
;;----------------------------------------------------------------------------------------

;;最近開いたファイルを表示する
(use-package recentf
  :straight t
  :init (recentf-mode 1)
  :custom
  (recentf-max-saved-items 2000) ;; 2000ファイルまで履歴保存する
  (recentf-auto-cleanup 'never)  ;; 存在しないファイルは消さない
  (recentf-exclude
   '("/recentf"
     "COMMIT_EDITMSG"
     "/.?TAGS"
     "^/sudo:"
     "/\\.emacs\\.d/games/*-scores"
     "/\\.emacs\\.d/\\.cask/"))
  (recentf-auto-save-timer (run-with-idle-timer 30 t 'recentf-save-list)))




(use-package neotree
  :straight t
  :init (setq-default neo-keymap-style 'concise)
  :preface
  ;; Change neotree's font size
  ;; Tips from https://github.com/jaypei/emacs-neotree/issues/218
  (defun neotree-text-scale ()
    "Text scale for neotree."
    (interactive)
    (text-scale-adjust 0)
    (text-scale-decrease 1)
    (message nil))
  ;; neotree enter hide
  ;; Tips from https://github.com/jaypei/emacs-neotree/issues/77
  (defun neo-open-file-hide (full-path &optional arg)
    "Open file and hiding neotree.
The description of FULL-PATH & ARG is in `neotree-enter'."
    (neo-global--select-mru-window arg)
    (find-file full-path)
    (neotree-hide))
  (defun neotree-enter-hide (&optional arg)
    "Neo-open-file-hide if file, Neo-open-dir if dir.
The description of ARG is in `neo-buffer--execute'."
    (interactive "P")
    (neo-buffer--execute arg 'neo-open-file-hide 'neo-open-dir))
  :bind
  (:map evil-normal-state-map ("SPC f t" . neotree-toggle))
  (:map dired-mode-map ("C-f t" . neotree-toggle))
  (:map neotree-mode-map
        ("RET" . 'neotree-enter-hide)
        ("a" . neotree-hidden-file-toggle)
        ("<left>" . neotree-select-up-node)
        ("<right>" . neotree-change-root))
  :custom
  (neo-smart-open t)
  (neo-create-file-auto-open t)
  (neo-theme (if (display-graphic-p) 'icons 'arrow))
  :config
  (add-hook 'neo-after-create-hook (lambda (_) (call-interactively 'neotree-text-scale))))


(use-package treemacs
  :straight t
  :defer t
  :init
  (with-eval-after-load 'winum
    (define-key winum-keymap (kbd "M-0") #'treemacs-select-window))
  :config
  (progn
    (setq treemacs-collapse-dirs                   (if treemacs-python-executable 3 0)
          treemacs-deferred-git-apply-delay        0.5
          treemacs-directory-name-transformer      #'identity
          treemacs-display-in-side-window          t
          treemacs-eldoc-display                   'simple
          treemacs-file-event-delay                2000
          treemacs-file-extension-regex            treemacs-last-period-regex-value
          treemacs-file-follow-delay               0.2
          treemacs-file-name-transformer           #'identity
          treemacs-follow-after-init               t
          treemacs-expand-after-init               t
          treemacs-find-workspace-method           'find-for-file-or-pick-first
          treemacs-git-command-pipe                ""
          treemacs-goto-tag-strategy               'refetch-index
          treemacs-header-scroll-indicators        '(nil . "^^^^^^")
          treemacs-hide-dot-git-directory          t
          treemacs-indentation                     2
          treemacs-indentation-string              " "
          treemacs-is-never-other-window           nil
          treemacs-max-git-entries                 5000
          treemacs-missing-project-action          'ask
          treemacs-move-forward-on-expand          nil
          treemacs-no-png-images                   nil
          treemacs-no-delete-other-windows         t
          treemacs-project-follow-cleanup          nil
          treemacs-persist-file                    (expand-file-name ".cache/treemacs-persist" user-emacs-directory)
          treemacs-position                        'left
          treemacs-read-string-input               'from-child-frame
          treemacs-recenter-distance               0.1
          treemacs-recenter-after-file-follow      nil
          treemacs-recenter-after-tag-follow       nil
          treemacs-recenter-after-project-jump     'always
          treemacs-recenter-after-project-expand   'on-distance
          treemacs-litter-directories              '("/node_modules" "/.venv" "/.cask")
          treemacs-project-follow-into-home        nil
          treemacs-show-cursor                     nil
          treemacs-show-hidden-files               t
          treemacs-silent-filewatch                nil
          treemacs-silent-refresh                  nil
          treemacs-sorting                         'alphabetic-asc
          treemacs-select-when-already-in-treemacs 'move-back
          treemacs-space-between-root-nodes        t
          treemacs-tag-follow-cleanup              t
          treemacs-tag-follow-delay                1.5
          treemacs-text-scale                      nil
          treemacs-user-mode-line-format           nil
          treemacs-user-header-line-format         nil
          treemacs-wide-toggle-width               70
          treemacs-width                           35
          treemacs-width-increment                 1
          treemacs-width-is-initially-locked       t
          treemacs-workspace-switch-cleanup        nil)

    ;; The default width and height of the icons is 22 pixels. If you are
    ;; using a Hi-DPI display, uncomment this to double the icon size.
    ;;(treemacs-resize-icons 44)

    (treemacs-follow-mode t)
    (treemacs-filewatch-mode t)
    (treemacs-fringe-indicator-mode 'always)
    (when treemacs-python-executable
      (treemacs-git-commit-diff-mode t))

    (pcase (cons (not (null (executable-find "git")))
                 (not (null treemacs-python-executable)))
      (`(t . t)
       (treemacs-git-mode 'deferred))
      (`(t . _)
       (treemacs-git-mode 'simple)))

    (treemacs-hide-gitignored-files-mode nil))
  :bind
  (nil :map global-map
       ("M-0"       . treemacs-select-window)
       ("C-x t 1"   . treemacs-delete-other-windows)
       ("C-x t t"   . treemacs)
       ("C-x t d"   . treemacs-select-directory)
       ("C-x t B"   . treemacs-bookmark)
       ("C-x t C-t" . treemacs-find-file)
       ("C-x t M-t" . treemacs-find-tag))
  :hook
  (treemacs-mode . (lambda () (text-scale-adjust -1)) )
  )






(use-package imenu-list
  :straight t
  :custom-face
  (imenu-list-entry-face-1 ((t (:foreground "white"))))
  :custom
  (imenu-list-focus-after-activation t)
  (imenu-list-auto-resize nil))





(use-package minimap
  :straight t
  :commands
  (minimap-create minimap-kill minimap-get-window)
  :custom
  (minimap-window-location 'right)
  (minimap-update-delay 0.2)
  (minimap-minimum-width 20)
  :bind
  (:map evil-normal-state-map ("SPC t m" . ladicle/toggle-minimap))
  :preface
  (defun ladicle/toggle-minimap ()
    "Toggle minimap for current buffer."
    (interactive)
    (if (null (minimap-get-window))
        (minimap-create)
      (minimap-kill)))
  :config
  (custom-set-faces
   '(minimap-active-region-background
     ((((background dark)) (:background "#555555555555"))
      (t (:background "#C847D8FEFFFF"))) :group 'minimap)))


;;----------------------------------------------------------------------------------------
;;                 Dired
;;----------------------------------------------------------------------------------------

;; その他の基本設定(dired-listing-switches、trash連携、詳細非表示など)はbasic.elに集約している

;; diredはevilのnormal-stateだと単一キーのネイティブコマンド(R:rename, C:copy等)が
;; vi的キーバインドと衝突するため、emacs-stateで起動して素のdired-mode-mapを使う
(evil-set-initial-state 'dired-mode 'emacs)

(use-package dired-subtree
  :straight t
  :after dired
  )

;; スペースキー等の操作でファイルをプレビュー(Finderのクイックルック相当)
(use-package dired-preview
  :straight t
  :hook (dired-mode . dired-preview-mode)
  :custom
  (dired-preview-delay 0.2)
  (dired-preview-max-size (* 10 1024 1024)))
;;----------------------------------------------------------------------------------------
;;                 補完
;;----------------------------------------------------------------------------------------

(use-package corfu
  :straight (corfu :type git :host github :repo "minad/corfu" :files (:defaults "extensions/*"))
  :custom (
           (corfu-auto t)
           (corfu-auto-prefix 1)
           (corfu-auto-delay 0)
           (corfu-cycle t)
           (corfu-preselect-first t)
           (tab-always-indent 'complete))
  :bind (nil
         :map corfu-map
         ("RET" . nil)
         ("<return>" . nil)
         ("TAB" . corfu-insert)
         ("<tab>" . corfu-insert))
  :init (global-corfu-mode +1)

  :config
  ;; java-mode などの一部のモードではタブに `c-indent-line-or-region` が割り当てられているので、
  ;; 補完が出るように `indent-for-tab-command` に置き換える
  (defun my/corfu-remap-tab-command ()
    (global-set-key [remap c-indent-line-or-region] #'indent-for-tab-command))
  (add-hook 'java-mode-hook #'my/corfu-remap-tab-command)

  ;; ミニバッファー上でverticoによる補完が行われない場合、corfuの補完が出るようにします。
  (defun corfu-enable-always-in-minibuffer ()
    "Enable Corfu in the minibuffer if Vertico/Mct are not active."
    (unless (or (bound-and-true-p mct--active)
                (bound-and-true-p vertico--input))
      ;; (setq-local corfu-auto nil) ;; Enable/disable auto completion
      (setq-local corfu-echo-delay nil ;; Disable automatic echo and popup
                  corfu-popupinfo-delay nil)
      (corfu-mode 1)))
  (add-hook 'minibuffer-setup-hook #'corfu-enable-always-in-minibuffer 1))


(use-package corfu-popupinfo
  :after corfu
  :config
  (corfu-popupinfo-mode +1))


(use-package company-tabnine
  :straight (company-tabnine :type git :host github :repo "karta0807913/company-tabnine"))




;;(use-package cape
;;  :straight t
;;  :hook ((prog-mode . my/set-basic-capf)
;;         (text-mode . my/set-basic-capf)
;;         (meghanada-mode . my/set-meghanada-capf)
;;         (lsp-completion-mode . my/set-lsp-capf))
;;  :config
;;  (defun my/convert-super-capf (arg-capf)
;;    (list (cape-capf-case-fold
;;           (cape-super-capf arg-capf
;;                            (cape-company-to-capf #'company-yasnippet)
;;                            (cape-company-to-capf #'company-tabnine)))
;;          #'cape-file
;;          #'cape-dabbrev))
;;
;;  (defun my/set-basic-capf ()
;;    (setq-local completion-at-point-functions (my/convert-super-capf (car completion-at-point-functions))))
;;
;;  (defun my/set-meghanada-capf ()
;;    (setq-local completion-at-point-functions (my/convert-super-capf (cape-company-to-capf #'company-meghanada))))
;;
;;  (defun my/set-lsp-capf ()
;;    (setq-local completion-at-point-functions (my/convert-super-capf #'lsp-completion-at-point)))
;;
;;  (add-to-list 'completion-at-point-functions (cape-company-to-capf #'company-tabnine) t)
;;  (add-to-list 'completion-at-point-functions #'cape-file t)
;;  (add-to-list 'completion-at-point-functions #'cape-tex t)
;;  (add-to-list 'completion-at-point-functions #'cape-dabbrev t)
;;  (add-to-list 'completion-at-point-functions #'cape-keyword t))



(use-package orderless
  :straight t
  :custom ((completion-styles '(orderless))
           (completion-category-defaults nil)
           (completion-category-overrides nil))
  :hook (corfu-mode . (lambda () (setq-local orderless-matching-styles '(orderless-flex)))))



(use-package prescient
  :straight t
  :config
  (prescient-persist-mode +1))



(use-package corfu-prescient
  :straight t
  :after corfu
  :init
  (with-eval-after-load 'orderless
    ;; prescientではなく、補完スタイルを使用して絞り込む
    (setq corfu-prescient-enable-filtering nil
          corfu-prescient-override-sorting t))
  :config
  (corfu-prescient-mode +1))



(use-package kind-icon
  :straight t
  :after corfu
  :custom (kind-icon-default-face 'corfu-default) ; to compute blended backgrounds correctly
  :config (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))



(use-package yasnippet
  :straight t
  :diminish yas-minor-mode
  :custom (yas-snippet-dirs '("~/.emacs.d/snippets"))
  :hook (after-init . yas-global-mode)
  :init (yas-global-mode +1)
  :bind
  ((:map yas-keymap
         ("C-<tab>" . nil)
         ("<tab>"   . nil))  ; for company
   (:map yas-minor-mode-map
         ("<tab>"   . nil)
         ("C-<tab>" . nil)
         ("C-c y e" . yas-expand)
         ("C-c y i" . yas-insert-snippet)
         ("C-c y n" . yas-new-snippet)
         ("C-c y v" . yas-visit-snippet-file)
         ("C-c y l" . yas-describe-tables)
         ("C-c y g" . yas-reload-all))))



;;; flymake
(use-package flycheck
  :straight t
  :hook
  ((prog-mode yaml-mode) . flycheck-mode )
  :bind
  (:map evil-normal-state-map ("SPC t f" . flycheck-mode)))




;;----------------------------------------------------------------------------------------
;;                 IME
;;----------------------------------------------------------------------------------------

;;日本語IME
(when (eq system-type 'windows-nt)
  (use-package tr-ime
    :straight t
    :config
    (tr-ime-standard-install)
    (setq default-input-method "W32-IME")
    (w32-ime-initialize)
    (add-hook 'minibuffer-setup-hook 'deactivate-input-method))
  )



;;----------------------------------------------------------------------------------------
;;                 その他
;;----------------------------------------------------------------------------------------

;;スタート画面をダッシュボードにする
(use-package dashboard
  :straight t
  :init
  (dashboard-setup-startup-hook))


(use-package cond-let
  :straight t)
(use-package llama
  :straight t)
(use-package transient
  :straight t)
(use-package with-editor
  :straight t)
(use-package magit-section
  :straight t)
(use-package magit
  :straight t
  :custom
  (magit-refs-show-commit-count 'all)
  (magit-auto-revert-mode nil)
  (magit-log-buffer-file-locked t)
  (magit-revision-show-gravatars nil)
  (magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1))
(remove-hook 'server-switch-hook 'magit-commit-diff)
(remove-hook 'with-editor-filter-visit-hook 'magit-commit-diff)
(use-package evil-collection
  :straight t
  :after (evil magit)
  :config
  (evil-collection-init '(magit vterm)))


(use-package which-key
  :straight t
  :diminish which-key-mode
  :config (which-key-setup-side-window-right-bottom)
  :hook (after-init . which-key-mode))




;;amx コマンドを打ったときに一緒にwhich-keyにkeybindを表示する
(use-package amx
  :straight t
  :config (amx-mode))





(use-package ivy
  :straight t
  :init (ivy-mode 1)
  :custom
  (ivy-use-virtual-buffers t)
  (enable-recursive-minibuffers t)
  (ivy-height 30)
  ;;(ivy-extra-directories nil);;ivyに.と..を表示させない
  (ivy-re-builders-alist '((t . ivy--regex-plus))))




(use-package ivy-posframe
  :straight t
  :init (ivy-posframe-mode 1)
  :custom
  (ivy-posframe-display-functions-alist '((t . ivy-posframe-display-at-window-center))))



;;カレントバッファがGit管理下の場合、左に直前のコミットの差分を表示する
(use-package git-gutter+
  :straight t
  :custom
  (git-gutter+-window-width 1)
  (git-gutter+-modified-sign "~")
  (git-gutter+-added-sign    "+")
  (git-gutter+-deleted-sign  "-")
  :custom-face
  (git-gutter+-modified ((t (:background "#f1fa8c"))))
  (git-gutter+-added    ((t (:background "#50fa7b"))))
  (git-gutter+-deleted  ((t (:background "#ff79c6"))))
  :config
  (global-git-gutter+-mode +1))


;;;;Emacs Application Framework
;;(add-to-list 'load-path "~/.emacs.d/site-lisp/emacs-application-framework/")
;;(require 'eaf)
;;(require 'eaf-git)
;;(add-hook 'eaf-mode-hook #'evil-emacs-state)
;;(require 'eaf-markdown-previewer)



;; =====================================================================
;; 1. 自動ファイル更新設定（Claude Code の変更を即座に隣のバッファに反映）
;; =====================================================================
(use-package autorevert
  :straight nil ; 組み込み機能のためインストール不要
  :hook (after-init . global-auto-revert-mode)
  :custom
  ;; 外部でのファイル変更を検知する間隔（秒）。デフォルトより短くしてVSCode感覚に
  (auto-revert-interval 0.5)
  ;; ファイル以外のバッファ（diredなど）も自動更新
  (global-auto-revert-non-file-buffers t)
  ;; バッファが書き換わった際のミニバッファへの通知を静かにする
  (auto-revert-verbose nil))

;; =====================================================================
;; 2. vterm 設定（自律エージェント Claude Code 起動用）
;; =====================================================================
(use-package vterm
  :straight t
  :commands vterm
  :init
  ;; -------------------------------------------------------------------
  ;; 0. 【共通】vtermバッファをモニターの向きに関わらず下側に分割表示する
  ;;    入力欄が見えれば十分な小さめのサイズ(3:7)で開始する。
  ;;    入力行数に応じた拡大はkeybind-manage.el側で行う。
  ;; -------------------------------------------------------------------
  (defvar my/vterm-window-ratio 0.3
    "vtermウィンドウの初期サイズ(フレームに対する割合)。")

  (defvar my/vterm-window-max-ratio 0.7
    "入力行数が増えた際にvtermウィンドウが広がる上限(フレームに対する割合)。")

  (defun my/vterm-pop-to-buffer (buffer-or-name)
    "BUFFER-OR-NAMEを常にウィンドウの下側に分割表示する。
vtermウィンドウはmy/vterm-window-ratio程度の小さめのサイズで開始する。"
    (let* ((vterm-size (max 1 (round (* (frame-height) my/vterm-window-ratio))))
           (win (split-window (selected-window) (- vterm-size) 'below)))
      (set-window-buffer win buffer-or-name)
      (select-window win)))

  (defun my/vterm-pop-to-buffer-oriented (buffer-or-name)
    "BUFFER-OR-NAMEをモニターの向きに応じて分割表示する。
横長モニター: 右(right)、縦長モニター: 上(above)。"
    (let* ((portrait-p (< (frame-pixel-width) (frame-pixel-height)))
           (side (if portrait-p 'above 'right))
           (total (if portrait-p (frame-height) (frame-width)))
           (vterm-size (max 1 (round (* total my/vterm-window-ratio))))
           (win (split-window (selected-window) (- vterm-size) side)))
      (set-window-buffer win buffer-or-name)
      (select-window win)))

  (defun my/vterm-get-or-create (buffer-name &optional pop-fn)
    "BUFFER-NAMEのvtermバッファを取得または新規作成して分割表示し、バッファを返す。
POP-FN(省略時はmy/vterm-pop-to-buffer)でウィンドウへの表示方法を指定できる。"
    (let ((pop-fn (or pop-fn #'my/vterm-pop-to-buffer)))
      (if (get-buffer buffer-name)
          (progn (funcall pop-fn buffer-name) (get-buffer buffer-name))
        ;; vterm-mode自体はautoload対象外のため、明示的にvterm.elをロードする
        (require 'vterm)
        (let ((buf (generate-new-buffer buffer-name)))
          (funcall pop-fn buf)
          (with-current-buffer buf
            (unless (derived-mode-p 'vterm-mode) (vterm-mode)))
          buf))))

  ;; -------------------------------------------------------------------
  ;; 0.5 Claude Codeを表示しているvtermバッファを識別するためのマイナーモード。
  ;;     プレーンなvterm端末(my/run-vterm-current-dir)とは区別し、
  ;;     Claude Code固有のキーバインドやフックはこのモード経由で追加していく。
  ;; -------------------------------------------------------------------
  (define-minor-mode my/claude-code-mode
    "Claude Codeをvtermでやりとりしているバッファであることを示すマイナーモード。"
    :lighter " Claude"
    :keymap (make-sparse-keymap))

  ;; -------------------------------------------------------------------
  ;; 0.6 プロセス終了時、バッファだけでなくそれを表示していたウィンドウも閉じる。
  ;;     バッファ自体はvterm-kill-buffer-on-exit(デフォルトt)で既に自動削除されるが、
  ;;     ウィンドウ(split)は残ってしまうため、exitで両方消えるようにする。
  ;; -------------------------------------------------------------------
  (defun my/vterm-close-window-on-exit (buffer _event)
    "vtermのプロセスが終了したとき、BUFFERを表示しているウィンドウも閉じる。"
    (when (buffer-live-p buffer)
      (dolist (win (get-buffer-window-list buffer nil t))
        (when (window-live-p win)
          (ignore-errors (delete-window win))))))
  (add-hook 'vterm-exit-functions #'my/vterm-close-window-on-exit)

  ;; -------------------------------------------------------------------
  ;; 1. 【新規】普通のカレントディレクトリで通常のターミナルを開く
  ;; -------------------------------------------------------------------
  (defun my/run-vterm-current-dir ()
    "現在のバッファのディレクトリで、通常のターミナル（vterm）を起動します。"
    (interactive)
    (let* ((current-dir default-directory)
           ;; 現在のフォルダ名を取得（バッファ名用）
           (dir-name (file-name-nondirectory (directory-file-name current-dir)))
           (buffer-name (format "*vterm:%s*" dir-name)))
      (my/vterm-get-or-create buffer-name)))

  ;; -------------------------------------------------------------------
  ;; 2. 【既存】プロジェクトルートで Claude Code を起動する
  ;; -------------------------------------------------------------------
  ;; vc-root-dirはファイル自体がVCに追跡されている場合しか使えないため、
  ;; .gitの存在だけでルートを判定できるproject-currentを使う
  (defun my/claude-code-project-root ()
    "現在のプロジェクトルートを返す(project.elが検出できない場合はdefault-directory)。"
    (let ((proj (project-current)))
      (expand-file-name (if proj (project-root proj) default-directory))))

  (defun my/claude-code-buffer-name (&optional project-root)
    "PROJECT-ROOT(省略時は現在のプロジェクトルート)に対応するClaude Codeバッファ名を返す。"
    (let* ((root (or project-root (my/claude-code-project-root)))
           (project-name (file-name-nondirectory (directory-file-name root))))
      (format "*claude-code:%s*" project-name)))

  (defun my/run-claude-code ()
    "現在のプロジェクトルートで Claude Code を起動します。"
    (interactive)
    (let* ((project-root (my/claude-code-project-root))
           (buffer-name (my/claude-code-buffer-name project-root))
           (existed (get-buffer buffer-name))
           (buf (my/vterm-get-or-create buffer-name #'my/vterm-pop-to-buffer-oriented)))
      (with-current-buffer buf
        (my/claude-code-mode 1))
      (unless existed
        (with-current-buffer buf
          (vterm-send-string (format "cd %s && claude\n" (shell-quote-argument project-root)))))))

  ;; -------------------------------------------------------------------
  ;; 2.5 【新規】Claude Codeを別フレームに切り出す
  ;; -------------------------------------------------------------------
  (defun my/claude-code-pop-to-frame ()
    "現在のプロジェクトのClaude Codeバッファを別フレームに切り出す。
すでに他のフレームで表示されていればそのフレームを選択するだけにする。
現在のフレームでウィンドウ分割表示されていれば、そのウィンドウは閉じる。
別フレームに出すだけなので、現在のフレームでの分割表示(split-window)は行わない。"
    (interactive)
    (let* ((project-root (my/claude-code-project-root))
           (buffer-name (my/claude-code-buffer-name project-root))
           (existed (get-buffer buffer-name))
           (other-frame-win
            (and existed
                 (seq-find (lambda (win) (not (eq (window-frame win) (selected-frame))))
                           (get-buffer-window-list existed nil t)))))
      (if other-frame-win
          (progn
            (select-frame-set-input-focus (window-frame other-frame-win))
            (select-window other-frame-win))
        (let* ((current-frame-win
                (and existed
                     (seq-find (lambda (win) (eq (window-frame win) (selected-frame)))
                               (get-buffer-window-list existed nil t))))
               ;; 現在のフレームがすでにこのバッファ専用(唯一のウィンドウ)になっているか
               (frame-dedicated-p
                (and current-frame-win
                     (= (length (window-list (selected-frame))) 1))))
          (if frame-dedicated-p
              ;; すでに専用フレームでそのまま表示されているだけなので何もしない
              (select-window current-frame-win)
            (let (buf)
              (if existed
                  (setq buf existed)
                (require 'vterm)
                (setq buf (generate-new-buffer buffer-name))
                (with-current-buffer buf
                  (vterm-mode)))
              (with-current-buffer buf
                (my/claude-code-mode 1))
              (unless existed
                (with-current-buffer buf
                  (vterm-send-string (format "cd %s && claude\n" (shell-quote-argument project-root)))))
              ;; 現在のフレームで分割表示されていれば、そのウィンドウだけ閉じる
              (dolist (win (get-buffer-window-list buf nil t))
                (when (eq (window-frame win) (selected-frame))
                  (delete-window win)))
              (select-frame-set-input-focus (make-frame '((name . "Claude Code"))))
              (switch-to-buffer buf)))))))) 
;; =====================================================================
;; 3. gptel 設定（エディタ一体型インライン書き換え & チャット用）
;; =====================================================================
(use-package gptel
  :straight t
  :commands (gptel gptel-menu)
  :init
  ;; 環境変数からAPIキーを取得
  (setq gptel-api-key (lambda () (getenv "ANTHROPIC_API_KEY")))
  :config
  ;; Anthropic Claudeをデフォルトに設定
  (setq gptel-backend (gptel-make-anthropic "Claude"
                        :key gptel-api-key
                        :stream t))
  ;; 好みに応じて sonnet などを指定
  (setq gptel-model 'claude-3-5-sonnet-latest)

  ;; gptelのバッファをポップアップではなく通常のバッファとして扱いやすくする設定
  (setq gptel-default-mode 'markdown-mode))
