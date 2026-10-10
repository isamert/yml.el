// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Isa Mert Gurbuz
// Copyright (C) 2019 Ayush Goyal (inherited MIT-covered code).
// Modified by Isa Mert Gurbuz in 2026; distributed under GPLv3 or later.
// The original MIT notice is preserved in LICENSES/MIT.txt.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

use emacs::{defun, Env, IntoLisp, Result, Value, Vector};
use hashlink::LinkedHashMap;
use yaml_rust2::{Yaml, YamlEmitter, YamlLoader};

emacs::plugin_is_GPL_compatible!();

// * Types

enum ArrayType {
    Array,
    List,
}

enum ObjectType {
    HashTable,
    PropertyList,
    AssociationList,
}

struct ParseOptions<'e> {
    array_type: ArrayType,
    object_type: ObjectType,
    null_object: Value<'e>,
    false_object: Value<'e>,
}

// * Init

#[emacs::module(name = "yml-core")]
fn init(env: &Env) -> Result<Value<'_>> {
    env.message("Loading yml!")
}

emacs::use_symbols! {
    SYM_ARRAY => "array"
    SYM_LIST => "list"
    SYM_HASH_TABLE => "hash-table"
    SYM_PLIST => "plist"
    SYM_ALIST => "alist"
    SYM_EQUAL => "equal"
    SYM_PARAM_TEST => ":test"
    SYM_PARAM_SIZE => ":size"
    SYM_INTEGER => "integer"
    SYM_FLOAT => "float"
    SYM_SYMBOL => "symbol"
    SYM_CONS => "cons"
    SYM_STRING => "string"
    SYM_VECTOR => "vector"
    SYM_PROCESS => "process"
    SYM_NIL => "nil"
    SYM_T => "t"
}

emacs::use_functions! {
    FN_CONSP => "consp"
    FN_YML__HASH_TABLE_PAIRS => "yml--hash-table-pairs"
    FN_SYMBOL_NAME => "symbol-name"
    FN_PUTHASH => "puthash"
    FN_MAKE_HASH_TABLE => "make-hash-table"
}

emacs::define_errors! {
    yml_error "YAML error"

    yml_serialization_error "YAML serialization error" (yml_error)

    yml_parse_error "YAML parsing error" (yml_error)
    yml_trailing_content "Unexpected additional YAML document" (yml_parse_error)
    yml_unsupported_alias "Unsupported YAML alias" (yml_parse_error)
    yml_non_string_key "Unexpected non-string key with plist object type" (yml_parse_error)
}

// * defun yml--parse-string

#[defun]
fn _parse_string<'e>(
    env: &'e Env,
    yaml: String,
    object_type: Value<'e>,
    array_type: Value<'e>,
    null_object: Value<'e>,
    false_object: Value<'e>,
    parse_all: Option<Value<'e>>,
) -> Result<Value<'e>> {
    let array_type = match array_type {
        value if value == SYM_ARRAY.bind(env) => ArrayType::Array,
        value if value == SYM_LIST.bind(env) => ArrayType::List,
        value => {
            return env.signal("error", ("One of array or list should be specified", value));
        }
    };

    let object_type = match object_type {
        value if value == SYM_HASH_TABLE.bind(env) => ObjectType::HashTable,
        value if value == SYM_PLIST.bind(env) => ObjectType::PropertyList,
        value if value == SYM_ALIST.bind(env) => ObjectType::AssociationList,
        value => {
            return env.signal(
                "error",
                (
                    "One of hash-table, alist or plist should be specified",
                    value,
                ),
            );
        }
    };

    let options = ParseOptions {
        array_type,
        object_type,
        null_object,
        false_object,
    };

    let documents = match YamlLoader::load_from_str(&yaml) {
        Ok(documents) => documents,
        Err(error) => {
            let marker = error.marker();
            return env.signal(
                yml_parse_error,
                (
                    error.info(),
                    marker.line(),
                    marker.col() + 1,
                    marker.index() + 1,
                ),
            );
        }
    };

    if parse_all.is_some() {
        let all_documents = documents
            .into_iter()
            .map(|doc| yaml_to_lisp(env, doc, &options))
            .collect::<Result<Vec<_>>>()?;

        env.list(&all_documents)
    } else {
        if documents.len() > 1 {
            return env.signal(
                yml_trailing_content,
                ("Expected a single YAML document; found multiple documents",),
            );
        }

        let document = documents.into_iter().next().unwrap_or(Yaml::Null);
        yaml_to_lisp(env, document, &options)
    }
}

