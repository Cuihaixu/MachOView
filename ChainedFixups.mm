//
//  MachOLayout+ChainedFixups.m
//  MachOView
//
//  Created by cu on 2024/8/9.
//

#import "ChainedFixups.h"
#import <mach-o/fixup-chains.h>
#import "Common.h"
#import "ReadWrite.h"
#import "DataController.h"
#import "SectionContents.h"
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

union ChainedFixupPointerOnDisk
{
    union Arm64e {
        dyld_chained_ptr_arm64e_auth_rebase authRebase;
        dyld_chained_ptr_arm64e_auth_bind   authBind;
        dyld_chained_ptr_arm64e_rebase      rebase;
        dyld_chained_ptr_arm64e_bind        bind;
        dyld_chained_ptr_arm64e_bind24      bind24;
        dyld_chained_ptr_arm64e_auth_bind24 authBind24;
    };

    union Generic64 {
        dyld_chained_ptr_64_rebase rebase;
        dyld_chained_ptr_64_bind   bind;
    };

    union Generic32 {
        dyld_chained_ptr_32_rebase rebase;
        dyld_chained_ptr_32_bind   bind;
    };

    struct Kernel64 : dyld_chained_ptr_64_kernel_cache_rebase {};
    
    struct Firm32 : dyld_chained_ptr_32_firmware_rebase {};

#if 0
    union Cache64e {
        dyld_chained_ptr_arm64e_shared_cache_rebase      regular;
        dyld_chained_ptr_arm64e_shared_cache_auth_rebase auth;
    };
#endif

    typedef dyld_chained_ptr_32_cache_rebase Cache32;

    uint64_t            raw64;
    Arm64e              arm64e;
    Generic64           generic64;
    Kernel64            kernel64;
#if 0
    Cache64e            cache64e;
#endif
    
    uint32_t            raw32;
    Generic32           generic32;
    Cache32             cache32;
    Firm32              firmware32;
};


@implementation MachOLayout (ChainedFixups)

- (unsigned)fixupsChainStrideSize:(uint16_t)pointerFormat
{
    switch (pointerFormat) {
        case DYLD_CHAINED_PTR_ARM64E:
        case DYLD_CHAINED_PTR_ARM64E_USERLAND:
        case DYLD_CHAINED_PTR_ARM64E_USERLAND24:
#if 0
        case DYLD_CHAINED_PTR_ARM64E_SHARED_CACHE:
#endif
            return 8;
        case DYLD_CHAINED_PTR_ARM64E_KERNEL:
        case DYLD_CHAINED_PTR_ARM64E_FIRMWARE:
        case DYLD_CHAINED_PTR_32_FIRMWARE:
        case DYLD_CHAINED_PTR_64:
        case DYLD_CHAINED_PTR_64_OFFSET:
        case DYLD_CHAINED_PTR_32:
        case DYLD_CHAINED_PTR_32_CACHE:
        case DYLD_CHAINED_PTR_64_KERNEL_CACHE:
            return 4;
        case DYLD_CHAINED_PTR_X86_64_KERNEL_CACHE:
            return 1;
    }
    assert(0 && "unsupported pointer chain format");
}


- (uint32_t)getImportFormatEntrySize:(uint32_t)format
{
    switch (format) {
        case DYLD_CHAINED_IMPORT:
            return sizeof(struct dyld_chained_import);
        case DYLD_CHAINED_IMPORT_ADDEND:
            return sizeof(struct dyld_chained_import_addend);
        case DYLD_CHAINED_IMPORT_ADDEND64:
            return sizeof(struct dyld_chained_import_addend64);
        default:
            return 0;
    }
}

- (NSString *)chainedFixupsSymbolFormatName:(uint32_t)format
{
    switch (format) {
        case 0: return @"uncompressed";
        case 1: return @"zlib compressed";
        default: return @"Unknown symbol format";
    }
}

