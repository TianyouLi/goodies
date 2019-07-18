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
;; setup req-package
;; ------------------------------------------
(require 'req-package)

;; (req-package el-get ;; prepare el-get (optional)
;;   :force t ;; load package immediately, no dependency resolution
;;   :config
;;   (add-to-list 'el-get-recipe-path "~/.emacs.d/el-get/el-get/recipes"))
;;  (el-get 'sync))

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
;(global-hl-line-mode t)
;; (set-face-attribute hl-line-face nil :underline t)
;(set-face-foreground 'highlight nil)
;(set-face-background 'highlight nil)
;(set-face-underline-p 'highlight t)

;; ------------------------------------------
;; enable gtags
;; ------------------------------------------
;; (gtags-mode 1)
;;
 

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


;; ------------------------------------------
;; company mode
;; ------------------------------------------
(req-package company
	:ensure t
	:force true
  :config
	(add-hook 'after-init-hook 'global-company-mode)
	(global-set-key (kbd "M-/") 'company-complete-common-or-cycle)
	(setq company-idle-delay 0))

;; ------------------------------------------
;; flycheck mode
;; ------------------------------------------
(req-package flycheck
  :config
	(global-flycheck-mode))


(require 'ggtags)
(add-hook 'c-mode-common-hook
          (lambda ()
            (when (derived-mode-p 'c-mode 'c++-mode 'java-mode 'asm-mode)
              (ggtags-mode 1))))

;; C++ dev config - irony config
(add-hook 'c++-mode-hook 'irony-mode)
(add-hook 'c-mode-hook 'irony-mode)
(add-hook 'objc-mode-hook 'irony-mode)
(add-hook 'irony-mode-hook 'irony-cdb-autosetup-compile-options)

;; C++ dev config - google style config
(add-hook 'c++-mode-hook 'google-set-c-style)
(add-hook 'c-mode-common-hook 'google-make-newline-indent)


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

(require 'clang-format)
(require 'google-c-style)

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
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages (quote (ggtags rtags req-package company-shell company))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
