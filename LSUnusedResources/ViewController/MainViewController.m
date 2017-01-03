//
//  MainViewController.m
//  LSUnusedResources
//
//  Created by lslin on 15/8/31.
//  Copyright (c) 2015年 lessfun.com. All rights reserved.
//

#import "MainViewController.h"
#import "ResourceFileSearcher.h"
#import "ResourceStringSearcher.h"
#import "StringUtils.h"

// Constant strings
static NSString * const kDefaultResourceSuffixs    = @"imageset;jpg;gif;png;webp";
static NSString * const kTableColumnImageIcon      = @"ImageIcon";
static NSString * const kTableColumnImageShortName = @"ImageShortName";
static NSString * const kTableColumnFileSize       = @"FileSize";

@interface MainViewController () <NSTableViewDelegate, NSTableViewDataSource>{
    BOOL _fileSizeDesc;//文件大小按降序排列
}

// Project
@property (weak) IBOutlet NSButton *browseButton;
@property (weak) IBOutlet NSTextField *pathTextField;
@property (weak) IBOutlet NSTextField *excludeFolderTextField;

// Settings
@property (weak) IBOutlet NSTextField *resSuffixTextField;

@property (weak) IBOutlet NSButton *headerCheckbox;
@property (weak) IBOutlet NSButton *mCheckbox;
@property (weak) IBOutlet NSButton *mmCheckbox;
@property (weak) IBOutlet NSButton *cppCheckbox;
@property (weak) IBOutlet NSButton *swiftCheckbox;

@property (weak) IBOutlet NSButton *htmlCheckbox;
@property (weak) IBOutlet NSButton *cssCheckbox;
@property (weak) IBOutlet NSButton *plistCheckbox;
@property (weak) IBOutlet NSButton *xibCheckbox;
@property (weak) IBOutlet NSButton *sbCheckbox;
@property (weak) IBOutlet NSButton *jsonCheckbox;

@property (weak) IBOutlet NSButton *ignoreSimilarCheckbox;

// Result
@property (weak) IBOutlet NSTableView *resultsTableView;
@property (weak) IBOutlet NSProgressIndicator *processIndicator;
@property (weak) IBOutlet NSTextField *statusLabel;

@property (weak) IBOutlet NSButton *searchButton;
@property (weak) IBOutlet NSButton *exportButton;
@property (weak) IBOutlet NSButton *deleteButton;

@property (strong, nonatomic) NSMutableArray *unusedResults;//<ResourceFileInfo *>
@property (assign, nonatomic) BOOL isFileDone;
@property (assign, nonatomic) BOOL isStringDone;
@property (strong, nonatomic) NSDate *startTime;

@property (nonatomic, copy) NSString *codePath;
@property (nonatomic, copy) NSString *pbfileLocation;

- (IBAction)onBrowseButtonClicked:(id)sender;
- (IBAction)onSearchButtonClicked:(id)sender;
- (IBAction)onExportButtonClicked:(id)sender;
- (IBAction)onDeleteButtonClicked:(id)sender;

@end

@implementation MainViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    // Setup double click
    self.unusedResults = [NSMutableArray array];
    [self.resultsTableView setDoubleAction:@selector(tableViewDoubleClicked)];
    self.resultsTableView.allowsEmptySelection = YES;
    self.resultsTableView.allowsMultipleSelection = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onResourceFileQueryDone:) name:kNotificationResourceFileQueryDone object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onResourceStringQueryDone:) name:kNotificationResourceStringQueryDone object:nil];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

#pragma mark - Action

- (IBAction)onBrowseButtonClicked:(id)sender {
    // Show an open panel
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseDirectories:YES];
    [openPanel setCanChooseFiles:NO];
    
    BOOL okButtonPressed = ([openPanel runModal] == NSModalResponseOK);
    if (okButtonPressed) {
        // Update the path text field
        NSString *path = [[openPanel URL] path];
        [self.pathTextField setStringValue:path];
    }
}

