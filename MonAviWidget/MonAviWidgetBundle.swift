import WidgetKit
import SwiftUI

@main
struct MonAviWidgetBundle: WidgetBundle {
    var body: some Widget {
        DayWidget()
        BudgetWidget()
        InvoiceScanWidget()
        if #available(iOS 18.0, *) {
            InvoiceScanControl()
            QuickAddControl()
        }
    }
}
