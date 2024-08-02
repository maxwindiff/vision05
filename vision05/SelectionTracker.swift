class SelectionTracker {
  enum State: CustomStringConvertible {
    case notSelecting
    case selecting
    case selected

    var description: String {
      switch self {
      case .notSelecting: "Not Selecting"
      case .selecting: "Selecting"
      case .selected: "Selected"
      }
    }
  }

  let windowSize = 20
  let dropWindowSize = 5
  let graspThreshold: Float = 0.3
  let ungraspThreshold: Float = 0.5
  let selectingThreshold: Float = 0.6

  private struct Record {
    let timestamp: Double
    let center: SIMD3<Float>
    let angle: Float
    let direction: SIMD3<Float>
    let straightness: Float
  }
  private var records: [Record] = []
  private var state: State = .notSelecting
  private var selection: Record?

  func update(timestamp: Double, center: SIMD3<Float>, angle: Float, direction: SIMD3<Float>, straightness: Float) -> (State, SIMD3<Float>, Float, SIMD3<Float>) {
    addRecord(
      Record(
        timestamp: timestamp,
        center: center,
        angle: angle,
        direction: direction,
        straightness: straightness
      )
    )

    switch state {
    case .notSelecting:
      if straightness > selectingThreshold {
        state = .selecting
        selection = nil
      }

    case .selecting:
      if let preDrop = findAbruptDrop() {
        state = .selected
        selection = preDrop
        records.removeAll()
      }

    case .selected:
      if straightness > ungraspThreshold {
        state = .selecting
        selection = nil
      }
    }

    switch state {
    case .notSelecting:
      return (state, [0, 0, 0], 0, [0, 0, 0])

    case .selecting:
      let averageCenter = records.reduce([0, 0, 0]) { $0 + $1.center } / Float(records.count)
      let averageAngle = records.reduce(0) { $0 + $1.angle } / Float(records.count)
      let averageDirection = records.reduce([0, 0, 0]) { $0 + $1.direction } / Float(records.count)
      return (state, averageCenter, averageAngle, averageDirection)

    case .selected:
      return (state, selection!.center, selection!.angle, selection!.direction)
    }
  }

  private func addRecord(_ value: Record) {
    // TODO: use ring buffer?
    records.append(value)
    if records.count > windowSize {
      records.removeFirst()
    }
  }

  private func findAbruptDrop() -> Record? {
    guard records.count >= dropWindowSize else { return nil }
    for i in stride(from: records.count-1, through: dropWindowSize, by: -1) {
      if records[i - dropWindowSize].straightness - records[i].straightness > graspThreshold {
        return records[i - dropWindowSize]
      }
    }
    return nil
  }
}