- (IBAction)onSearchButtonClicked:(id)sender {
    // Check if user has selected or entered a path
    NSString *projectPath = self.pathTextField.stringValue;
    if (projectPath.length <= 0) {
        projectPath = @"/Users/yxj/Desktop/OneCarpoolDev/DeleteDuplicatedImage/ONECarpool";
    }
    if (!projectPath.length) {
        [self showAlertWithStyle:NSWarningAlertStyle title:@"Path Error" subtitle:@"Project path is empty"];
        return;
    }
    
    // Check the path exists
    BOOL pathExists = [[NSFileManager defaultManager] fileExistsAtPath:projectPath];
    if (!pathExists) {
        [self showAlertWithStyle:NSWarningAlertStyle title:@"Path Error" subtitle:@"Project folder is not exists"];
        return;
    }
    self.codePath = projectPath;
    
    self.startTime = [NSDate date];
    
    // Reset
    [[ResourceFileSearcher sharedObject] reset];
    [[ResourceStringSearcher sharedObject] reset];
    
    [self.unusedResults removeAllObjects];//unusedResults NSMutableArray<ResourceFileInfo *>, 主界面的数据源
    [self.resultsTableView reloadData];
    [self setUIEnabled:NO];//开始搜索，禁用 UI 交互
    self.isFileDone = NO;
    self.isStringDone = NO;//初始化状态
    
    NSArray *resourceSuffixs = [self resourceSuffixs];
    if (!self.resourceSuffixs.count) {
        [self showAlertWithStyle:NSWarningAlertStyle title:@"Suffix Error" subtitle:@"Resource suffix is invalid"];
        return ;
    }
    NSArray *fileSuffixs = [self includeFileSuffixs];//要去检索的是否有引用图片的文件类型？
    //排除的文件夹，好像有 bug？
    NSArray *excludeFolders = self.excludeFolderTextField.stringValue.length ? [self.excludeFolderTextField.stringValue componentsSeparatedByString:@";"] : nil;
    if (!excludeFolders) {
        excludeFolders = @[@"Project", @"docs", @"Pods"];
    }
    
    [[ResourceFileSearcher sharedObject] startWithProjectPath:projectPath excludeFolders:excludeFolders resourceSuffixs:resourceSuffixs];
    [[ResourceStringSearcher sharedObject] startWithProjectPath:projectPath excludeFolders:excludeFolders resourceSuffixs:resourceSuffixs fileSuffixs:fileSuffixs];
}

- (IBAction)onExportButtonClicked:(id)sender {
    NSSavePanel *save = [NSSavePanel savePanel];
    [save setAllowedFileTypes:[NSArray arrayWithObject:@"txt"]];
    
    BOOL okButtonPressed = ([save runModal] == NSModalResponseOK);
    if (okButtonPressed) {
        NSString *selectedFile = [[save URL] path];
        
        NSMutableString *outputResults = [[NSMutableString alloc] init];
        NSString *projectPath = [self.pathTextField stringValue];
        [outputResults appendFormat:@"Unused Resources In Project: \n%@\n\n", projectPath];
        
        for (ResourceFileInfo *info in self.unusedResults) {
            [outputResults appendFormat:@"%@\n", info.path];
        }
        
        // Output
        NSError *writeError = nil;
        [outputResults writeToFile:selectedFile atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
        
        // Check write result
        if (writeError == nil) {
            [self showAlertWithStyle:NSInformationalAlertStyle title:@"Export Complete" subtitle:[NSString stringWithFormat:@"Export Complete: %@", selectedFile]];
        } else {
            [self showAlertWithStyle:NSCriticalAlertStyle title:@"Export Error" subtitle:[NSString stringWithFormat:@"Export Error: %@", writeError]];
        }
    }
}

- (IBAction)onDeleteButtonClicked:(id)sender {
    if (self.resultsTableView.numberOfSelectedRows > 0) {
        NSArray *results = [self.unusedResults copy];
        NSIndexSet *selectedIndexSet = self.resultsTableView.selectedRowIndexes;
        NSUInteger index = [selectedIndexSet firstIndex];
        NSMutableArray *toRemoveReferenceFiles = [NSMutableArray array];
        while (index != NSNotFound) {
            if (index < results.count) {
                ResourceFileInfo *info = [results objectAtIndex:index];
                [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:info.path] error:nil];
                [toRemoveReferenceFiles addObject:info.name];
            }
            index = [selectedIndexSet indexGreaterThanIndex:index];
        }
        [self removeReferenceFileLines:toRemoveReferenceFiles];
        [self.unusedResults removeObjectsAtIndexes:selectedIndexSet];
        [self.resultsTableView reloadData];
        [self updateUnusedResultsCount];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Please select first."];
        [alert runModal];
    }
}
/*
 //还需要删除 /Users/yxj/Library/Developer/Xcode/DerivedData/OneTravel-akukjnbplxnurwddecvkprozvjub/ 不然编译会报错 或者可以
 //同时删除 xcode 中 reference 比较方便
 // /Users/yxj/Desktop/OneCarpoolDev/DeleteDuplicatedImage/Pods/Pods.xcodeproj/project.pbxproj 删除这个文件中引用了要删除文件的行
 //1. 取到当前所在目录
 //2. 拼接 /Pods/Pods.xcodeproj/project.pbxproj
 //3. 读取 pbxproj 文件内容，去掉待删文件相关行
 //4. 写回 pbxproj 文件
 */
