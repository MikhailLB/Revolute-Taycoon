//! Anti-tamper layer.
//!
//! The functions tagged `#[safetynet]` are lowered at compile time into
//! bytecode for an embedded stack VM, so their logic (the gaming tax schedule,
//! the save sealing keys and the in-memory ledger tag) does not exist as
//! ordinary machine code in the shipped binary.
//!
//! The VM has no floats: money crosses it as integer cents.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use safetynet::{Typed, VmLayout, safetynet};
use serde::{Deserialize, Serialize};

static TAMPERED: AtomicBool = AtomicBool::new(false);
static KEY_COUNTER: AtomicU64 = AtomicU64::new(0x51A7_E5C0_FFEE_D00D);

pub fn tampered() -> bool {
    TAMPERED.load(Ordering::Relaxed)
}

pub fn flag_tamper() {
    TAMPERED.store(true, Ordering::Relaxed);
}

pub fn clear_tamper() {
    TAMPERED.store(false, Ordering::Relaxed);
}

#[derive(Clone, Copy, VmLayout)]
pub struct P1 {
    pub ggr_cents: u64,
    pub schedule: u32,
}

/// Progressive gaming tax on one venue's monthly GGR, in cents.
#[safetynet]
#[allow(clippy::assign_op_pattern)]
pub fn q1(q: P1) -> u64 {
    static BANDS: [u64; 12] = [
        10000000, 50000000, 200000000, 900000000000000000,
        20000000, 100000000, 500000000, 900000000000000000,
        50000000, 300000000, 1000000000, 900000000000000000,
    ];
    static RATES: [u64; 12] = [
        1200, 1800, 2400, 3000,
        1800, 2600, 3200, 3800,
        2500, 3500, 4200, 5000,
    ];

    let ggr: u64 = q.ggr_cents.typed::<u64>();
    let mut s: u64 = q.schedule.typed::<u32>() as u64;
    if s > 2 {
        s = 2;
    }
    let mut tax: u64 = 0;
    let mut lower: u64 = 0;
    let mut k: u64 = 0;
    while k < 4 {
        let idx: u64 = s * 4 + k;
        let upper: u64 = BANDS[idx as usize];
        let rate: u64 = RATES[idx as usize];
        if ggr > lower {
            let mut top: u64 = ggr;
            if top > upper {
                top = upper;
            }
            tax = tax + (top - lower) * rate / 10000;
        }
        lower = upper;
        k = k + 1;
    }
    tax
}

#[derive(Clone, Copy, VmLayout)]
pub struct P2 {
    pub nonce: u64,
    pub lane: u32,
}

/// Derives the keystream seed and MAC salt of a save from its nonce.
#[safetynet]
#[allow(clippy::assign_op_pattern)]
pub fn q2(input: P2) -> u64 {
    let nonce: u64 = input.nonce.typed::<u64>();
    let lane: u64 = input.lane.typed::<u32>() as u64;
    let mut lo: u64 = (nonce & 4294967295) ^ 2654435769;
    let mut hi: u64 = ((nonce >> 32) & 4294967295) ^ 1013904223;
    lo = lo ^ (lane * 2246822519 & 4294967295);
    let mut i: u64 = 0;
    while i < 24 {
        lo = (lo * 1664525 + 1013904223 + hi) & 4294967295;
        hi = (hi ^ ((lo << 7) & 4294967295) ^ (lo >> 11)) & 4294967295;
        hi = (hi * 2891336453 + 12345) & 4294967295;
        i = i + 1;
    }
    (hi << 32) | lo
}

#[derive(Clone, VmLayout)]
pub struct P3 {
    pub salt: u64,
    pub data: Vec<u8>,
}

/// Keyed 64-bit digest over the sealed save bytes.
#[safetynet]
#[allow(clippy::assign_op_pattern)]
pub fn q3(input: P3) -> u64 {
    let salt: u64 = input.salt.typed::<u64>();
    let mut h1: u64 = (salt ^ 2166136261) & 4294967295;
    let mut h2: u64 = ((salt >> 32) ^ 3266489917) & 4294967295;
    let mut i: u64 = 0;
    for b in input.data.iter() {
        let v: u64 = *b as u64;
        h1 = ((h1 ^ v) * 16777619) & 4294967295;
        h2 = ((h2 ^ ((v + i) & 255)) * 2246822519) & 4294967295;
        h2 = ((h2 << 5) | (h2 >> 27)) & 4294967295;
        i = i + 1;
    }
    h1 = (h1 ^ (i & 4294967295)) & 4294967295;
    h1 = ((h1 ^ (h1 >> 16)) * 2246822507) & 4294967295;
    h1 = ((h1 ^ (h1 >> 13)) * 3266489909) & 4294967295;
    h2 = ((h2 ^ (h2 >> 16) ^ h1) * 2246822507) & 4294967295;
    h2 = (h2 ^ (h2 >> 15)) & 4294967295;
    (h1 << 32) | h2
}

#[derive(Clone, Copy, VmLayout)]
pub struct P4 {
    pub masked: u64,
    pub key: u64,
}

