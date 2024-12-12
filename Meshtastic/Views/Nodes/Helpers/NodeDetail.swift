/*
 Abstract:
 A view showing the details for a node.
 */

import SwiftUI
import WeatherKit
import MapKit
import CoreLocation
import OSLog

struct NodeDetail: View {
	private let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	private static let relativeFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter
	}()
	var modemPreset: ModemPresets = ModemPresets(
		rawValue: UserDefaults.modemPreset
	) ?? ModemPresets.longFast

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var showingShutdownConfirm: Bool = false
	@State private var showingRebootConfirm: Bool = false
	@State private var dateFormatRelative: Bool = true
	@State private var currentDevice: DeviceHardware?

	// The node the device is currently connected to
	var connectedNode: NodeInfoEntity?

	// The node information being displayed on the detail screen
	@ObservedObject
	var node: NodeInfoEntity

	var columnVisibility = NavigationSplitViewVisibility.all

	var body: some View {
		NavigationStack {
			List {
				let connectedNode = getNodeInfo(
					id: bleManager.connectedPeripheral?.num ?? -1,
					context: context
				)

				Section("Hardware") {
					NodeInfoItem(node: node, supported: currentDevice?.activelySupported ?? false)
				}
				Section("Node") {
					HStack(alignment: .center) {
						Spacer()
						CircleText(
							text: node.user?.shortName ?? "?",
							color: Color(UIColor(hex: UInt32(node.num))),
							circleSize: 75
						)
						if node.snr != 0 && !node.viaMqtt && node.hopsAway == 0 {
							Spacer()
							VStack {
								let signalStrength = getLoRaSignalStrength(snr: node.snr, rssi: node.rssi, preset: modemPreset)
								LoRaSignalStrengthIndicator(signalStrength: signalStrength)
								Text("Signal \(signalStrength.description)").font(.footnote)
								Text("SNR \(String(format: "%.2f", node.snr))dB")
									.foregroundColor(getSnrColor(snr: node.snr, preset: modemPreset))
									.font(.caption)
								Text("RSSI \(node.rssi)dB")
									.foregroundColor(getRssiColor(rssi: node.rssi))
									.font(.caption)
							}
						}
						if node.telemetries?.count ?? 0 > 0 {
							Spacer()
							BatteryGauge(node: node)
						}
						Spacer()
					}
					.listRowSeparator(.hidden)
					if let user = node.user {
						if !user.keyMatch {
							Label {
								VStack(alignment: .leading) {
									Text("Public Key Mismatch")
										.font(.title3)
										.foregroundStyle(.red)
									Text("The most recent public key for this node does not match the previously recorded key. You can delete the node and let it exchange keys again, but this also may indicate a more serious security problem. Contact the user through another trusted channel to determine if the key change was due to a factory reset or other intentional action.")
										.foregroundStyle(.secondary)
										.font(.callout)
								}
							} icon: {
								Image(systemName: "key.slash.fill")
									.symbolRenderingMode(.multicolor)
									.foregroundStyle(.red)
							}
						}
					}
					HStack {
						Label {
							Text("Node Number")
						} icon: {
							Image(systemName: "number")
								.symbolRenderingMode(.hierarchical)
						}
						Spacer()
						Text(String(node.num))
						.textSelection(.enabled)
					}

					HStack {
						Label {
							Text("User Id")
						} icon: {
							Image(systemName: "person")
								.symbolRenderingMode(.multicolor)
						}
						Spacer()
						Text(node.num.toHex())
						.textSelection(.enabled)
					}

					if let metadata = node.metadata {
						HStack {
							Label {
								Text("firmware.version")
							} icon: {
								Image(systemName: "memorychip")
									.symbolRenderingMode(.multicolor)
							}
							Spacer()

							Text(metadata.firmwareVersion ?? "unknown".localized)
						}
					}

					if let role = node.user?.role, let deviceRole = DeviceRoles(rawValue: Int(role)) {
						HStack {
							Label {
								Text("Role")
							} icon: {
								Image(systemName: deviceRole.systemName)
									.symbolRenderingMode(.multicolor)
							}
							Spacer()
							Text(deviceRole.name)
						}
					}

					if let dm = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0")).lastObject as? TelemetryEntity, dm.uptimeSeconds > 0 {
						HStack {
							Label {
								Text("\("uptime".localized)")
							} icon: {
								Image(systemName: "checkmark.circle.fill")
									.foregroundColor(.green)
									.symbolRenderingMode(.hierarchical)
							}
							Spacer()

							let now = Date.now
							let later = now + TimeInterval(dm.uptimeSeconds)
							let uptime = (now..<later).formatted(.components(style: .narrow))
							Text(uptime)
								.textSelection(.enabled)
						}
					}

					if let firstHeard = node.firstHeard, firstHeard.timeIntervalSince1970 > 0 {
						HStack {
							Label {
								Text("First heard")
							} icon: {
								Image(systemName: "clock")
									.symbolRenderingMode(.multicolor)
							}
							Spacer()
							if dateFormatRelative, let text = Self.relativeFormatter.string(for: firstHeard) {
								Text(text)
									.textSelection(.enabled)
							} else {
								Text(firstHeard.formatted())
									.textSelection(.enabled)
							}
						}.onTapGesture {
							dateFormatRelative.toggle()
						}
					}

					if let lastHeard = node.lastHeard, lastHeard.timeIntervalSince1970 > 0 {
						HStack {
							Label {
								Text("Last heard")
							} icon: {
								Image(systemName: "clock.arrow.circlepath")
									.symbolRenderingMode(.multicolor)
							}
							Spacer()

							if dateFormatRelative, let text = Self.relativeFormatter.string(for: lastHeard) {
								Text(text)
									.textSelection(.enabled)
							} else {
								Text(lastHeard.formatted())
									.textSelection(.enabled)
							}
						}.onTapGesture {
							dateFormatRelative.toggle()
						}
					}
				}
				if node.hasPositions && UserDefaults.environmentEnableWeatherKit || node.hasEnvironmentMetrics {
					Section("Environment") {
						if !node.hasEnvironmentMetrics {
							LocalWeatherConditions(location: node.latestPosition?.nodeLocation)
						} else {
							VStack {
								if node.latestEnvironmentMetrics?.iaq ?? -1 > 0 {
									IndoorAirQuality(iaq: Int(node.latestEnvironmentMetrics?.iaq ?? 0), displayMode: .gradient)
										.padding(.vertical)
								}
								LazyVGrid(columns: gridItemLayout) {
									WeatherConditionsCompactWidget(temperature: String(node.latestEnvironmentMetrics?.temperature.shortFormattedTemperature() ?? "99°"), symbolName: "cloud.sun", description: "TEMP")
									if node.latestEnvironmentMetrics?.relativeHumidity ?? 0.0 > 0.0 {
										HumidityCompactWidget(humidity: Int(node.latestEnvironmentMetrics?.relativeHumidity ?? 0.0), dewPoint: String(format: "%.0f", calculateDewPoint(temp: node.latestEnvironmentMetrics?.temperature ?? 0.0, relativeHumidity: node.latestEnvironmentMetrics?.relativeHumidity ?? 0.0)) + "°")
									}
									if node.latestEnvironmentMetrics?.barometricPressure ?? 0.0 > 0.0 {
										PressureCompactWidget(pressure: String(format: "%.2f", node.latestEnvironmentMetrics?.barometricPressure ?? 0.0), unit: "hPA", low: node.latestEnvironmentMetrics?.barometricPressure ?? 0.0 <= 1009.144)
									}
									if node.latestEnvironmentMetrics?.windSpeed ?? 0.0 > 0.0 {
										let windSpeed = Measurement(value: Double(node.latestEnvironmentMetrics?.windSpeed ?? 0.0), unit: UnitSpeed.metersPerSecond)
										let windGust = Measurement(value: Double(node.latestEnvironmentMetrics?.windGust ?? 0.0), unit: UnitSpeed.metersPerSecond)
										let direction = cardinalValue(from: Double(node.latestEnvironmentMetrics?.windDirection ?? 0))
										WindCompactWidget(speed: windSpeed.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))),
														  gust: node.latestEnvironmentMetrics?.windGust ?? 0.0 > 0.0 ? windGust.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))) : "", direction: direction)
									}
								}
								.padding(node.latestEnvironmentMetrics?.iaq ?? -1 > 0 ? .bottom : .vertical)
							}
						}
					}
				}
				Section("Logs") {
					// Metrics
					NavigationLink {
						DeviceMetricsLog(node: node)
					} label: {
						Label {
							Text("Device Metrics Log")
						} icon: {
							Image(systemName: "flipphone")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasDeviceMetrics)

					NavigationLink {
						NodeMapSwiftUI(node: node, showUserLocation: connectedNode?.num ?? 0 == node.num)
					} label: {
						Label {
							Text("Node Map")
						} icon: {
							Image(systemName: "map")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasPositions)

					NavigationLink {
						PositionLog(node: node)
					} label: {
						Label {
							Text("Position Log")
						} icon: {
							Image(systemName: "mappin.and.ellipse")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasPositions)

					NavigationLink {
						EnvironmentMetricsLog(node: node)
					} label: {
						Label {
							Text("Environment Metrics Log")
						} icon: {
							Image(systemName: "cloud.sun.rain")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasEnvironmentMetrics)

					NavigationLink {
						TraceRouteLog(node: node)
					} label: {
						Label {
							Text("Trace Route Log")
						} icon: {
							Image(systemName: "signpost.right.and.left")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(node.traceRoutes?.count ?? 0 == 0)

					NavigationLink {
						DetectionSensorLog(node: node)
					} label: {
						Label {
							Text("Detection Sensor Log")
						} icon: {
							Image(systemName: "sensor")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasDetectionSensorMetrics)

					if node.hasPax {
						NavigationLink {
							PaxCounterLog(node: node)
						} label: {
							Label {
								Text("paxcounter.log")
							} icon: {
								Image(systemName: "figure.walk.motion")
									.symbolRenderingMode(.multicolor)
							}
						}
						.disabled(!node.hasPax)
					}
				}

				Section("Actions") {
					if let user = node.user {
						NodeAlertsButton(
							context: context,
							node: node,
							user: user
						)
					}

					if let connectedNode {
						FavoriteNodeButton(
							bleManager: bleManager,
							context: context,
							node: node
						)
						if connectedNode.num != node.num {
							ExchangePositionsButton(
								bleManager: bleManager,
								node: node
							)
							TraceRouteButton(
								bleManager: bleManager,
								node: node
							)
							if node.isStoreForwardRouter {
								ClientHistoryButton(
									bleManager: bleManager,
									connectedNode: connectedNode,
									node: node
								)
							}
							DeleteNodeButton(
								bleManager: bleManager,
								context: context,
								connectedNode: connectedNode,
								node: node
							)
						}
					}
				}

				if let metadata = node.metadata,
				   let connectedNode,
				   self.bleManager.connectedPeripheral != nil {
					Section("Administration") {
						if connectedNode.myInfo?.hasAdmin ?? false {
							Button {
								let adminMessageId = bleManager.requestDeviceMetadata(
									fromUser: connectedNode.user!,
									toUser: node.user!,
									adminIndex: connectedNode.myInfo!.adminIndex,
									context: context
								)
								if adminMessageId > 0 {
									Logger.mesh.info("Sent node metadata request from node details")
								}
							} label: {
								Label {
									Text("Refresh device metadata")
								} icon: {
									Image(systemName: "arrow.clockwise")
								}
							}
						}

						if metadata.canShutdown {
							Button {
								showingShutdownConfirm = true
							} label: {
								Label("Power Off", systemImage: "power")
							}.confirmationDialog(
								"are.you.sure",
								isPresented: $showingShutdownConfirm
							) {
								Button("Shutdown Node?", role: .destructive) {
									if !bleManager.sendShutdown(
										fromUser: connectedNode.user!,
										toUser: node.user!,
										adminIndex: connectedNode.myInfo!.adminIndex
									) {
										Logger.mesh.warning("Shutdown Failed")
									}
								}
							}
						}

						Button {
							showingRebootConfirm = true
						} label: {
							Label(
								"reboot",
								systemImage: "arrow.triangle.2.circlepath"
							)
						}.confirmationDialog(
							"are.you.sure",
							isPresented: $showingRebootConfirm
						) {
							Button("reboot.node", role: .destructive) {
								if !bleManager.sendReboot(
									fromUser: connectedNode.user!,
									toUser: node.user!,
									adminIndex: connectedNode.myInfo!.adminIndex
								) {
									Logger.mesh.warning("Reboot Failed")
								}
							}
						}
					}
				}
			}
			.listStyle(.insetGrouped)
			.onFirstAppear {
				Api().loadDeviceHardwareData { (hw) in
					for device in hw {
						let currentHardware = node.user?.hwModel ?? "UNSET"
						let deviceString = device.hwModelSlug.replacingOccurrences(of: "_", with: "")
						if deviceString == currentHardware {
							currentDevice = device
						}
					}
				}
			}
		}
	}
}

func cardinalValue(from heading: Double) -> String {
	switch heading {
	case 0 ..< 22.5:
		return "North"
	case 22.5 ..< 67.5:
		return "North East"
	case 67.5 ..< 112.5:
		return "East"
	case 112.5 ..< 157.5:
		return "South East"
	case 157.5 ..< 202.5:
		return "South"
	case 202.5 ..< 247.5:
		return "South West"
	case 247.5 ..< 292.5:
		return "West"
	case 292.5 ..< 337.5:
		return "North West"
	case 337.5 ... 360.0:
		return "North"
	default:
		return ""
	}
}
