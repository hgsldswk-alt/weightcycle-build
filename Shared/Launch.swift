import Foundation

enum Launch {
    static let freePeriod = false
    static let arguments = ProcessInfo.processInfo.arguments
    static let isTesting = arguments.contains("-ui-testing")
    static let proID = "com.hgsldswk.weightcycle.pro"
    static let trialID = "com.hgsldswk.weightcycle.trial"
}