- (NSString *)chainedFixupsImportFormatName:(uint32_t)format
{
    switch (format) {
        case DYLD_CHAINED_IMPORT: return @"DYLD_CHAINED_IMPORT";
        case DYLD_CHAINED_IMPORT_ADDEND: return @"DYLD_CHAINED_IMPORT_ADDEND";
        case DYLD_CHAINED_IMPORT_ADDEND64: return @"DYLD_CHAINED_IMPORT_ADDEND64";
        default: return @"Unknown import format";
    }
}

- (MVNode *) createChainedFixupsChildNodes:(MVNode *)parent
                                  location:(uint64_t)location
                                    length:(uint64_t)length
{

    /* chained fixups header */
    struct dyld_chained_fixups_header header;
    [self createChainedFixupsHeaderNode:parent
                                caption:@"Fixups Header"
                               location:location
                                 length:sizeof(struct dyld_chained_fixups_header)
                                 header:&header];
    
    uint32_t entrySize = [self getImportFormatEntrySize:header.imports_format];
    NSAssert1(entrySize != 0, @"chained fixups, unknown imports_format (%d)", header.imports_format);
    [self createChainedFixupsImportNode:parent
                                caption:@"Fixups Imports"
                               location:location + header.imports_offset
                                 length:header.imports_count * entrySize
                           importFormat:header.imports_format
                            importCount:header.imports_count
                                symbols:location + header.symbols_offset + imageOffset
                            symbolsSize:length - header.symbols_offset];
    
    [self createChainedFixupsSymbolsNode:parent
                                 caption:@"Fixups Symbols"
                                location:location + header.symbols_offset
                                  length:length - header.symbols_offset];
    
    [self createChainedFixupsStartsNode:parent
                                caption:@"Fixups Starts"
                               location:location + header.starts_offset
                                 length:0];
    
  
    

    return NULL;
}

- (MVNode *) createChainedFixupsHeaderNode:(MVNode *)parent
                                   caption:(NSString *)caption
                                  location:(uint64_t)location
                                    length:(uint64_t)length
                                    header:(struct dyld_chained_fixups_header *)header
{
    NSRange range = NSMakeRange(location,0);
    NSString * lastReadHex;
    MVNodeSaver nodeSaver;
    MVNode * node = [parent insertChildWithDetails:caption location:location length:length saver:nodeSaver];
    {
        header->fixups_version = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Fixups Version"
                               :[NSString stringWithFormat:@"%d", header->fixups_version]];
    }
    {
        header->starts_offset = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Starts Offset"
                               :[NSString stringWithFormat:@"%d (0x%llx)", header->starts_offset,
                                location + header->starts_offset]];
    }
    {
        header->imports_offset = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Imports Offset"
                               :[NSString stringWithFormat:@"%d (0x%llx)", header->imports_offset,
                                location + header->imports_offset]];
    }
    {
        header->symbols_offset = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Symbols Offset"
                               :[NSString stringWithFormat:@"%d (0x%llx)", header->symbols_offset,
                                location + header->symbols_format]];
        
    }
    {
        header->imports_count = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Imports Count"
                               :[NSString stringWithFormat:@"%d", header->imports_count]];
        
    }
    {
        header->imports_format = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Imports Format"
                               :[NSString stringWithFormat:@"%d (%@)", header->imports_format,
                                [self chainedFixupsImportFormatName:header->imports_format]]];
        
    }
    {
        header->symbols_format = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Symbols Format"
                               :[NSString stringWithFormat:@"%d (%@)", header->symbols_format,
                                [self chainedFixupsSymbolFormatName:header->symbols_format]]];
    }
    return node;
}



