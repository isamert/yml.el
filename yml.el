;;; yml.el --- Fast YAML parser  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 by Isa Mert Gurbuz

;; Author: Isa Mert Gurbuz <isamertgurbuz@gmail.com>
;; URL: https://github.com/isamert/emacs-yml
;; Version: 0.2.0
;; License: MIT

;;; Commentary:

;; Read YAML files using the `yml' dynamic module.

;;; Code:

(require 'yml)
(require 'cl-lib)

;;;; Public

;;;###autoload
(cl-defun yml-parse-string
    (string &key
            (object-type 'hash-table)
            (array-type 'array)
            (null-object :null)
            (false-object :false))
  "Parse the YAML STRING into a Lisp value.

This is essentially the reverse operation of `yml-serialize',
which see.  The returned value will be the YAML null value, the YAML
false value, t, a number, a string, a vector, a list, a hash-table, an
alist, or a plist.  Its elements will be further values of these
types.  If STRING doesn't contain a valid YAML value, this function
signals an error of type `yml-parse-error'.  If the STRING
contains multiple YAML values, then this function signals an error of
type `yml-trailing-content'. You can use
`yml-parse-string-all' to parse multi document YAML strings.

OBJECT-TYPE TYPE -- use TYPE to represent YAML objects.
  TYPE can be `hash-table' (the default), `alist' or `plist'.
  If an object has members with the same key, `hash-table' keeps only
  the last value of such keys, while `alist' and `plist' keep all the
  members.  With `plist', non-string keys signals an error of type
  `yml-non-string-key'.

ARRAY-TYPE TYPE -- use TYPE to represent YAML arrays.
  TYPE can be `array' (the default) or `list'.

NULL-OBJECT OBJ -- use OBJ to represent a YAML null value.
  It defaults to `:null'.

FALSE-OBJECT OBJ -- use OBJ to represent a YAML false value.
  It defaults to `:false'."
  (yml--parse-string
   string object-type array-type null-object false-object))

;;;###autoload
(cl-defun yml-parse-string-all
    (string &key
            (object-type 'hash-table)
            (array-type 'array)
            (null-object :null)
            (false-object :false))
  "Same as `yml-parse-string' but supports multi document YAMLs.

Returned result is a list of Lisp objects.  See `yml-parse-string'
for STRING, OBJECT-TYPE, ARRAY-TYPE, NULL-OBJECT AND FALSE-OBJECT."
  (yml--parse-string
   string object-type array-type null-object false-object
   'parse-all))

;;;###autoload
(cl-defun yml-serialize
    (object &key
            (null-object :null)
            (false-object :false))
  "Return the YAML representation of OBJECT as a string.

OBJECT is translated as follows:

t          -- the YAML true value.
nil        -- Empty YAML object or null if NULL-OBJECT is nil
number     -- a YAML number.
string     -- a YAML string.
vector     -- a YAML array.
hash-table -- a YAML object.
alist      -- a YAML object.
plist      -- a YAML object.  Keys must be symbols.
              A leading colon in plist key names is elided.

For duplicate object keys, the last value is used.

The Lisp equivalents to the YAML null and false values are
configurable:

NULL-OBJECT OBJ -- use OBJ to represent a YAML null value.
  It defaults to :null.

FALSE-OBJECT OBJ -- use OBJ to represent a YAML false value.
  It defaults to :false."
  (yml--serialize object null-object false-object))

;;;; Internal

(defun yml--hash-table-pairs (table)
  (let (pairs)
    (maphash (lambda (key value)
               (push (cons key value) pairs))
             table)
    (vconcat pairs)))

;;;; Footer

(provide 'yml-wrapper)
;;; yml.el ends here