- (void)removeReferenceFileLines:(NSMutableArray *)toRemoveReferenceFiles {
    NSString *pbxprojFileLocation = self.pbfileLocation;
    NSString *content = [NSString stringWithContentsOfFile:pbxprojFileLocation encoding:NSUTF8StringEncoding error:nil];
    if (!content) {
        return;
    }
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    NSMutableArray *resultM = [NSMutableArray array];
    for (NSString *line in lines) {
        if (![self containReferedFile:toRemoveReferenceFiles lineStr:line]) {
            [resultM addObject:line];
        }
    }
    //写回 pb 文件
    NSMutableString *outputPbfile = [[NSMutableString alloc] init];
    NSString *outputPath = self.pbfileLocation;
    //最后一行不要 append \n
    [resultM enumerateObjectsUsingBlock:^(NSString *line, NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx == [resultM count]-1) {
            [outputPbfile appendFormat:@"%@", line];
        } else {
            [outputPbfile appendFormat:@"%@\n", line];
        }
    }];
    NSError *writeError = nil;
    [outputPbfile writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    
    // Check write result
    if (writeError == nil) {
        [self showAlertWithStyle:NSInformationalAlertStyle title:@"Delete Complete" subtitle:[NSString stringWithFormat:@"Delete Complete: %@", outputPath]];
    } else {
        [self showAlertWithStyle:NSCriticalAlertStyle title:@"Delete Error" subtitle:[NSString stringWithFormat:@"Delete Error: %@", writeError]];
    }
}

