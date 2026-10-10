# yml.el -- Fast & correct YAML parser for Emacs

**yml.el** is a fast YAML parser for Emacs Lisp. It is a simple
wrapper around Rust's `yaml-rust2`, enables you to parse YAML
strings/files very fast. Modeled after native `json-parse-string`'s
interface, so it's pretty intuitive to use. It also supports much of
the YAML quirks too.

> Originally forked from
> [perfectayush/emacs-yamlmod](https://github.com/perfectayush/emacs-yamlmod),
> yml.el is an independently maintained derivative with a redesigned
> API and additional functionality. The original code remains
> [MIT-licensed](LICENSES/MIT.txt), while subsequent contributions in
> this release and going forward are licensed under [GPLv3 or
> later](LICENSE).

## Usage

```elisp
(require 'yml)

...TODO...
```

## Installation

### Automatic

TODO

### Manual

Build requires Rust 1.85 or newer and Cargo to be pre-installed.

```shell
git clone https://github.com/isamert/yml.el
cd yml.el
make
```

Add this project to load path:

```elisp
(add-to-list 'load-path "/path/to/directory/for/yml.el")
```

Then require it:

```elisp
(require 'yml)
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
