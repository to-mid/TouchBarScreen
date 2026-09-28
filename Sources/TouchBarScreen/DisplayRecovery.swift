import CoreGraphics

enum DisplayRecovery {
    static func selectedDisplayID(
        currentID: CGDirectDisplayID?,
        in availableDisplays: [CapturableDisplay],
        previouslySelected: CapturableDisplay?
    ) -> CGDirectDisplayID? {
        if let currentID,
           availableDisplays.contains(where: { $0.id == currentID }) {
            return currentID
        }
        if let previouslySelected,
           let matchingDisplay = availableDisplays.first(where: {
               $0.name == previouslySelected.name
                   && $0.width == previouslySelected.width
                   && $0.height == previouslySelected.height
           }) {
            return matchingDisplay.id
        }
        return availableDisplays.first(where: { !$0.isMain })?.id
            ?? availableDisplays.first?.id
    }
}
