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
  :pin "df9091b98186e22eb5f23c38228ce1e74061d8fa")

;; Real-time collaboration package. Fetched from GitHub rather than a
;; :local-repo: a local checkout cannot be resolved deterministically, so
;; nix-doom-emacs-unstraightened refuses it outright --
;;   noteworthy-collab: not in nixpkgs or emacs-overlay, not pinned.
;; Same reason typst-preview and noteworthy above carry pins.
(package! noteworthy-collab
  :recipe (:type git :host github :repo "R0K0R/noteworthy-collab.el")
  :pin "a348c5fd045055d2679c0643dbcc6ff84a6d7332")

(package! treemacs-nerd-icons)

(package! pdf-view-restore)
