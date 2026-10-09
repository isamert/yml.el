use emacs::{Env, Result, Value, defun};
use yaml_rust2::{Event, YamlLoader, parser::Parser};

mod yamlwrapper;
use yamlwrapper::YamlWrapper;

// Emacs won't load the module without this.
emacs::plugin_is_GPL_compatible!();

// Register the initialization hook that Emacs will call when it loads the module.
#[emacs::module]
fn init(env: &Env) -> Result<Value<'_>> {
    env.message("Loading yamlmod!")
}

// Parse a yaml string into elisp data structure
#[defun]
fn load(yaml: String) -> Result<YamlWrapper> {
    let documents = YamlLoader::load_from_str(&yaml)?;
    Ok(YamlWrapper(documents[0].clone()))
}

// Search a ypath in yaml. ypath is a dot separated string, to act as nested key
// lookup for yaml
#[defun]
fn ypath_search(yaml: String, ypath: String) -> Result<Option<usize>> {
    let mut remaining_path = split_search_path(&ypath);
    let mut parser = Parser::new(yaml.chars());
    let mut search_depth: u64 = 0;
    loop {
        let (event, marker) = parser.next_token()?;
        match event {
            Event::DocumentEnd | Event::StreamEnd => break,
            Event::Scalar(scalar, _, _, _) => {
                if scalar == remaining_path[0] {
                    remaining_path.remove(0);
                }

                if remaining_path.is_empty() {
                    return Ok(Some(marker.index() + 1));
                }
            }
            Event::MappingStart(_, _) | Event::SequenceStart(_, _) => {
                search_depth += 1;
            }
            Event::MappingEnd | Event::SequenceEnd => {
                search_depth -= 1;
                // reset remaining_path if value not found in a nest
                if search_depth == 0 {
                    remaining_path = split_search_path(&ypath);
                }
            }
            _ => (),
        }
    }
    Ok(None)
}

// helper function for ypath_search
fn split_search_path(search_path: &str) -> Vec<&str> {
    search_path.split('.').collect()
}
