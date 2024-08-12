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

    struct Kernel64 : dyld_chained_ptr_64_kernel_cache_rebase {
    };

    struct Firm32 : dyld_chained_ptr_32_firmware_rebase { };

    union Cache64e {
        dyld_chained_ptr_arm64e_shared_cache_rebase      regular;
        dyld_chained_ptr_arm64e_shared_cache_auth_rebase auth;
    };

    typedef dyld_chained_ptr_32_cache_rebase Cache32;

    uint64_t            raw64;
    Arm64e              arm64e;
    Generic64           generic64;
    Kernel64            kernel64;
    Cache64e            cache64e;

    uint32_t            raw32;
    Generic32           generic32;
    Cache32             cache32;
    Firm32              firmware32;
};

@implementation MachOLayout (ChainedFixups)

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
                                caption:@"Chained Fixups Header"
                               location:location
                                 length:sizeof(struct dyld_chained_fixups_header)
                                 header:&header];
    
    [self createChainedFixupsStartsNode:parent
                                caption:@"Starts In Image"
                               location:location + header.starts_offset
                                 length:0];
    
    uint32_t entrySize = [self getImportFormatEntrySize:header.imports_format];
    NSAssert1(entrySize != 0, @"chained fixups, unknown imports_format (%d)", header.imports_format);
    [self createChainedFixupsImportNode:parent
                                caption:@"Imports"
                               location:location + header.imports_offset
                                 length:header.imports_count * entrySize
                           importFormat:header.imports_format
                            importCount:header.imports_count
                                symbols:location + header.symbols_offset + imageOffset
                            symbolsSize:length - header.symbols_offset];
    
    [self createChainedFixupsSymbolsNode:parent
                                 caption:@"Symbols"
                                location:location + header.symbols_offset
                                  length:length - header.symbols_offset];
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
        for (uint32_t seg = 0; seg < segmentCount; seg++) {
            uint32_t entryOffset = dyld_chained_starts_in_image->seg_info_offset[seg];
            const char *segname = segments_64[seg]->segname;
            if (entryOffset != 0) {
                
            }
        }
        
    }
    return NULL;
}

- (MVNode *) createFixupInSegmentChainsNodes:(MVNode *)parent 
                                    location:(uint64_t)location
                                      length:(uint64_t)length
{
    
    return NULL;
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
                                       :[NSString stringWithFormat:@"%d", dyld_chained_import->weak_import]];
                
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
    return [self createCStringsNode:parent
                            caption:caption
                           location:location
                             length:length];
}

@end
