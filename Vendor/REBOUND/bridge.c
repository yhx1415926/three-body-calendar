/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "include/CRebound.h"

void trisolaris_rebound_set_collision_halt(struct reb_simulation *simulation) {
    if (simulation == NULL) return;
    simulation->collision = REB_COLLISION_LINE;
    simulation->collision_resolve = reb_collision_resolve_halt;
}
