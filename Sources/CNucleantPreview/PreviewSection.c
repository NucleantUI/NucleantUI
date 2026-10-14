//
//  PreviewSection.c
//  NucleantUI
//
//  Section names must match `PreviewMacro`'s expansion: `__DATA,nucleant_prev`
//  on Mach-O, `nucleant_previews` on ELF (Linux, Android) and wasm.
//

#include "CNucleantPreview.h"

#if defined(__APPLE__)
// ld64 defines both for any section named this way, as an empty range when
// nothing was placed in it.
extern const char nucleant_preview_section_start __asm("section$start$__DATA$nucleant_prev");
extern const char nucleant_preview_section_end __asm("section$end$__DATA$nucleant_prev");

const void *nucleant_preview_records_start(void) { return &nucleant_preview_section_start; }
const void *nucleant_preview_records_end(void) { return &nucleant_preview_section_end; }
#else
// lld and wasm-ld define these only when the section exists; weak, so a
// build without previews links and reads an empty range.
extern const char __start_nucleant_previews[] __attribute__((weak));
extern const char __stop_nucleant_previews[] __attribute__((weak));

const void *nucleant_preview_records_start(void) { return __start_nucleant_previews; }
const void *nucleant_preview_records_end(void) { return __stop_nucleant_previews; }
#endif
