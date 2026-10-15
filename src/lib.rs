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

use emacs::{defun, Env, ErrorKind, IntoLisp, ModuleError, Result, Value, Vector};
use hashlink::LinkedHashMap;
use yaml_rust2::{Yaml, YamlEmitter};

mod yaml_tree;
use yaml_tree::{Node, NodeId, YamlTree};

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

enum ObjectKeyType {
    Symbol,
    Keyword,
    String,
}

struct ParseOptions<'e> {
    array_type: ArrayType,
    object_type: ObjectType,
    object_key_type: ObjectKeyType,
    null_object: Value<'e>,
    false_object: Value<'e>,
}

// * Init

#[emacs::module(name = "yml-core")]
fn init(_: &Env) -> Result<()> {
    Ok(())
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
    SYM_KEYWORD => "keyword"
    SYM_CONS => "cons"
    SYM_STRING => "string"
    SYM_VECTOR => "vector"
    SYM_PROCESS => "process"
    SYM_NIL => "nil"
    SYM_T => "t"
}

emacs::use_functions! {
    FN_CONSP => "consp"
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
    yml_non_string_key "Unexpected non-string key for symbol or keyword conversion" (yml_parse_error)
}

// * defun yml-core--parse-string

#[defun]
fn _parse_string<'e>(
    env: &'e Env,
    yaml: String,
    object_type: Value<'e>,
    object_key_type: Value<'e>,
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

    let object_key_type = match object_key_type {
        value if value == SYM_SYMBOL.bind(env) => ObjectKeyType::Symbol,
        value if value == SYM_KEYWORD.bind(env) => ObjectKeyType::Keyword,
        value if value == SYM_STRING.bind(env) => ObjectKeyType::String,
        value => {
            return env.signal(
                "error",
                (
                    "One of symbol, keyword or string should be specified",
                    value,
                ),
            );
        }
    };

    let options = ParseOptions {
        array_type,
        object_type,
        object_key_type,
        null_object,
        false_object,
    };

    let documents = match YamlTree::load(&yaml) {
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
            .roots
            .iter()
            .map(|&root| yaml_to_lisp(env, &documents, root, &options))
            .collect::<Result<Vec<_>>>()?;

        env.list(&all_documents)
    } else {
        if documents.roots.len() > 1 {
            return env.signal(
                yml_trailing_content,
                ("Expected a single YAML document; found multiple documents",),
            );
        }

        match documents.roots.first() {
            Some(&root) => yaml_to_lisp(env, &documents, root, &options),
            None => Ok(options.null_object),
        }
    }
}

// ** Helpers

fn yaml_to_lisp<'e>(
    env: &'e Env,
    documents: &YamlTree,
    node: NodeId,
    options: &ParseOptions<'e>,
) -> Result<Value<'e>> {
    match &documents.nodes[node] {
        Node::Scalar(scalar) => match scalar {
            Yaml::Null => Ok(options.null_object),
            Yaml::String(s) => s.into_lisp(env),
            Yaml::Boolean(false) => Ok(options.false_object),
            Yaml::Boolean(true) => true.into_lisp(env),
            Yaml::Real(_) => scalar.as_f64().into_lisp(env),
            Yaml::Integer(value) => (*value).into_lisp(env),
            Yaml::BadValue => env.signal(yml_parse_error, ("Invalid YAML value",)),
            _ => unreachable!("document scalar cannot contain a collection"),
        },
        Node::Sequence(items) => {
            let values = items
                .iter()
                .map(|&item| yaml_to_lisp(env, documents, item, options))
                .collect::<Result<Vec<_>>>()?;
            match options.array_type {
                ArrayType::List => env.list(&values),
                ArrayType::Array => env.vector(&values),
            }
        }
        Node::Mapping(pairs) => match options.object_type {
            ObjectType::HashTable => {
                let hash = FN_MAKE_HASH_TABLE.bind(env).call([
                    SYM_PARAM_TEST.bind(env),
                    SYM_EQUAL.bind(env),
                    SYM_PARAM_SIZE.bind(env),
                    pairs.len().into_lisp(env)?,
                ])?;
                for &(key, value) in pairs {
                    FN_PUTHASH.bind(env).call([
                        yaml_key_to_lisp(env, documents, key, options)?,
                        yaml_to_lisp(env, documents, value, options)?,
                        hash,
                    ])?;
                }
                Ok(hash)
            }
            ObjectType::AssociationList => {
                let values = pairs
                    .iter()
                    .map(|&(key, value)| {
                        let lisp_key = yaml_key_to_lisp(env, documents, key, options)?;
                        let lisp_val = yaml_to_lisp(env, documents, value, options)?;
                        env.cons(lisp_key, lisp_val)
                    })
                    .collect::<Result<Vec<_>>>()?;
                env.list(&values)
            }
            ObjectType::PropertyList => {
                let mut plist = Vec::with_capacity(pairs.len() * 2);
                for &(key, value) in pairs {
                    plist.push(yaml_key_to_lisp(env, documents, key, options)?);
                    plist.push(yaml_to_lisp(env, documents, value, options)?);
                }
                env.list(&plist)
            }
        },
    }
}

