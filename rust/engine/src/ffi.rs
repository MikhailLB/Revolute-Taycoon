//! C ABI consumed by Swift. Strings cross as NUL-terminated UTF-8 JSON owned
//! by Rust and must be released with `rt_string_free`; byte buffers with
//! `rt_bytes_free`.

use std::ffi::{CStr, CString, c_char};

use serde_json::json;

use crate::actions::{self, Action};
use crate::{Engine, catalog, save, snapshot};

fn to_c(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rt_engine_new(seed: u64) -> *mut Engine {
    Box::into_raw(Box::new(Engine::new(seed)))
}

/// Returns null when the save is corrupt or has been tampered with.
///
/// # Safety
/// `data` must point to `len` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rt_engine_load(data: *const u8, len: usize) -> *mut Engine {
    if data.is_null() || len == 0 {
        return std::ptr::null_mut();
    }
    let bytes = unsafe { std::slice::from_raw_parts(data, len) };
    match save::open(bytes) {
        Some(state) => Box::into_raw(Box::new(Engine::from_state(state))),
        None => std::ptr::null_mut(),
    }
}

/// # Safety
/// `engine` must come from `rt_engine_new`/`rt_engine_load` and not be used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rt_engine_free(engine: *mut Engine) {
    if !engine.is_null() {
        drop(unsafe { Box::from_raw(engine) });
    }
}

/// Advances the simulation by up to `hours` and returns status flags.
///
/// # Safety
/// `engine` must be a live engine pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rt_engine_step(engine: *mut Engine, hours: u32) -> u32 {
    let Some(e) = (unsafe { engine.as_mut() }) else { return 0 };
    e.step(hours)
}

/// # Safety
/// `engine` must be a live engine pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rt_engine_snapshot(engine: *const Engine) -> *mut c_char {
    let Some(e) = (unsafe { engine.as_ref() }) else { return std::ptr::null_mut() };
    match serde_json::to_string(&snapshot::build(&e.state)) {
        Ok(s) => to_c(s),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Applies a JSON action and returns `{"ok":bool,"message":string}`.
///
/// # Safety
/// `engine` must be a live engine pointer and `json` a NUL-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rt_engine_action(engine: *mut Engine, json: *const c_char) -> *mut c_char {
    let Some(e) = (unsafe { engine.as_mut() }) else { return std::ptr::null_mut() };
    if json.is_null() {
        return std::ptr::null_mut();
    }
    let text = unsafe { CStr::from_ptr(json) }.to_string_lossy();
    let result = if crate::secure::tampered() {
        Err("Integrity check failed".to_owned())
    } else {
        match serde_json::from_str::<Action>(&text) {
            Ok(a) => actions::apply(&mut e.state, a),
            Err(err) => Err(format!("Bad action: {err}")),
        }
    };
    let v = match result {
        Ok(m) => json!({ "ok": true, "message": m }),
        Err(m) => json!({ "ok": false, "message": m }),
    };
    to_c(v.to_string())
}

/// Seals the current game. Returns null when saving is refused.
///
/// # Safety
/// `engine` must be live and `out_len` writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rt_engine_save(engine: *const Engine, out_len: *mut usize) -> *mut u8 {
    let Some(e) = (unsafe { engine.as_ref() }) else { return std::ptr::null_mut() };
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    let Some(bytes) = e.save() else { return std::ptr::null_mut() };
    let boxed = bytes.into_boxed_slice();
    unsafe { *out_len = boxed.len() };
    Box::into_raw(boxed) as *mut u8
}

/// # Safety
/// `ptr`/`len` must come from `rt_engine_save`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rt_bytes_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)) });
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rt_catalog() -> *mut c_char {
    match serde_json::to_string(&catalog::catalog()) {
        Ok(s) => to_c(s),
        Err(_) => std::ptr::null_mut(),
    }
}

/// # Safety
/// `ptr` must come from one of the string-returning functions above.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rt_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(unsafe { CString::from_raw(ptr) });
    }
}
