;;; yml.el --- Fast YAML parser  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 by Isa Mert Gurbuz

;; Author: Isa Mert Gurbuz <isamertgurbuz@gmail.com>
;; URL: https://github.com/isamert/yml.el
;; Version: 0.1.0
;; License: GPL-3.0-or-later
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Like `json-parse-string' but for YAML.  Use `yml-parse-string' to
;; parse YAMLs and `yml-serialize' to serialize Lisp objects into
;; YAML.

;;; Code:

(require 'yml-core)
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

This is essentially the reverse operation of `yml-serialize', which see.
The returned value will be the YAML null value, the YAML false value, t,
a number, a string, a vector, a list, a hash-table, an alist, or a
plist.  Its elements will be further values of these types.  If STRING
doesn't contain a valid YAML value, this function signals an error of
type `yml-parse-error'.  If the STRING contains multiple YAML values,
then this function signals an error of type `yml-trailing-content'.  You
can use `yml-parse-string-all' to parse multi document YAML strings.

OBJECT-TYPE TYPE -- use TYPE to represent YAML objects.
  TYPE can be `hash-table' (the default), `alist' or `plist'.  Duplicate
  mapping keys are not rejected: hash-tables use the last value, while
  alists and plists retain duplicate entries.  With `plist', non-string
  keys signal an error of type `yml-non-string-key'.

ARRAY-TYPE TYPE -- use TYPE to represent YAML arrays.
  TYPE can be `array' (the default) or `list'.

Integer parsing follows yaml-rust2.  Integers within the signed 64-bit
range (-2^63 through 2^63-1) are represented exactly; larger literals may
be interpreted as floats or strings, or rejected, depending on their
syntax and tags.  Large decimal literals can lose precision when parsed
as floats; exact large-integer round trips are not guaranteed.

NULL-OBJECT OBJ -- use OBJ to represent a YAML null value.
  It defaults to `:null'.

FALSE-OBJECT OBJ -- use OBJ to represent a YAML false value.
  It defaults to `:false'."
  (yml-core--parse-string
   string object-type array-type null-object false-object nil))

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
  (yml-core--parse-string
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
integer    -- a YAML integer in the signed 64-bit range.
float      -- a YAML floating-point number.
string     -- a YAML string.
vector     -- a YAML array.
hash-table -- a YAML object.
alist      -- a YAML object.
plist      -- a YAML object.  Keys must be symbols.
              A leading colon in plist key names is elided.

Lists represent mappings, not YAML arrays.  Use vectors for arrays,
including empty arrays ([]).  If parsing with ARRAY-TYPE set to `list',
convert each resulting array list to a vector before serialization;
`vconcat' converts one list, but does not convert nested arrays.

Integers outside the signed 64-bit range (-2^63 through 2^63-1) signal
`yml-serialization-error'.

For duplicate object keys in an alist or plist, the last value is used.
When parsing, hash-tables use the last duplicate mapping value, while
alists and plists retain duplicate entries.

The Lisp equivalents to the YAML null and false values are
configurable:

NULL-OBJECT OBJ -- use OBJ to represent a YAML null value.
  It defaults to :null.

FALSE-OBJECT OBJ -- use OBJ to represent a YAML false value.
  It defaults to :false."
  (yml-core--serialize object null-object false-object))

;;;; Internal

(defun yml--hash-table-pairs (table)
  (let ((pairs (make-vector (hash-table-count table) nil))
        (index 0))
    (maphash
     (lambda (key value)
       (aset pairs index (cons key value))
       (setq index (1+ index)))
     table)
    pairs))

;;;; Footer

(provide 'yml)
;;; yml.el ends here
