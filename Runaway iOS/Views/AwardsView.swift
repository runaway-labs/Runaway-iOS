//
//  AwardsView.swift
//  Runaway iOS
//
//  Awards and achievements display page
//

import SwiftUI

// MARK: - Full Awards View

struct AwardsView: View {
    @Environment(DataManager.self) private var dataManager
    @ObservedObject private var awardsService = AwardsService.shared
    @ObservedObject private var breakthroughService = BreakthroughService.shared
    @State private var awardsData: [(award: AwardDefinition, isEarned: Bool, progress: Double)] = []
    @State private var selectedCategory: AwardCategory? = nil
    @State private var selectedAward: AwardDefinition? = nil
    @State private var showingDetail = false

    var body: some View {
        ZStack {
            (AppTheme.Colors.adaptiveBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // Breakthrough Milestones
                    if !breakthroughService.milestones.isEmpty {
                        BreakthroughsSection(milestones: breakthroughService.milestones)
                    }

                    // Summary Header
                    AwardsSummaryHeader(
                        earnedCount: awardsData.filter { $0.isEarned }.count,
                        totalCount: awardsData.count
                    )

                    // Category Filter
                    CategoryFilterBar(selectedCategory: $selectedCategory)

                    // Awards Grid
                    if awardsService.isLoading {
                        VStack(spacing: AppTheme.Spacing.md) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading stats...")
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                        }
                        .padding(.top, 50)
                    } else {
                        // Stats summary
                        if let stats = awardsService.lifetimeStats {
                            Text("\(stats.totalRuns) runs • \(String(format: "%.0f", stats.totalDistanceMiles)) miles lifetime")
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                        }

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: AppTheme.Spacing.md) {
                            ForEach(filteredAwards, id: \.award.id) { item in
                                Button(action: {
                                    // Only allow tap if stats are loaded
                                    guard awardsService.lifetimeStats != nil else { return }
                                    selectedAward = item.award
                                    showingDetail = true
                                }) {
                                    AwardBadgeView(
                                        award: item.award,
                                        isEarned: item.isEarned,
                                        progress: item.progress,
                                        showProgress: true
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(awardsService.lifetimeStats == nil)
                                .opacity(awardsService.lifetimeStats == nil ? 0.6 : 1.0)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.md)
            }
        }
        .adaptiveSurfaceTint()
        .navigationTitle("Awards")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadAwards()
        }
        .sheet(isPresented: $showingDetail) {
            if let award = selectedAward {
                AwardDetailSheetFromStats(award: award)
            }
        }
        .darkSurfaceTint()
    }

    private var filteredAwards: [(award: AwardDefinition, isEarned: Bool, progress: Double)] {
        if let category = selectedCategory {
            return awardsData.filter { $0.award.category == category }
        }
        return awardsData
    }

    private func loadAwards() async {
        let athleteId = dataManager.athlete?.id ?? 0

        await breakthroughService.fetchMilestones(for: athleteId)

        // Load lifetime stats with a single DB call (efficient!)
        await awardsService.loadLifetimeStats(for: athleteId)

        // Get awards using the cached stats
        awardsData = awardsService.getAllAwardsWithStatusFromStats()

        // Sort: earned first, then by tier (platinum > gold > silver > bronze)
        awardsData.sort { a, b in
            if a.isEarned != b.isEarned {
                return a.isEarned
            }
            return tierOrder(a.award.tier) > tierOrder(b.award.tier)
        }
    }

    private func tierOrder(_ tier: AwardTier) -> Int {
        switch tier {
        case .platinum: return 4
        case .gold: return 3
        case .silver: return 2
        case .bronze: return 1
        }
    }
}

// MARK: - Breakthroughs Section

struct BreakthroughsSection: View {
    let milestones: [BreakthroughMilestone]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Breakthroughs")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                .padding(.horizontal, AppTheme.Spacing.md)

            ForEach(milestones) { milestone in
                BreakthroughCard(milestone: milestone)
            }
        }
    }
}

struct BreakthroughCard: View {
    let milestone: BreakthroughMilestone

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: milestone.detectedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(milestone.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            Text(milestone.coachMessage)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(formattedDate)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                .padding(.top, 2)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(12)
        .padding(.horizontal, AppTheme.Spacing.md)
    }
}

