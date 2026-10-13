use fsearch::{index::Index, live::Live, query::Searcher, walk};
use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString, c_char, c_void};
use std::os::unix::ffi::OsStrExt;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;
use std::sync::Once;
use std::sync::atomic::{AtomicUsize, Ordering};
mod engine;

static ACTIVE_BRIDGE_CALLS: AtomicUsize = AtomicUsize::new(0);
static PANIC_HOOK: Once = Once::new();
const UPSTREAM_VERSION: &str = "0.2.1 / 88e63fdf850cf7749deae8198b187accd21f8ba5";

struct ActiveCall;

impl Drop for ActiveCall {
    fn drop(&mut self) {
        ACTIVE_BRIDGE_CALLS.fetch_sub(1, Ordering::SeqCst);
    }
}

fn contained<T>(operation: impl FnOnce() -> T) -> std::thread::Result<T> {
    PANIC_HOOK.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            // The default hook prints payloads before catch_unwind runs.
            // Upstream also uses worker threads. While a bridge call is active,
            // suppress payloads process-wide; outside calls preserve the old hook.
            if ACTIVE_BRIDGE_CALLS.load(Ordering::SeqCst) == 0 {
                previous(info);
            }
        }));
    });
    ACTIVE_BRIDGE_CALLS.fetch_add(1, Ordering::SeqCst);
    let _active = ActiveCall;
    catch_unwind(AssertUnwindSafe(operation))
}

