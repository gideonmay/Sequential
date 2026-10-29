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

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "PGFolderAdapter.h"
#import <sys/event.h>

// Models
#import "PGDocument.h"
#import "PGNode.h"
#import "PGResourceIdentifier.h"
#import "PGResourceDataProvider.h"
#import "PGDataProvider.h"

// Controllers
#import "PGDocumentController.h"

// Other Sources
#import "PGFoundationAdditions.h"

static NSArray *PGIgnoredPaths = nil;

@interface PGDiskFolderDataProvider : PGResourceDataProvider	//	2023/10/22
@end

//	MARK: -
@implementation PGDiskFolderDataProvider

//	MARK: PGDataProvider
- (NSString *)UTIType
{
	if (@available(macOS 11.0, *))
		return UTTypeFolder.identifier;
	else
		return (NSString *)kUTTypeFolder;
}
- (OSType)typeCode
{
	return 'fold';
}

@end

//	MARK: -
@implementation PGFolderAdapter

//	MARK: +NSObject

+ (void)initialize
{
	if([PGFolderAdapter class] != self) return;
	PGIgnoredPaths = @[@"/net", @"/etc", @"/home", @"/tmp", @"/var", @"/mach_kernel.ctfsys", @"/mach.sym"];
}

//	MARK: +PGDataProviderCustomizing

//	2023/10/22
+ (PGDataProvider *)customDataProviderWithResourceIdentifier:(PGResourceIdentifier *)ident displayableName:(NSString *)name
{
	if(!ident.isFileIdentifier)
		return nil;
	NSURL *const URL = ident.URL;
	NSError *error = nil;
	NSURLFileResourceType value = nil;
	BOOL const b = [URL getResourceValue:&value forKey:NSURLFileResourceTypeKey error:&error];
	if(!b || error || ![value isEqual:NSURLFileResourceTypeDirectory])
		return nil;
#if __has_feature(objc_arc)
	return [[PGDiskFolderDataProvider alloc] initWithResourceIdentifier:ident displayableName:name];
#else
	return [[[PGDiskFolderDataProvider alloc] initWithResourceIdentifier:ident displayableName:name] autorelease];
#endif
}

//	MARK: - PGFolderAdapter

static
BOOL
IsPackage(NSURL* URL) {
#if 1	//	2021/07/21
	id value = nil;
	NSError* error = nil;
	BOOL b = [URL getResourceValue:&value forKey:NSURLIsPackageKey error:&error];
	return b ? ![value isEqual:@NO] : YES;
//	return [URL getResourceValue:&value forKey:NSURLIsPackageKey error:&error] && ![value isEqual:@NO];
#else
	LSItemInfoRecord info;
	return LSCopyItemInfoForURL((CFURLRef)URL, kLSRequestBasicFlagsOnly, &info) == noErr &&
			0 != (info.flags & kLSItemInfoIsPackage);
#endif
}

static
bool
IsVisibleInFinder(NSURL* pageURL) {
#if 1	//	2021/07/21
	id value = nil;
	NSError* error = nil;
	BOOL b = [pageURL getResourceValue:&value forKey:NSURLIsHiddenKey error:&error];
	return b ? [value isEqual:@NO] : NO;
//	return [pageURL getResourceValue:&value forKey:NSURLIsHiddenKey error:&error] && [value isEqual:NO];
#else
	LSItemInfoRecord info;
	return LSCopyItemInfoForURL((CFURLRef)pageURL, kLSRequestBasicFlagsOnly, &info) == noErr &&
			0 != (info.flags & kLSItemInfoIsInvisible);
#endif
}

