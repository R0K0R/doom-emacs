;;; tools/minuet/config.el -*- lexical-binding: t; -*-

;; AI completion as you type: grey suggestion text at point, by
;; fill-in-the-middle -- the model sees the text before and after the cursor,
;; which the Typst completion benchmark showed matters far more than size.
;;
;; Served by victus-15 over Tailscale: Qwen2.5-Coder 1.5B on its GPU (the
;; flake's hosts/victus-15/llm-completion.nix), free and private.  Away from
;; the tailnet the requests just fail and nothing is shown.
;;
;; While a suggestion shows: M-A accepts it, M-a its first line, M-n / M-p
;; cycle, M-e dismisses.  `minuet-show-suggestion' asks for one by hand.

(defvar my/minuet-server "http://victus-15:8012"
  "The llama.cpp server minuet asks for completions.")

(defun my/minuet-qwen-fim-prompt (ctx)
  "Qwen2.5-Coder's fill-in-the-middle prompt for minuet context CTX.
llama-server's completions endpoint takes a plain prompt, so the
model's own prefix/suffix/middle tokens go into it, and no suffix is sent."
  (format "<|fim_prefix|>%s<|fim_suffix|>%s<|fim_middle|>"
          (plist-get ctx :before-cursor)
          (plist-get ctx :after-cursor)))

(use-package! minuet
  :commands (minuet-show-suggestion minuet-auto-suggestion-mode minuet-complete-with-minibuffer)
  :init
  (add-hook 'typst-ts-mode-hook #'minuet-auto-suggestion-mode)
  (add-hook 'prog-mode-hook #'minuet-auto-suggestion-mode)
  :config
  (setq minuet-provider 'openai-fim-compatible
        ;; One suggestion per request, kept short: inline completion wants the
        ;; rest of a line or two, not a page.
        minuet-n-completions 1
        ;; Characters of surrounding text sent, before and after together; the
        ;; server runs a 4096-token context.
        minuet-context-window 6000
        minuet-request-timeout 3)
  (plist-put minuet-openai-fim-compatible-options :name "victus-15")
  (plist-put minuet-openai-fim-compatible-options :end-point (concat my/minuet-server "/v1/completions"))
  ;; llama-server needs no key; minuet wants a non-empty one, read from an
  ;; environment variable by name -- any variable that is always set.
  (plist-put minuet-openai-fim-compatible-options :api-key "TERM")
  (plist-put minuet-openai-fim-compatible-options :model "qwen2.5-coder-1.5b")
  (plist-put minuet-openai-fim-compatible-options :template
             '(:prompt my/minuet-qwen-fim-prompt :suffix nil))
  (minuet-set-optional-options minuet-openai-fim-compatible-options :max_tokens 64)
  (minuet-set-optional-options minuet-openai-fim-compatible-options :stop ["\n\n"])
  (map! :map minuet-active-mode-map
        "M-A" #'minuet-accept-suggestion
        "M-a" #'minuet-accept-suggestion-line
        "M-n" #'minuet-next-suggestion
        "M-p" #'minuet-previous-suggestion
        "M-e" #'minuet-dismiss-suggestion))
