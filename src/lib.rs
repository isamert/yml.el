use emacs::{defun, Env, IntoLisp, Result, Value};
use yaml_rust2::{Yaml, YamlLoader};

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

#[emacs::module]
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
