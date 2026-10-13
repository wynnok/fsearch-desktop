//! Opt-in validation Engine. Confinement is installed before any worker starts.
use super::*;
use fsearch::{Engine, Options};
use std::path::Path;
use std::sync::{Arc, Mutex};

unsafe extern "C" {
    fn sandbox_init(profile: *const c_char, flags: u64, error: *mut *mut c_char) -> i32;
    fn sandbox_free_error(error: *mut c_char);
}

struct EngineHandle {
    engine: Engine,
    root: PathBuf,
    changes: Arc<Mutex<Vec<Change>>>,
}

#[derive(Serialize)]
struct Change {
    path: String,
    recursive: bool,
}

// SKIP is process-wide upstream state; a process gets one confinement policy.
static STARTED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

fn confine(root: &Path, data: &Path) -> Result<Vec<PathBuf>, String> {
    let mut skip = Vec::new();
    let mut ancestors = Vec::new();
    let mut child = root;
    while let Some(parent) = child.parent() {
        ancestors.push(parent.to_path_buf());
        for entry in std::fs::read_dir(parent).map_err(|_| "Cannot prove scan exclusions")? {
            let path = entry.map_err(|_| "Cannot prove scan exclusions")?.path();
            if path != child {
                skip.push(path);
            }
        }
        child = parent;
    }
    // Ancestors may be listed, but no sibling directory or new sibling can
    // be read. Runtime libraries remain readable and are excluded by SKIP.
    let quote = |p: &Path| serde_json::to_string(&p.to_string_lossy()).unwrap();
    let mut profile = String::from("(version 1)(allow default)(deny file-read-data)");
    for p in [root, data] {
        profile.push_str(&format!("(allow file-read-data (subpath {}))", quote(p)));
    }
    for p in &ancestors {
        profile.push_str(&format!("(allow file-read-data (literal {}))", quote(p)));
    }
    for p in [
        "/System",
        "/usr/lib",
        "/usr/share/langid",
        "/Library/Apple",
        "/Applications/Xcode.app",
    ] {
        profile.push_str(&format!("(allow file-read-data (subpath \"{p}\"))"));
    }
    profile.push_str("(allow file-read-data (literal \"/dev/null\") (literal \"/dev/urandom\"))");
    let profile = CString::new(profile).map_err(|_| "Invalid confinement path")?;
    let mut error = std::ptr::null_mut();
    let result = unsafe { sandbox_init(profile.as_ptr(), 0, &mut error) };
    if !error.is_null() {
        unsafe { sandbox_free_error(error) };
    }
    if result != 0 {
        return Err("Cannot install Engine scan confinement; Engine was not started".into());
    }
    Ok(skip)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_engine_open(
    directory: *const c_char,
    index: *const c_char,
    error: *mut *mut c_char,
) -> *mut c_void {
    if error.is_null() {
        return std::ptr::null_mut();
    }
    unsafe { *error = std::ptr::null_mut() };
    let result = contained(|| -> Result<EngineHandle, String> {
        let root = PathBuf::from(unsafe { input(directory)? })
            .canonicalize()
            .map_err(|_| "Engine fixture must exist")?;
        let data = PathBuf::from(unsafe { input(index)? });
        if !data.is_absolute() || root == Path::new("/") || data.starts_with(&root) {
            return Err("Engine index must be an absolute directory outside its fixture".into());
        }
        std::fs::create_dir_all(&data).map_err(|_| "Cannot create independent Engine index")?;
        let data = data
            .canonicalize()
            .map_err(|_| "Cannot resolve independent Engine index")?;
        if data.starts_with(&root) || root.starts_with(&data) {
            return Err("Fixture and index must be separate".into());
        }
        if STARTED.swap(true, Ordering::SeqCst) {
            return Err("Engine confinement requires one Engine per process".into());
        }
        let sibling = root
            .parent()
            .ok_or("Fixture requires a parent")?
            .join("confinement-denied.txt");
        std::fs::read(&sibling)
            .map_err(|_| "Create confinement-denied.txt beside the fixture before validation")?;
        let skip = confine(&root, &data)?;
        // Independently prove an excluded sibling cannot be read before start.
        // read_dir on a runtime directory is allowed, so use the fixture's sibling.
        if std::fs::read(&sibling).is_ok() {
            return Err("Engine confinement proof failed".into());
        }
        let engine = Engine::start(Options {
            dir: data,
            home: root.to_string_lossy().into(),
            skip: Some(skip),
        })?;
        let changes = Arc::new(Mutex::new(Vec::new()));
        let queue = changes.clone();
        let change_root = root.clone();
        engine.on_change(move |batch| {
            let mut queue = queue.lock().unwrap();
            for (path, recursive) in batch {
                let path = PathBuf::from(std::ffi::OsStr::from_bytes(path));
                if path.starts_with(&change_root) {
                    queue.push(Change {
                        path: path.to_string_lossy().into(),
                        recursive: *recursive,
                    });
                }
            }
            // Notification batches are invalidation signals, not a file journal.
            if queue.len() > 1024 {
                let excess = queue.len() - 1024;
                queue.drain(..excess);
            }
        });
        Ok(EngineHandle {
            engine,
            root,
            changes,
        })
    });
    match result {
        Ok(Ok(handle)) => Box::into_raw(Box::new(handle)).cast(),
        failure => {
            let message = match failure {
                Ok(Err(message)) => message,
                _ => "Engine initialization failed".into(),
            };
            unsafe { *error = owned_string(message) };
            std::ptr::null_mut()
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EngineStatus {
    mode: &'static str,
    ready: bool,
    engine_validated: bool,
    upstream_version: &'static str,
    owner: bool,
    entries: usize,
    content_pending: usize,
}

fn status(handle: &EngineHandle) -> EngineStatus {
    let s = handle.engine.status();
    EngineStatus {
        mode: "engine",
        ready: s.ready,
        engine_validated: true,
        upstream_version: UPSTREAM_VERSION,
        owner: s.owner,
        entries: s.entries,
        content_pending: s.content_pending,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_engine_status(handle: *mut c_void) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    contained(|| {
        serde_json::to_string(&status(unsafe { &*handle.cast::<EngineHandle>() })).map(owned_string)
    })
    .ok()
    .and_then(Result::ok)
    .unwrap_or(std::ptr::null_mut())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_engine_changes(handle: *mut c_void) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    contained(|| {
        let h = unsafe { &*handle.cast::<EngineHandle>() };
        serde_json::to_string(&std::mem::take(&mut *h.changes.lock().unwrap())).map(owned_string)
    })
    .ok()
    .and_then(Result::ok)
    .unwrap_or(std::ptr::null_mut())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_engine_save(handle: *mut c_void) {
    if !handle.is_null() {
        let _ = contained(|| unsafe { &*handle.cast::<EngineHandle>() }.engine.save());
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_engine_search(
    handle: *mut c_void,
    json: *const c_char,
) -> *mut c_char {
    unsafe { engine_search(handle, json, false) }
}

#[cfg(debug_assertions)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_engine_test_panic(
    handle: *mut c_void,
    json: *const c_char,
) -> *mut c_char {
    unsafe { engine_search(handle, json, true) }
}

unsafe fn engine_search(
    handle: *mut c_void,
    json: *const c_char,
    inject_panic: bool,
) -> *mut c_char {
    let mut response = Response::new(String::new());
    let result = contained(|| -> Result<Vec<Found>, String> {
        if handle.is_null() {
            return Err("Engine is not open".into());
        }
        let h = unsafe { &*handle.cast::<EngineHandle>() };
        if inject_panic {
            let worker = std::thread::spawn(|| -> () {
                panic!("Injected Engine test failure with private query material")
            });
            if let Err(payload) = worker.join() {
                std::panic::resume_unwind(payload);
            }
        }
        let request: Request =
            serde_json::from_str(unsafe { input(json)? }).map_err(|_| "Invalid search request")?;
        response.request_id = request.id.clone();
        let mut query = super::make_query(&request)?;
        response.status.mode = "engine";
        response.status.ready = h.engine.status().ready;
        response.status.engine_validated = true;
        if query.grep.is_some() {
            return Err("Text content search is not exposed by this validation window".into());
        }
        if query
            .scope
            .as_ref()
            .is_some_and(|p| !Path::new(std::ffi::OsStr::from_bytes(p)).starts_with(&h.root))
        {
            return Err("Query scope is outside the confined fixture".into());
        }
        query
            .scope
            .get_or_insert_with(|| h.root.as_os_str().as_bytes().to_vec());
        if matches!(request.mode, SearchMode::Contains) && request.query.trim().is_empty() {
            response.is_complete = true;
            return Ok(Vec::new());
        }
        // Upstream huge-limit regression covers usize::MAX; Engine search holds
        // one live read lock for the whole collection, including its overlay.
        query.limit = if request.collect_all {
            usize::MAX
        } else {
            request.limit as usize
        };
        let found = h.engine.search(&query)?;
        response.is_complete = request.collect_all;
        found
            .into_iter()
            .map(|f| {
                Ok(Found {
                    path: f
                        .path
                        .to_str()
                        .ok_or("Engine filename is not UTF-8")?
                        .into(),
                    kind: f.kind & 3,
                    indexed_size: f.size,
                    modified_at: f.mtime,
                    score: f.score,
                })
            })
            .collect()
    });
    match result {
        Ok(Ok(found)) => response.results = found,
        Ok(Err(error)) => response.error = Some(error),
        Err(_) => {
            response.error = Some("Engine query failed inside Rust".into());
            response.error_kind = Some("bridge");
        }
    }
    if response.error.is_some() {
        response.is_complete = false;
    }
    serde_json::to_string(&response).map_or(std::ptr::null_mut(), owned_string)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_engine_close(handle: *mut c_void) {
    // Upstream workers own Engine clones. Full shutdown is process exit;
    // dropping a service must never pretend to release the index lock.
    if !handle.is_null() {
        let _ = contained(|| unsafe {
            drop(Box::from_raw(handle.cast::<EngineHandle>()));
        });
    }
}
