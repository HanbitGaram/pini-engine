/****************************************************************************
 Copyright (c) 2014-2017 Chukong Technologies Inc.
 
 http://www.cocos2d-x.org
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 ****************************************************************************/

#include "platform/CCPlatformConfig.h"

// Webview not available on tvOS
#if (CC_TARGET_PLATFORM == CC_PLATFORM_IOS) && !defined(CC_TARGET_OS_TVOS)

#import <WebKit/WebKit.h>

#include "ui/UIWebViewImpl-ios.h"
#include "renderer/CCRenderer.h"
#include "base/CCDirector.h"
#include "platform/CCGLView.h"
#include "platform/ios/CCEAGLView-ios.h"
#include "platform/CCFileUtils.h"
#include "ui/UIWebView.h"

static std::string getFixedBaseUrl(const std::string& baseUrl)
{
    std::string fixedBaseUrl;
    if (baseUrl.empty() || baseUrl.at(0) != '/') {
        fixedBaseUrl = [[[NSBundle mainBundle] resourcePath] UTF8String];
        fixedBaseUrl += "/";
        fixedBaseUrl += baseUrl;
    }
    else {
        fixedBaseUrl = baseUrl;
    }
    
    size_t pos = 0;
    while ((pos = fixedBaseUrl.find(" ")) != std::string::npos) {
        fixedBaseUrl.replace(pos, 1, "%20");
    }
    
    if (fixedBaseUrl.at(fixedBaseUrl.length() - 1) != '/') {
        fixedBaseUrl += "/";
    }
    
    return fixedBaseUrl;
}

@interface WKWebViewWrapper : NSObject
@property (nonatomic) std::function<bool(std::string url)> shouldStartLoading;
@property (nonatomic) std::function<void(std::string url)> didFinishLoading;
@property (nonatomic) std::function<void(std::string url)> didFailLoading;
@property (nonatomic) std::function<void(std::string url)> onJsCallback;

@property(nonatomic, readonly, getter=canGoBack) BOOL canGoBack;
@property(nonatomic, readonly, getter=canGoForward) BOOL canGoForward;

+ (instancetype)webViewWrapper;

- (void)setVisible:(bool)visible;

- (void)setBounces:(bool)bounces;

- (void)setFrameWithX:(float)x y:(float)y width:(float)width height:(float)height;

- (void)setJavascriptInterfaceScheme:(const std::string &)scheme;

- (void)loadData:(const std::string &)data MIMEType:(const std::string &)MIMEType textEncodingName:(const std::string &)encodingName baseURL:(const std::string &)baseURL;

- (void)loadHTMLString:(const std::string &)string baseURL:(const std::string &)baseURL;

- (void)loadUrl:(const std::string &)urlString cleanCachedData:(BOOL) needCleanCachedData;

- (void)loadFile:(const std::string &)filePath;

- (void)stopLoading;

- (void)reload;

- (void)evaluateJS:(const std::string &)js;

- (void)goBack;

- (void)goForward;

- (void)setScalesPageToFit:(const bool)scalesPageToFit;
@end


/* [UIWebView -> WKWebView 이식]
   UIWebView 는 iOS 12 에서 deprecated 되었고, 이걸 포함한 바이너리는 앱스토어가 거부한다
   (ITMS-90809). SDK 에는 아직 선언이 남아 있어 빌드는 되지만 제출이 막힌다.
   클래스 이름(WKWebViewWrapper)은 이 파일 밖(UIWebViewImpl-ios.h)에서도 쓰이므로 그대로 두고,
   내부 구현만 WKWebView 로 바꿨다. */
@interface WKWebViewWrapper () <WKNavigationDelegate>
@property(nonatomic, retain) WKWebView *wkWebView;
@property(nonatomic, copy) NSString *jsScheme;
@property(nonatomic, assign) BOOL scalesPageToFitEnabled;
@end

@implementation WKWebViewWrapper {
    
}

