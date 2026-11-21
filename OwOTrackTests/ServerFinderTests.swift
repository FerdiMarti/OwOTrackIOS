//
//  ServerFinderTests.swift
//  OwOTrackTests
//
//  Finding SlimeVR (or the old owoTrack driver) on the network: the search itself against the fake server on this Mac,
//  the addresses it asks, and what the connect screen does with the result.
//

import Foundation
import Testing
@testable import OwOTrack_iOS

extension OwOTrackTests {
    @Suite("Finding the server", .timeLimit(.minutes(1)))
    @MainActor
    struct FindingServer {

        // MARK: the search

        @Test("SlimeVR answers the search, which uses this device's handshake")
        func findsSlimeVR() async {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let result = await search(port: server.port, candidates: ["127.0.0.1"])
            #expect(result == ServerSearchResult(servers: [FoundServer(address: "127.0.0.1", type: .slimeVR)]))
            //SlimeVR keeps it as this device's tracker: its MAC, and no short handshake that would add another tracker
            let handshakes = server.received(type: 3)
            #expect(handshakes.compactMap { SlimeVRHandshake(packet: $0.raw)?.mac }.first == "02:0E:57:00:00:01")
            #expect(handshakes.allSatisfy { $0.raw.count > 12 })
        }

        @Test("the old owoTrack driver is found too, by the short handshake it can read")
        func findsDriver() async {
            let server = FakeServer(mode: .oldDriver)
            defer { server.stop() }
            let result = await search(port: server.port, candidates: ["127.0.0.1"])
            #expect(result == ServerSearchResult(servers: [FoundServer(address: "127.0.0.1", type: .owoTrackDriver)]))
        }

        @Test("nothing answers: an empty result; no network: a reason")
        func nothingFound() async {
            let server = FakeServer(mode: .slimeVR)
            server.stop()       //its port is free now: nobody answers there
            #expect(await search(port: server.port, candidates: ["127.0.0.1"]) == ServerSearchResult())
            #expect(await search(port: 6969, candidates: nil) == ServerSearchResult(failure: "Connect to Wi-Fi to search for SlimeVR"))
        }

        @Test("no handshake can go out (no Local Network access): it says so instead of \"nothing found\"")
        func sendsBlocked() async {
            //a broadcast without permission fails to send, like every send does while iOS blocks the local network
            #expect(await search(port: 6969, candidates: ["255.255.255.255"])
                    == ServerSearchResult(failure: "Allow Local Network access for OwOTrack, then search again"))
        }

