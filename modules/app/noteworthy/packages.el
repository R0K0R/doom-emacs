;; -*- no-byte-compile: t; -*-
;;; app/noteworthy/packages.el

(package! websocket)
(package! dtrt-indent)
;; :pin required for nix-doom-emacs-unstraightened: neither package exists in
;; nixpkgs/emacs-overlay, so without a pin resolution fails outright (noteworthy
;; points at an unpublished private repo and can only ever resolve via :pin).
(package! typst-preview
  :recipe (:type git :host github :repo "havarddj/typst-preview.el")
  :pin "7e89cf105e4fef5e79977a4a790d5b3b18d305f6")

(package! noteworthy
  ;; :files must be spelled out: straight's default directive copies only
  ;; Lisp and info files, which would leave the shipped snippets/ behind.
  :recipe (:type git :host github :repo "R0K0R/noteworthy.el"
           :files (:defaults "snippets"))
  :pin "299816ec3f282c6de3c655e4bfc5b42eccb7bb36")

;; Real-time collaboration package (local checkout for now; :pin is
;; meaningless for a local repo, so nix-doom-emacs-unstraightened users need
;; this path to exist).
(package! noteworthy-collab
  :recipe (:local-repo "~/Typst/noteworthy-collab.el"))

(package! treemacs-nerd-icons)

(package! pdf-view-restore)
