import SwiftUI
import WidgetKit

/// The TracendWidgets extension: the rest-timer Live Activity with its
/// buttons. Home and Lock Screen widgets join it in D2.
@main
struct TracendWidgetsBundle: WidgetBundle {
  var body: some Widget {
    RestLiveActivity()
  }
}