+ (instancetype)webViewWrapper {
    return [[[self alloc] init] autorelease];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.wkWebView = nil;
        self.shouldStartLoading = nullptr;
        self.didFinishLoading = nullptr;
        self.didFailLoading = nullptr;
        self.scalesPageToFitEnabled = NO;
    }
    return self;
}

- (void)dealloc {
    self.wkWebView.navigationDelegate = nil;
    [self.wkWebView removeFromSuperview];
    self.wkWebView = nil;
    self.jsScheme = nil;
    [super dealloc];
}

- (void)setupWebView {
    if (!self.wkWebView) {
        WKWebViewConfiguration *config = [[[WKWebViewConfiguration alloc] init] autorelease];
        // UIWebView 는 기본으로 인라인 재생이었다. WKWebView 는 명시해 줘야 한다.
        config.allowsInlineMediaPlayback = YES;
        self.wkWebView = [[[WKWebView alloc] initWithFrame:CGRectZero configuration:config] autorelease];
        self.wkWebView.navigationDelegate = self;
    }
    if (!self.wkWebView.superview) {
        auto view = cocos2d::Director::getInstance()->getOpenGLView();
        auto eaglview = (CCEAGLView *) view->getEAGLView();
        [eaglview addSubview:self.wkWebView];
    }
}

- (void)setVisible:(bool)visible {
    self.wkWebView.hidden = !visible;
}

- (void)setBounces:(bool)bounces {
  self.wkWebView.scrollView.bounces = bounces;
}

- (void)setFrameWithX:(float)x y:(float)y width:(float)width height:(float)height {
    if (!self.wkWebView) {[self setupWebView];}
    CGRect newFrame = CGRectMake(x, y, width, height);
    if (!CGRectEqualToRect(self.wkWebView.frame, newFrame)) {
        self.wkWebView.frame = CGRectMake(x, y, width, height);
    }
}

- (void)setJavascriptInterfaceScheme:(const std::string &)scheme {
    self.jsScheme = @(scheme.c_str());
}

- (void)loadData:(const std::string &)data MIMEType:(const std::string &)MIMEType textEncodingName:(const std::string &)encodingName baseURL:(const std::string &)baseURL {
    if (!self.wkWebView) {[self setupWebView];}
    // WKWebView 는 인자 이름이 characterEncodingName: 이다 (UIWebView 는 textEncodingName:).
    [self.wkWebView loadData:[NSData dataWithBytes:data.c_str() length:data.length()]
                    MIMEType:@(MIMEType.c_str())
       characterEncodingName:@(encodingName.c_str())
                     baseURL:[NSURL URLWithString:@(getFixedBaseUrl(baseURL).c_str())]];
}

- (void)loadHTMLString:(const std::string &)string baseURL:(const std::string &)baseURL {
    if (!self.wkWebView) {[self setupWebView];}
    [self.wkWebView loadHTMLString:@(string.c_str()) baseURL:[NSURL URLWithString:@(getFixedBaseUrl(baseURL).c_str())]];
}

- (void)loadUrl:(const std::string &)urlString cleanCachedData:(BOOL) needCleanCachedData {
    if (!self.wkWebView) {[self setupWebView];}
    NSURL *url = [NSURL URLWithString:@(urlString.c_str())];

    NSURLRequest *request = nil;
    if (needCleanCachedData)
        request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    else
        request = [NSURLRequest requestWithURL:url];

    [self.wkWebView loadRequest:request];
}



- (void)loadFile:(const std::string &)filePath {
    if (!self.wkWebView) {[self setupWebView];}
    NSURL *url = [NSURL fileURLWithPath:@(filePath.c_str())];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.wkWebView loadRequest:request];
}

- (void)stopLoading {
    [self.wkWebView stopLoading];
}

- (void)reload {
    [self.wkWebView reload];
}

- (BOOL)canGoForward {
    return self.wkWebView.canGoForward;
}

- (BOOL)canGoBack {
    return self.wkWebView.canGoBack;
}

- (void)goBack {
    [self.wkWebView goBack];
}

- (void)goForward {
    [self.wkWebView goForward];
}

