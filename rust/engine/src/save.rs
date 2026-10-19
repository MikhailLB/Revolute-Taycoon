//! Sealed save format.
//!
//! `RVTY` | version u8 | nonce u64 | length u32 | ciphertext | digest u64
//!
//! The payload is the JSON state XOR-ed with a keystream whose seed comes
//! from `seal_key` inside the VM; the trailing digest is `seal_digest` over
//! everything before it. A save edited by hand fails the digest and is refused.

use crate::model::GameState;
use crate::rng::Rng;
use crate::secure;

const MAGIC: &[u8; 4] = b"RVTY";
const FORMAT: u8 = 1;
const HEADER: usize = 4 + 1 + 8 + 4;

fn keystream(nonce: u64, data: &mut [u8]) {
    let seed = secure::seal_key(nonce, 1);
    let mut rng = Rng::new(seed);
    for chunk in data.chunks_mut(8) {
        let k = rng.next_u64().to_le_bytes();
        for (b, kb) in chunk.iter_mut().zip(k.iter()) {
            *b ^= kb;
        }
    }
}

fn digest(nonce: u64, bytes: &[u8]) -> u64 {
    let salt = secure::seal_key(nonce, 2);
    secure::seal_digest(salt, bytes)
}

pub fn seal(state: &GameState, nonce: u64) -> Option<Vec<u8>> {
    let mut payload = serde_json::to_vec(state).ok()?;
    keystream(nonce, &mut payload);
    let mut out = Vec::with_capacity(HEADER + payload.len() + 8);
    out.extend_from_slice(MAGIC);
    out.push(FORMAT);
    out.extend_from_slice(&nonce.to_le_bytes());
    out.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    out.extend_from_slice(&payload);
    let d = digest(nonce, &out);
    out.extend_from_slice(&d.to_le_bytes());
    Some(out)
}

pub fn open(bytes: &[u8]) -> Option<GameState> {
    if bytes.len() < HEADER + 8 || &bytes[0..4] != MAGIC || bytes[4] != FORMAT {
        return None;
    }
    let nonce = u64::from_le_bytes(bytes[5..13].try_into().ok()?);
    let len = u32::from_le_bytes(bytes[13..17].try_into().ok()?) as usize;
    if bytes.len() != HEADER + len + 8 {
        return None;
    }
    let body_end = HEADER + len;
    let stored = u64::from_le_bytes(bytes[body_end..body_end + 8].try_into().ok()?);
    if digest(nonce, &bytes[..body_end]) != stored {
        return None;
    }
    let mut payload = bytes[HEADER..body_end].to_vec();
    keystream(nonce, &mut payload);
    let state: GameState = serde_json::from_slice(&payload).ok()?;
    if !state.cash.verify() {
        return None;
    }
    Some(state)
}
