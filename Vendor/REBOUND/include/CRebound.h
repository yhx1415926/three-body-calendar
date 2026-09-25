#ifndef TRISOLARIS_C_REBOUND_H
#define TRISOLARIS_C_REBOUND_H

#include "../src/rebound.h"

/// Enable continuous (line-path) collision detection and stop without merging.
/// Restore this callback after loading a simulation archive.
void trisolaris_rebound_set_collision_halt(struct reb_simulation *simulation);

#endif
