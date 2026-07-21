import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testBackgroundModelDescriptorRoundTripsThroughTaskDescription() throws {
    let transferId = String(repeating: "a", count: 64)
    let descriptor = try BackgroundModelTransferDescriptor(
      arguments: [
        "transferId": transferId,
        "sourceUrl": "https://models.example.test/model.gguf",
        "destinationPath": "/tmp/model.gguf.part",
        "expectedBytes": 512,
      ]
    )

    let restored = BackgroundModelTransferDescriptor.decode(
      taskDescription: try descriptor.encodedTaskDescription()
    )

    XCTAssertEqual(restored, descriptor)
    XCTAssertEqual(restored?.transferId, transferId)
  }

  func testBackgroundModelDescriptorRejectsUnsafeOrUnpinnedRequests() {
    XCTAssertThrowsError(
      try BackgroundModelTransferDescriptor(
        arguments: [
          "transferId": "not-stable",
          "sourceUrl": "file:///tmp/model.gguf",
          "destinationPath": "relative/model.gguf.part",
          "expectedBytes": 0,
        ]
      )
    )
  }

}