- (BOOL)containReferedFile:(NSMutableArray *)filenames lineStr:(NSString *)line{
    for (NSString *filename in filenames) {
        if ([line containsString:filename]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - NSNotification

- (void)onResourceFileQueryDone:(NSNotification *)notification {
    self.isFileDone = YES;
    [self searchUnusedResourcesIfNeeded];
    //统计总数
    if(self.unusedResults.count > 0){
        uint64_t countSize = 0;
        for(ResourceFileInfo *info in self.unusedResults){
            countSize += info.fileSize;
        }
        self.statusLabel.stringValue = [self.statusLabel.stringValue stringByAppendingString:[NSString stringWithFormat:@",total size is:%.2f(KB)", countSize / 1024.0]];
    }
}

- (void)onResourceStringQueryDone:(NSNotification *)notification {
    self.isStringDone = YES;
    [self searchUnusedResourcesIfNeeded];
    //统计总数
    if(self.unusedResults.count > 0){
        uint64_t countSize = 0;
        for(ResourceFileInfo *info in self.unusedResults){
            countSize += info.fileSize;
        }
        self.statusLabel.stringValue = [self.statusLabel.stringValue stringByAppendingString:[NSString stringWithFormat:@",total size is:%.2f(KB)", countSize / 1024.0]];
    }
}

#pragma mark - <NSTableViewDelegate>

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [self.unusedResults count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex {
    // Get the unused image
    ResourceFileInfo *info = [self.unusedResults objectAtIndex:rowIndex];
    
    // Check the column
    NSString *columnIdentifier = [tableColumn identifier];
    if ([columnIdentifier isEqualToString:kTableColumnImageIcon]) {
        return [info image];
    } else if ([columnIdentifier isEqualToString:kTableColumnImageShortName]) {
        return info.name;
    } else if ([columnIdentifier isEqualToString:kTableColumnFileSize]) {
        return [NSString stringWithFormat:@"%.2f", info.fileSize / 1024.0];
    }
    
    return info.path;
}

- (void)tableViewDoubleClicked {
    // Open finder
    ResourceFileInfo *info = [self.unusedResults objectAtIndex:[self.resultsTableView clickedRow]];
    [[NSWorkspace sharedWorkspace] selectFile:info.path inFileViewerRootedAtPath:@""];
}

- (void)tableView:(NSTableView *)tableView mouseDownInHeaderOfTableColumn:(NSTableColumn *)tableColumn{
    if([tableColumn.identifier isEqualToString:@"FileSize"]){
        //点击FileSize头部
        _fileSizeDesc = !_fileSizeDesc;
        if(_fileSizeDesc){
            //降序
            NSArray *array = [self.unusedResults sortedArrayUsingComparator:^NSComparisonResult(ResourceFileInfo *obj1, ResourceFileInfo *obj2) {
                return obj1.fileSize < obj2.fileSize;
            }];
            self.unusedResults = [array mutableCopy];
            [self.resultsTableView reloadData];
        }else{
            NSArray *array = [self.unusedResults sortedArrayUsingComparator:^NSComparisonResult(ResourceFileInfo *obj1, ResourceFileInfo *obj2) {
                return obj1.fileSize > obj2.fileSize;
            }];
            self.unusedResults = [array mutableCopy];
            [self.resultsTableView reloadData];
        }
    }else if([tableColumn.identifier isEqualToString:@"ImageShortName"]){
        NSArray *array = [self.unusedResults sortedArrayUsingComparator:^NSComparisonResult(ResourceFileInfo *obj1, ResourceFileInfo *obj2) {
            return [obj1.name compare:obj2.name];
        }];
        self.unusedResults = [array mutableCopy];
        [self.resultsTableView reloadData];
    }
}

#pragma mark - Private

- (void)showAlertWithStyle:(NSAlertStyle)style title:(NSString *)title subtitle:(NSString *)subtitle {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = style;
    [alert setMessageText:title];
    [alert setInformativeText:subtitle];
    [alert runModal];
}

- (NSArray *)resourceSuffixs {
    NSString *suffixs = self.resSuffixTextField.stringValue;
    if (!suffixs.length) {
        suffixs = kDefaultResourceSuffixs;
    }
    suffixs = [suffixs lowercaseString];
    suffixs = [suffixs stringByReplacingOccurrencesOfString:@" " withString:@""];
    suffixs = [suffixs stringByReplacingOccurrencesOfString:@"." withString:@""];
    return [suffixs componentsSeparatedByString:@";"];
}

- (NSArray *)includeFileSuffixs {
    NSMutableArray *suffixs = [NSMutableArray array];
    
    if ([self.headerCheckbox state]) {
        [suffixs addObject:@"h"];
    }
    if ([self.mCheckbox state]) {
        [suffixs addObject:@"m"];
    }
    if ([self.mmCheckbox state]) {
        [suffixs addObject:@"mm"];
    }
    if ([self.cppCheckbox state]) {
        [suffixs addObject:@"cpp"];
    }
    if ([self.swiftCheckbox state]) {
        [suffixs addObject:@"swift"];
    }
    if ([self.htmlCheckbox state]) {
        [suffixs addObject:@"html"];
    }
    if ([self.jsonCheckbox state]) {
        [suffixs addObject:@"json"];
    }
    if ([self.plistCheckbox state]) {
        [suffixs addObject:@"plist"];
    }
    if ([self.cssCheckbox state]) {
        [suffixs addObject:@"css"];
    }
    if ([self.xibCheckbox state]) {
        [suffixs addObject:@"xib"];
    }
    if ([self.sbCheckbox state]) {
        [suffixs addObject:@"storyboard"];
    }
    
    if (suffixs.count == 0) {
        [suffixs addObject:@"m"];
    }
    return suffixs;
}

- (void)setUIEnabled:(BOOL)state {
    // Individual
    if (state) {
        [self updateUnusedResultsCount];
    } else {
        [self.processIndicator startAnimation:self];
        self.statusLabel.stringValue = @"Searching...";
    }
    
    // Button groups
    
    [_browseButton setEnabled:state];
    [_resSuffixTextField setEnabled:state];
    [_pathTextField setEnabled:state];
    [_excludeFolderTextField setEnabled:state];
    
    [_mCheckbox setEnabled:state];
    [_xibCheckbox setEnabled:state];
    [_sbCheckbox setEnabled:state];
    [_cppCheckbox setEnabled:state];
    [_mmCheckbox setEnabled:state];
    [_headerCheckbox setEnabled:state];
    [_htmlCheckbox setEnabled:state];
    [_jsonCheckbox setEnabled:state];
    [_plistCheckbox setEnabled:state];
    [_cssCheckbox setEnabled:state];
    [_swiftCheckbox setEnabled:state];
    
    [_ignoreSimilarCheckbox setEnabled:state];

    [_searchButton setEnabled:state];
    [_exportButton setHidden:!state];
    [_deleteButton setEnabled:state];
    [_deleteButton setHidden:!state];
    [_processIndicator setHidden:state];
}

- (void)updateUnusedResultsCount {
    [self.processIndicator stopAnimation:self];
    NSUInteger count = self.unusedResults.count;
    NSString *tips = count > 2 ? @"resources" : @"resource";
    NSTimeInterval time = [[NSDate date] timeIntervalSinceDate:self.startTime];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"%ld unsued %@. time %.2fs", (long)count, tips, time];
}

- (void)searchUnusedResourcesIfNeeded {
    NSString *tips = @"Searching...";
    if (self.isFileDone) {
        tips = [tips stringByAppendingString:[NSString stringWithFormat:@"%ld resources", [[ResourceFileSearcher sharedObject].resNameInfoDict allKeys].count]];
    }
    if (self.isStringDone) {
        tips = [tips stringByAppendingString:[NSString stringWithFormat:@"%ld strings", [ResourceStringSearcher sharedObject].resStringSet .count]];
    }
    self.statusLabel.stringValue = tips;
    
    if (self.isFileDone && self.isStringDone) {
        NSArray *resNames = [[[ResourceFileSearcher sharedObject].resNameInfoDict allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *name in resNames) { //遍历文件名列表
            if (![[ResourceStringSearcher sharedObject] containsResourceName:name]) { //代码里面出现过的字符串集合不包含这个文件名，需要添加到未使用资源数组中
                if (!self.ignoreSimilarCheckbox.state || ![[ResourceStringSearcher sharedObject] containsSimilarResourceName:name]) {//未勾选忽略相似文件或者不含有相似文件
                    [self.unusedResults addObject:[ResourceFileSearcher sharedObject].resNameInfoDict[name]];
                }
                //上面这个 if 等价于下面这个复杂点的
//                //进一步检查，如果开启了想忽略相似文件，还需做进一步检查
//                if (self.ignoreSimilarCheckbox.state){
//                    if (![[ResourceStringSearcher sharedObject] containsSimilarResourceName:name]) { //检查到不包含相似文件名，可以添加
//                        [self.unusedResults addObject:[ResourceFileSearcher sharedObject].resNameInfoDict[name]];
//                    }
//                } else { // 如果没有开启忽略相似文件，直接 add
//                    [self.unusedResults addObject:[ResourceFileSearcher sharedObject].resNameInfoDict[name]];
//                }
            }
        }
        
        [self.resultsTableView reloadData];
        
        [self setUIEnabled:YES];
    }
}
// /Users/yxj/Desktop/OneCarpoolDev/DeleteDuplicatedImage/Pods/Pods.xcodeproj/project.pbxproj 删除这个文件中引用了要删除文件的行
//1. 取到当前所在目录
//2. 拼接 /Pods/Pods.xcodeproj/project.pbxproj
- (NSString *)pbfileLocation {
    if (!_pbfileLocation) {
        _pbfileLocation = [[NSString alloc] init];
        _pbfileLocation = [[self.codePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"/Pods/Pods.xcodeproj/project.pbxproj"];
    }
    return _pbfileLocation;
}

- (BOOL)usingResWithDiffrentDirName:(ResourceFileInfo *)resInfo
{
    if (!resInfo.isDir) {
        return NO;
    }
    NSDirectoryEnumerator *fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:resInfo.path];
    for (NSString *fileName in fileEnumerator) {
        if (![StringUtils isImageTypeWithName:fileName]) {
            continue;
        }
        
        NSString *fileNameWithoutExt = [StringUtils stringByRemoveResourceSuffix:fileName];
        
        if ([fileNameWithoutExt isEqualToString:resInfo.name]) {
            return NO;
        }
        
        if ([[ResourceStringSearcher sharedObject] containsResourceName:fileNameWithoutExt]) {
            return YES;
        }
    }
    return NO;
}

@end
