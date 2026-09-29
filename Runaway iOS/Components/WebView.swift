//
//  WebView.swift
//  Runaway iOS
//
//  Created by Jack Rudelic on 6/28/25.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    let onWebViewCreated: (WKWebView) -> Void
    let onError: ((String) -> Void)?
    let onSuccess: (() -> Void)?
    
    init(url: URL, isLoading: Binding<Bool>, canGoBack: Binding<Bool>, canGoForward: Binding<Bool>, onWebViewCreated: @escaping (WKWebView) -> Void, onError: ((String) -> Void)? = nil, onSuccess: (() -> Void)? = nil) {
        self.url = url
        self._isLoading = isLoading
        self._canGoBack = canGoBack
        self._canGoForward = canGoForward
        self.onWebViewCreated = onWebViewCreated
        self.onError = onError
        self.onSuccess = onSuccess
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // Configure web view for better reading experience
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Load the initial URL
        let request = URLRequest(url: url)
        webView.load(request)
        
        // Mark that we've loaded the initial URL
        context.coordinator.hasLoadedInitialURL = true
        context.coordinator.initialURL = url
        
        // Call the callback with the web view
        onWebViewCreated(webView)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if the URL has actually changed and we haven't loaded it yet
        if !context.coordinator.hasLoadedInitialURL || context.coordinator.initialURL != url {
            let request = URLRequest(url: url)
            webView.load(request)
            context.coordinator.hasLoadedInitialURL = true
            context.coordinator.initialURL = url
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        var hasLoadedInitialURL = false
        var initialURL: URL?
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            parent.onSuccess?()
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            let errorMessage = "Navigation failed: \(error.localizedDescription)"
            #if DEBUG
            print("WebView navigation failed: \(error.localizedDescription)")
            #endif
            parent.onError?(errorMessage)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            let errorMessage = "Failed to load: \(error.localizedDescription)"
            #if DEBUG
            print("WebView provisional navigation failed: \(error.localizedDescription)")
            #endif
            parent.onError?(errorMessage)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation for now, but log it
            #if DEBUG
            print("WebView navigation to: \(navigationAction.request.url?.absoluteString ?? "unknown")")
            #endif
            decisionHandler(.allow)
        }
    }
}

struct ArticleWebView: View {
    let article: ResearchArticle
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webView: WKWebView?
    @State private var hasError = false
    @State private var errorMessage = ""
    @State private var loadingTimeout: Timer?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Loading indicator
                if isLoading && !hasError {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading article...")
                            .font(.caption)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                }
                
                // Error state
                if hasError {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        
                        Text("Unable to load article")
                            .font(.headline)
                        
                        Text(errorMessage.isEmpty ? "The article failed to load. Please check your internet connection." : errorMessage)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        HStack(spacing: 12) {
                            Button("Retry") {
                                retryLoading()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.Colors.pine)
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.vertical, AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.strideLime)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                            
                            Button("Open in Safari") {
                                openInSafari()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let url = URL(string: article.url) {
                    // Web view
                    WebView(
                        url: url,
                        isLoading: $isLoading,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        onWebViewCreated: { webView in
                            self.webView = webView
                            setupLoadingTimeout()
                        },
                        onError: { error in
                            cancelTimeout()
                            hasError = true
                            errorMessage = error
                        },
                        onSuccess: {
                            cancelTimeout()
                        }
                    )
                } else {
                    // Fallback for invalid URLs
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        
                        Text("Invalid URL")
                            .font(.headline)
                        
                        Text("The article URL appears to be invalid: \(article.url)")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Dismiss") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(article.source)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onDisappear {
                cancelTimeout()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.accent)
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!canGoBack)
                        .foregroundColor(AppTheme.Colors.accent)

                        Button(action: goForward) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!canGoForward)
                        .foregroundColor(AppTheme.Colors.accent)

                        Button(action: openInSafari) {
                            Image(systemName: "safari")
                        }
                        .foregroundColor(AppTheme.Colors.accent)
                    }
                }
            }
        }
    }
    
    private func goBack() {
        webView?.goBack()
    }
    
    private func goForward() {
        webView?.goForward()
    }
    
    private func openInSafari() {
        if let url = URL(string: article.url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func retryLoading() {
        hasError = false
        errorMessage = ""
        isLoading = true
        
        if let url = URL(string: article.url) {
            let request = URLRequest(url: url)
            webView?.load(request)
            setupLoadingTimeout()
        }
    }
    
    private func setupLoadingTimeout() {
        // Cancel any existing timeout
        loadingTimeout?.invalidate()
        
        // Set a 30-second timeout for loading
        loadingTimeout = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
            if isLoading {
                isLoading = false
                hasError = true
                errorMessage = "The article took too long to load. Please check your internet connection or try again."
            }
        }
    }
    
    private func cancelTimeout() {
        loadingTimeout?.invalidate()
        loadingTimeout = nil
    }
}

#Preview {
    ArticleWebView(
        article: ResearchArticle(
            title: "Sample Article",
            summary: "This is a sample article",
            url: "https://www.runnersworld.com",
            publishedDate: Date(),
            source: "Runner's World",
            category: .general
        )
    )
}