fn yaml_key_to_lisp<'e>(
    env: &'e Env,
    documents: &YamlTree,
    key: NodeId,
    options: &ParseOptions<'e>,
) -> Result<Value<'e>> {
    match (&options.object_key_type, &options.object_type) {
        (ObjectKeyType::Keyword, _) | (ObjectKeyType::Symbol, ObjectType::PropertyList) => {
            let name = yaml_parse_key_as_string(env, options, documents, key)?;
            env.intern(&format!(":{name}"))
        }
        (ObjectKeyType::Symbol, _) => {
            let name = yaml_parse_key_as_string(env, options, documents, key)?;
            env.intern(name)
        }
        (ObjectKeyType::String, _) => yaml_to_lisp(env, documents, key, options),
    }
}

fn yaml_parse_key_as_string<'e>(
    env: &'e Env,
    options: &ParseOptions<'e>,
    documents: &'e YamlTree,
    node_id: NodeId,
) -> Result<&'e str> {
    match &documents.nodes[node_id] {
        Node::Scalar(Yaml::String(str)) => Ok(str),
        _ => env.signal(
            yml_non_string_key,
            (
                "YAML keys must be strings for symbol or keyword conversion.",
                yaml_to_lisp(env, documents, node_id, options)?,
            ),
        ),
    }
}

// * defun yml-core--serialize

#[defun]
fn _serialize<'e>(
    env: &'e Env,
    object: Value<'e>,
    null_object: Value<'e>,
    false_object: Value<'e>,
) -> Result<String> {
    let yaml = serialize_helper(env, object, null_object, false_object)?;
    let mut output = String::new();
    if let Err(error) = YamlEmitter::new(&mut output).dump(&yaml) {
        return env.signal(yml_serialization_error, (error.to_string(),));
    }
    Ok(output)
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
        match object.into_rust::<i64>() {
            Ok(value) => Ok(Yaml::Integer(value)),
            Err(error)
                if matches!(
                    error.downcast_ref::<ErrorKind>(),
                    Some(ErrorKind::Module(ModuleError::IntegerOutOfRange { .. }))
                ) =>
            {
                env.signal(
                    yml_serialization_error,
                    ("Integer outside supported signed 64-bit range", object),
                )
            }
            Err(error) => Err(error),
        }
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
        // yml.el defines this helper after loading the module, so cant cache the fn.
        let pairs: Vector<'e> = env.call("yml--hash-table-pairs", [object])?.into_rust()?;
        let size = pairs.len();
        let mut map = LinkedHashMap::with_capacity(size);
        for pair in pairs {
            let key: Value<'e> = pair.car()?;
            let value: Value<'e> = pair.cdr()?;
            map.insert(
                serialize_mapping_key(env, key, null_object, false_object)?,
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
                    serialize_mapping_key(env, key, null_object, false_object)?,
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

fn serialize_mapping_key<'e>(
    env: &'e Env,
    key: Value<'e>,
    null_object: Value<'e>,
    false_object: Value<'e>,
) -> Result<Yaml> {
    if env.type_of(key)? == SYM_SYMBOL.bind(env) {
        let name: String = FN_SYMBOL_NAME.bind(env).call([key])?.into_rust()?;
        Ok(Yaml::String(name))
    } else {
        serialize_helper(env, key, null_object, false_object)
    }
}

// * defun yml-core-version

// This might be useful for diagnosing potential problems. Not using
// it in the installer, it depends on the path of the library to
// resolve the correct version.

#[defun]
fn version() -> Result<String> {
    Ok(env!("CARGO_PKG_VERSION").to_owned())
}
