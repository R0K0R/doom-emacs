;; -*- no-byte-compile: t; -*-
;;; ui/kitty/packages.el

;; My fork of cashmeredev/kitty-graphics.el, carrying fixes not upstream.
(package! kitty-graphics
  :recipe (:host github :repo "R0K0R/kitty-graphics.el")
  :pin "99bd20f585c92b5f088aad068e4795946922a983")
