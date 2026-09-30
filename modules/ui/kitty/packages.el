;; -*- no-byte-compile: t; -*-
;;; ui/kitty/packages.el

;; My fork of cashmeredev/kitty-graphics.el, carrying fixes not upstream.
(package! kitty-graphics
  :recipe (:host github :repo "R0K0R/kitty-graphics.el")
  :pin "aee5692e14d6305ac521a5558def36d9b72a5741")