// MARK: - Awards Summary Header

struct AwardsSummaryHeader: View {
    let earnedCount: Int
    let totalCount: Int

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(AppTheme.Colors.adaptiveTextSecondary.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: totalCount > 0 ? CGFloat(earnedCount) / CGFloat(totalCount) : 0)
                    .stroke(AppTheme.Colors.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(earnedCount)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.Colors.accent)
                    Text("of \(totalCount)")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }
            }

            Text("Awards Earned")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }
}

// MARK: - Category Filter Bar

struct CategoryFilterBar: View {
    @Binding var selectedCategory: AwardCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                CategoryChip(
                    title: "All",
                    icon: "star.fill",
                    isSelected: selectedCategory == nil,
                    action: { selectedCategory = nil }
                )

                ForEach(AwardCategory.allCases, id: \.self) { category in
                    CategoryChip(
                        title: category.displayName,
                        icon: category.icon,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        }
    }
}

struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(AppTheme.Typography.caption)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                isSelected ?
                AppTheme.Colors.accent :
                AppTheme.Colors.adaptiveCardBackground
            )
            .foregroundColor(
                isSelected ?
                .white :
                AppTheme.Colors.adaptiveTextPrimary
            )
            .clipShape(Capsule())
        }
    }
}

// MARK: - Award Badge View

struct AwardBadgeView: View {
    let award: AwardDefinition
    let isEarned: Bool
    let progress: Double
    var showProgress: Bool = false
    var size: BadgeSize = .medium

    enum BadgeSize {
        case small, medium, large

        var iconSize: CGFloat {
            switch self {
            case .small: return 24
            case .medium: return 36
            case .large: return 48
            }
        }

        var frameSize: CGFloat {
            switch self {
            case .small: return 60
            case .medium: return 90
            case .large: return 120
            }
        }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            ZStack {
                // Custom badge design
                CustomAwardBadge(
                    award: award,
                    isEarned: isEarned,
                    size: size.frameSize
                )

                // Progress ring (if showing progress and not earned)
                if showProgress && !isEarned && progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(award.tier.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: size.frameSize + 8, height: size.frameSize + 8)
                        .rotationEffect(.degrees(-90))
                }
            }

            // Award name
            Text(award.name)
                .font(size == .small ? AppTheme.Typography.caption : AppTheme.Typography.subheadline)
                .foregroundColor(
                    isEarned ?
                    AppTheme.Colors.adaptiveTextPrimary :
                    AppTheme.Colors.adaptiveTextSecondary
                )
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Tier badge (for medium and large sizes)
            if size != .small && isEarned {
                Text(award.tier.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(award.tier.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(award.tier.color.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Progress text (for unearned awards with progress)
            if showProgress && !isEarned && progress > 0 {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
            }
        }
        .frame(width: size.frameSize + 20)
    }
}

// MARK: - Awards Preview Section (for AthleteView)

struct AwardsPreviewSection: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(AppRouter.self) private var router
    @ObservedObject private var awardsService = AwardsService.shared
    @State private var earnedAwards: [(award: AwardDefinition, earnedDate: Date?)] = []
    @State private var selectedAward: AwardDefinition? = nil
    @State private var showingDetail = false

    private let maxDisplayCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Header
            HStack {
                Image(systemName: "medal.fill")
                    .foregroundColor(AppTheme.Colors.warning)
                    .font(.title2)

                Text("Awards")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                Spacer()

                Button(action: {
                    router.navigate(to: .awards)
                }) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(AppTheme.Typography.subheadline)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundColor(AppTheme.Colors.accent)
                }
            }

