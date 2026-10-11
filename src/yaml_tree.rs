// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Isa Mert Gurbuz

//! Lightweight YAML document tree.
//!
//! ---
//!
//! The alternative of this is simply using
//! `YamlLoader::load_from_str(&yaml)` and traversing that output,
//! instead of creating our own YAML document tree. This completely
//! gets rid of this file but performance drops by ~20-30% (on really
//! big files), and that'd due to `YamlLoader` using `LinkedHashMap`
//! for YAML objects. Instead here we simply keep them as
//! `Vec<(NodeId, NodeId)>`, no hashing overhead. In my benchmarks,
//! the earlier implementation (the one that uses `YamlLoader`) was
//! ~10-20% slower than emacs-libyaml parser because of this.
//!
//! ---
//!
//! The whole Lisp object construction can be moved into this event
//! receiver, instead of building this YAML document and then
//! traversing it but:
//!
//! - The performance is already really good.
//! - Implementation becomes much more hairy.
//! - We can easily go back to YamlLoader based implementation if
//!   upstream makes `LinkedHashMap` usage optional.
//! - Having the tree built earlier also have some advantages like
//!   knowing map sizes etc. which enables us to allocate Lisp
//!   hash-tables/vectors with known size.

use std::collections::HashMap;

use yaml_rust2::parser::{Event, MarkedEventReceiver, Parser};
use yaml_rust2::scanner::{Marker, ScanError, TScalarStyle};
use yaml_rust2::{Yaml, YamlLoader};

// * Types

pub type NodeId = usize;

pub enum Node {
    Scalar(Yaml),
    Sequence(Vec<NodeId>),
    Mapping(Vec<(NodeId, NodeId)>),
}

#[derive(Default)]
pub struct YamlTree {
    pub nodes: Vec<Node>,
    pub roots: Vec<NodeId>,
    stack: Vec<Frame>,
    anchors: HashMap<usize, NodeId>,
    root: Option<NodeId>,
    error: Option<ScanError>,
}

struct Frame {
    node: NodeId,
    anchor: usize,
    key: Option<NodeId>,
}

// * Impls

impl YamlTree {
    pub fn load(source: &str) -> Result<Self, ScanError> {
        let mut documents = Self::default();
        Parser::new_from_str(source).load(&mut documents, true)?;
        match documents.error {
            Some(error) => Err(error),
            None => Ok(documents),
        }
    }

    fn add(&mut self, node: Node) -> NodeId {
        let id = self.nodes.len();
        self.nodes.push(node);
        id
    }

    fn attach(&mut self, node: NodeId, anchor: usize, marker: Marker) -> Result<(), ScanError> {
        if anchor > 0 {
            self.anchors.insert(anchor, node);
        }

        if let Some(parent) = self.stack.last_mut() {
            let parent_node = self
                .nodes
                .get_mut(parent.node)
                .ok_or_else(|| ScanError::new(marker, "Invalid YAML parent node"))?;
            match parent_node {
                Node::Sequence(items) => items.push(node),
                Node::Mapping(pairs) => match parent.key.take() {
                    Some(key) => pairs.push((key, node)),
                    None => parent.key = Some(node),
                },
                Node::Scalar(_) => {
                    return Err(ScanError::new(
                        marker,
                        "Cannot attach YAML node to a scalar",
                    ));
                }
            }
        } else {
            self.root = Some(node);
        }
        Ok(())
    }

    fn on_event_impl(&mut self, event: Event, marker: Marker) -> Result<(), ScanError> {
        match event {
            Event::DocumentStart => {
                self.anchors.clear();
                self.root = None;
            }
            Event::DocumentEnd => {
                let root = self
                    .root
                    .ok_or_else(|| ScanError::new(marker, "YAML document ended without a root"))?;
                self.roots.push(root);
            }
            Event::SequenceStart(anchor, _) | Event::MappingStart(anchor, _) => {
                let node = match event {
                    Event::SequenceStart(..) => Node::Sequence(Vec::new()),
                    _ => Node::Mapping(Vec::new()),
                };
                let node = self.add(node);
                self.stack.push(Frame {
                    node,
                    anchor,
                    key: None,
                });
            }
            Event::SequenceEnd | Event::MappingEnd => {
                let frame = self
                    .stack
                    .pop()
                    .ok_or_else(|| ScanError::new(marker, "Unexpected YAML container end"))?;
                self.attach(frame.node, frame.anchor, marker)?;
            }
            Event::Scalar(value, style, anchor, tag) => {
                let scalar = if style != TScalarStyle::Plain {
                    Yaml::String(value)
                } else if tag.is_none() {
                    Yaml::from_str(&value)
                } else {
                    // Reuse upstream's tag resolution rather than
                    // maintaining a second scalar schema.  Untagged
                    // scalars (the common path) do not instantiate a
                    // YamlLoader.
                    let mut loader = YamlLoader::default();
                    loader.on_event(Event::Scalar(value, style, 0, tag), marker);
                    loader.on_event(Event::DocumentEnd, marker);
                    loader.documents().first().cloned().ok_or_else(|| {
                        ScanError::new(marker, "Tagged YAML scalar did not produce a value")
                    })?
                };
                let node = self.add(Node::Scalar(scalar));
                self.attach(node, anchor, marker)?;
            }
            Event::Alias(anchor) => {
                let node = self.anchors.get(&anchor).copied().ok_or_else(|| {
                    ScanError::new(
                        marker,
                        "YAML alias refers to an unknown or unfinished anchor",
                    )
                })?;
                self.attach(node, 0, marker)?;
            }
            Event::Nothing | Event::StreamStart | Event::StreamEnd => {}
        }
        Ok(())
    }
}

impl MarkedEventReceiver for YamlTree {
    fn on_event(&mut self, event: Event, marker: Marker) {
        if self.error.is_some() {
            return;
        }
        if let Err(error) = self.on_event_impl(event, marker) {
            self.error = Some(error);
        }
    }
}