// ** Helpers

fn yaml_to_lisp<'e>(env: &'e Env, yaml: Yaml, options: &ParseOptions<'e>) -> Result<Value<'e>> {
    match yaml {
        Yaml::Null => Ok(options.null_object),
        Yaml::String(s) => s.into_lisp(env),
        Yaml::Boolean(false) => Ok(options.false_object),
        Yaml::Boolean(true) => true.into_lisp(env),
        Yaml::Array(items) => {
            let values = items
                .into_iter()
                .map(|item| yaml_to_lisp(env, item, options))
                .collect::<Result<Vec<_>>>()?;
            match options.array_type {
                ArrayType::List => env.list(&values),
                ArrayType::Array => env.vector(&values),
            }
        }
        Yaml::Hash(t) => match options.object_type {
            ObjectType::HashTable => {
                let hash = FN_MAKE_HASH_TABLE.bind(env).call([
                    SYM_PARAM_TEST.bind(env),
                    SYM_EQUAL.bind(env),
                    SYM_PARAM_SIZE.bind(env),
                    t.len().into_lisp(env)?,
                ])?;

                for (key, value) in t {
                    FN_PUTHASH.bind(env).call([
                        yaml_to_lisp(env, key, options)?,
                        yaml_to_lisp(env, value, options)?,
                        hash,
                    ])?;
                }
                Ok(hash)
            }
            ObjectType::AssociationList => {
                let pairs = t
                    .into_iter()
                    .map(|(key, val)| {
                        env.cons(
                            yaml_to_lisp(env, key, options)?,
                            yaml_to_lisp(env, val, options)?,
                        )
                    })
                    .collect::<Result<Vec<_>>>()?;

                env.list(&pairs)
            }
            ObjectType::PropertyList => {
                let mut plist = Vec::with_capacity(t.len() * 2);

                for (key, value) in t {
                    let keyword = match key {
                        Yaml::String(key) => env.intern(&format!(":{key}"))?,
                        key => {
                            return env.signal(
                                yml_non_string_key,
                                (
                                    "YAML plist keys must be strings",
                                    yaml_to_lisp(env, key, options)?,
                                ),
                            );
                        }
                    };

                    plist.push(keyword);
                    plist.push(yaml_to_lisp(env, value, options)?);
                }

                env.list(&plist)
            }
        },
        Yaml::Real(_) => yaml.as_f64().into_lisp(env),
        Yaml::Integer(t) => t.into_lisp(env),
        Yaml::Alias(x) => env.signal(
            yml_unsupported_alias,
            ("Unsupported alias field in the parsed YAML", x),
        ),
        Yaml::BadValue => env.signal(yml_parse_error, ("Invalid YAML value",)),
    }
}

// * defun yml--serialize

#[defun]
fn _serialize<'e>(
    env: &'e Env,
    object: Value<'e>,
    null_object: Value<'e>,
    false_object: Value<'e>,
) -> Result<String> {
    let yaml = serialize_helper(env, object, null_object, false_object)?;
    let mut output = String::new();
    YamlEmitter::new(&mut output).dump(&yaml[0]).unwrap();
    return Ok(output);
}

// ** Helpers