            if awardsService.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading awards...")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.md)
            } else if earnedAwards.isEmpty {
                // Empty state
                VStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "medal")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary.opacity(0.5))

                    Text("No awards yet")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)

                    Text("Keep running to earn your first award!")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.lg)
            } else {
                // Awards grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: AppTheme.Spacing.sm) {
                    ForEach(earnedAwards.prefix(maxDisplayCount), id: \.award.id) { item in
                        Button(action: {
                            selectedAward = item.award
                            showingDetail = true
                        }) {
                            AwardBadgeView(
                                award: item.award,
                                isEarned: true,
                                progress: 1.0,
                                size: .small
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Show "View More" button if there are more awards
                if earnedAwards.count > maxDisplayCount {
                    Button(action: {
                        router.navigate(to: .awards)
                    }) {
                        Text("+ \(earnedAwards.count - maxDisplayCount) more awards")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppTheme.Spacing.xs)
                }
            }
        }
        .surfaceCard()
        .task {
            await loadEarnedAwards()
        }
        .sheet(isPresented: $showingDetail) {
            if let award = selectedAward {
                AwardDetailSheetFromStats(award: award)
            }
        }
        .adaptiveSurfaceTint()
    }

    private func loadEarnedAwards() async {
        let athleteId = dataManager.athlete?.id ?? 0

        // Load lifetime stats with a single DB call (efficient!)
        await awardsService.loadLifetimeStats(for: athleteId)

        // Get earned awards from stats
        earnedAwards = awardsService.getEarnedAwardsFromStats()

        // Sort by tier (platinum first)
        earnedAwards.sort { a, b in
            tierOrder(a.award.tier) > tierOrder(b.award.tier)
        }
    }

    private func tierOrder(_ tier: AwardTier) -> Int {
        switch tier {
        case .platinum: return 4
        case .gold: return 3
        case .silver: return 2
        case .bronze: return 1
        }
    }
}

// MARK: - Award Detail Sheet

struct AwardDetailSheet: View {
    let award: AwardDefinition
    let activities: [Activity]
    @Environment(\.dismiss) private var dismiss

    private let awardsService = AwardsService.shared

    private var progressDetails: (current: Double, target: Double, unit: String, formattedCurrent: String, formattedTarget: String) {
        awardsService.getProgressDetails(for: award, activities: activities)
    }

    private var isEarned: Bool {
        progressDetails.current >= progressDetails.target ||
        (award.requirement.type == .fastestPace && progressDetails.current > 0 && progressDetails.current <= progressDetails.target)
    }

    private var progress: Double {
        guard progressDetails.target > 0 else { return 0 }
        if award.requirement.type == .fastestPace {
            // For pace, lower is better
            if progressDetails.current == 0 { return 0 }
            return progressDetails.current <= progressDetails.target ? 1.0 : min(progressDetails.target / progressDetails.current, 0.99)
        }
        return min(progressDetails.current / progressDetails.target, 1.0)
    }