struct Sample {
    root: PathBuf,
    live: Live,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Request {
    id: String,
    query: String,
    limit: i64,
    mode: SearchMode,
    collect_all: bool,
    ordinary_forms: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
enum SearchMode {
    Contains,
    Advanced,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Found {
    path: String,
    kind: u8,
    indexed_size: u64,
    modified_at: u32,
    score: i32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Status {
    mode: &'static str,
    ready: bool,
    engine_validated: bool,
    upstream_version: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Response {
    #[serde(rename = "requestID")]
    request_id: String,
    results: Vec<Found>,
    status: Status,
    error: Option<String>,
    error_kind: Option<&'static str>,
    is_complete: bool,
}

impl Response {
    fn new(request_id: String) -> Self {
        Self {
            request_id,
            results: Vec::new(),
            status: Status {
                mode: "sample",
                ready: true,
                engine_validated: false,
                upstream_version: UPSTREAM_VERSION,
            },
            error: None,
            error_kind: None,
            is_complete: false,
        }
    }
}

fn owned_string(value: String) -> *mut c_char {
    // JSON escapes embedded NUL; fixed adapter errors contain none.
    CString::new(value).map_or(std::ptr::null_mut(), CString::into_raw)
}

unsafe fn input<'a>(value: *const c_char) -> Result<&'a str, String> {
    if value.is_null() {
        return Err("Missing UTF-8 input".into());
    }
    unsafe { CStr::from_ptr(value) }
        .to_str()
        .map_err(|_| "Input must be UTF-8".into())
}

// Recursively scan only this explicit sample root; no Engine or disk crawl.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_sample_open(
    directory: *const c_char,
    error: *mut *mut c_char,
) -> *mut c_void {
    if error.is_null() {
        return std::ptr::null_mut();
    }
    unsafe { *error = std::ptr::null_mut() };
    let result = contained(|| -> Result<Sample, String> {
        let root = PathBuf::from(unsafe { input(directory)? });
        if !root.is_absolute() || !root.is_dir() {
            return Err("Sample directory must be an existing absolute directory".into());
        }
        walk::list_one(root.as_os_str().as_bytes()).ok_or("Cannot read sample directory")?;
        let listings = walk::scan(root.as_os_str().as_bytes(), 2);
        let live = Live::new(Index::build(listings, 0, 0, b"/"));
        Ok(Sample { root, live })
    });
    match result {
        Ok(Ok(sample)) => Box::into_raw(Box::new(sample)).cast(),
        failure => {
            let message = match failure {
                Ok(Err(message)) => message,
                _ => "Fsearch sample initialization failed".into(),
            };
            unsafe { *error = owned_string(message) };
            std::ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_sample_search(
    handle: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    unsafe { search(handle, request_json, false) }
}

#[cfg(debug_assertions)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_sample_test_panic(
    handle: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    unsafe { search(handle, request_json, true) }
}

unsafe fn search(
    handle: *mut c_void,
    request_json: *const c_char,
    inject_panic: bool,
) -> *mut c_char {
    let mut response = Response::new(String::new());
    let result = contained(|| -> Result<Vec<Found>, String> {
        let request: Request = serde_json::from_str(unsafe { input(request_json)? })
            .map_err(|_| "Invalid search request".to_string())?;
        response.request_id = request.id.clone();
        let mut query = make_query(&request)?;
        if handle.is_null() {
            return Err("Sample service is not open".into());
        }
        let sample = unsafe { &*handle.cast::<Sample>() };
        if inject_panic {
            // Exercise worker propagation as well as the outer FFI boundary.
            let worker = std::thread::spawn(|| -> () {
                panic!("Injected test failure with private query material")
            });
            if let Err(payload) = worker.join() {
                std::panic::resume_unwind(payload);
            }
        }
        if matches!(request.mode, SearchMode::Contains) && request.query.trim().is_empty() {
            response.is_complete = true;
            return Ok(Vec::new());
        }
        if query.grep.is_some() {
            return Err("Text content queries are not supported in sample mode".into());
        }
        query.limit = request.limit as usize;
        if request.collect_all {
            query.limit = sample.live.base.n.max(1);
        }
        // The immutable sample has no overlay: n is a proven upper bound.
        response.is_complete = query.limit >= sample.live.base.n;
        let hits = Searcher { live: &sample.live }.search(&query);
        hits.into_iter()
            .map(|hit| {
                let i = hit.idx as usize;
                let mut path = Vec::new();
                sample.live.base.path(i, &mut path);
                // Index::build uses a virtual '/' root for the sample subtree.
                let name =
                    std::str::from_utf8(&path).map_err(|_| "Sample filename is not UTF-8")?;
                let path = sample.root.join(name.trim_start_matches('/'));
                Ok(Found {
                    path: path.to_str().ok_or("Sample path is not UTF-8")?.into(),
                    kind: sample.live.base.kind(i) & 3,
                    indexed_size: sample.live.base.size_of(i),
                    modified_at: sample.live.base.mtime(i),
                    score: hit.score,
                })
            })
            .collect()
    });
    match result {
        Ok(Ok(results)) => response.results = results,
        Ok(Err(error)) => {
            response.error = Some(error);
            response.is_complete = false;
        }
        Err(_) => {
            response.error = Some("Fsearch query failed inside Rust".into());
            response.error_kind = Some("bridge");
            response.is_complete = false;
        }
    }
    serde_json::to_string(&response).map_or(std::ptr::null_mut(), owned_string)
}

fn make_query(request: &Request) -> Result<fsearch::Query, String> {
    if request.id.is_empty() || request.id.contains('\0') {
        return Err("Request identifier must be nonempty and contain no NUL".into());
    }
    if request.query.contains('\0') {
        return Err("Query must contain no NUL".into());
    }
    if !(1..=1000).contains(&request.limit) {
        return Err("Result limit must be between 1 and 1000".into());
    }
    match request.mode {
        SearchMode::Advanced => fsearch::Query::parse(&request.query, "/")
            .map_err(|_| "Invalid advanced query; check its syntax".to_string()),
        SearchMode::Contains => {
            let mut query = fsearch::Query::parse("", "/")?;
            let alternatives = request
                .ordinary_forms
                .iter()
                .map(|form| regex::escape(form))
                .collect::<Vec<_>>()
                .join("|");
            query.name_re = Some(
                regex::bytes::Regex::new(&format!("(?i)(?:{})", alternatives))
                    .map_err(|_| "Name query is too complex".to_string())?,
            );
            Ok(query)
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_sample_close(handle: *mut c_void) {
    if !handle.is_null() {
        let _ = contained(|| unsafe {
            drop(Box::from_raw(handle.cast::<Sample>()));
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_string_free(value: *mut c_char) {
    if !value.is_null() {
        let _ = contained(|| unsafe { drop(CString::from_raw(value)) });
    }
}
