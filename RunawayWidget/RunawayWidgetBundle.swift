//
//  RunawayWidgetBundle.swift
//  RunawayWidget
//
//  Created by Jack Rudelic on 2/18/25.
//

import WidgetKit
import SwiftUI

@main
struct RunawayWidgetBundle: WidgetBundle {
    var body: some Widget {
        RunawayWidget()
        CommitmentWidget()
        RaceCountdownWidget()
        RunawayWidgetControl()
    }
}