- (void)evaluateJS:(const std::string &)js {
    if (!self.wkWebView) {[self setupWebView];}
    // UIWebView 의 stringByEvaluatingJavaScriptFromString 은 동기였고 결과 문자열을 돌려줬다.
    // WKWebView 는 비동기만 제공한다. cocos 의 WebView::evaluateJS() 는 반환값이 void 라
    // 호출부에 영향은 없다.
    [self.wkWebView evaluateJavaScript:@(js.c_str()) completionHandler:nil];
}

- (void)setScalesPageToFit:(const bool)scalesPageToFit {
    if (!self.wkWebView) {[self setupWebView];}
    // WKWebView 에는 scalesPageToFit 프로퍼티가 없다. 페이지 로드가 끝난 뒤
    // viewport meta 를 주입해 같은 효과를 낸다 (아래 didFinishNavigation 참조).
    self.scalesPageToFitEnabled = scalesPageToFit ? YES : NO;
}

- (void)applyScalesPageToFit {
    if (!self.scalesPageToFitEnabled) { return; }
    NSString *js =
        @"var m=document.querySelector('meta[name=viewport]');"
        @"if(!m){m=document.createElement('meta');m.name='viewport';"
        @"document.getElementsByTagName('head')[0].appendChild(m);}"
        @"m.content='width=device-width, initial-scale=1.0, user-scalable=yes';";
    [self.wkWebView evaluateJavaScript:js completionHandler:nil];
}

#pragma mark - WKNavigationDelegate
/* UIWebViewDelegate 의 세 콜백을 WKNavigationDelegate 로 옮긴 것.
   - shouldStartLoadWithRequest  -> decidePolicyForNavigationAction (BOOL 반환 대신 decisionHandler)
   - webViewDidFinishLoad        -> didFinishNavigation
   - didFailLoadWithError        -> didFailNavigation / didFailProvisionalNavigation
     (WKWebView 는 서버 응답 전 실패를 provisional 쪽으로 따로 알려 준다. UIWebView 는 하나였다.) */
