use serde::{Deserialize, Serialize};

/// Deterministic PCG-style generator. The state is part of the save, so a
/// reloaded game continues the exact same random sequence.
#[derive(Clone, Serialize, Deserialize)]
pub struct Rng {
    state: u64,
}

impl Rng {
    pub fn new(seed: u64) -> Self {
        let mut r = Rng {
            state: seed ^ 0x9E37_79B9_7F4A_7C15,
        };
        r.next_u64();
        r
    }

    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    pub fn f(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }

    pub fn range(&mut self, lo: f64, hi: f64) -> f64 {
        lo + (hi - lo) * self.f()
    }

    pub fn chance(&mut self, p: f64) -> bool {
        self.f() < p
    }

    pub fn below(&mut self, n: u32) -> u32 {
        if n == 0 {
            return 0;
        }
        (self.next_u64() % n as u64) as u32
    }

    /// Approximately normal noise with mean 0 and given sigma (Irwin–Hall).
    pub fn normal(&mut self, sigma: f64) -> f64 {
        let mut s = 0.0;
        for _ in 0..6 {
            s += self.f();
        }
        (s - 3.0) * sigma * std::f64::consts::SQRT_2
    }
}
