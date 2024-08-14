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
    
    uint64_t            raw64;
    Arm64e              arm64e;
    Generic64           generic64;
};

struct ChainedFixups
{
public:
    ChainedFixups(const dyld_chained_fixups_header* fixupInfo, uint64_t location, size_t size) :
    _fixupsHeader(fixupInfo), _fixupsLocation(location), _fixupsSize(size) {
        _imageHeader = ((uintptr_t)fixupInfo - location);
    }
    
    static const char* importsFormatName(uint32_t format) {
        switch (format) {
            case DYLD_CHAINED_IMPORT:
                return "DYLD_CHAINED_IMPORT";
            case DYLD_CHAINED_IMPORT_ADDEND:
                return "DYLD_CHAINED_IMPORT_ADDEND";
            case DYLD_CHAINED_IMPORT_ADDEND64:
                return "DYLD_CHAINED_IMPORT_ADDEND64";
        }
        return "unknown";
    }
    
    static uint32_t importsFormatStride(uint32_t format) {
        switch (format) {
            case DYLD_CHAINED_IMPORT: return sizeof(dyld_chained_import);
            case DYLD_CHAINED_IMPORT_ADDEND: return sizeof(dyld_chained_import_addend);
            case DYLD_CHAINED_IMPORT_ADDEND64: return sizeof(dyld_chained_import_addend64);
            default: return 0;
        }
    }
    
    uint32_t importsFormatStride(void)
    {
        return importsFormatStride(_fixupsHeader->imports_format);
    }
    
    const char* importsFormatName() const {
        return importsFormatName(_fixupsHeader->imports_offset);
    }
    
    static const char* pointerFormat(uint16_t format)
    {
        switch (format) {
            case DYLD_CHAINED_PTR_ARM64E:
                return "authenticated arm64e, 8-byte stride, target vmadddr";
            case DYLD_CHAINED_PTR_ARM64E_USERLAND:
                return "authenticated arm64e, 8-byte stride, target vmoffset";
            case DYLD_CHAINED_PTR_ARM64E_FIRMWARE:
                return "authenticated arm64e, 4-byte stride, target vmadddr";
            case DYLD_CHAINED_PTR_ARM64E_KERNEL:
                return "authenticated arm64e, 4-byte stride, target vmoffset";
            case DYLD_CHAINED_PTR_64:
                return "generic 64-bit, 4-byte stride, target vmadddr";
            case DYLD_CHAINED_PTR_64_OFFSET:
                return "generic 64-bit, 4-byte stride, target vmoffset ";
            case DYLD_CHAINED_PTR_32:
                return "generic 32-bit";
            case DYLD_CHAINED_PTR_32_CACHE:
                return "32-bit for dyld cache";
            case DYLD_CHAINED_PTR_64_KERNEL_CACHE:
                return "64-bit for kernel cache";
            case DYLD_CHAINED_PTR_X86_64_KERNEL_CACHE:
                return "64-bit for x86_64 kernel cache";
            case DYLD_CHAINED_PTR_ARM64E_USERLAND24:
                return "authenticated arm64e, 8-byte stride, target vmoffset, 24-bit bind ordinals";
        }
        return "unknown";
    }
    
    static const char *pointerFormatName(uint16_t format)
    {
        switch (format) {
            case DYLD_CHAINED_PTR_ARM64E:
                return "DYLD_CHAINED_PTR_ARM64E";
            case DYLD_CHAINED_PTR_ARM64E_USERLAND:
                return "DYLD_CHAINED_PTR_ARM64E_USERLAND";
            case DYLD_CHAINED_PTR_ARM64E_FIRMWARE:
                return "DYLD_CHAINED_PTR_ARM64E_FIRMWARE";
            case DYLD_CHAINED_PTR_ARM64E_KERNEL:
                return "DYLD_CHAINED_PTR_ARM64E_KERNEL";
            case DYLD_CHAINED_PTR_64:
                return "DYLD_CHAINED_PTR_64";
            case DYLD_CHAINED_PTR_64_OFFSET:
                return "DYLD_CHAINED_PTR_64_OFFSET";
            case DYLD_CHAINED_PTR_32:
                return "DYLD_CHAINED_PTR_32";
            case DYLD_CHAINED_PTR_32_CACHE:
                return "DYLD_CHAINED_PTR_32_CACHE";
            case DYLD_CHAINED_PTR_64_KERNEL_CACHE:
                return "DYLD_CHAINED_PTR_64_KERNEL_CACHE";
            case DYLD_CHAINED_PTR_X86_64_KERNEL_CACHE:
                return "DYLD_CHAINED_PTR_X86_64_KERNEL_CACHE";
            case DYLD_CHAINED_PTR_ARM64E_USERLAND24:
                return "DYLD_CHAINED_PTR_ARM64E_USERLAND24";
        }
        return "unknown";
    }
    