//	2026/10/28 added: lists the subfolders of a folder on background threads
//	(several at a time) while the folder's files are processed, so that their
//	listings are in the file system's cache when they're loaded; on network
//	volumes each listing is a round trip, which made up most of the loading time
static void
PGPrefetchSubfolderListings(NSArray<NSURL *> *URLs)
{
	static dispatch_queue_t queue;
	static dispatch_semaphore_t slots;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("PGFolderAdapter.prefetch", DISPATCH_QUEUE_CONCURRENT);
		slots = dispatch_semaphore_create(8);
	});
	for(NSURL *const URL in URLs) {
		NSNumber *isDirectory = nil, *isPackage = nil;
		[URL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
		[URL getResourceValue:&isPackage forKey:NSURLIsPackageKey error:NULL];
		if(!isDirectory.boolValue || isPackage.boolValue) continue;
		dispatch_async(queue, ^{
			dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
			@autoreleasepool {
				(void)[[NSFileManager new] contentsOfDirectoryAtURL:URL
					includingPropertiesForKeys:@[NSURLIsHiddenKey, NSURLIsDirectoryKey, NSURLIsPackageKey]
					options:kNilOptions error:NULL];
			}
			dispatch_semaphore_signal(slots);
		});
	}
}

- (void)createChildren
{
	NSURL *const URL = [((PGDataProvider *)self.dataProvider).identifier URLByFollowingAliases:YES];
	if(IsPackage(URL))
		return;

	self.document.processingNodes = YES;
#if __has_feature(objc_arc)
	NSMutableArray *const oldPages = [self.unsortedChildren mutableCopy];
#else
	NSMutableArray *const oldPages = [[[self unsortedChildren] mutableCopy] autorelease];
#endif
	NSMutableArray *const newPages = [NSMutableArray array];
	PGDocumentController *const dc = [PGDocumentController sharedDocumentController];	//	2026/10/28 added
	//	2026/10/28 the attributes that are needed are fetched with the listing
	//	(in bulk) instead of one request per file, which is slow on network volumes
	NSArray<NSURL *> *const pageURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:URL
		includingPropertiesForKeys:@[NSURLIsHiddenKey, NSURLIsDirectoryKey, NSURLIsPackageKey, NSURLTypeIdentifierKey]
		options:kNilOptions error:NULL];
	//	2026/10/28 added: only the subfolders that will be loaded (see -shouldRecursivelyCreateChildren)
	PGRecursionPolicy const policy = self.descendantRecursionPolicy;
	if(PGRecurseToAnyDepth == policy || (PGRecurseToMaxDepth == policy &&
	   self.depth <= [[[NSUserDefaults standardUserDefaults] objectForKey:PGMaxDepthKey] unsignedIntegerValue]))
		PGPrefetchSubfolderListings(pageURLs);
	for(NSURL *const pageURL in pageURLs) {
		if(dc.loadingProgressStopped) break;
		NSString *const pagePath = pageURL.path;
		[dc noteLoadingProgressForPath:pagePath];
		if([PGIgnoredPaths containsObject:pagePath]) continue;
		if(!IsVisibleInFinder(pageURL))
			continue;

		if(dc.loadingProgressWantsThumbnail &&	//	2026/10/28 added
		   [[UTType typeWithFilenameExtension:pagePath.pathExtension] conformsToType:UTTypeImage])
			[dc addLoadingProgressThumbnailFromURL:pageURL];

		PGDisplayableIdentifier *const pageIdent = pageURL.PG_displayableIdentifier;
		PGNode *node = [self childForIdentifier:pageIdent];
		if(node) {
			[oldPages removeObjectIdenticalTo:node];
			[node noteFileEventDidOccurDirect:NO];
		} else {
#if __has_feature(objc_arc)
			node = [[PGNode alloc] initWithParent:self identifier:pageIdent];
#else
			node = [[[PGNode alloc] initWithParent:self identifier:pageIdent] autorelease];
#endif
			node.dataProvider = [PGDataProvider providerWithResourceIdentifier:pageIdent];
		}
		if(node) [newPages addObject:node];
	}
	[self setUnsortedChildren:newPages presortedOrder:PGUnsorted];
	self.document.processingNodes = NO;
}

//	MARK: - PGResourceAdapter

- (void)load
{
	[self createChildren];
	[self.node loadFinishedForAdapter:self];
}

//	MARK: - <PGResourceAdapting>

- (void)noteFileEventDidOccurDirect:(BOOL)flag
{
	if(!((PGDataProvider *)self.dataProvider).identifier.hasTarget) [self.node removeFromDocument];
	else if(flag) [self createChildren];
}

@end