/// Tag binding a masked value to its key. Editing either in memory breaks it.
#[safetynet]
#[allow(clippy::assign_op_pattern)]
pub fn q4(input: P4) -> u64 {
    let m: u64 = input.masked.typed::<u64>();
    let k: u64 = input.key.typed::<u64>();
    let mut a: u64 = (m & 4294967295) ^ ((k >> 32) & 4294967295);
    let mut b: u64 = ((m >> 32) & 4294967295) ^ (k & 4294967295);
    let mut i: u64 = 0;
    while i < 6 {
        a = ((a ^ (b >> 3)) * 2654435761 + 40503) & 4294967295;
        b = ((b ^ (a << 2)) * 2246822519 + 7919) & 4294967295;
        i = i + 1;
    }
    (a << 32) | b
}

pub fn gaming_tax(ggr: f64, schedule: u32) -> f64 {
    if ggr <= 0.0 {
        return 0.0;
    }
    let cents = (ggr * 100.0).round().min(9.0e17) as u64;
    q1(P1 {
        ggr_cents: cents,
        schedule,
    }) as f64
        / 100.0
}

pub fn seal_key(nonce: u64, lane: u32) -> u64 {
    q2(P2 { nonce, lane })
}

pub fn seal_digest(salt: u64, data: &[u8]) -> u64 {
    q3(P3 {
        salt,
        data: data.to_vec(),
    })
}

fn splitmix(mut z: u64) -> u64 {
    z = z.wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

fn fresh_key() -> u64 {
    let c = KEY_COUNTER.fetch_add(0x6A09_E667_F3BC_C909, Ordering::Relaxed);
    let addr = &c as *const u64 as u64;
    splitmix(c ^ addr.rotate_left(17))
}

/// A number that never sits in memory in the clear. The value is XOR-masked
/// with a key that rotates on every write, and bound to that key by a tag
/// computed inside the VM. Memory scanners cannot find it, and patching it
/// trips the tamper flag on the next read.
#[derive(Clone, Serialize, Deserialize)]
pub struct Guarded {
    m: u64,
    k: u64,
    t: u64,
}

impl Guarded {
    pub fn new(value: f64) -> Self {
        let mut g = Guarded { m: 0, k: 0, t: 0 };
        g.set(value);
        g
    }

    pub fn get(&self) -> f64 {
        let tag = q4(P4 {
            masked: self.m,
            key: self.k,
        });
        if tag != self.t {
            flag_tamper();
        }
        f64::from_bits(self.m ^ self.k)
    }

    pub fn set(&mut self, value: f64) {
        let v = if value.is_finite() { value } else { 0.0 };
        self.k = fresh_key();
        self.m = v.to_bits() ^ self.k;
        self.t = q4(P4 {
            masked: self.m,
            key: self.k,
        });
    }

    pub fn verify(&self) -> bool {
        q4(P4 {
            masked: self.m,
            key: self.k,
        }) == self.t
    }
}

/// True when a debugger is attached to the process. Only compiled into
/// hardened (App Store) builds so development in Xcode is unaffected.
#[cfg(all(feature = "hardened", any(target_os = "ios", target_os = "macos")))]
pub fn debugger_attached() -> bool {
    use std::ffi::c_void;
    unsafe extern "C" {
        fn sysctl(
            name: *mut i32,
            namelen: u32,
            oldp: *mut c_void,
            oldlenp: *mut usize,
            newp: *mut c_void,
            newlen: usize,
        ) -> i32;
        fn getpid() -> i32;
    }
    const CTL_KERN: i32 = 1;
    const KERN_PROC: i32 = 14;
    const KERN_PROC_PID: i32 = 1;
    const P_TRACED: i32 = 0x0000_0800;
    // `kinfo_proc` is 648 bytes on 64-bit Darwin; `kp_proc.p_flag` sits at 32.
    let mut buf = [0u8; 1024];
    let mut size: usize = 648;
    let mut mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, unsafe { getpid() }];
    let rc = unsafe {
        sysctl(
            mib.as_mut_ptr(),
            4,
            buf.as_mut_ptr() as *mut c_void,
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        return false;
    }
    let flag = i32::from_ne_bytes([buf[32], buf[33], buf[34], buf[35]]);
    flag & P_TRACED != 0
}

#[cfg(not(all(feature = "hardened", any(target_os = "ios", target_os = "macos"))))]
pub fn debugger_attached() -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tax_is_progressive() {
        let t1 = gaming_tax(50_000.0, 0);
        assert!((t1 - 6_000.0).abs() < 0.01);
        let t2 = gaming_tax(200_000.0, 0);
        // 100k @12% + 100k @18%
        assert!((t2 - 30_000.0).abs() < 0.01);
        assert!(gaming_tax(1_000_000.0, 2) > gaming_tax(1_000_000.0, 0));
    }

    #[test]
    fn guarded_roundtrip_and_tamper() {
        clear_tamper();
        let mut g = Guarded::new(1234.5);
        assert_eq!(g.get(), 1234.5);
        g.set(-7.25);
        assert_eq!(g.get(), -7.25);
        assert!(!tampered());
        g.m ^= 1;
        assert!(!g.verify());
        clear_tamper();
    }
}