    static const char *chainedPtrStartName(uint16_t offsetInPage) {
        if (offsetInPage == DYLD_CHAINED_PTR_START_NONE)
        {
            return "DYLD_CHAINED_PTR_START_NONE";
        }
        if (offsetInPage & DYLD_CHAINED_PTR_START_MULTI)
        {
            return "DYLD_CHAINED_PTR_START_MULTI";
        } else {
            return "ONE_CHAIN_PER_PAGE";
        }
        return "unknown";
    }
    
    const dyld_chained_fixups_header *getFixupsHeader(void) const
    {
        return _fixupsHeader;
    }
    uint32_t getFixupsHeaderSize(void) const
    {
        return _fixupsHeader->starts_offset;
    }
    
    const dyld_chained_starts_in_image *getImageStarts(void) const
    {
        if (_fixupsHeader->starts_offset == 0) {
            return nullptr;
        }
        return (const dyld_chained_starts_in_image *)((uintptr_t)_fixupsHeader + _fixupsHeader->starts_offset);
    }
    
    size_t getImageStartsSize(void) const
    {
        return _fixupsHeader->starts_offset - _fixupsHeader->imports_offset;
    }
    
    const char *getSymbolsPool(void) const
    {
        if (_fixupsHeader->symbols_offset == 0) {
            return nullptr;
        }
        return (const char *)((uintptr_t)_fixupsHeader + _fixupsHeader->symbols_offset);
    }
    
    const char *getSymbolName(uint32_t nameOffset)
    {
        const char *symbolsPool = getSymbolsPool();
        size_t poolSize = getSymbolsPoolSize();
        if (symbolsPool == nullptr || poolSize < 1 || nameOffset >= poolSize) {
            return "Unknown symbols";
        }
        return &symbolsPool[nameOffset];
    }
    
    size_t getSymbolsPoolSize(void) const
    {
        return _fixupsSize - _fixupsHeader->symbols_offset;
    }

    void * getFixupsImports(void) const
    {
        return (void *)((uintptr_t)_fixupsHeader + _fixupsHeader->imports_offset);
    }
    
    size_t getFixupsImportsSize(void) const
    {
        return _fixupsHeader->symbols_offset - _fixupsHeader->imports_offset;
    }
    
    const dyld_chained_starts_in_segment* startsForSegment(uint32_t segIndex) const
    {
        const dyld_chained_starts_in_image* imageStarts = (dyld_chained_starts_in_image*)((uint8_t*)_fixupsHeader + _fixupsHeader->starts_offset);
        if ( segIndex >= imageStarts->seg_count )
            return nullptr;
        uint32_t segInfoOffset = imageStarts->seg_info_offset[segIndex];
        if ( segInfoOffset == 0 )
            return nullptr;
        return (dyld_chained_starts_in_segment*)((uint8_t*)imageStarts + segInfoOffset);
    }
    
    void forEachFixupChainSegment(const dyld_chained_starts_in_image* starts,
                                  void (^handler)(const dyld_chained_starts_in_segment* segInfo, uint32_t segIndex, bool& stop)) const {
        bool stopped = false;
        for (uint32_t segIndex=0; segIndex < starts->seg_count && !stopped; ++segIndex) {
            if ( starts->seg_info_offset[segIndex] == 0 )
                continue;
            const dyld_chained_starts_in_segment* segInfo = (dyld_chained_starts_in_segment*)((uint8_t*)starts + starts->seg_info_offset[segIndex]);
            handler(segInfo, segIndex, stopped);
        }
    }
    
    uint64_t toLocation(void *pointer) {
        return (uintptr_t)pointer - _imageHeader;
    }
    
    uint64_t toLocation(const void *pointer) {
        return (uintptr_t)pointer - _imageHeader;
    }
    
