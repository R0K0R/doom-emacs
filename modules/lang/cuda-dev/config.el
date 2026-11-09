;;; lang/cuda-dev/config.el -*- lexical-binding: t; -*-
;;
;; CUDA kernels in projects made from the home repo's template
;; (`nix flake init -t ~/config/home#cuda'). :lang (cc +lsp) already brings
;; cuda-mode and starts lsp-mode for it; this adds the two things it cannot
;; know: which clangd, and where to run.
;;
;; clangd. A bare clangd knows nothing of CUDA's headers, and on yulee there is
;; none on PATH at all. The template's tools/clangd runs clangd inside the
;; project's dev shell, which pins the toolkit and writes a .clangd with
;; --cuda-path; so for any buffer under a project that has one, lsp-mode is
;; pointed at it. Same file locally and over TRAMP: the path handed to lsp is
;; the remote-local one (`file-local-name').
;;
;; Over TRAMP nothing more is needed: lsp-mode registers a :remote? twin of
;; every client (`lsp-auto-register-remote-clients', on by default) --
;; `clangd-tramp', built from the same command function, so it reads the same
;; buffer-local executable.
;;
;; compile-command. Locally, `cudarun yulee' (syncs, builds and runs on the
;; 5090); over TRAMP the project is already on the GPU host, so make runs
;; there in the dev shell directly. Either way only a default: M-x compile
;; edits it, and a .dir-locals.el wins.

(defvar +cuda-dev-default-host "yulee"
  "GPU host `cudarun' targets by default from a local project.")

(defun +cuda-dev--project-clangd ()
  "The project's tools/clangd for this buffer, as a remote-local path, or nil."
  (when-let* ((dir (or (and buffer-file-name (file-name-directory buffer-file-name))
                       default-directory))
              (root (locate-dominating-file dir "tools/clangd"))
              ((file-exists-p (expand-file-name "flake.nix" root))))
    (file-local-name (expand-file-name "tools/clangd" root))))

(defadvice! +cuda-dev--use-project-clangd-a (&rest _)
  "Before lsp picks a client, point clangd at the project's dev-shell clangd.
On `lsp' itself rather than a mode hook, so buffers restored from a session
(mode set without its hooks) get it too -- as tools/remote-lsp does for pyright."
  :before '(lsp lsp-deferred)
  (when (derived-mode-p 'c-mode 'c++-mode 'cuda-mode 'c-ts-mode 'c++-ts-mode)
    (when-let* ((clangd (+cuda-dev--project-clangd)))
      (setq-local lsp-clients-clangd-executable clangd))))

(add-hook! '(cuda-mode-hook cuda-ts-mode-hook)
  (defun +cuda-dev-compile-command-h ()
    "Default compile-command for template projects (see the file header)."
    (when (+cuda-dev--project-clangd)
      (setq-local compile-command
                  (if (file-remote-p default-directory)
                      "nix develop --quiet --command make run"
                    (format "cudarun %s run" +cuda-dev-default-host))))))
