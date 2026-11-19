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
  :pin "39815811cf7631048cff7c79ca381324faaa66b9")

;; The emacs-collab stack (replaces the retired noteworthy-collab). Fetched
;; from GitHub and pinned, for the same reason as typst-preview and noteworthy
;; above: nix-doom-emacs-unstraightened refuses unpinned or local packages.
;; emacs-collab is the shared client (sync, layout, mirror); the three
;; *-workspace packages are its frontends. Each needs only its top-level .el
;; files, so test/ and the bridge-ref/conformance/docs trees stay out.
(package! emacs-collab
  :recipe (:host github :repo "R0K0R/emacs-collab.el" :files ("*.el"))
  :pin "b0cfc017859ca1777239693e0d2ea6cfb3c60c20")

(package! syncworthy-workspace
  :recipe (:host github :repo "R0K0R/syncworthy-workspace" :files ("*.el"))
  :pin "44517667bc47e1eb687d8ce20e74914e710a87c5")

(package! noteworthy-workspace
  :recipe (:host github :repo "R0K0R/noteworthy-workspace" :files ("*.el"))
  :pin "f55578a7ead2aaebf913d9b09ca99994e984c19a")

(package! overleaf-workspace
  :recipe (:host github :repo "R0K0R/overleaf-workspace" :files ("*.el"))
  :pin "c6c589c68230f05349ceb69d94ca1423b91522bc")

(package! texlyre-workspace
  :recipe (:host github :repo "R0K0R/TeXlyre-workspace" :files ("*.el"))
  :pin "d9366ea3e64326079bc7cec58bdcda8307d307c4")

(package! treemacs-nerd-icons)

(package! pdf-view-restore)
