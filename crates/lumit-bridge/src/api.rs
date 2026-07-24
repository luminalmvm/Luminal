use core::{panic, prelude::v1};
use std::{
    collections::BTreeMap,
    error::Error,
    fmt,
    path::PathBuf,
    println,
    sync::{Arc, LazyLock, RwLock},
    todo,
};

use flutter_rust_bridge::frb;
use lumit_core::{
    model::{FootageItem, Layer, ProjectItem},
    store::DocumentChange,
    Document, DocumentStore, OpError,
};
use lumit_project::JournalFile;
use lumit_ui::app_state::media::MediaStatus;
use serde_json::json;
use uuid::Uuid;

use crate::{frb_generated::StreamSink, media::MediaCache};

#[frb(ignore_all)]
pub struct LumitBridgeState {
    pub store: DocumentStore,
    pub path: Option<PathBuf>,
    pub media: MediaCache,
    pub journal: Option<JournalFile>,
}

type CallbackStream = StreamSink<ScopedChange>;

// Global Singleton for storing bridged state.
// Supports storing multiple projects, but for now should only ever have one
// just in case one day we want to support having multiple projects open at a time
static PROJECTS: LazyLock<RwLock<BTreeMap<Uuid, Arc<RwLock<LumitBridgeState>>>>> =
    LazyLock::new(|| RwLock::new(BTreeMap::new()));

// Guarded by different lock, so we dont deadlock if called while PROJECTS is locked
static STREAMS: LazyLock<RwLock<BTreeMap<Uuid, Arc<CallbackStream>>>> =
    LazyLock::new(|| RwLock::new(BTreeMap::new()));

#[frb(opaque)]
#[derive(Debug)]
pub struct LumitProject {
    id: Uuid,
}

#[frb(opaque)]
#[derive(Debug)]
pub struct LumitProjectItem {
    project: Uuid,
    id: Uuid,
}

#[frb(opaque)]
#[derive(Debug)]
pub struct LumitComposition {
    project_id: Uuid,
    item_id: Uuid,
}

#[frb(opaque)]
#[derive(Debug)]
pub struct LumitLayer {
    project_id: Uuid,
    comp_id: Uuid,
    layer_id: Uuid,
}

#[frb(non_opaque)]
#[derive(Debug)]
pub struct ScopedChange {
    pub project: LumitProject,
    pub item: Option<LumitProjectItem>,
    pub layer: Option<LumitLayer>,
}

#[derive(Debug)]
pub enum BridgeError {
    InvalidProject,
    InvalidComp,
    InvalidItem,
    InvalidLayer,
    ReadFailed,
    WriteFailed,
    OpError(OpError),
}

impl Error for BridgeError {}

impl fmt::Display for BridgeError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        let _ = match &self {
            BridgeError::ReadFailed => write!(f, "Read Failed"),
            BridgeError::InvalidProject => write!(f, "Invalid ProjectItem"),
            BridgeError::InvalidComp => write!(f, "Invalid Comp"),
            BridgeError::InvalidItem => write!(f, "Invalid Item"),
            BridgeError::InvalidLayer => write!(f, "Invalid Layer"),
            BridgeError::WriteFailed => write!(f, "Write Failed"),
            BridgeError::OpError(op_error) => write!(f, "{}", op_error),
        };

        Ok(())
    }
}

impl LumitBridgeState {
    #[frb(sync)]
    pub fn new_project(on_change_stream: Option<CallbackStream>) -> LumitProject {
        let id = Uuid::now_v7();

        let mut p = PROJECTS.write().unwrap();

        let mut state = LumitBridgeState {
            store: DocumentStore::new(Document::new()),
            path: None,
            media: MediaCache::default(),
            journal: None,
        };

        match on_change_stream {
            Some(stream) => {
                let mut s = STREAMS.write().unwrap();
                s.insert(id.clone(), Arc::new(stream));
            }
            None => (),
        }

        state.store.set_callback(Arc::new(move |c| {
            Self::handle_change_callback(c, id.clone())
        }));

        p.insert(id.clone(), Arc::new(RwLock::new(state)));

        LumitProject { id: id }
    }

    #[frb(sync)]
    pub fn get_current_project() -> Option<LumitProject> {
        let p = PROJECTS.read().unwrap();
        let item = p.iter().next();

        match item {
            Some(i) => Some(LumitProject { id: i.0.clone() }),
            None => None,
        }
    }

