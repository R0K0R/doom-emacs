;; -*- no-byte-compile: t; -*-
;;; app/noteworthy/packages.el

(package! websocket)
(package! dtrt-indent)
;; :pin required for nix-doom-emacs-unstraightened: neither package exists in
;; nixpkgs/emacs-overlay, so without a pin resolution fails outright (noteworthy
;; points at an unpublished private repo and can only ever resolve via :pin).
(package! typst-preview
  :recipe (:type git :host github :repo "havarddj/typst-preview.el")
  ;; havarddj's commit, NOT noteworthy.el's: a noteworthy bump edits the pin
  ;; below. Bumps that took the first :pin in this file twice broke evaluation
  ;; (a noteworthy.el hash here is a 404 at github.com/havarddj).
  :pin "f2903a1b98e13be7c927de835ae0d9159dd9fb9a")

(package! noteworthy
  ;; :files must be spelled out: straight's default directive copies only
  ;; Lisp and info files, which would leave the shipped snippets/ behind.
  :recipe (:type git :host github :repo "R0K0R/noteworthy.el"
           :files (:defaults "snippets"))
  :pin "269f788606fc7042a30c4ae1dffc6c2296f489eb")

;; The emacs-collab stack (replaces the retired noteworthy-collab). Fetched
;; from GitHub and pinned, for the same reason as typst-preview and noteworthy
;; above: nix-doom-emacs-unstraightened refuses unpinned or local packages.
;; emacs-collab is the shared client (sync, layout, mirror); the three
;; *-workspace packages are its frontends. Each needs only its top-level .el
;; files, so test/ and the bridge-ref/conformance/docs trees stay out.
(package! emacs-collab
  :recipe (:host github :repo "R0K0R/emacs-collab.el" :files ("*.el"))
  :pin "b28ff39da659643f4eadf03ce88384d58ba99ed9")

(package! noteworthy-workspace
  :recipe (:host github :repo "R0K0R/noteworthy-workspace" :files ("*.el"))
  :pin "6eb7ad5d104b7d0bcc74a7eb69d11ecad7d8d011")

(package! overleaf-workspace
  :recipe (:host github :repo "R0K0R/overleaf-workspace" :files ("*.el"))
  :pin "d734b53101d84ffb3e5a4821169d2b808119744b")

(package! texlyre-workspace
  :recipe (:host github :repo "R0K0R/TeXlyre-workspace" :files ("*.el"))
  :pin "d9366ea3e64326079bc7cec58bdcda8307d307c4")

(package! treemacs-nerd-icons)

(package! pdf-view-restore)
