import SwiftUI
import WidgetKit

/// The TracendWidgets extension: the rest-timer Live Activity with its
/// buttons, the Today widgets for the Home Screen and the Lock Screen
/// widgets.
@main
struct TracendWidgetsBundle: WidgetBundle {
  var body: some Widget {
    RestLiveActivity()
    TodayWidget()
    LockScreenWidget()
  }
}
