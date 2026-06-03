import Darwin
import Foundation
import Testing

@testable import Maestro

struct ProcessDetectionSmokeTests {
  @Test func readsCurrentProcessArguments() throws {
    let pid = getpid()

    let argv0 = try #require(ProcessDetection.processArgv0Name(pid: pid))
    let cmdline = try #require(ProcessDetection.processCommandLine(pid: pid))
    let info = try #require(ProcessDetection.processBSDInfo(pid: pid))
    let comm = try #require(ProcessDetection.comm(from: info))

    #expect(!argv0.isEmpty)
    #expect(!cmdline.isEmpty)
    #expect(!comm.isEmpty)
  }

  @Test func listsCurrentProcessGroupWithoutScanningAllProcesses() {
    let pids = ProcessDetection.processGroupPIDs(getpgrp())

    #expect(pids.contains(getpid()))
  }

  @Test func readsCurrentProcessDirectory() throws {
    let path = try #require(ProcessDetection.processCurrentDirectory(pid: getpid()))
    let actual = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    let expected = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).standardizedFileURL

    #expect(actual == expected)
  }

  @Test func returnsNilForInvalidProcessDirectoryPID() {
    #expect(ProcessDetection.processCurrentDirectory(pid: -1) == nil)
  }
}
