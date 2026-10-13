use fsearch::{index::Index, live::Live, query::Searcher, walk};
use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString, c_char, c_void};
use std::os::unix::ffi::OsStrExt;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;

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
                upstream_version: "0.2.1 / 88e63fdf850cf7749deae8198b187accd21f8ba5",
            },
            error: None,
        }
    }
}

fn owned_string(value: String) -> *mut c_char {
    // JSON escapes embedded NUL; fixed adapter errors contain none.
    CString::new(value)
        .expect("adapter output contains NUL")
        .into_raw()
}

unsafe fn input<'a>(value: *const c_char) -> Result<&'a str, String> {
    if value.is_null() {
        return Err("Missing UTF-8 input".into());
    }
    unsafe { CStr::from_ptr(value) }
        .to_str()
        .map_err(|_| "Input must be UTF-8".into())
}

// Only list this directory, without recursion, FSEvents or Engine::start.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_sample_open(
    directory: *const c_char,
    error: *mut *mut c_char,
) -> *mut c_void {
    if error.is_null() {
        return std::ptr::null_mut();
    }
    unsafe { *error = std::ptr::null_mut() };
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<Sample, String> {
        let root = PathBuf::from(unsafe { input(directory)? });
        if !root.is_absolute() || !root.is_dir() {
            return Err("Sample directory must be an existing absolute directory".into());
        }
        let listing =
            walk::list_one(root.as_os_str().as_bytes()).ok_or("Cannot read sample directory")?;
        let live = Live::new(Index::build(vec![listing], 0, 0, b"/"));
        Ok(Sample { root, live })
    }));
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
    let mut response = Response::new(String::new());
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<Vec<Found>, String> {
        let request: Request = serde_json::from_str(unsafe { input(request_json)? })
            .map_err(|_| "Invalid search request".to_string())?;
        response.request_id = request.id;
        if handle.is_null() {
            return Err("Sample service is not open".into());
        }
        let sample = unsafe { &*handle.cast::<Sample>() };
        if !(1..=1000).contains(&request.limit) {
            return Err("Result limit must be between 1 and 1000".into());
        }
        let mut query = fsearch::Query::parse(&request.query, "/")?;
        query.limit = request.limit as usize;
        let hits = Searcher { live: &sample.live }.search(&query);
        hits.into_iter()
            .map(|hit| {
                let i = hit.idx as usize;
                let mut path = Vec::new();
                sample.live.base.path(i, &mut path);
                // Index::build uses a virtual '/' root for this one listing.
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
    }));
    match result {
        Ok(Ok(results)) => response.results = results,
        Ok(Err(error)) => response.error = Some(error),
        Err(_) => response.error = Some("Fsearch query failed inside Rust".into()),
    }
    owned_string(serde_json::to_string(&response).expect("serializable response"))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_sample_close(handle: *mut c_void) {
    if !handle.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
            drop(Box::from_raw(handle.cast::<Sample>()));
        }));
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsearch_string_free(value: *mut c_char) {
    if !value.is_null() {
        unsafe { drop(CString::from_raw(value)) };
    }
}