// TODO: Add a depth limit?
fn serialize_helper<'e>(
    env: &'e Env,
    object: Value<'e>,
    null_object: Value<'e>,
    false_object: Value<'e>,
) -> Result<Yaml> {
    if object == null_object {
        return Ok(Yaml::Null);
    }
    if object == false_object {
        return Ok(Yaml::Boolean(false));
    }
    if object == SYM_T.bind(env) {
        return Ok(Yaml::Boolean(true));
    }
    if object == SYM_NIL.bind(env) {
        return Ok(Yaml::Hash(LinkedHashMap::with_capacity(0)));
    }

    let typ = env.type_of(object)?;

    if typ == SYM_INTEGER.bind(env) {
        Ok(Yaml::Integer(object.into_rust()?))
    } else if typ == SYM_FLOAT.bind(env) {
        let val = object.into_rust::<f64>()?;
        let mut text = if val.is_nan() {
            ".nan".to_string()
        } else if val.is_infinite() && val.is_sign_positive() {
            ".inf".to_string()
        } else if val.is_infinite() {
            "-.inf".to_string()
        } else {
            val.to_string()
        };
        if !text.contains(['.', 'e', 'E']) {
            text.push_str(".0");
        }
        Ok(Yaml::Real(text))
    } else if typ == SYM_STRING.bind(env) {
        Ok(Yaml::String(object.into_rust()?))
    } else if typ == SYM_VECTOR.bind(env) {
        let items: Vector<'e> = object.into_rust()?;
        Ok(Yaml::Array(
            items
                .into_iter()
                .map(|item| serialize_helper(env, item, null_object, false_object))
                .collect::<Result<Vec<_>>>()?,
        ))
    } else if typ == SYM_HASH_TABLE.bind(env) {
        // TODO: Is it possible to collect pairs without calling elisp?
        let pairs: Vector<'e> = FN_YML__HASH_TABLE_PAIRS
            .bind(env)
            .call([object])?
            .into_rust()?;
        let size = pairs.len();
        let mut map = LinkedHashMap::with_capacity(size);
        for pair in pairs {
            let key: Value<'e> = pair.car()?;
            let value: Value<'e> = pair.cdr()?;
            map.insert(
                serialize_helper(env, key, null_object, false_object)?,
                serialize_helper(env, value, null_object, false_object)?,
            );
        }
        Ok(Yaml::Hash(map))
    } else if typ == SYM_CONS.bind(env) {
        let is_alist = FN_CONSP.bind(env).call([object.car()?])?.is_not_nil();

        let mut items: Vec<Value<'e>> = Vec::new();
        let mut tail = object;
        while tail.is_not_nil() {
            if env.type_of(tail)? != SYM_CONS.bind(env) {
                return env.signal(yml_serialization_error, ("Expected a proper list", object));
            }
            let head = tail.car()?;
            tail = tail.cdr()?;
            items.push(head);
        }

        let map = if is_alist {
            let size = items.len();
            let mut map = LinkedHashMap::with_capacity(size);
            for pair in items {
                let key: Value<'e> = pair.car()?;
                let value: Value<'e> = pair.cdr()?;
                map.insert(
                    serialize_helper(env, key, null_object, false_object)?,
                    serialize_helper(env, value, null_object, false_object)?,
                );
            }
            map
        } else {
            let size = items.len() / 2;
            let mut map = LinkedHashMap::with_capacity(size);
            let mut items_iter = items.into_iter();
            while let Some(key) = items_iter.next() {
                let Some(value) = items_iter.next() else {
                    return env.signal(
                        yml_serialization_error,
                        ("Expected an even number of elements in plist", object),
                    );
                };

                let name: String = FN_SYMBOL_NAME.bind(env).call([key])?.into_rust()?;
                let key_normalized = name.strip_prefix(':').unwrap_or(&name);

                map.insert(
                    Yaml::String(key_normalized.to_owned()),
                    serialize_helper(env, value, null_object, false_object)?,
                );
            }
            map
        };
        Ok(Yaml::Hash(map))
    } else {
        env.signal(yml_serialization_error, ("Unexpected type of object", typ))
    }
}
