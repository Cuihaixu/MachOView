//
//  MachOLayout+ChainedFixups.m
//  MachOView
//
//  Created by cu on 2024/8/9.
//

#import "ChainedFixups.h"
#import <mach-o/fixup-chains.h>
#import "Common.h"
#import "DyldInfo.h"
#import "ReadWrite.h"
#import "DataController.h"

@implementation MachOLayout (ChainedFixups)

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
                               :@""];
    }
    {
        header->starts_offset = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Starts Offset"
                               :@""];
    }
    {
        header->imports_offset = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Imports Offset"
                               :@""];
    }
    {
        header->symbols_offset = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Symbols Offset"
                               :@""];
        
    }
    {
        header->imports_count = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Imports Count"
                               :@""];
        
    }
    {
        header->imports_format = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Fixups Version"
                               :@""];
        
    }
    {
        header->symbols_format = [dataController read_uint32:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"Symbols Format"
                               :@""];
    }
    return node;
}

- (MVNode *) createChainedFixupsStartsNode:(MVNode *)parent
                                   caption:(NSString *)caption
                                  location:(uint64_t)location
                                    length:(uint64_t)length
{
    
    
    return NULL;
}

@end
