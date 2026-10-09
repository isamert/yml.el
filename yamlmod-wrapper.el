;;; yamlmod-wrapper.el --- Wraps yamlmod dynamic module in elisp  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 by Isa Mert Gurbuz

;; Author: Isa Mert Gurbuz <isamertgurbuz@gmail.com>
;; URL: https://github.com/isamert/emacs-yamlmod
;; Version: 0.2.0
;; License: MIT

;;; Commentary:

;; Read YAML files using the yamlmod dynamic module.

;;; Code:

(require 'yamlmod)
(require 'cl-lib)

;;;###autoload
(cl-defun yamlmod-parse-string
    (string &key
            (object-type 'hash-table)
            (array-type 'array)
            (null-object :null)
            (false-object :false))
  "Parse the YAML STRING into a Lisp value.

This is essentially the reverse operation of `yamlmod-serialize',
which see.  The returned value will be the YAML null value, the YAML
false value, t, a number, a string, a vector, a list, a hash-table, an
alist, or a plist.  Its elements will be further values of these
types.  If STRING doesn't contain a valid YAML value, this function
signals an error of type `yamlmod-parse-error'.  If the STRING
contains multiple YAML values, then this function signals an error of
type `yamlmod-trailing-content'. You can use
`yamlmod-parse-string-all' to parse multi document YAML strings.

OBJECT-TYPE TYPE -- use TYPE to represent YAML objects.
  TYPE can be `hash-table' (the default), `alist' or `plist'.
  If an object has members with the same key, `hash-table' keeps only
  the last value of such keys, while `alist' and `plist' keep all the
  members.  With `plist', non-string keys signals an error of type
  `yamlmod-non-string-key'.

ARRAY-TYPE TYPE -- use TYPE to represent YAML arrays.
  TYPE can be `array' (the default) or `list'.

NULL-OBJECT OBJ -- use OBJ to represent a YAML null value.
  It defaults to `:null'.

FALSE-OBJECT OBJ -- use OBJ to represent a YAML false value.
  It defaults to `:false'."
  (yamlmod--parse-string
   string object-type array-type null-object false-object))

;;;###autoload
(cl-defun yamlmod-parse-string-all
    (string &key
            (object-type 'hash-table)
            (array-type 'array)
            (null-object :null)
            (false-object :false))
  "Same as `yamlmod-parse-string' but supports multi document YAMLs.

Returned result is a list of Lisp objects.  See `yamlmod-parse-string'
for STRING, OBJECT-TYPE, ARRAY-TYPE, NULL-OBJECT AND FALSE-OBJECT."
  (yamlmod--parse-string
   string object-type array-type null-object false-object
   'parse-all))

(provide 'yamlmod-wrapper)

;;; yamlmod-wrapper.el ends here