    private var earnedDate: Date? {
        awardsService.getEarnedAwardsWithDetails(activities: activities, athleteId: 0)
            .first { $0.award.id == award.id }?.earnedDate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                (AppTheme.Colors.adaptiveBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.Spacing.xl) {
                        // Award Icon
                        ZStack {
                            Circle()
                                .fill(
                                    isEarned ?
                                    award.tier.color.opacity(0.2) :
                                    Color.gray.opacity(0.1)
                                )
                                .frame(width: 140, height: 140)

                            if !isEarned && progress > 0 {
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(award.tier.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                    .frame(width: 134, height: 134)
                                    .rotationEffect(.degrees(-90))
                            }

                            Image(systemName: award.icon)
                                .font(.system(size: 60))
                                .foregroundColor(
                                    isEarned ?
                                    award.tier.color :
                                    Color.gray.opacity(0.4)
                                )
                        }

                        // Award Name & Tier
                        VStack(spacing: AppTheme.Spacing.sm) {
                            Text(award.name)
                                .font(AppTheme.Typography.title)
                                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                            Text(award.tier.displayName)
                                .font(AppTheme.Typography.subheadline)
                                .foregroundColor(award.tier.color)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(award.tier.color.opacity(0.15))
                                .clipShape(Capsule())

                            Text(award.category.displayName)
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                        }

                        // Description
                        Text(award.description)
                            .font(AppTheme.Typography.body)
                            .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.Spacing.lg)

                        // Progress Section
                        VStack(spacing: AppTheme.Spacing.md) {
                            Text("Your Progress")
                                .font(AppTheme.Typography.headline)
                                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                            // Progress Bar
                            VStack(spacing: AppTheme.Spacing.sm) {
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(height: 16)

                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isEarned ? award.tier.color : AppTheme.Colors.accent)
                                            .frame(width: geometry.size.width * progress, height: 16)
                                    }
                                }
                                .frame(height: 16)

                                // Current / Target
                                HStack {
                                    Text(progressDetails.formattedCurrent)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundColor(isEarned ? award.tier.color : AppTheme.Colors.accent)

                                    Text("/ \(progressDetails.formattedTarget) \(progressDetails.unit)")
                                        .font(AppTheme.Typography.body)
                                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.lg)

                            // Percentage
                            Text("\(Int(progress * 100))% Complete")
                                .font(AppTheme.Typography.subheadline)
                                .foregroundColor(
                                    isEarned ?
                                    award.tier.color :
                                    AppTheme.Colors.adaptiveTextSecondary
                                )

                            // Remaining (if not earned)
                            if !isEarned {
                                let remaining = progressDetails.target - progressDetails.current
                                if remaining > 0 {
                                    Text(remainingText(remaining: remaining))
                                        .font(AppTheme.Typography.caption)
                                        .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
                                }
                            }
                        }
                        .padding()
                        .background(AppTheme.Colors.adaptiveCardBackground)
                        .cornerRadius(AppTheme.CornerRadius.large)
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Earned Date (if earned)
                        if isEarned, let date = earnedDate {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(award.tier.color)
                                Text("Earned on \(date.formatted(date: .long, time: .omitted))")
                                    .font(AppTheme.Typography.subheadline)
                                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                            }
                            .padding()
                            .background(award.tier.color.opacity(0.1))
                            .cornerRadius(AppTheme.CornerRadius.medium)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, AppTheme.Spacing.xl)
                }
            }
            .adaptiveSurfaceTint()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                            .font(.title2)
                    }
                    .darkSurfaceTint()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func remainingText(remaining: Double) -> String {
        let unit = progressDetails.unit
        switch award.requirement.type {
        case .totalDistance, .singleRunDistance:
            return String(format: "%.1f more %@ to go!", remaining, unit)
        case .totalRuns:
            return "\(Int(remaining)) more \(remaining == 1 ? "run" : "runs") to go!"
        case .weeklyStreak:
            return "\(Int(remaining)) more \(remaining == 1 ? "week" : "weeks") to go!"
        case .totalTime:
            return String(format: "%.1f more %@ to go!", remaining, unit)
        case .elevationGain:
            return String(format: "%.0f more %@ to go!", remaining, unit)
        case .fastestPace:
            return "Run faster to unlock this award!"
        default:
            return "Keep going to unlock this award!"
        }
    }
}

// MARK: - Award Detail Sheet (using lifetime stats - efficient)

struct AwardDetailSheetFromStats: View {
    let award: AwardDefinition
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var awardsService = AwardsService.shared

    private var progressDetails: (current: Double, target: Double, unit: String, formattedCurrent: String, formattedTarget: String) {
        awardsService.getProgressDetailsFromStats(for: award)
    }

    private var hasStats: Bool {
        awardsService.lifetimeStats != nil
    }

    private var isEarned: Bool {
        progressDetails.current >= progressDetails.target ||
        (award.requirement.type == .fastestPace && progressDetails.current > 0 && progressDetails.current <= progressDetails.target)
    }

