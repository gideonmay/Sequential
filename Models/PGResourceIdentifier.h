/* Copyright © 2007-2009, The Sequential Project
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the the Sequential Project nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE SEQUENTIAL PROJECT ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE SEQUENTIAL PROJECT BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
// Models
@class PGDisplayableIdentifier;
@class PGSubscription;

extern NSString *const PGDisplayableIdentifierIconDidChangeNotification;
extern NSString *const PGDisplayableIdentifierDisplayNameDidChangeNotification;

#if 1	//	2021/07/21 modernized

@interface PGResourceIdentifier : NSObject <NSSecureCoding>	//	NSCoding

+ (instancetype)resourceIdentifierWithURL:(NSURL *)URL;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_DESIGNATED_INITIALIZER;

@property(readonly) PGResourceIdentifier *identifier;
@property(readonly) PGDisplayableIdentifier *displayableIdentifier;
@property(readonly) PGResourceIdentifier *superidentifier;
@property(readonly) PGResourceIdentifier *rootIdentifier;
@property(readonly) NSURL *URL; // Equivalent to -URLByFollowingAliases:NO.
@property(readonly) NSInteger index;
@property(readonly) BOOL hasTarget;
@property(readonly) BOOL isFileIdentifier;

- (PGResourceIdentifier *)subidentifierWithIndex:(NSInteger)index;

- (NSURL *)superURLByFollowingAliases:(BOOL)flag; // Our URL, or our superidentifier's otherwise.
- (NSURL *)URLByFollowingAliases:(BOOL)flag;

- (PGSubscription *)subscriptionWithDescendents:(BOOL)flag;

@end

#else
/*

enum {
	PGLabelNone   = 0,
	PGLabelRed    = 6,
	PGLabelOrange = 7,
	PGLabelYellow = 5,
	PGLabelGreen  = 2,
	PGLabelBlue   = 4,
	PGLabelPurple = 3,
	PGLabelGray   = 1
};
typedef UInt8 PGLabelColor;

@interface PGResourceIdentifier : NSObject <NSCoding>

+ (id)resourceIdentifierWithURL:(NSURL *)URL;
//+ (id)resourceIdentifierWithAliasData:(const uint8_t *)data length:(NSUInteger)length; // For backward compatability.

@property(readonly) PGResourceIdentifier *identifier;
@property(readonly) PGDisplayableIdentifier *displayableIdentifier;
@property(readonly) PGResourceIdentifier *superidentifier;
@property(readonly) PGResourceIdentifier *rootIdentifier;
@property(readonly) NSURL *URL; // Equivalent to -URLByFollowingAliases:NO.
@property(readonly) NSInteger index;
@property(readonly) BOOL hasTarget;
@property(readonly) BOOL isFileIdentifier;

- (PGResourceIdentifier *)subidentifierWithIndex:(NSInteger)index;

- (NSURL *)superURLByFollowingAliases:(BOOL)flag; // Our URL, or our superidentifier's otherwise.
- (NSURL *)URLByFollowingAliases:(BOOL)flag;
- (BOOL)getRef:(out FSRef *)outRef byFollowingAliases:(BOOL)flag;

- (PGSubscription *)subscriptionWithDescendents:(BOOL)flag;

@end

*/
#endif

//	MARK: -

@interface PGDisplayableIdentifier : PGResourceIdentifier
#if !__has_feature(objc_arc)
{
	@private
	PGResourceIdentifier *_identifier;
	BOOL _postsNotifications;
	NSImage *_icon;
	NSString *_naturalDisplayName;
	NSString *_customDisplayName;
}
#endif

#if __has_feature(objc_arc)
@property (nonatomic, assign) BOOL postsNotifications;
@property (nonatomic, strong) NSImage *icon;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, copy) NSString *customDisplayName;
@property (nonatomic, copy) NSString *naturalDisplayName; // The name from the filesystem or raw address of the URL.
//@property(readonly) PGLabelColor labelColor;	2021/07/21 modernized
@property (nonatomic, readonly) NSColor* labelColor;
@property (nonatomic, readonly) NSArray<NSColor *> *tagColors;	//	2026/10/28 added: the colors of the file's Finder tags (cached)
@property (nonatomic, readonly) NSArray<NSNumber *> *tagLabels;	//	2026/10/28 added: the label numbers of the file's Finder tags in their order (cached)
#else
@property(assign) BOOL postsNotifications;
@property(retain) NSImage *icon;
@property(readonly) NSString *displayName;
@property(copy) NSString *customDisplayName;
@property(copy) NSString *naturalDisplayName; // The name from the filesystem or raw address of the URL.
//@property(readonly) PGLabelColor labelColor;	2021/07/21 modernized
@property(readonly) NSColor* labelColor;
#endif

- (NSAttributedString *)attributedStringWithAncestory:(BOOL)flag;
- (void)noteNaturalDisplayNameDidChange;
- (void)noteFinderTagsDidChange;	//	2026/10/28 added: rereads the tags next time

@end

//	2026/10/28 added: Finder tags are read and written as the extended attribute
//	that holds them, a list of "name\nlabel" strings (the label number is the
//	tag's color, an index into -[NSWorkspace fileLabels]), so that tags that
//	are already there keep their colors
extern NSArray<NSString *> *PGFinderTagsOfURL(NSURL *URL);
extern BOOL PGSetFinderTagsOfURL(NSURL *URL, NSArray<NSString *> *tags);
extern NSUInteger PGFinderTagLabel(NSString *tag, NSArray<NSString *> *labels);	//	0 if it has no color

//	MARK: -

@interface NSURL(PGResourceIdentifierCreation)

@property(readonly) PGResourceIdentifier *PG_resourceIdentifier;
@property(readonly) PGDisplayableIdentifier *PG_displayableIdentifier;

@end
