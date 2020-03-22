;;; Emacs is not a package manager, and here we load its package manager!
(require 'package)
(dolist (source '(("marmalade" . "http://marmalade-repo.org/packages/")
		  ("elpa" . "http://tromey.com/elpa/")
		  ;; TODO: Maybe, use this after emacs24 is released
		  ;; (development versions of packages)
		  ("melpa" . "http://melpa.milkbox.net/packages/")
		  ))
  (add-to-list 'package-archives source t))
(package-initialize)

;; Bootstrap `use-package'
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

;; set on mac
(setq mac-command-key-is-meta t)

(setq inhibit-startup-message t)
(menu-bar-mode -1)
(setq tool-bar-mode nil)
(setq make-backup-files nil)

;;; reduce font lock overhead to open 'large' c/c++ files
(setq font-lock-maximum-decoration 2)


;; -------------------------------------------
;; set line number
;; -------------------------------------------
(global-linum-mode t)
(unless window-system
  (add-hook 'linum-before-numbering-hook
	    (lambda ()
	      (setq-local linum-format-fmt
			  (let ((w (length (number-to-string
					    (count-lines (point-min) (point-max))))))
			    (concat "%" (number-to-string w) "d"))))))

(defun linum-format-func (line)
  (concat
   (propertize (format linum-format-fmt line) 'face 'linum)
   (propertize " " 'face 'mode-line)))

(unless window-system
  (setq linum-format 'linum-format-func))


;; ------------------------------------------
;; keyboad map config
;; ------------------------------------------
(global-set-key "\C-o" 'undo-only)
(global-set-key "\C-u" 'enlarge-window)
(global-set-key "\C-h" 'enlarge-window-horizontally)
(global-set-key "\C-m" 'newline-and-indent)
(global-set-key "\C-J" 'newline)

(global-set-key "\M-i" 'indent-region)
(global-set-key "\M-p" 'comment-region)
(global-set-key "\M-\\" 'split-window-horizontally)
(global-set-key "\M--" 'split-window-vertically)
(global-set-key [(f1)] 'other-window)
(global-set-key [(f2)] 'delete-other-windows)

;; ------------------------------------------
;; install ido
;; ------------------------------------------
(use-package ido
	:ensure t
	:init
	(ido-mode t)
	(setq ido-save-directory-list-file nil))

;; white space config
(setq default-tab-width 2)              ;set default tab width
(setq c-basic-offset 2)
(setq indent-tabs-mode nil)


;; ------------------------------------------
;; company mode
;; ------------------------------------------
(use-package company
	:ensure t
  :config
	(add-hook 'after-init-hook 'global-company-mode)
	(global-set-key (kbd "M-/") 'company-complete-common-or-cycle)
	(setq company-idle-delay 0))

;; ------------------------------------------
;; flycheck mode
;; ------------------------------------------
(use-package flycheck
	:ensure t
  :init
	(global-flycheck-mode t))

;; ------------------------------------------
;; heml-gtags mode
;; ------------------------------------------
(use-package helm-gtags
	:ensure
	:init
	(add-hook
	 'c-mode-common-hook
	 (lambda ()
		 (when (derived-mode-p 'c-mode 'c++-mode 'java-mode 'asm-mode)
			 (helm-gtags-mode 1)))))

;; ------------------------------------------
;; rust mode
;; ------------------------------------------
(use-package racer
	:ensure t
	:config
	(setq racer-cmd "/home/tli7/.cargo/bin/racer")
	(setq racer-rust-src-path "/home/tli7/.rust/src/"))

(use-package company-racer
	:ensure t)

(use-package flycheck-rust
	:ensure t)

(use-package rust-mode
	:ensure t
  :init
	(add-hook 'rust-mode-hook
     '(lambda ()
     ;; Enable racer
     (racer-activate)
     ;; Hook in racer with eldoc to provide documentation
     (racer-turn-on-eldoc)
     ;; Use flycheck-rust in rust-mode
     (add-hook 'flycheck-mode-hook #'flycheck-rust-setup)
     ;; Use company-racer in rust mode
     (set (make-local-variable 'company-backends) '(company-racer))
     ;; Key binding to jump to method definition
     (local-set-key (kbd "M-.") #'racer-find-definition)
     ;; Key binding to auto complete and indent
     (local-set-key (kbd "TAB") #'racer-complete-or-indent))))

(add-to-list 'auto-mode-alist '("\\.rs\\'" . rust-mode))

;; ------------------------------------------
;; key bindings
;; ------------------------------------------
(with-eval-after-load 'helm-gtags
  (define-key helm-gtags-mode-map (kbd "M-.") 'helm-gtags-find-tag)
  (define-key helm-gtags-mode-map (kbd "M-r") 'helm-gtags-find-rtag)
  (define-key helm-gtags-mode-map (kbd "M-s") 'helm-gtags-find-symbol)
  (define-key helm-gtags-mode-map (kbd "M-g M-p") 'helm-gtags-parse-file)
  (define-key helm-gtags-mode-map (kbd "C-c <") 'helm-gtags-previous-history)
  (define-key helm-gtags-mode-map (kbd "C-c >") 'helm-gtags-next-history)
  (define-key helm-gtags-mode-map (kbd "M-,") 'helm-gtags-pop-stack))


;; ------------------------------------------
;; yasnippet mode
;; ------------------------------------------
(use-package yasnippet
  :ensure t
  :init
  (yas-global-mode 1))
(use-package yasnippet-snippets
	:ensure t)

(use-package clang-format
	:ensure t)
(use-package google-c-style
	:ensure t)


;; ------------------------------------------
;; markdown mode
;; ------------------------------------------
(use-package markdown-mode
	:ensure t)


;; ------------------------------------------
;; look and feel
;; ------------------------------------------
(use-package powerline
	:ensure t)
(use-package moe-theme
  :ensure t)
(moe-dark)
(powerline-moe-theme)

;; ------------------------------------------
;; C++ dev config - irony config
;; ------------------------------------------
(add-hook 'c++-mode-hook 'irony-mode)
(add-hook 'c-mode-hook 'irony-mode)
(add-hook 'objc-mode-hook 'irony-mode)
(add-hook 'irony-mode-hook 'irony-cdb-autosetup-compile-options)

;; ------------------------------------------
;; C++ dev config - google style config
;; ------------------------------------------
(add-hook 'c++-mode-hook 'google-set-c-style)
(add-hook 'c-mode-common-hook 'google-make-newline-indent)

;;; javascript

(use-package js2-mode
  :ensure t
  :init
  (setq js-basic-indent 2)
  (setq-default js2-basic-indent 2
                js2-basic-offset 2
                js2-auto-indent-p t
                js2-cleanup-whitespace t
                js2-enter-indents-newline t
                js2-indent-on-enter-key t
                js2-global-externs (list "window" "module" "require" "buster"
					 "sinon" "assert" "refute" "setTimeout"
					 "clearTimeout" "setInterval" "clearInterval"
					 "location" "__dirname" "console" "JSON" "jQuery" "$"))
  (add-hook 'js2-mode-hook
            (lambda ()
              (push '("function" . ?ƒ) prettify-symbols-alist)))

  (add-to-list 'auto-mode-alist '("\\.js$" . js2-mode)))

(use-package color-identifiers-mode
    :ensure t
    :init
    (add-hook 'js2-mode-hook 'color-identifiers-mode))

;; gdb config
(add-hook
 'gud-mode-hook
 '(lambda ()
		(local-set-key
		 [home] ; move to beginning of line, after prompt
		 'comint-bol)
		(local-set-key
		 [up] ; cycle backward through command history
		 '(lambda () (interactive)
				(if (comint-after-pmark-p)
						(comint-previous-input 1)
					(previous-line 1))))
		(local-set-key
		 [down] ; cycle forward through command history
		 '(lambda () (interactive)
				(if (comint-after-pmark-p)
						(comint-next-input 1)
					(forward-line 1))))
		))

;; alias list
(setq
 auto-mode-alist
 (append
	'(
		("\\.sh$" . sh-mode)
		("\\.h$" . c++-mode)
		("\\.hh$". c++-mode)
		("\\.csh$" . csh-mode)
		("\\.py$" . python-mode)
		("Makefile*" . makefile-gmake-mode)
		("makefile*" . makefile-gmake-mode)
		)auto-mode-alist))

;; backup files settings
(setq backup-directory-alist
			`((".*" . ,temporary-file-directory)))
(setq auto-save-file-name-transforms
			`((".*" ,temporary-file-directory t)))

;; python hook
(defun my-python-mode-hook()
	(setq indent-tabs-mode nil)
	(setq tab-width 2)
	(setq python-indent 2)
	(setq-default tab-width 2)
	(setq-default indent-tabs-mode nil)
)

(add-hook 'python-mode-hook 'my-python-mode-hook)

;; xml hook
(defun my-xml-mode-hook()
	(setq indent-tabs-mode nil)
	(setq tab-width 2)
	(setq-default tab-width 2)
	(setq-default indent-tabs-mode nil)
)

(add-hook 'nxml-mode-hook 'my-xml-mode-hook)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   (quote
    (treemacs-persp treemacs-magit treemacs-icons-dired treemacs-projectile treemacs-evil treemacs flycheck-rust helm-gtags rtags company-shell company))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

;; ------------------------------------------
;; treeview
;; ------------------------------------------

;; (use-package treemacs
;;   :ensure t
;;   :defer t
;;   :init
;;   (with-eval-after-load 'winum
;;     (define-key winum-keymap (kbd "M-0") #'treemacs-select-window))
;;   :config
;;   (progn
;;     (treemacs-follow-mode t)
;;     (treemacs-filewatch-mode t)
;;     (treemacs-fringe-indicator-mode t)
;;     (pcase (cons (not (null (executable-find "git")))
;; 		 (not (null treemacs-python-executable)))
;;       (`(t . t)
;;        (treemacs-git-mode 'deferred))
;;       (`(t . _)
;;        (treemacs-git-mode 'simple))))
;;   :bind
;;   (:map global-map
;; 	("M-0"       . treemacs-select-window)
;; 	("C-x t"     . treemacs)))

;; (use-package treemacs-evil
;;   :after treemacs evil
;;   :ensure t)

;; (use-package treemacs-projectile
;;   :after treemacs projectile
;;   :ensure t)

;; (use-package treemacs-icons-dired
;;   :after treemacs dired
;;   :ensure t
;;   :config (treemacs-icons-dired-mode))

;; (use-package treemacs-magit
;;   :after treemacs magit
;;   :ensure t)

;; (use-package treemacs-persp
;;   :after treemacs persp-mode
;;   :ensure t
;;   :config (treemacs-set-scope-type 'Perspectives))