    fn handle_change_callback(document_change: DocumentChange, project_id: Uuid) {
        let p = STREAMS.read().unwrap();
        let p = p.get(&project_id);

        let converted = json!(document_change.op);

        let mut change = ScopedChange {
            project: LumitProject {
                id: project_id.clone(),
            },
            item: None,
            layer: None,
        };

        match converted {
            serde_json::Value::Object(map) => {
                let layer = map.get("layer").map_or(None, |f| {
                    f.as_str()
                        .map_or(None, |f| Some(Uuid::parse_str(f).unwrap()))
                });

                let comp = map.get("comp").map_or(None, |f| {
                    f.as_str()
                        .map_or(None, |f| Some(Uuid::parse_str(f).unwrap()))
                });

                if let Some(comp) = comp {
                    change.item = Some(LumitProjectItem {
                        project: project_id.clone(),
                        id: comp.clone(),
                    });

                    if let Some(layer) = layer {
                        change.layer = Some(LumitLayer {
                            project_id: project_id.clone(),
                            comp_id: comp.clone(),
                            layer_id: layer.clone(),
                        })
                    }
                }
            }
            _ => panic!(),
        }

        println!("Got change: {:#?}", change);

        match &p {
            Some(stream) => {
                _ = stream.add(change);
            }
            None => (),
        }

        println!("Document changed! - {}", project_id.clone());
    }

    #[frb(sync)]
    pub fn open_project(
        path: &str,
        on_change_stream: Option<CallbackStream>,
    ) -> Option<LumitProject> {
        let path = PathBuf::from(path);
        match lumit_project::open(&path) {
            Ok((doc, _manifest)) => {
                let id = Uuid::now_v7();

                let mut state = LumitBridgeState {
                    store: DocumentStore::new(doc),
                    path: Some(path),
                    media: MediaCache::default(),
                    journal: None,
                };
                state.store.set_callback(Arc::new(move |c| {
                    Self::handle_change_callback(c, id.clone())
                }));

                match on_change_stream {
                    Some(stream) => {
                        let mut s = STREAMS.write().unwrap();
                        s.insert(id.clone(), Arc::new(stream));
                    }
                    None => (),
                }

                {
                    let mut p = PROJECTS.write().unwrap();

                    for entry in p.iter_mut() {
                        let mut e = entry.1.write().unwrap();
                        e.media.clear()
                    }

                    // Clear any other project that is currently open
                    // Will also prevent any existing references from working
                    p.clear();

                    p.insert(id.clone(), Arc::new(RwLock::new(state)));
                }

                Some(LumitProject { id })
            }
            Err(_) => None,
        }
    }
}

impl LumitProject {
    fn state(&self) -> Arc<std::sync::RwLock<LumitBridgeState>> {
        let projects = PROJECTS.read().unwrap();
        let project = projects.get(&self.id);

        project.unwrap().clone()
    }

    #[frb(sync)]
    pub fn get_items(&self) -> Vec<LumitProjectItem> {
        let s = self.state();
        let s = s.read().unwrap();

        let snapshot = s.store.snapshot();

        snapshot
            .items
            .iter()
            .map(|i| LumitProjectItem {
                project: self.id.clone(),
                id: i.id(),
            })
            .collect()
    }

    #[frb(sync)]
    pub fn undo(&self) -> Result<(), BridgeError> {
        let s = self.state();
        let s = s.read().unwrap();

        s.store.undo().map_err(|e| BridgeError::OpError(e))?;

        Ok(())
    }

    #[frb(sync)]
    pub fn redo(&self) -> Result<(), BridgeError> {
        let s = self.state();
        let s = s.read().unwrap();

        s.store.redo().map_err(|e| BridgeError::OpError(e))?;

        Ok(())
    }
}

#[frb(non_opaque)]
pub enum LumitProjectItemType {
    Footage,
    Solid,
    Composition(LumitComposition),
    Folder,
}

pub enum LumitMediaStatus {
    Missing,
    Ready,
}

#[frb(non_opaque)]
pub struct LumitProjectItemInfo {
    pub item_type: LumitProjectItemType,
    pub name: String,
}

impl LumitProjectItem {
    // TODO: create macros that can be used for shorthand to get the project item like: item!()
    // it should automatically handle errors
    #[frb(ignore)]
    fn project(&self) -> Result<Arc<std::sync::RwLock<LumitBridgeState>>, BridgeError> {
        let projects = PROJECTS.read().unwrap();
        let project = projects.get(&self.project);

        let p = project.ok_or(BridgeError::InvalidProject)?;
        Ok(p.clone())
    }

    #[frb(sync)]
    pub fn equals(&self, item: &LumitProjectItem) -> bool {
        self.id == item.id
            && self.project == item.project
    }

    #[frb(sync)]
    pub fn get_info(&self) -> Result<LumitProjectItemInfo, BridgeError> {
        let proj = self.project()?;
        let proj = proj.read().map_err(|_| BridgeError::ReadFailed)?;

        let snapshot = proj.store.snapshot();
        let item = snapshot.item(self.id).unwrap();

        match item {
            lumit_core::model::ProjectItem::Footage(footage_item) => Ok(LumitProjectItemInfo {
                item_type: LumitProjectItemType::Footage,
                name: footage_item.name.clone(),
            }),
            lumit_core::model::ProjectItem::Folder(folder) => Ok(LumitProjectItemInfo {
                item_type: LumitProjectItemType::Folder,
                name: folder.name.clone(),
            }),
            lumit_core::model::ProjectItem::Composition(composition) => Ok(LumitProjectItemInfo {
                item_type: LumitProjectItemType::Composition(LumitComposition {
                    project_id: self.project.clone(),
                    item_id: self.id.clone(),
                }),
                name: composition.name.clone(),
            }),
            lumit_core::model::ProjectItem::Solid(solid_def) => Ok(LumitProjectItemInfo {
                item_type: LumitProjectItemType::Solid,
                name: solid_def.name.clone(),
            }),
        }
    }

