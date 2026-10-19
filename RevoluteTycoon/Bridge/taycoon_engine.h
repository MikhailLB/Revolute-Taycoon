#ifndef TAYCOON_ENGINE_H
#define TAYCOON_ENGINE_H

#include <stddef.h>
#include <stdint.h>

/// Opaque handle to the Rust simulation.
typedef struct Engine Engine;

Engine *rt_engine_new(uint64_t seed);
/// Returns NULL when the save is corrupt or was tampered with.
Engine *rt_engine_load(const uint8_t *data, size_t len);
void rt_engine_free(Engine *engine);

/// Advances the world by up to `hours` and returns status flags:
/// 1 = decision pending, 2 = game over, 4 = integrity failure, 8 = month closed.
uint32_t rt_engine_step(Engine *engine, uint32_t hours);

/// JSON strings owned by Rust; release with rt_string_free.
char *rt_engine_snapshot(const Engine *engine);
char *rt_engine_action(Engine *engine, const char *json);
char *rt_catalog(void);
void rt_string_free(char *ptr);

/// Sealed save bytes; release with rt_bytes_free. NULL when saving is refused.
uint8_t *rt_engine_save(const Engine *engine, size_t *out_len);
void rt_bytes_free(uint8_t *ptr, size_t len);

#endif
