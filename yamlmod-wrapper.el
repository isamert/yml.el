;;; yamlmod-wrapper.el --- Wraps yamlmod dynamic module in elisp  -*- lexical-binding: t; -*-

;; Copyright (C) 2019 by Ayush Goyal

;; Author: Ayush Goyal <perfectayush@gmail.com>
;; URL: https://github.com/perfectayush/emacs-yamlmod
;; Version: 0.2.0
;; License: MIT
;; Package-Requires: ((f "0.20.0"))

;;; Commentary:

;; Read YAML files using the yamlmod dynamic module.

;;; Code:

(require 'yamlmod)
(require 'f)

;;;###autoload
(defun yamlmod-read-file (file)
  "Parse UTF-8 YAML from FILE into an Emacs Lisp value."
  (yamlmod-load (f-read-text file 'utf-8)))

(provide 'yamlmod-wrapper)

;;; yamlmod-wrapper.el ends here
