import Foundation

@main
struct ProgressClassificationChecks {
    static func main() {
        precondition(ProgressActivityKind("GravelRide") == .bike, "Gravel rides must appear as cycling in the shared activity chart")
        precondition(ProgressActivityKind("Stretch & Mobility") == .mobility, "Mobility sessions must retain their training category")
        precondition(ProgressActivityKind("Trail Run") == .run)
        precondition(ProgressActivityKind("Weight Training") == .strength)
        print("4 activity classification checks passed")
    }
}