    private var progress: Double {
        guard progressDetails.target > 0 else { return 0 }
        if award.requirement.type == .fastestPace {
            if progressDetails.current == 0 { return 0 }
            return progressDetails.current <= progressDetails.target ? 1.0 : min(progressDetails.target / progressDetails.current, 0.99)
        }
        return min(progressDetails.current / progressDetails.target, 1.0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                (AppTheme.Colors.adaptiveBackground).ignoresSafeArea()

                if awardsService.isLoading || !hasStats {
                    // Loading state - show while stats are loading
                    VStack(spacing: AppTheme.Spacing.md) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading progress...")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.Spacing.xl) {
                            // Award Icon
                            ZStack {
                                Circle()
                                    .fill(
                                        isEarned ?
                                        award.tier.color.opacity(0.2) :
                                        Color.gray.opacity(0.1)
                                    )
                                    .frame(width: 140, height: 140)

                                if !isEarned && progress > 0 {
                                    Circle()
                                        .trim(from: 0, to: progress)
                                        .stroke(award.tier.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                        .frame(width: 134, height: 134)
                                        .rotationEffect(.degrees(-90))
                                }

                                Image(systemName: award.icon)
                                    .font(.system(size: 60))
                                    .foregroundColor(
                                        isEarned ?
                                        award.tier.color :
                                        Color.gray.opacity(0.4)
                                    )
                            }

                            // Award Name & Tier
                            VStack(spacing: AppTheme.Spacing.sm) {
                                Text(award.name)
                                    .font(AppTheme.Typography.title)
                                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                                Text(award.tier.displayName)
                                    .font(AppTheme.Typography.subheadline)
                                    .foregroundColor(award.tier.color)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(award.tier.color.opacity(0.15))
                                    .clipShape(Capsule())

                                Text(award.category.displayName)
                                    .font(AppTheme.Typography.caption)
                                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                            }

                            // Description
                            Text(award.description)
                                .font(AppTheme.Typography.body)
                                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                                .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.Spacing.lg)

                        // Progress Section
                        VStack(spacing: AppTheme.Spacing.md) {
                            Text("Your Progress")
                                .font(AppTheme.Typography.headline)
                                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                            // Progress Bar
                            VStack(spacing: AppTheme.Spacing.sm) {
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(height: 16)

                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isEarned ? award.tier.color : AppTheme.Colors.accent)
                                            .frame(width: geometry.size.width * progress, height: 16)
                                    }
                                }
                                .frame(height: 16)

                                // Current / Target
                                HStack {
                                    Text(progressDetails.formattedCurrent)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundColor(isEarned ? award.tier.color : AppTheme.Colors.accent)

                                    Text("/ \(progressDetails.formattedTarget) \(progressDetails.unit)")
                                        .font(AppTheme.Typography.body)
                                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.lg)

                            // Percentage
                            Text("\(Int(progress * 100))% Complete")
                                .font(AppTheme.Typography.subheadline)
                                .foregroundColor(
                                    isEarned ?
                                    award.tier.color :
                                    AppTheme.Colors.adaptiveTextSecondary
                                )

                            // Remaining (if not earned)
                            if !isEarned {
                                let remaining = progressDetails.target - progressDetails.current
                                if remaining > 0 {
                                    Text(remainingText(remaining: remaining))
                                        .font(AppTheme.Typography.caption)
                                        .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
                                }
                            }
                        }
                        .padding()
                        .background(AppTheme.Colors.adaptiveCardBackground)
                        .cornerRadius(AppTheme.CornerRadius.large)
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Earned indicator
                        if isEarned {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(award.tier.color)
                                Text("Award Earned!")
                                    .font(AppTheme.Typography.subheadline)
                                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                            }
                            .padding()
                            .background(award.tier.color.opacity(0.1))
                            .cornerRadius(AppTheme.CornerRadius.medium)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, AppTheme.Spacing.xl)
                    } // end ScrollView
                } // end else (hasStats)
            }
            .adaptiveSurfaceTint()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                            .font(.title2)
                    }
                    .darkSurfaceTint()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func remainingText(remaining: Double) -> String {
        let unit = progressDetails.unit
        switch award.requirement.type {
        case .totalDistance, .singleRunDistance:
            return String(format: "%.1f more %@ to go!", remaining, unit)
        case .totalRuns:
            return "\(Int(remaining)) more \(remaining == 1 ? "run" : "runs") to go!"
        case .weeklyStreak:
            return "\(Int(remaining)) more \(remaining == 1 ? "week" : "weeks") to go!"
        case .totalTime:
            return String(format: "%.1f more %@ to go!", remaining, unit)
        case .elevationGain:
            return String(format: "%.0f more %@ to go!", remaining, unit)
        case .fastestPace:
            return "Run faster to unlock this award!"
        default:
            return "Keep going to unlock this award!"
        }
    }
}
