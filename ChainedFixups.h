//
//  MachOLayout+ChainedFixups.h
//  MachOView
//
//  Created by cu on 2024/8/9.
//

#import "MachOLayout.h"

NS_ASSUME_NONNULL_BEGIN

@interface MachOLayout (ChainedFixups)

- (MVNode *) createChainedFixupsChildNodes:(MVNode *)parent
                                  location:(uint64_t)location
                                    length:(uint64_t)length;

- (MVNode *) createChainedFixupsParseNode:(MVNode *)parent
                                 location:(uint64_t)location
                                   length:(uint64_t)length;
@end

NS_ASSUME_NONNULL_END
