/*
 * Minimal snapshot hooks for browser boot builds.
 */

#include "qemu/osdep.h"
#include "migration/qemu-file.h"

void xemu_snapshots_save_extra_data(QEMUFile *f);
bool xemu_snapshots_offset_extra_data(QEMUFile *f);
void xemu_snapshots_mark_dirty(void);

void xemu_snapshots_save_extra_data(QEMUFile *f)
{
}

bool xemu_snapshots_offset_extra_data(QEMUFile *f)
{
    return true;
}

void xemu_snapshots_mark_dirty(void)
{
}
