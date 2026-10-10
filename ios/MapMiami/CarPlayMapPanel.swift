import CarPlay

/// iOS 27 adds CPMapPanel for a custom list beside the CarPlay map.
/// This SDK does not ship that class. When it is present, the same route rows are handed to it.
/// Until then, CPMapTemplate trip previews show those rows.
enum CarPlayMapPanel {
    @MainActor
    static func presentIfAvailable(on template: CPMapTemplate, trip: Trip) {
        guard let panelClass = NSClassFromString("CPMapPanel") as? NSObject.Type,
              let sectionClass = NSClassFromString("CPMapPanelSection") as? NSObject.Type,
              panelClass.instancesRespond(to: NSSelectorFromString("setTitle:")),
              sectionClass.instancesRespond(to: NSSelectorFromString("setItems:"))
        else { return }

        let panel = panelClass.init()
        panel.setValue("Routes", forKey: "title")
        let section = sectionClass.init()
        let items: [CPInformationItem] = trip.routes.prefix(12).map { route in
            CPInformationItem(title: route.label, detail: "\(RouteFormat.minutes(route.durationSeconds)). \(route.flood.summary) Not a closure.")
        }
        section.setValue(items, forKey: "items")
        if panel.responds(to: NSSelectorFromString("setSections:")) {
            panel.setValue([section], forKey: "sections")
        }
        for name in ["setMapPanel:", "showMapPanel:", "presentMapPanel:"] {
            let selector = NSSelectorFromString(name)
            if template.responds(to: selector) {
                template.perform(selector, with: panel)
                return
            }
        }
    }
}
