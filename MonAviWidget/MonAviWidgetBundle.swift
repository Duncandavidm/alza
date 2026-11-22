import WidgetKit
import SwiftUI

@main
struct MonAviWidgetBundle: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
        InvoiceScanWidget()
        if #available(iOS 18.0, *) {
            InvoiceScanControl()
        }
    }
}