    // copy pasted from lumit-ui/src/headless.rs
    // would be good if these could be shared
    fn footage_path(p: &LumitBridgeState, f: &FootageItem) -> PathBuf {
        if f.media.absolute_path.is_empty() {
            let path = p.path.clone().unwrap();
            let path = path.parent().unwrap();
            println!("current path: {}", path.to_str().unwrap());
            let path = path.join(PathBuf::from(&f.media.relative_path));
            path.canonicalize().unwrap()
        } else {
            PathBuf::from(&f.media.absolute_path)
        }
    }

    pub fn get_status(&self) -> Result<LumitMediaStatus, BridgeError> {
        let proj = self.project()?;
        let proj = proj.read().map_err(|_| BridgeError::ReadFailed)?;

        let snapshot = proj.store.snapshot();
        let item = snapshot.item(self.id).unwrap();

        match item {
            lumit_core::model::ProjectItem::Footage(footage_item) => {
                let path = Self::footage_path(&proj, footage_item);

                let probe = lumit_media::probe::probe(&path);

                match probe {
                    // not sure where this info comes from
                    Ok(v) => Ok(LumitMediaStatus::Ready),
                    Err(e) => Ok(LumitMediaStatus::Missing),
                }
            }
            lumit_core::model::ProjectItem::Folder(_) => Ok(LumitMediaStatus::Missing),
            lumit_core::model::ProjectItem::Composition(_) => Ok(LumitMediaStatus::Missing),
            lumit_core::model::ProjectItem::Solid(_) => Ok(LumitMediaStatus::Missing),
        }
    }
}

impl LumitComposition {
    #[frb(ignore)]
    fn project(&self) -> Result<Arc<std::sync::RwLock<LumitBridgeState>>, BridgeError> {
        let projects = PROJECTS.read().unwrap();
        let project = projects.get(&self.project_id);

        let p = project.ok_or(BridgeError::InvalidProject)?;
        Ok(p.clone())
    }

    #[frb(sync)]
    pub fn get_layers(&self) -> Result<Vec<LumitLayer>, BridgeError> {
        let proj = self.project()?;
        let proj = proj.read().map_err(|_| BridgeError::ReadFailed)?;

        let snapshot = proj.store.snapshot();
        let item = snapshot.item(self.item_id).unwrap();

        match item {
            lumit_core::model::ProjectItem::Composition(composition) => Ok(composition
                .layers
                .iter()
                .map(|i| LumitLayer {
                    project_id: self.project_id.clone(),
                    comp_id: self.item_id.clone(),
                    layer_id: i.id.clone(),
                })
                .collect()),
            _ => todo!(),
        }
    }
}

impl LumitLayer {
    #[frb(ignore)]
    fn project(&self) -> Result<Arc<std::sync::RwLock<LumitBridgeState>>, BridgeError> {
        let projects = PROJECTS.read().unwrap();
        let project = projects.get(&self.project_id);

        let p = project.ok_or(BridgeError::InvalidProject)?;
        Ok(p.clone())
    }

    #[frb(ignore)]
    fn item(&self) -> Result<Layer, BridgeError> {
        let proj = self.project()?;
        let proj = proj.read().map_err(|_| BridgeError::ReadFailed)?;
        let snapshot = proj.store.snapshot();

        let item = snapshot
            .item(self.comp_id)
            .ok_or(BridgeError::InvalidItem)?;

        let comp = match item {
            lumit_core::model::ProjectItem::Composition(composition) => composition,
            _ => return Err(BridgeError::InvalidItem),
        };

        let layer = comp
            .layers
            .iter()
            .filter(|f| f.id == self.layer_id)
            .next()
            .ok_or(BridgeError::InvalidLayer)?;

        Ok(layer.clone())
    }

    #[frb(sync)]
    pub fn equals(&self, layer: &LumitLayer) -> bool {
        self.comp_id == layer.comp_id
            && self.project_id == layer.project_id
            && self.layer_id == layer.layer_id
    }

    #[frb(sync)]
    pub fn get_name(&self) -> Result<String, BridgeError> {
        let item = self.item()?;

        Ok(item.name)
    }

    #[frb(sync)]
    pub fn rename(&self, name: String) -> Result<(), BridgeError> {
        let proj = self.project()?;
        let proj = proj.write().map_err(|_| BridgeError::WriteFailed)?;

        proj.store
            .commit(lumit_core::Op::RenameLayer {
                comp: self.comp_id,
                layer: self.layer_id,
                name,
            })
            .map_err(|r| BridgeError::OpError(r))?;

        Ok(())
    }
}
