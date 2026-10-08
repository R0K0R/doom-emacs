;;; tools/minuet/config.el -*- lexical-binding: t; -*-

;; AI completion as you type: grey suggestion text at point, from Codestral by
;; fill-in-the-middle -- the model sees the text before and after the cursor,
;; which the local benchmark showed matters far more than model size.
;;
;; Mistral's free "Experiment" plan covers it.  The key lives in the agenix
;; authinfo (age/authinfo.age in the flake, read from /run/agenix/authinfo):
;;
;;   machine api.mistral.ai login apikey password <KEY>
;;
;; Until that line exists nothing is turned on, so there are no errors.
;;
;; While a suggestion shows: M-A accepts it, M-a its first line, M-n / M-p
;; cycle, M-e dismisses.  `minuet-show-suggestion' asks for one by hand.

(defun my/minuet-api-key ()
  "The Mistral API key from auth-source, or nil."
  (require 'auth-source)
  (auth-source-pick-first-password :host "api.mistral.ai"))

(defun my/minuet-maybe-enable ()
  "Turn on suggestions as you type, if there is a key to ask with."
  (when (my/minuet-api-key)
    (minuet-auto-suggestion-mode 1)))

(use-package! minuet
  :commands (minuet-show-suggestion minuet-auto-suggestion-mode minuet-complete-with-minibuffer)
  :init
  (add-hook 'typst-ts-mode-hook #'my/minuet-maybe-enable)
  (add-hook 'prog-mode-hook #'my/minuet-maybe-enable)
  :config
  (setq minuet-provider 'codestral
        ;; One suggestion per request, kept short: inline completion wants the
        ;; rest of a line or two, not a page.
        minuet-n-completions 1
        ;; Characters of surrounding text sent, before and after together.
        minuet-context-window 8000)
  ;; The general API endpoint, which free-plan keys use (codestral.mistral.ai
  ;; is for its own separate IDE keys).
  (plist-put minuet-codestral-options :end-point "https://api.mistral.ai/v1/fim/completions")
  (plist-put minuet-codestral-options :model "codestral-latest")
  (plist-put minuet-codestral-options :api-key #'my/minuet-api-key)
  (minuet-set-optional-options minuet-codestral-options :max_tokens 64)
  (map! :map minuet-active-mode-map
        "M-A" #'minuet-accept-suggestion
        "M-a" #'minuet-accept-suggestion-line
        "M-n" #'minuet-next-suggestion
        "M-p" #'minuet-previous-suggestion
        "M-e" #'minuet-dismiss-suggestion))
