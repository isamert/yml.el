use emacs::{Env, IntoLisp, Result, Value};
use yaml_rust2::Yaml;

pub struct YamlWrapper(pub Yaml);

impl<'e> IntoLisp<'e> for YamlWrapper {
    fn into_lisp(self, env: &'e Env) -> Result<Value<'e>> {
        match self.0 {
            Yaml::Array(items) => {
                let values = items
                    .into_iter()
                    .map(|item| YamlWrapper(item).into_lisp(env))
                    .collect::<Result<Vec<_>>>()?;
                env.vector(&values)
            }
            Yaml::String(s) => s.into_lisp(env),
            Yaml::Boolean(t) => t.into_lisp(env),
            Yaml::Hash(t) => {
                let hash = env.call(
                    "make-hash-table",
                    [env.intern(":test")?, env.intern("equal")?],
                )?;
                for (key, value) in t {
                    env.call(
                        "puthash",
                        [
                            YamlWrapper(key).into_lisp(env)?,
                            YamlWrapper(value).into_lisp(env)?,
                            hash,
                        ],
                    )?;
                }
                Ok(hash)
            }
            Yaml::Real(t) => env.call("string-to-number", [t.into_lisp(env)?]),
            Yaml::Integer(t) => t.into_lisp(env),
            _ => env.intern("nil"),
        }
    }
}
