/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "include/CRebound.h"

void trisolaris_rebound_set_collision_halt(struct reb_simulation *simulation) {
    if (simulation == NULL) return;
    simulation->collision = REB_COLLISION_LINE;
    simulation->collision_resolve = reb_collision_resolve_halt;
}

struct reb_simulation *trisolaris_rebound_copy(struct reb_simulation *simulation) {
    struct reb_simulation *copy = reb_simulation_create();
    if (!copy) return NULL;
    enum reb_simulation_binary_error_codes warnings = REB_SIMULATION_BINARY_WARNING_NONE;
    reb_simulation_copy_with_messages(copy, simulation, &warnings);
    if (warnings & ~REB_SIMULATION_BINARY_WARNING_POINTERS) {
        reb_simulation_free(copy);
        return NULL;
    }
    trisolaris_rebound_set_collision_halt(copy);
    return copy;
}
