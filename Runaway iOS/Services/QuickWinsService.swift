//
//  QuickWinsService.swift
//  Runaway iOS
//
//  Service for fetching AI-powered Quick Wins insights
//  Uses Supabase Edge Functions for analysis
//

import Foundation

class QuickWinsService: ObservableObject {
    @Published var isLoading = false
    @Published var error: QuickWinsError?

    // MARK: - Fetch Comprehensive Analysis

    /// Fetch comprehensive analysis including weather, VO2 max, and training load
    func fetchComprehensiveAnalysis() async throws -> QuickWinsResponse {
        throw QuickWinsError.networkError(
            LocalIntelligenceBoundaryError.retiredCloudAnalysis
        )
    }

    // MARK: - Helper Methods with Loading State

    /// Fetch with loading state management
    @MainActor
    func fetchWithLoading<T>(
        operation: () async throws -> T
    ) async -> Result<T, QuickWinsError> {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let result = try await operation()
            return .success(result)
        } catch let quickWinsError as QuickWinsError {
            error = quickWinsError
            return .failure(quickWinsError)
        } catch {
            let wrappedError = QuickWinsError.networkError(error)
            self.error = wrappedError
            return .failure(wrappedError)
        }
    }
}
