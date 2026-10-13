//
//  CNucleantPreview.h
//  NucleantUI
//
//  The bounds of the linker section `@Preview` records are placed in. The
//  linker names them with symbols Swift cannot spell (`section$start$…` on
//  Mach-O, `__start_…` on ELF and wasm), so C hands them over.
//

#ifndef CNucleantPreview_h
#define CNucleantPreview_h

/// First byte of the previews section.
const void *nucleant_preview_records_start(void);

/// One past its last byte; equal to the start when no record was linked.
const void *nucleant_preview_records_end(void);

#endif