    void forEachFixupInSegmentChainsPageStarts(const dyld_chained_starts_in_segment segInfo, void(^callback)(uint32_t pageIndex, uint16_t *offsetInPage)) {
        
    }
    
    void forEachFixupInSegmentChains(const dyld_chained_starts_in_segment* segInfo,
                                     bool notifyNonPointers, uint8_t* segmentContent,
                                     void (^handler)(uint32_t pageIndex, uint16_t offsetInPage, ChainedFixupPointerOnDisk* fixupLocation, bool& stop))
    {
        bool stopped = false;
        for (uint32_t pageIndex = 0; pageIndex < segInfo->page_count && !stopped; pageIndex++) {
            uint16_t offsetInPage = segInfo->page_start[pageIndex];
            if (offsetInPage == DYLD_CHAINED_PTR_START_NONE) {
                continue;
            }
            if (offsetInPage & DYLD_CHAINED_PTR_START_MULTI) {
                uint32_t overflowIndex = offsetInPage & ~DYLD_CHAINED_PTR_START_MULTI;
                bool chainEnd = false;
                while (!chainEnd) {
                    chainEnd = (segInfo->page_start[overflowIndex] & DYLD_CHAINED_PTR_START_LAST);
                    offsetInPage = (segInfo->page_start[overflowIndex] & ~DYLD_CHAINED_PTR_START_LAST);
                    uint8_t* pageContentStart = segmentContent + (pageIndex * segInfo->page_size);
                    ChainedFixupPointerOnDisk* chain = (ChainedFixupPointerOnDisk*)(pageContentStart+offsetInPage);
                    stopped = walkChain(chain, segInfo->pointer_format, notifyNonPointers, segInfo->max_valid_pointer, overflowIndex, offsetInPage, handler);
                    ++overflowIndex;
                }
            } else {
                uint8_t *pageContentStart = (uint8_t *)(segmentContent + (pageIndex * segInfo->page_size));
                ChainedFixupPointerOnDisk *chain = (ChainedFixupPointerOnDisk *)(pageContentStart + offsetInPage);
                stopped = walkChain(chain, segInfo->pointer_format, notifyNonPointers, segInfo->max_valid_pointer, pageIndex, offsetInPage, handler);
            }
        }
    }
    
    bool walkChain( ChainedFixupPointerOnDisk* chain, uint16_t pointer_format, bool notifyNonPointers, uint32_t max_valid_pointer, uint32_t pageIndex, uint16_t offsetInPage,
                   void (^handler)(uint32_t pageIndex, uint16_t offsetInPage, ChainedFixupPointerOnDisk* fixupLocation, bool& stop)) {
        bool stopped = false;
        handler(pageIndex, offsetInPage, chain, stopped);
        return stopped;
    }
    
    union ImportUnion
    {
        struct dyld_chained_import *imports;
        struct dyld_chained_import_addend *importsA32;
        struct dyld_chained_import_addend64 *importsA64;
        const void *rawPointer;
    };
    
private:
    const dyld_chained_fixups_header*          _fixupsHeader   = nullptr;
    uint64_t                                   _fixupsLocation = 0;
    uint64_t                                   _imageHeader    = 0;
    size_t                                     _fixupsSize     = 0;
};