        @Test("the addresses asked: the whole home network, around this device in big networks, only private networks")
        func addresses() throws {
            let ip = try #require(LocalServerFinder.parse("192.168.1.37"))
            let home = LocalServerFinder.otherAddresses(ip: ip, mask: 0xFFFF_FF00).map(LocalServerFinder.format)
            #expect(home.count == 253)
            #expect(home.first == "192.168.1.1" && home.last == "192.168.1.254" && !home.contains("192.168.1.37"))

            let office = LocalServerFinder.otherAddresses(ip: try #require(LocalServerFinder.parse("10.20.130.7")), mask: 0xFFFF_0000)
            #expect(office.count == 1021)          //the /22 around it: 10.20.128.1 … 10.20.131.254, without itself
            #expect(LocalServerFinder.format(office.first!) == "10.20.128.1")
            #expect(LocalServerFinder.otherAddresses(ip: ip, mask: 0xFFFF_FFFF).isEmpty)

            #expect(LocalServerFinder.isPrivate(try #require(LocalServerFinder.parse("172.20.0.5"))))
            #expect(!LocalServerFinder.isPrivate(try #require(LocalServerFinder.parse("172.32.0.5"))))
            #expect(!LocalServerFinder.isPrivate(try #require(LocalServerFinder.parse("8.8.8.8"))))
        }

        // MARK: the connect screen

        @Test("Connect without an address searches, fills in the server and connects to it")
        func connectSearches() async {
            let (model, service, finder) = makeModel(found: [FoundServer(address: "192.168.1.230", type: .slimeVR)])
            model.ip = ""
            model.connectPressed()
            #expect(model.status == .searching)
            #expect(!model.canEdit)
            #expect(await waitUntil { service.started == ["192.168.1.230"] })
            #expect(model.ip == "192.168.1.230")
            #expect(finder.searches == 1)
        }

        @Test("the search button fills in the server without connecting")
        func searchButton() async {
            let (model, service, _) = makeModel(found: [FoundServer(address: "my-pc.local", type: .slimeVR)])
            model.ip = "192.168.0.10"
            model.searchPressed()
            #expect(await waitUntil { model.ip == "my-pc.local" })
            #expect(model.status == .notConnected)
            #expect(service.started.isEmpty)
        }

        @Test("several servers: the user picks one, and Connect then connects to it")
        func severalServers() async {
            let servers = [FoundServer(address: "192.168.1.230", type: .slimeVR), FoundServer(address: "192.168.1.40", type: .owoTrackDriver)]
            let (model, service, _) = makeModel(found: servers)
            model.ip = ""
            model.connectPressed()
            #expect(await waitUntil { model.serverChoices == servers })
            #expect(service.started.isEmpty)
            model.chooseServer(nil)             //SwiftUI may close the list before it runs the button's action
            model.chooseServer(servers[1])
            #expect(model.serverChoices.isEmpty)
            #expect(model.ip == "192.168.1.40")
            #expect(service.started == ["192.168.1.40"])
        }

        @Test("nothing found: the reason, without offering to search again")
        func nothingFoundOnScreen() async {
            let (model, _, _) = makeModel(found: [])
            model.searchPressed()
            #expect(await waitUntil { model.status == .failed("No SlimeVR server found on this Wi-Fi") })
            #expect(!model.offersSearch)
        }

        @Test("connecting failed: searching the network is offered, and connects to what it finds")
        func searchAfterFailure() async {
            let (model, service, _) = makeModel(found: [FoundServer(address: "192.168.1.77", type: .slimeVR)])
            model.ip = "192.168.1.230"
            model.connectPressed()
            #expect(service.started == ["192.168.1.230"])
            model.setUnconnected()
            model.setFailed("Couldn't connect to 192.168.1.230")
            #expect(await waitUntil { model.offersSearch })
            model.searchPressed(thenConnect: true)
            #expect(await waitUntil { service.started == ["192.168.1.230", "192.168.1.77"] })
            #expect(!model.offersSearch)
        }

        // MARK: the watch

        @Test("the watch searches through the iPhone, with its own MAC")
        func watchSearches() async {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup(finderCandidates: ["127.0.0.1"])
            defer { relay.stop() }
            var result: ServerSearchResult?
            relay.watch.findServers(port: String(server.port)) { result = $0 }
            #expect(await waitUntil(5) { result != nil })
            #expect(result == ServerSearchResult(servers: [FoundServer(address: "127.0.0.1", type: .slimeVR)]))
            #expect(server.lastHandshake?.mac == "02:0E:57:00:00:02")
            #expect(server.lastHandshake?.firmware.hasPrefix("owoTrack watchOS ") == true)
        }

        @Test("the watch without the iPhone app: it says what to do")
        func watchSearchesWithoutPhone() async {
            let relay = RelaySetup(withHost: false)
            defer { relay.stop() }
            var result: ServerSearchResult?
            relay.watch.findServers(port: "6969") { result = $0 }
            #expect(await waitUntil(10) { result != nil })
            #expect(result == ServerSearchResult(failure: "Open OwOTrack on your iPhone, then search again"))
        }

        // MARK: helpers

        private func search(port: UInt16, candidates: [String]?) async -> ServerSearchResult {
            let finder = LocalServerFinder(mac: FakeHardware.testMac, platform: "iOS", candidates: { candidates }, timing: .fastTest)
            return await withCheckedContinuation { continuation in
                finder.findServers(port: String(port)) { continuation.resume(returning: $0) }
            }
        }

        private func makeModel(found: [FoundServer]) -> (ConnectionModel, RecordingService, FakeFinder) {
            let service = RecordingService()
            let finder = FakeFinder(result: ServerSearchResult(servers: found))
            let model = ConnectionModel(service: service, sharing: nil, finder: finder)
            model.port = "6969"
            return (model, service, finder)
        }
    }
}

extension LocalServerFinder.Timing {
    static let fastTest = LocalServerFinder.Timing(slimeVRResend: 0.15, driverAfter: 0.35, driverResend: 0.55, total: 0.9)
}

//records what the connect screen asks the tracking to do
final class RecordingService: TrackingControl {
    private(set) var started: [String] = []

    func start(ipAdress: String, port: String, magnetometer: Bool, connectUI: ConnectUI) {
        started.append(ipAdress)
    }
    func stop() {}
    func sendReset(yaw: Bool) {}
}

//answers every search with the same result, a moment later
final class FakeFinder: ServerFinding {
    let result: ServerSearchResult
    private(set) var searches = 0

    init(result: ServerSearchResult) {
        self.result = result
    }

    func findServers(port: String, completion: @escaping (ServerSearchResult) -> Void) {
        searches += 1
        let result = self.result
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            completion(result)
        }
    }
}