- (MVNode *) createChainedFixupsStartsNode:(MVNode *)parent
                                   caption:(NSString *)caption
                                  location:(uint64_t)location
                                    length:(uint64_t)length
{
    struct dyld_chained_starts_in_image starts;
    NSRange range = NSMakeRange(location,0);
    NSString * lastReadHex;
    MVNodeSaver nodeSaver;
    MVNode * node = [parent insertChildWithDetails:caption location:location length:length saver:nodeSaver];
    MATCH_STRUCT(dyld_chained_starts_in_image, location)
    {
        uint32_t segmentCount = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Segment Count"
                               :[NSString stringWithFormat:@"%d", segmentCount]];
        [node.details appendRow:@""
                               :@""
                               :@"Segment Info Offset"
                               :@""];
        for (uint32_t segment = 0; segment < segmentCount ; segment++) {
            uint32_t entryOffset = [dataController read_uint32:range lastReadHex:&lastReadHex];
            NSString *valueInfo = nil;
            if (entryOffset == 0) {
                valueInfo = @"0 (This segment has no fixups)";
            } else {
                valueInfo = [NSString stringWithFormat:@"%d (0x%llx)", entryOffset, location + entryOffset];
            }
            [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                                   :lastReadHex
                                   :[NSString stringWithFormat:@"%s", segments_64[segment]->segname]
                                   :valueInfo];
        }
        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        
        for (uint32_t seg = 0; seg < segmentCount; seg++) {
            uint32_t entryOffset = dyld_chained_starts_in_image->seg_info_offset[seg];
//            const char *segname = segments_64[seg]->segname;
            if (entryOffset != 0) {
                [self createFixupInSegmentChainsNodes:node location:location + entryOffset length:0 segmentIndex:seg];
            }
        }
        
    }
    return NULL;
}