#define MATCH_STRUCT_FORM_IMAGE(obj, var, location) \
  struct obj const * var = (struct obj *)[self imageAt:(location)]; \
  if (!var) [NSException raise:@"null exception" format:@#var " is null"];

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

- (MVNode *) createChainedFixupsParseNode:(MVNode *)parent
                                 location:(uint64_t)location
                                   length:(uint64_t)length {
    const dyld_chained_fixups_header *fixupsHeader = nullptr;
    fixupsHeader = (const dyld_chained_fixups_header *)[self imageAt:location];
    ChainedFixups chainedFixups(fixupsHeader, location, length);
    
    [self createChainedFixupsHeaderNode:parent location:location
                                 length:chainedFixups.getFixupsHeaderSize()
                          chainedFixups:chainedFixups];
    
    [self createChainedFixupsImageStartsNode:parent
                                    location:location + fixupsHeader->starts_offset
                                      length:chainedFixups.getImageStartsSize()
                               chainedFixups:chainedFixups];
    
    [self createChainedFixupsImportsNode:parent
                                location:location + fixupsHeader->imports_offset
                                  length:chainedFixups.getFixupsImportsSize()
                           chainedFixups:chainedFixups];
    
    [self createChainedFixupsSymbolsPoolNode:parent
                                    location:location + fixupsHeader->symbols_offset
                                      length:chainedFixups.getSymbolsPoolSize()];
    
    
    return NULL;
}

- (MVNode *) createChainedFixupsHeaderNode:(MVNode *)parent
                                  location:(uint64_t)location
                                    length:(uint64_t)length
                             chainedFixups:(ChainedFixups &)chainedFixups
{
    size_t headerSize = 0;
    const dyld_chained_fixups_header *fixupsHeader = nullptr;
    fixupsHeader = chainedFixups.getFixupsHeader();
    headerSize = chainedFixups.getFixupsHeaderSize();
    if (fixupsHeader == nullptr || headerSize == 0) {
        return nullptr;
    }
    MVNode *dataNode = [self createDataNode:parent
                                    caption:@"Fixups Header"
                                   location:location
                                     length:headerSize];
    
    NSRange range = NSMakeRange(location,0);
    NSString * lastReadHex;
    MVNodeSaver nodeSaver;
    MVNode * node = [dataNode insertChildWithDetails:@"dyld_chained_fixups_header" location:location length:headerSize saver:nodeSaver];
    {
        [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Fixups Version"
                               :[NSString stringWithFormat:@"%d", fixupsHeader->fixups_version]];
    }
    {
        [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Starts Offset"
                               :[NSString stringWithFormat:@"%d (0x%llx)", fixupsHeader->starts_offset,
                                location + fixupsHeader->starts_offset]];
    }
    {
        [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Imports Offset"
                               :[NSString stringWithFormat:@"%d (0x%llx)", fixupsHeader->imports_offset,
                                location + fixupsHeader->imports_offset]];
    }
    {
        [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Symbols Offset"
                               :[NSString stringWithFormat:@"%d (0x%llx)", fixupsHeader->symbols_offset,
                                location + fixupsHeader->symbols_format]];
        
    }
    {
        [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Imports Count"
                               :[NSString stringWithFormat:@"%d", fixupsHeader->imports_count]];
        
    }
    {
        [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Imports Format"
                               :[NSString stringWithFormat:@"%d (%@)", fixupsHeader->imports_format,
                                [self chainedFixupsImportFormatName:fixupsHeader->imports_format]]];
        
    }
    {
        [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Symbols Format"
                               :[NSString stringWithFormat:@"%d (%@)", fixupsHeader->symbols_format,
                                [self chainedFixupsSymbolFormatName:fixupsHeader->symbols_format]]];
    }
    return node;
}

#pragma mark - 1. 创建 Image Stars 节点 - dyld_chained_starts_in_image (镜像中有几个段需要修复)
- (MVNode *) createChainedFixupsImageStartsNode:(MVNode *)parent
                                       location:(uint64_t)location
                                         length:(uint64_t)length
                                  chainedFixups:(ChainedFixups &)chainedFixups
{
    MVNode *dataNode = [self createDataNode:parent caption:@"Fixups Starts" location:location length:length];
    NSRange range = NSMakeRange(location,0);
    NSString * lastReadHex;
    MVNodeSaver nodeSaver;
    const dyld_chained_starts_in_image *imageStarts = chainedFixups.getImageStarts();
    MVNode * node = [dataNode insertChildWithDetails:@"Fixups Image Starts"
                                            location:location length:imageStarts->seg_count + 1 * sizeof(uint32_t) saver:nodeSaver];
    {
        [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Segment Info Count"
                               :[NSString stringWithFormat:@"%d", imageStarts->seg_count]];
        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        [node.details setAttributes:MVCellColorAttributeName, [NSColor purpleColor], nil];
        
        for (uint32_t segmentIndex = 0; segmentIndex < imageStarts->seg_count; segmentIndex++) {
            [dataController read_uint32:range lastReadHex:&lastReadHex];
            [node.details appendRow:[NSString stringWithFormat:@"#%d", segmentIndex]
                                   :@""
                                   :[NSString stringWithFormat:@"Segment (%s)", segments_64[segmentIndex]->segname]
                                   :nil];
            
            uint32_t offset = imageStarts->seg_info_offset[segmentIndex];
            NSString *offsetInfo = nil;
            if (offset == 0) {
                offsetInfo = @"0 (NO FIXUPS)";
            } else {
                offsetInfo = [NSString stringWithFormat:@"%d (0x%llx)", offset, location + offset];
            }
            [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                                   :lastReadHex
                                   :[NSString stringWithFormat:@"Starts Offset"]
                                   :offsetInfo];
            
            [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        }
    }
    
    chainedFixups.forEachFixupChainSegment(imageStarts, ^(const dyld_chained_starts_in_segment *segInfo, uint32_t segIndex, bool &stop) {
        [self createChainedFixupsSegmentInfoNode:dataNode
                                        location:chainedFixups.toLocation(segInfo)
                                          length:segInfo->size
                                    segmentIndex:segIndex
                                   chainedFixups:chainedFixups];
    });
    return dataNode;
}

#pragma mark - 2. 创建 Segment Starts - dyld_chained_starts_in_segment (每个段中有多少页需要修复)

/**
 - Image Fixups Chains
    - Segment Fixups Chains
        - In Page Fixups Chains
            - chiled Fixups Starts
        - fixups Actions
    
- Fixups Actions
    - page Info
        - 所在段、节
        - page 索引
        - chain starts index (节点)
    - location:
    - REBASE
        
    - BIND
        - lib name
        - symbol name
        - import symbol index
        
 */

- (MVNode *) createChainedFixupsSegmentInfoNode:(MVNode *)parent
                                       location:(uint64_t)location
                                         length:(uint64_t)length
                                   segmentIndex:(uint32_t)segmentIndex
                                  chainedFixups:(ChainedFixups &)chainedFixups
{
    const dyld_chained_starts_in_segment *segInfo = chainedFixups.startsForSegment(segmentIndex);
    NSRange range = NSMakeRange(location,0);
    NSString * lastReadHex;
    MVNodeSaver nodeSaver;
    MVNodeSaver opcodesSaver;
    MVNodeSaver actionsSaver;
    
    MVNode *dataNode = [self createDataNode:parent caption:[NSString stringWithFormat:@"Fixups Segment (%s)", segments_64[segmentIndex]->segname]
                                   location:location length:length];
    MVNode *opcodesNode = [dataNode insertChildWithDetails:@"Opcodes" location:location length:length saver:opcodesSaver];
    MVNode *actionsNode = [dataNode insertChildWithDetails:@"Actions" location:location length:length saver:actionsSaver];
    {
        [dataController read_uint32:range lastReadHex:&lastReadHex];
        [opcodesNode.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Size"
                               :[NSString stringWithFormat:@"%d", segInfo->size]];
        
        [opcodesNode.details setAttributes:MVCellColorAttributeName, [NSColor purpleColor], nil];
        [dataController read_uint16:range lastReadHex:&lastReadHex];
        [opcodesNode.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Page Size"
                               :[NSString stringWithFormat:@"%d", segInfo->page_size]];
        
        [opcodesNode.details setAttributes:MVCellColorAttributeName, [NSColor purpleColor], nil];
        [dataController read_uint16:range lastReadHex:&lastReadHex];
        [opcodesNode.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Pointer Format"
                               :[NSString stringWithFormat:@"%d (%s)", segInfo->pointer_format,
                                             ChainedFixups::pointerFormatName(segInfo->pointer_format)]];
        
        [opcodesNode.details setAttributes:MVCellColorAttributeName, [NSColor purpleColor], nil];
        [dataController read_uint64:range lastReadHex:&lastReadHex];
        [opcodesNode.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Segment Offset"
                               :[NSString stringWithFormat:@"%lld (%s)", segInfo->segment_offset, segments_64[segmentIndex]->segname]];
        
        [opcodesNode.details setAttributes:MVCellColorAttributeName, [NSColor purpleColor], nil];
        [dataController read_uint32:range lastReadHex:&lastReadHex];
        [opcodesNode.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Max Valid Pointer"
                               :[NSString stringWithFormat:@"%d", segInfo->max_valid_pointer]];
        
        [opcodesNode.details setAttributes:MVCellColorAttributeName, [NSColor purpleColor], nil];
        [dataController read_uint16:range lastReadHex:&lastReadHex];
        [opcodesNode.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Page Count"
                               :[NSString stringWithFormat:@"%d", segInfo->page_count]];
        [opcodesNode.details setAttributes:MVCellColorAttributeName, [NSColor purpleColor], nil];
        [opcodesNode.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        
        if ([self isSupportePointerFormat:segInfo->pointer_format]) {
            [actionsNode.details appendRow:[NSString stringWithFormat:@"%.8lX", (unsigned long)0]
                                          :@""
                                          :@"Exception information"
                                          :[NSString stringWithFormat:@"Unsupported pointer format (%s)", chainedFixups.pointerFormatName(segInfo->pointer_format)]];
            [actionsNode.details setAttributes:MVCellColorAttributeName, [NSColor redColor], nil];
        }
        
        
        for (uint32_t pageIndex = 0; pageIndex < segInfo->page_count; pageIndex++) {
            uint16_t offsetInPage = [dataController read_uint16:range lastReadHex:&lastReadHex];
            NSString *pageContentStartInfo = nil;
            if (offsetInPage == DYLD_CHAINED_PTR_START_NONE) {
                pageContentStartInfo = @"DYLD_CHAINED_PTR_START_NONE (Not Fixups)";
            } else if (offsetInPage & DYLD_CHAINED_PTR_START_MULTI) {
                pageContentStartInfo = @"DYLD_CHAINED_PTR_START_MULTI (Not Supported)";
            } else {
                uint64_t pageContentStart = segInfo->segment_offset + (pageIndex * segInfo->page_size);
                pageContentStartInfo = [NSString stringWithFormat:@"0x%llx + $%d (0x%llx)", pageContentStart, offsetInPage, pageContentStart + offsetInPage];
     
            }
            [opcodesNode.details appendRow:[NSString stringWithFormat:@"#%d", pageIndex] :nil :@"Page Index" :nil];
            [opcodesNode.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                                          :lastReadHex
                                          :@"Fixups Chain Starts"
                                          :pageContentStartInfo];
            [opcodesNode.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        }
    }
    return dataNode;
}

- (BOOL)isSupportePointerFormat:(uint32_t)pointerFormat
{
    switch (pointerFormat) {
        case DYLD_CHAINED_PTR_ARM64E:
        case DYLD_CHAINED_PTR_ARM64E_USERLAND:
        case DYLD_CHAINED_PTR_ARM64E_USERLAND24:
        case DYLD_CHAINED_PTR_64:
        case DYLD_CHAINED_PTR_64_OFFSET:
            return YES;
        default:
            return NO;
    }
}

- (void)forEachChain:(ChainedFixupPointerOnDisk *)chain pointerFormat:(uint32_t)pointerFormat callback:(void(^)(ChainedFixupPointerOnDisk *fixupsLocation))callback  {
    callback(chain);
    switch (pointerFormat) {
        case DYLD_CHAINED_PTR_ARM64E:
        case DYLD_CHAINED_PTR_ARM64E_USERLAND:
        case DYLD_CHAINED_PTR_ARM64E_USERLAND24:
        {
            
        }
            break;
        case DYLD_CHAINED_PTR_64:
        case DYLD_CHAINED_PTR_64_OFFSET:
        {
            
        }
            break;
            
        case DYLD_CHAINED_PTR_32:
        case DYLD_CHAINED_PTR_32_CACHE:
        case DYLD_CHAINED_PTR_32_FIRMWARE:
        case DYLD_CHAINED_PTR_ARM64E_KERNEL:
        case DYLD_CHAINED_PTR_ARM64E_FIRMWARE:
        case DYLD_CHAINED_PTR_64_KERNEL_CACHE:
        case DYLD_CHAINED_PTR_X86_64_KERNEL_CACHE:
        default:
            //TODO: Not supported
            break;
    }
    
    
}

- (MVNode *) createChainedFixupsSegmentActionsNode:(MVNode *)parent
                                           caption:(NSString *)caption
                                       location:(uint64_t)location
                                         length:(uint64_t)length
                                   segmentIndex:(uint32_t)segmentIndex
                                     chainedFixups:(ChainedFixups &)chainedFixups {
    NSString * lastReadHex;
    MVNodeSaver nodeSaver;
    MVNode * node = [parent insertChildWithDetails:caption location:location length:length saver:nodeSaver];
    return node;
}

- (bool)walkChain:(ChainedFixupPointerOnDisk *)chain location:(uint64_t)location
                                                pointerFormat:(uint16_t)pointerFormat
         callback:(void(^)(ChainedFixupPointerOnDisk *fixupsLocation))callbck
{
    
    return false;
}

#pragma mark - 创建 Page Starts 节点 - offsetInPage (每页中有多少数据需要修复)
- (void) insertChainedFixupsChainStartsNode:(MVNode *)opcodes
                                actionsNode:(MVNode *)actions
                                   location:(uint64_t)location
                                     length:(uint64_t)length
                                segmentInfo:(const dyld_chained_starts_in_segment *)segInfo
                               segmentIndex:(uint32_t)segmentIndex
                                  pageIndex:(uint32_t)pageIndex
                              chainedFixups:(ChainedFixups &)chainedFixups
{
    const segment_command_64 *segment_cmd = segments_64[segmentIndex];
    uint64_t segmentVmaddr = segment_cmd->vmaddr;
    uint64_t segmentContent = segment_cmd->fileoff;
    uint16_t offsetInPage = segInfo->page_start[pageIndex];
    if (offsetInPage & DYLD_CHAINED_PTR_START_MULTI) {
        
    } else {
        uint64_t pageContentStart = segmentContent + pageIndex * segInfo->page_size;
        uint64_t pageVmaddrStart = segmentVmaddr + pageIndex * segInfo->page_size;
        [self createChainedFixupsPageNode:opcodes
                                 location:pageContentStart + offsetInPage
                            pointerFormat:segInfo->pointer_format
                          maxValidPointer:segInfo->max_valid_pointer
                             segmentIndex:segmentIndex
                            targetAddress:pageVmaddrStart];
    }
    
//    [opcodes.details appendRow:@"opt" :@"" :@"Chain Starts" :[NSString stringWithFormat:@"0x%llx", location]];
//    [opcodes.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
    
}

- (MVNode *) createChainedFixupsImportsNode:(MVNode *)parent
                                  location:(uint64_t)location
                                    length:(uint64_t)length
                             chainedFixups:(ChainedFixups &)chainedFixups
{
    MVNode *dataNode = [self createDataNode:parent caption:@"Fixups Imports" location:location length:length];
    NSRange range = NSMakeRange(location,0);
    NSString * lastReadHex;
    MVNodeSaver nodeSaver;
    MVNode * node = [dataNode insertChildWithDetails:@"Imports Table"
                                            location:location
                                              length:length saver:nodeSaver];
    uint32_t importCount = chainedFixups.getFixupsHeader()->imports_count;
    uint32_t importFormat = chainedFixups.getFixupsHeader()->imports_format;
    
    union ChainedFixups::ImportUnion importUnion;
    importUnion.rawPointer = [self imageAt:location];
    for (uint32_t index = 0; index < importCount; index++) {
        [node.details appendRow:[NSString stringWithFormat:@"#%d", index] :nil :nil :nil];
        switch (importFormat) {
            case DYLD_CHAINED_IMPORT:
            {
                const dyld_chained_import *importInfo = &importUnion.imports[index];
                [dataController read_uint32:range lastReadHex:&lastReadHex];
                [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                                       :lastReadHex
                                       :@"Import Info"
                                       :@"DYLD_CHAINED_IMPORT"];
                
                [node.details appendRow:@"" :@""
                                       :@"Lib Ordinal"
                                       :[NSString stringWithFormat:@"%d (%@)", importInfo->lib_ordinal, [self getImportDylibNameWithLibOrdinal:importInfo->lib_ordinal]]];
                
                [node.details appendRow:@"" :@""
                                       :@"Weak Import"
                                       :[NSString stringWithFormat:@"%d", importInfo->weak_import]];
                
                [node.details appendRow:@"" :@""
                                       :@"Name Offset"
                                       :[NSString stringWithFormat:@"#%d (%s)", importInfo->name_offset, chainedFixups.getSymbolName(importInfo->name_offset)]];
            }
                break;
            case DYLD_CHAINED_IMPORT_ADDEND:
            {
                const dyld_chained_import_addend *importInfo = &importUnion.importsA32[index];
                [dataController read_uint32:range lastReadHex:&lastReadHex];
                [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                                       :lastReadHex
                                       :@"Import Info"
                                       :@"DYLD_CHAINED_IMPORT_ADDEND"];
                
                [node.details appendRow:@"" :@""
                                       :@"Lib Ordinal"
                                       :[NSString stringWithFormat:@"%d (%@)", importInfo->lib_ordinal, [self getImportDylibNameWithLibOrdinal:importInfo->lib_ordinal]]];
                
                [node.details appendRow:@"" :@""
                                       :@"Weak Import"
                                       :[NSString stringWithFormat:@"%d", importInfo->weak_import]];
                
                [node.details appendRow:@"" :@""
                                       :@"Name Offset"
                                       :[NSString stringWithFormat:@"#%d (%s)", importInfo->name_offset, chainedFixups.getSymbolName(importInfo->name_offset)]];
                
                [dataController read_uint32:range lastReadHex:&lastReadHex];
                [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                                       :lastReadHex
                                       :@"Addend"
                                       :[NSString stringWithFormat:@"%d", importInfo->addend]];
                
            }
                break;
            case DYLD_CHAINED_IMPORT_ADDEND64:
            {
                const dyld_chained_import_addend64 *importInfo = &importUnion.importsA64[index];
                [dataController read_uint64:range lastReadHex:&lastReadHex];
                [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                                       :lastReadHex
                                       :@"Import Info"
                                       :@"DYLD_CHAINED_IMPORT_ADDEND64"];
                
                [node.details appendRow:@"" :@""
                                       :@"Lib Ordinal"
                                       :[NSString stringWithFormat:@"%d (%@)", importInfo->lib_ordinal, [self getImportDylibNameWithLibOrdinal:importInfo->lib_ordinal]]];
                
                [node.details appendRow:@"" :@""
                                       :@"Reserved"
                                       :[NSString stringWithFormat:@"%d", importInfo->reserved]];
                
                [node.details appendRow:@"" :@""
                                       :@"Weak Import"
                                       :[NSString stringWithFormat:@"%d", importInfo->weak_import]];
                
                [node.details appendRow:@"" :@""
                                       :@"Name Offset"
                                       :[NSString stringWithFormat:@"#%d (%s)", importInfo->name_offset, chainedFixups.getSymbolName(importInfo->name_offset)]];
                
                [dataController read_uint32:range lastReadHex:&lastReadHex];
                [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                                       :lastReadHex
                                       :@"Addend"
                                       :[NSString stringWithFormat:@"%lld", importInfo->addend]];
            }
                break;
            default:
                
                break;
        }
        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
    }
    return node;
}

- (MVNode *) createChainedFixupsSymbolsPoolNode:(MVNode *)parent
                                  location:(uint64_t)location
                                    length:(uint64_t)length
{
    MVNode *dataNode = [self createDataNode:parent caption:@"Fixups Symbols" location:location length:length];
    return [self createCStringsNode:dataNode
                            caption:@"C String Literals"
                           location:location
                             length:length];
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
//            case DYLD_CHAINED_PTR_64_KERNEL_CACHE:
//            case DYLD_CHAINED_PTR_X86_64_KERNEL_CACHE:
//            {
//                if (chainContent->kernel64.next == 0) {
//                    chainEnd = true;
//                } else {
//                    chainPointer += chainContent->kernel64.next * stride;
//                }
//            }
//                break;
//            case DYLD_CHAINED_PTR_32_FIRMWARE:
//            {
//                if (chainContent->firmware32.next == 0) {
//                    chainEnd = true;
//                } else {
//                    chainPointer += chainContent->firmware32.next * 4;
//                }
//            }
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

/* Chained Fixups Layout
    struct dyld_chained_fixups_header
    {
        uint32_t    fixups_version;    // 0
        uint32_t    starts_offset;     // offset of dyld_chained_starts_in_image in chain_data
        uint32_t    imports_offset;    // offset of imports table in chain_data
        uint32_t    symbols_offset;    // offset of symbol strings in chain_data
        uint32_t    imports_count;     // number of imported symbol names
        uint32_t    imports_format;    // DYLD_CHAINED_IMPORT*
        uint32_t    symbols_format;    // 0 => uncompressed, 1 => zlib compressed
        // align8 对齐
    }; -> 32
    
    struct dyld_chained_starts_in_image
    {
        uint32_t    seg_count;
        uint32_t    seg_info_offset[1];  // each entry is offset into this struct for that segment
        // followed by pool of dyld_chain_starts_in_segment data
    }; -> seg_count * uint32_t
 
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
    }; -> bind or rebase chains 22 + list
    
    
    struct dyld_chained_import_* // imports_format ->
    {
        uint32_t    lib_ordinal :  8,
                    weak_import :  1,
                    name_offset : 23;
    };
 */