- (void)webView:(WKWebView *)webView
        decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                        decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *requestURL = navigationAction.request.URL;
    NSString *url = [requestURL absoluteString];

    if (self.jsScheme && [[requestURL scheme] isEqualToString:self.jsScheme]) {
        if (self.onJsCallback && url) {
            self.onJsCallback([url UTF8String]);
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (self.shouldStartLoading && url) {
        bool allow = self.shouldStartLoading([url UTF8String]);
        decisionHandler(allow ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self applyScalesPageToFit];
    if (self.didFinishLoading) {
        NSString *url = [webView.URL absoluteString];
        if (url) {
            self.didFinishLoading([url UTF8String]);
        }
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self reportFailure:error];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self reportFailure:error];
}

- (void)reportFailure:(NSError *)error {
    if (self.didFailLoading) {
        NSString *url = error.userInfo[NSURLErrorFailingURLStringErrorKey];
        if (url) {
            self.didFailLoading([url UTF8String]);
        }
    }
}

@end



namespace cocos2d {
namespace experimental {
    namespace ui{

WebViewImpl::WebViewImpl(WebView *webView)
        : _wkWebViewWrapper([WKWebViewWrapper webViewWrapper]),
        _webView(webView) {
    [_wkWebViewWrapper retain];
            
    _wkWebViewWrapper.shouldStartLoading = [this](std::string url) {
        if (this->_webView->_onShouldStartLoading) {
            return this->_webView->_onShouldStartLoading(this->_webView, url);
        }
        return true;
    };
    _wkWebViewWrapper.didFinishLoading = [this](std::string url) {
        if (this->_webView->_onDidFinishLoading) {
            this->_webView->_onDidFinishLoading(this->_webView, url);
        }
    };
    _wkWebViewWrapper.didFailLoading = [this](std::string url) {
        if (this->_webView->_onDidFailLoading) {
            this->_webView->_onDidFailLoading(this->_webView, url);
        }
    };
    _wkWebViewWrapper.onJsCallback = [this](std::string url) {
        if (this->_webView->_onJSCallback) {
            this->_webView->_onJSCallback(this->_webView, url);
        }
    };
}

WebViewImpl::~WebViewImpl(){
    [_wkWebViewWrapper release];
    _wkWebViewWrapper = nullptr;
}

void WebViewImpl::setJavascriptInterfaceScheme(const std::string &scheme) {
    [_wkWebViewWrapper setJavascriptInterfaceScheme:scheme];
}

void WebViewImpl::loadData(const Data &data,
                           const std::string &MIMEType,
                           const std::string &encoding,
                           const std::string &baseURL) {
    
    std::string dataString(reinterpret_cast<char *>(data.getBytes()), static_cast<unsigned int>(data.getSize()));
    [_wkWebViewWrapper loadData:dataString MIMEType:MIMEType textEncodingName:encoding baseURL:baseURL];
}

void WebViewImpl::loadHTMLString(const std::string &string, const std::string &baseURL) {
    [_wkWebViewWrapper loadHTMLString:string baseURL:baseURL];
}

void WebViewImpl::loadURL(const std::string &url) {
    this->loadURL(url, false);
}

void WebViewImpl::loadURL(const std::string &url, bool cleanCachedData) {
    [_wkWebViewWrapper loadUrl:url cleanCachedData:cleanCachedData];
}

void WebViewImpl::loadFile(const std::string &fileName) {
    auto fullPath = cocos2d::FileUtils::getInstance()->fullPathForFilename(fileName);
    [_wkWebViewWrapper loadFile:fullPath];
}

void WebViewImpl::stopLoading() {
    [_wkWebViewWrapper stopLoading];
}

void WebViewImpl::reload() {
    [_wkWebViewWrapper reload];
}

bool WebViewImpl::canGoBack() {
    return _wkWebViewWrapper.canGoBack;
}

bool WebViewImpl::canGoForward() {
    return _wkWebViewWrapper.canGoForward;
}

void WebViewImpl::goBack() {
    [_wkWebViewWrapper goBack];
}

void WebViewImpl::goForward() {
    [_wkWebViewWrapper goForward];
}

void WebViewImpl::evaluateJS(const std::string &js) {
    [_wkWebViewWrapper evaluateJS:js];
}

void WebViewImpl::setBounces(bool bounces) {
    [_wkWebViewWrapper setBounces:bounces];
}

void WebViewImpl::setScalesPageToFit(const bool scalesPageToFit) {
    [_wkWebViewWrapper setScalesPageToFit:scalesPageToFit];
}

void WebViewImpl::draw(cocos2d::Renderer *renderer, cocos2d::Mat4 const &transform, uint32_t flags) {
    if (flags & cocos2d::Node::FLAGS_TRANSFORM_DIRTY) {
        
        auto director = cocos2d::Director::getInstance();
        auto glView = director->getOpenGLView();
        auto frameSize = glView->getFrameSize();
        
        auto scaleFactor = [static_cast<CCEAGLView *>(glView->getEAGLView()) contentScaleFactor];

        auto winSize = director->getWinSize();

        auto leftBottom = this->_webView->convertToWorldSpace(cocos2d::Vec2::ZERO);
        auto rightTop = this->_webView->convertToWorldSpace(cocos2d::Vec2(this->_webView->getContentSize().width, this->_webView->getContentSize().height));

        auto x = (frameSize.width / 2 + (leftBottom.x - winSize.width / 2) * glView->getScaleX()) / scaleFactor;
        auto y = (frameSize.height / 2 - (rightTop.y - winSize.height / 2) * glView->getScaleY()) / scaleFactor;
        auto width = (rightTop.x - leftBottom.x) * glView->getScaleX() / scaleFactor;
        auto height = (rightTop.y - leftBottom.y) * glView->getScaleY() / scaleFactor;

        [_wkWebViewWrapper setFrameWithX:x
                                      y:y
                                  width:width
                                 height:height];
    }
}

void WebViewImpl::setVisible(bool visible){
    [_wkWebViewWrapper setVisible:visible];
}
        
    } // namespace ui
} // namespace experimental
} //namespace cocos2d

#endif // CC_TARGET_PLATFORM == CC_PLATFORM_IOS
