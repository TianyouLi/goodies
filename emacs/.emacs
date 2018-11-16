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


(setq inhibit-startup-message t)
(menu-bar-mode nil)
;;(tool-bar-mode nil)
(setq make-backup-files nil)

;; ------------------------------------------
;; font lock config
;; ------------------------------------------
(global-font-lock-mode t)
(setq font-lock-maximum-decoration t)
(show-paren-mode 1)
(which-func-mode t)
(transient-mark-mode t)
(column-number-mode t)


;; -------------------------------------------
;; set line number
;; -------------------------------------------
(global-linum-mode t)
(setq linum-format "%d ")

;; -------------------------------------------
;; highlight current line
;; -------------------------------------------
(global-hl-line-mode t)
;; (set-face-attribute hl-line-face nil :underline t)
(set-face-foreground 'highlight nil)
(set-face-background 'highlight nil)
(set-face-underline-p 'highlight t)

;; ------------------------------------------
;; enable gtags
;; ------------------------------------------
;; (gtags-mode 1)

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
(global-set-key (kbd "M-s") 'gtags-find-rtag)
(global-set-key [(f1)] 'other-window)
(global-set-key [(f2)] 'delete-other-windows)


;; add load path
(add-to-list 'load-path "~/.elisp/")

;;; install color theme
;; (load-file "~/.elisp/color-theme.el")
;; (require 'color-theme)
;; (if window-system
;; 		(color-theme-gnome2)
;; 	(color-theme-dark-laptop))

;;; install ido
(require 'ido)
(ido-mode t)
(setq ido-save-directory-list-file nil)

;; line number 
;; (require 'wb-line-number)
;; (wb-line-number-toggle)

;; white space config
(setq default-tab-width 2)              ;set default tab width
(setq c-basic-offset 2)
(setq indent-tabs-mode nil)

;; gdb config
(add-hook 'gud-mode-hook
          '(lambda ()
             (local-set-key [home] ; move to beginning of line, after prompt
                            'comint-bol)
             (local-set-key [up] ; cycle backward through command history
                            '(lambda () (interactive)
                               (if (comint-after-pmark-p)
                                   (comint-previous-input 1)
                                 (previous-line 1))))
             (local-set-key [down] ; cycle forward through command history
                            '(lambda () (interactive)
                               (if (comint-after-pmark-p)
                                   (comint-next-input 1)
                                 (forward-line 1))))
             ))

;; alias list
(setq auto-mode-alist
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

(require 'clang-format)
(require 'google-c-style)

;; c hook
;; (defun my-c-mode-common-hook()
;;   (setq tab-width 2 indent-tabs-mode nil)
;;   ;;; hungry-delete and auto-newline
;;   ;;  (c-toggle-auto-hungry-state 1)
;;   (c-toggle-syntactic-indentation 1)
;;   (define-key c-mode-base-map (kbd "<return>") 'newline-and-indent)
;;   (define-key c-mode-base-map [tab] 'indent-for-tab-command)
;;   (local-set-key [(return)] 'newline-and-indent)
;;   (setq c-macro-shrink-window-flag t)
;;   (setq c-macro-preprocessor "cpp")
;;   (setq c-macro-cppflags " ")
;;   (setq c-macro-prompt-flag t)
;;   (setq abbrev-mode t)
;; )
;; (add-hook 'c-mode-common-hook 'my-c-mode-common-hook)

;; (defun clang-format-region-google (s e)
;; 	(interactive
;; 	 (if (use-region-p)
;; 			 (list (region-beginning) (region-end))
;; 		 (list (point) (point))))
;; 	(clang-format-region s e "google"))


(add-hook 'c-mode-common-hook 'google-make-newline-indent)

;; c++ hook
(defun my-c++-mode-hook()
	(fset 'c-indent-region 'clang-format-region)
  (setq tab-width 4 indent-tabs-mode nil)
  (setq c-basic-offset 4)
  (local-set-key [(return)] 'newline-and-indent)
  (define-key c++-mode-map (kbd "<return>") 'newline-and-indent)
  (define-key c++-mode-map [tab] 'indent-for-tab-command)
  (define-key c++-mode-map [(f7)] 'compile)
  (set (make-local-variable 'compile-command)
       (concat "make "))
)

(add-hook 'c++-mode-hook 'my-c++-mode-hook)

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

;; js doc support
;; (require 'js-doc)
;; (setq js-doc-mail-address "tianyou.li@gmail.com"
;;       js-doc-author (format "Tianyou Li <%s>" js-doc-mail-address)
;;       js-doc-url "https://github.com/tianyouli"
;;       js-doc-license "Intel")

;; javascript hook
;; (require 'flycheck)
;; (defun my-js-mode-hook()
;; 	(setq indent-tabs-mode nil)
;; 	(setq tab-width 2)
;; 	(setq-default tab-width 2)
;; 	(setq-default indent-tabs-mode nil)
;;   (setq js-indent-level 2)
;; 	(flycheck-mode t)
;; 	(tern-mode t)
;;   (auto-complete-mode t)
;; 	(define-key js-mode-map "\C-ci" 'js-doc-insert-function-doc)
;; 	(define-key js-mode-map "@" 'js-doc-insert-tag)
;; )

;; setup tern
(eval-after-load 'tern
	'(progn
		 (require 'tern-auto-complete)
		 (tern-ac-setup)))

(add-hook 'js-mode-hook 'my-js-mode-hook)

;; jade mode
(require 'sws-mode)
(require 'jade-mode)
(add-to-list 'auto-mode-alist '("\\.styl$" . sws-mode))
(add-to-list 'auto-mode-alist '("\\.jade$" . jade-mode))