- (void) createFixupInSegmentChainsNodes:(MVNode *)parent
                                    location:(uint64_t)location
                                      length:(uint64_t)length
                                    segmentIndex:(uint32_t)segmentIndex
{
    MATCH_STRUCT(dyld_chained_starts_in_segment, location);
    /**
     struct dyld_chained_starts_in_segment
     {
         uint32_t    size;               // size of this (amount kernel needs to copy)
         uint16_t    page_size;          // 0x1000 or 0x4000
         uint16_t    pointer_format;     // DYLD_CHAINED_PTR_*
         uint64_t    segment_offset;     // offset in memory to start of segment
         uint32_t    max_valid_pointer;  // for 32-bit OS, any value beyond this is not a pointer
         uint16_t    page_count;         // how many pages are in array
         uint16_t    page_start[1];      // each entry is offset in each page of first element in chain
                                         // or DYLD_CHAINED_PTR_START_NONE if no fixups on page
      // uint16_t    chain_starts[1];    // some 32-bit formats may require multiple starts per page.
                                         // for those, if high bit is set in page_starts[], then it
                                         // is index into chain_starts[] which is a list of starts
                                         // the last of which has the high bit set
     };
     */
    NSRange range = NSMakeRange(location,0);
    NSString * lastReadHex;
    [dataController read_uint32:range lastReadHex:&lastReadHex];
    [parent.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                             :lastReadHex
                             :@"Size"
                             :[NSString stringWithFormat:@"%d", dyld_chained_starts_in_segment->size]];
    
    [dataController read_uint16:range lastReadHex:&lastReadHex];
    [parent.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                             :lastReadHex
                             :@"Page Size"
                             :[NSString stringWithFormat:@"%d", dyld_chained_starts_in_segment->page_size]];
    
    [dataController read_uint16:range lastReadHex:&lastReadHex];
    [parent.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                             :lastReadHex
                             :@"Pointer Format"
                             :[NSString stringWithFormat:@"%d", dyld_chained_starts_in_segment->pointer_format]];
    
    [dataController read_uint64:range lastReadHex:&lastReadHex];
    [parent.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                             :lastReadHex
                             :@"Segment Offset"
                             :[NSString stringWithFormat:@"%lld", dyld_chained_starts_in_segment->segment_offset]];
    
    [dataController read_uint32:range lastReadHex:&lastReadHex];
    [parent.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                             :lastReadHex
                             :@"Max Valid Pointer"
                             :[NSString stringWithFormat:@"%d", dyld_chained_starts_in_segment->max_valid_pointer]];
    
    [dataController read_uint32:range lastReadHex:&lastReadHex];
    [parent.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                             :lastReadHex
                             :@"Page Count"
                             :[NSString stringWithFormat:@"%d", dyld_chained_starts_in_segment->page_count]];
    const uint64_t segmentBuffer = segments_64[segmentIndex]->fileoff;
    const uint64_t segmentVmaddr = segments_64[segmentIndex]->vmaddr;
    for (uint32_t pageIndex = 0; pageIndex < dyld_chained_starts_in_segment->page_count; pageIndex++) {
        uint16_t offsetInPage = dyld_chained_starts_in_segment->page_start[pageIndex];
        if (offsetInPage == DYLD_CHAINED_PTR_START_NONE) {
//            NSLog(@"segIndex: %d pageIndex: %d == DYLD_CHAINED_PTR_START_NONE", segmentIndex, pageIndex);
            continue;
        }
        // [segment.base + pageIndex * pageSize + offsetInPage]
        uint64_t pageContentStart = segmentBuffer + pageIndex * dyld_chained_starts_in_segment->page_size;
        uint64_t vmPageContentStart = segmentVmaddr + pageIndex * dyld_chained_starts_in_segment->page_size;
        if (offsetInPage & DYLD_CHAINED_PTR_START_MULTI) {
            uint32_t overflowIndex = offsetInPage & ~DYLD_CHAINED_PTR_START_MULTI;
            bool chainEnd = false;
            while (!chainEnd) {
                chainEnd = (dyld_chained_starts_in_segment->page_start[overflowIndex] & DYLD_CHAINED_PTR_START_LAST);
                offsetInPage = (dyld_chained_starts_in_segment->page_start[overflowIndex] & ~DYLD_CHAINED_PTR_START_LAST);
                [self createChainedFixupsPageNode:parent
                                         location:pageContentStart + offsetInPage
                                    pointerFormat:dyld_chained_starts_in_segment->pointer_format
                                  maxValidPointer:dyld_chained_starts_in_segment->max_valid_pointer
                                     segmentIndex:segmentIndex
                                    targetAddress:vmPageContentStart];
            }
        } else {
            [self createChainedFixupsPageNode:parent
                                     location:pageContentStart + offsetInPage
                                pointerFormat:dyld_chained_starts_in_segment->pointer_format
                              maxValidPointer:dyld_chained_starts_in_segment->max_valid_pointer
                                 segmentIndex:segmentIndex
                                targetAddress:vmPageContentStart];
        }
    }
    [parent.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
}

- (void) createChainedFixupsPageNode:(MVNode *)parent
                            location:(uint64_t)location
                       pointerFormat:(uint16_t)format
                     maxValidPointer:(uint32_t)maxValidPointer
                        segmentIndex:(uint16_t)segmentIndex
                       targetAddress:(uint64_t)targetAddress
{
    [parent.details appendRow:@""
                             :@""
                             :[NSString stringWithFormat:@"location: 0x%llx", location]
                             :@""];
    [parent.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
    
    const unsigned stride = [self fixupsChainStrideSize:format];
    bool chainEnd = false;
    uint64_t chainPointer = location;
    uint64_t offsetVmAddress = targetAddress;
    while (!chainEnd) {
        ChainedFixupPointerOnDisk *chainContent = (ChainedFixupPointerOnDisk *)[self imageAt:chainPointer];
        [self appendPageFixupsInfoNode:parent
                              location:chainPointer
                          chainContent:chainContent
                         pointerFormat:format
                       maxValidPointer:maxValidPointer
                          segmentIndex:segmentIndex
                         targetAddress:offsetVmAddress];
        switch (format) {
            case DYLD_CHAINED_PTR_ARM64E:
            case DYLD_CHAINED_PTR_ARM64E_KERNEL:
            case DYLD_CHAINED_PTR_ARM64E_USERLAND:
            case DYLD_CHAINED_PTR_ARM64E_USERLAND24:
            case DYLD_CHAINED_PTR_ARM64E_FIRMWARE:
            {
                if (chainContent->arm64e.rebase.next == 0) {
                    chainEnd = true;
                } else {
                    chainPointer += chainContent->arm64e.rebase.next * stride;
                }
            }
                break;
            case DYLD_CHAINED_PTR_64:
            case DYLD_CHAINED_PTR_64_OFFSET:
            {
                if (chainContent->generic64.rebase.next == 0) {
                    chainEnd = true;
                } else {
                    chainPointer += chainContent->generic64.rebase.next * stride;
                    offsetVmAddress += chainContent->generic64.rebase.next * stride;
                }
            }
                break;
            case DYLD_CHAINED_PTR_32:
            {
                if (chainContent->generic32.rebase.next == 0) {
                    chainEnd = true;
                } else {
                    chainPointer += chainContent->generic32.rebase.next * 4;
                }
            }
                break;
            case DYLD_CHAINED_PTR_64_KERNEL_CACHE:
            case DYLD_CHAINED_PTR_X86_64_KERNEL_CACHE:
            {
                if (chainContent->kernel64.next == 0) {
                    chainEnd = true;
                } else {
                    chainPointer += chainContent->kernel64.next * stride;
                }
            }
                break;
            case DYLD_CHAINED_PTR_32_FIRMWARE:
            {
                if (chainContent->firmware32.next == 0) {
                    chainEnd = true;
                } else {
                    chainPointer += chainContent->firmware32.next * 4;
                }
            }
                break;
            default:
                chainEnd = true;
                [parent.details appendRow:@""
                                         :@""
                                         :@""
                                         :[NSString stringWithFormat:@"unknown pointer format 0x%04X", format]];
                break;
        }
    }
    return;
}

- (NSString *)getImportDylibNameWithLibOrdinal:(uint32_t)ordinal {
    struct dylib const *dylib = [self getDylibByIndex:ordinal];
    switch (ordinal) {
        case SELF_LIBRARY_ORDINAL: return @"SELF_LIBRARY_ORDINAL";
        case DYNAMIC_LOOKUP_ORDINAL: return @"DYNAMIC_LOOKUP_ORDINAL";
        case EXECUTABLE_ORDINAL: return @"EXECUTABLE_ORDINAL";
        default: return [NSSTRING((uint8_t *)dylib + dylib->name.offset - sizeof(struct load_command)) lastPathComponent];
    }
}

- (void)appendPageFixupsInfoNode:(MVNode *)parent
                        location:(uint64_t)location
                    chainContent:(ChainedFixupPointerOnDisk *)chainContent
                   pointerFormat:(uint16_t)pointerFormat
                 maxValidPointer:(uint32_t)maxValidPointer
                    segmentIndex:(uint16_t)segmentIndex
                targetAddress:(uint64_t)targetAddress
{
    switch (pointerFormat) {
        case DYLD_CHAINED_PTR_ARM64E:
        case DYLD_CHAINED_PTR_ARM64E_KERNEL:
        case DYLD_CHAINED_PTR_ARM64E_USERLAND:
        case DYLD_CHAINED_PTR_ARM64E_FIRMWARE:
        case DYLD_CHAINED_PTR_ARM64E_USERLAND24:
        {
            
        }
            break;
        case DYLD_CHAINED_PTR_64:
        case DYLD_CHAINED_PTR_64_OFFSET:
        {
            if (chainContent->generic64.rebase.bind) {
                /**
                 struct dyld_chained_ptr_64_bind
                 {
                     uint64_t    ordinal   : 24,
                                 addend    :  8,   // 0 thru 255
                                 reserved  : 19,   // all zeros
                                 next      : 12,   // 4-byte stride
                                 bind      :  1;   // == 1
                 };
                 */
                NSString *libraryName = @"Error";
                NSString *symboName = @"Unknown Symbol Name";
                if (chainContent->generic64.bind.ordinal < imports.size()) {
                    struct dyld_chained_import *chainedImport = imports[chainContent->generic64.bind.ordinal];
                    libraryName = [self getImportDylibNameWithLibOrdinal:chainedImport->lib_ordinal];
                    symboName = [NSString stringWithFormat:@"%s", (const char *)((uintptr_t)importSymbols + chainedImport->name_offset)];
                }
                
                [parent.details appendRow:[NSString stringWithFormat:@"%.8llX", location]
                                         :[NSString stringWithFormat:@"%08llX", chainContent->raw64]
                                         :@"BIND"
                                         :[NSString stringWithFormat:@"target: 0x%llx (%@)", targetAddress, [self findSectionContainsRVA:targetAddress]]];
                [parent.details appendRow:nil
                                         :nil
                                         :@"SymbolName"
                                         :[NSString stringWithFormat:@"[%@]: %@", libraryName, symboName]];
                
                [parent.details appendRow:nil
                                         :@""
                                         :@"Ordinal"
                                         :[NSString stringWithFormat:@"#%d", chainContent->generic64.bind.ordinal]];
                
                [parent.details appendRow:nil
                                         :@""
                                         :@"Addend"
                                         :[NSString stringWithFormat:@"%d", chainContent->generic64.bind.addend]];
                
                [parent.details appendRow:nil
                                         :@""
                                         :@"Reserved"
                                         :[NSString stringWithFormat:@"%d", chainContent->generic64.bind.reserved]];
                
                [parent.details appendRow:nil
                                         :@""
                                         :@"Next"
                                         :[NSString stringWithFormat:@"%d", chainContent->generic64.bind.next]];
                
                [parent.details appendRow:nil
                                         :@""
                                         :@"Bind"
                                         :[NSString stringWithFormat:@"%d", chainContent->generic64.bind.bind]];
            } else {
                /**
                 struct dyld_chained_ptr_64_rebase
                 {
                     uint64_t    target    : 36,    // 64GB max image size (DYLD_CHAINED_PTR_64 => vmAddr, DYLD_CHAINED_PTR_64_OFFSET => runtimeOffset)
                                 high8     :  8,    // top 8 bits set to this (DYLD_CHAINED_PTR_64 => after slide added, DYLD_CHAINED_PTR_64_OFFSET => before slide added)
                                 reserved  :  7,    // all zeros
                                 next      : 12,    // 4-byte stride
                                 bind      :  1;    // == 0
                 };
                 */
                
                [parent.details appendRow:[NSString stringWithFormat:@"%.8llX", location]
                                         :[NSString stringWithFormat:@"%08llX", chainContent->raw64]
                                         :@"REBASE"
                                         :nil];
                
                [parent.details appendRow:nil
                                         :@""
                                         :@"Target"
                                         :[NSString stringWithFormat:@"0x%llx location:0x%llx (%@)", chainContent->generic64.rebase.target, targetAddress, [self findSectionContainsRVA:targetAddress]]];
                
                [parent.details appendRow:nil
                                         :@""
                                         :@"High8"
                                         :[NSString stringWithFormat:@"%d", chainContent->generic64.rebase.high8]];
                
                [parent.details appendRow:nil
                                         :@""
                                         :@"Reserved"
                                         :[NSString stringWithFormat:@"%d", chainContent->generic64.rebase.reserved]];
                
                [parent.details appendRow:nil
                                         :@""
                                         :@"Next"
                                         :[NSString stringWithFormat:@"%d", chainContent->generic64.rebase.next]];
                
                [parent.details appendRow:nil
                                         :@""
                                         :@"Bind"
                                         :[NSString stringWithFormat:@"%d", chainContent->generic64.rebase.bind]];
            }
            [parent.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        }
            break;
        case DYLD_CHAINED_PTR_32:
        {
            
        }
            break;
        default:
            [parent.details appendRow:@""
                                     :@""
                                     :@""
                                     :[NSString stringWithFormat:@"unknown pointer type %d\n", pointerFormat]];
            break;
    }
}

- (MVNode *)createChainedFixupsImportNode:(MVNode *)parent
                                  caption:(NSString *)caption
                                 location:(uint64_t)location
                                   length:(uint64_t)length
                             importFormat:(uint32_t)format
                              importCount:(uint32_t)count
                                  symbols:(uint64_t)symbols
                              symbolsSize:(uint64_t)symbolsSize
                              
{
    NSRange range = NSMakeRange(location,0);
    uint64_t currentEntry = location;
    NSString * lastReadHex;
    MVNodeSaver nodeSaver;
    MVNode * node = [parent insertChildWithDetails:caption location:location length:length saver:nodeSaver];
    
    for (uint32_t i = 0; i < count; i++) {
        switch (format) {
            case DYLD_CHAINED_IMPORT:
            {
                MATCH_STRUCT(dyld_chained_import, currentEntry);
                struct dyld_chained_import *chainedImpart = (struct dyld_chained_import *)[self imageAt:currentEntry];
                imports.push_back(chainedImpart);
                currentEntry += sizeof(struct dyld_chained_import);
                [node.details appendRow:[NSString stringWithFormat:@"#%d", i]
                                       :nil
                                       :nil
                                       :nil];
                [dataController read_uint32:range lastReadHex:&lastReadHex];
                [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                                       :lastReadHex
                                       :@"DYLD_CHAINED_IMPORT"
                                       :nil];
                
                uint32_t libOrdinal = dyld_chained_import->lib_ordinal;
                struct dylib const *dylib = [self getDylibByIndex:libOrdinal];
                [node.details appendRow:@"":@"":@"Library Ordinal"
                                       :[NSString stringWithFormat:@"%u (%@)",libOrdinal,
                                         libOrdinal == SELF_LIBRARY_ORDINAL ? @"SELF_LIBRARY_ORDINAL" :
                                         libOrdinal == DYNAMIC_LOOKUP_ORDINAL ? @"DYNAMIC_LOOKUP_ORDINAL" :
                                         libOrdinal == EXECUTABLE_ORDINAL ? @"EXECUTABLE_ORDINAL" :
                                         [NSSTRING((uint8_t *)dylib + dylib->name.offset - sizeof(struct load_command)) lastPathComponent]]];
    
                [node.details appendRow:@""
                                       :@""
                                       :@"Weak Import"
                                       :[NSString stringWithFormat:@"%d (%@)", dyld_chained_import->weak_import, dyld_chained_import->weak_import ? @"weak-import" :@"no-weak-import"]];
                
                NSString *symbol = nil;
                if (dyld_chained_import->name_offset < symbolsSize) {
                    
                    NSRange range = NSMakeRange((uintptr_t)symbols + dyld_chained_import->name_offset, 0);
                    NSString *name = [dataController read_string:range];
                    symbol = [NSString stringWithFormat:@"%d (%@)", dyld_chained_import->name_offset, name];
                } else {
                    symbol = [NSString stringWithFormat:@"%d (Error Offset)", dyld_chained_import->name_offset];
                }
                
                [node.details appendRow:@""
                                       :@""
                                       :@"Name Offset"
                                       :symbol];
                [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
            }
                break;
            case DYLD_CHAINED_IMPORT_ADDEND:
            {
                MATCH_STRUCT(dyld_chained_import_addend, currentEntry);
                currentEntry += sizeof(struct dyld_chained_import_addend);
            }
                break;
            case DYLD_CHAINED_IMPORT_ADDEND64:
            {
                MATCH_STRUCT(dyld_chained_import_addend64, currentEntry);
                currentEntry += sizeof(struct dyld_chained_import_addend64);
            }
                break;
            default:
                break;
        }
    }

    
    return NULL;
}

- (MVNode *)createChainedFixupsSymbolsNode:(MVNode *)parent
                                  caption:(NSString *)caption
                                 location:(uint64_t)location
                                   length:(uint64_t)length
{
    importSymbols = (char const *)[self imageAt:location];
    return [self createCStringsNode:parent
                            caption:caption
                           location:location
                             length:length];
}


@end
