# yml.el -- Fast & correct YAML parser for Emacs

**yml.el** is a fast YAML parser for Emacs Lisp. It is a simple
wrapper around Rust's `yaml-rust2`, enables you to parse YAML
strings/files very fast. Modeled after native `json-parse-string`'s
interface, so it's pretty intuitive to use. It also supports much of
the YAML quirks too.

## Usage

```elisp
(require 'yml)

(yml-parse-string "name: example\nitems: [1, 2]")
;; => #s(hash-table test equal data ("name" "example" "items" [1 2]))

(yml-parse-string "name: example\nitems: [1, 2]"
                  :object-type 'alist)
;; => (("name" . "example") ("items" . [1 2]))

(yml-parse-string "name: example\nitems: [1, 2]"
                  :object-type 'plist
                  :array-type 'list)
;; => (:name "example" :items (1 2))

(yml-parse-string "[true, false, null]")
;; => [t :false :null]

(yml-parse-string "[true, false, null]"
                  :false-object nil
                  :null-object 'missing)
;; => [t nil missing]

(yml-parse-string-all "---\nname: first\n---\nname: second\n"
                      :object-type 'plist)
;; => ((:name "first") (:name "second"))

(yml-serialize '(:name "example" :items [1 2]))
;; => "---\nname: example\nitems:\n  - 1\n  - 2"

(yml-serialize [t nil missing] :false-object nil :null-object 'missing)
;; => "---\n- true\n- false\n- ~"
```

## Installation

```elisp
(use-package yml
  ;; elpaca
  :ensure (:host github :repo "isamert/yml.el"
           :files ("*.el"))

  ;; vc
  ;; :vc (:url "https://github.com/isamert/yml.el")

  ;; straight.el
  ;; :straight (:host github :repo "isamert/yml.el"
  ;;            :files ("*.el"))
  )
```

### Automatic native module installation

After installing the package, do `M-x yml-install-module`.  You'll be
asked if you want to download a prebuilt library or if you want to
compile it yourself.

### Manual native module installation

Build requires Rust 1.88 or newer and Cargo to be pre-installed.

```shell
git clone https://github.com/isamert/yml.el
cd yml.el
make
```

Add this project to load path:

```elisp
(add-to-list 'load-path "</path/to/directory/for/yml.el>")
```

Then require it:

```elisp
(require 'yml)
```

Try it:

```elisp
(yml-parse-string "name: example\nitems: [1, 2]")
;; => #s(hash-table test equal data ("name" "example" "items" [1 2]))
```

## Prior Art

- *[zkry/yaml.el](https://github.com/zkry/yaml.el)*: Pure elisp YAML
  parser. Very portable and easy to use but pretty slow and can't
  really parse really deeply nested YAMLs.
- *[syohex/emacs-libyaml](https://github.com/syohex/emacs-libyaml)*:
  libyaml bindings for Emacs. Pretty similar to this package, instead
  it uses a C library to do the parsing instead. Haven't been updated
  for a long time and no way to configure how parsing is handled (Only
  allows hash-table objects, no plist/alist object support or
  configurable null/false objects like `json-parse-string`.) Also you
  have to manually install it, no automatic installation etc.
- *[perfectayush/emacs-yamlmod](https://github.com/perfectayush/emacs-yamlmod)*:
  What this package is based on. I completely changed the interface
  (made it `json.c`-esque, hence configurable object/null/false
  objects), dropped f.el dependency, fixed bunch of problems/bugs,
  simplified and made a bit more performant etc. Also it did not have
  a serialize function, multi-doc YAML parser, automatic native module
  installation etc. which now exists in this package. Thanks a lot for
  this package!

### Benchmarks

Average milliseconds per parse, on Emacs 31.1, x86-64 Linux.

| Input       |    Size | yml.el hash-table | yml.el alist | yml.el plist | emacs-libyaml (only hash-table) |
|-------------|--------:|------------------:|-------------:|-------------:|--------------------------------:|
| docker.yaml |  470 KB |             14.85 |        13.39 |    **11.42** |                           14.91 |
| github.yaml | 9.90 MB |            291.87 |       265.09 |   **245.84** |                          312.36 |
| gitlab.yaml | 2.45 MB |             94.56 |        88.56 |    **79.85** |                           98.21 |

I was only able to complete the **docker.yaml** benchmark with
yaml.el, which took **9.89 seconds** for one parse. So I just excluded
it from the benchmarks.

To reproduce (dependencies and inputs are cached in temporary directories):

```sh
emacs --batch -Q -L . -l benchmarks/yml-bench.el --eval '(yml-bench-run 15)'
```

## Rationale

You can see the comparison with already existing solutions above. This
makes it clear that Emacs needs a fast and stable YAML parser. This
package tries to fill this gap. Also tried to modernize
things. Generally speaking, a native module is a bit of a work to
install and people shy away from them. By providing means to
automatically handle this as other modern packages like vterm, ghostel
etc. I tried to bridge that gap.

I specifically did not name this package as something like `yaml-rs`
because the underlying implementation might change but the interface
will stay stable. It might be even purely written in Emacs Lisp one
day if we can keep the same performance characteristics (not possible
as of today but what future may bring is a mystery).

I choose Rust as the native layer because there was already a nice
package that did the ground work
([perfectayush/emacs-yamlmod](https://github.com/perfectayush/emacs-yamlmod))
and I don't know C well. Rust is something I have dabbed with and
people are generally more willing to contribute.

_Why is this a needed at all_, you might ask. I have couple packages
that parses YAML strings and they all suffer from performance problems
when it comes to parsing. This package simply fixes that.
