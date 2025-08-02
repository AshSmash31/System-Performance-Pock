//
//  helloWorldWidget.swift
//  HelloWorld
//
//  Created by Akshat Nair on 7/23/25.
//
//

import Foundation
import AppKit
import PockKit
import IOKit
import IOKit.graphics

class helloWorldWidget: PKWidget {
    static var identifier: String = "com.ash31.HelloWorld"
    var customizationLabel: String = "System Performance"
    var view: NSView!
    var cpuLabel: NSTextField!
    var ramLabel: NSTextField!
    var cpuGraphView: GraphView!
    var ramGraphView: GraphView!
    var cpuHistory: [Double] = []
    var ramHistory: [Double] = []
    let maxHistoryPoints = 20
    var timer: Timer?
    
    var previousCPUTicks: host_cpu_load_info = host_cpu_load_info()

    required init() {
        // Horizontal stack view with safe layout
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 16
        stackView.alignment = .centerY
        stackView.distribution = .fillProportionally

        // CPU Label
        cpuLabel = NSTextField(labelWithString: "CPU: Loading…")
        cpuLabel.alignment = .center
        cpuLabel.textColor = NSColor.systemRed
        cpuLabel.isBezeled = false
        cpuLabel.drawsBackground = false
        cpuLabel.isEditable = false
        cpuLabel.isSelectable = false
        cpuLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        cpuLabel.wantsLayer = true
        cpuLabel.layer?.zPosition = 1

        // RAM Label
        ramLabel = NSTextField(labelWithString: "RAM: Loading…")
        ramLabel.alignment = .center
        ramLabel.textColor = NSColor.systemGreen
        ramLabel.isBezeled = false
        ramLabel.drawsBackground = false
        ramLabel.isEditable = false
        ramLabel.isSelectable = false
        ramLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)

        // Graphs for CPU and RAM
        cpuGraphView = GraphView()
        cpuGraphView.color = .systemRed
        cpuGraphView.translatesAutoresizingMaskIntoConstraints = false
        cpuGraphView.widthAnchor.constraint(equalToConstant: 50).isActive = true
        cpuGraphView.heightAnchor.constraint(equalToConstant: 15).isActive = true

        ramGraphView = GraphView()
        ramGraphView.color = .systemGreen
        ramGraphView.translatesAutoresizingMaskIntoConstraints = false
        ramGraphView.widthAnchor.constraint(equalToConstant: 50).isActive = true
        ramGraphView.heightAnchor.constraint(equalToConstant: 17).isActive = true

        // Stack for CPU label above graph
        let cpuStack = NSStackView()
        cpuStack.orientation = .vertical
        cpuStack.spacing = 2
        cpuStack.alignment = .centerX
        cpuStack.addArrangedSubview(cpuLabel)
        cpuStack.addArrangedSubview(cpuGraphView)

        // Stack for RAM label above graph
        let ramStack = NSStackView()
        ramStack.orientation = .vertical
        ramStack.spacing = 2
        ramStack.alignment = .centerX
        ramStack.addArrangedSubview(ramLabel)
        ramStack.addArrangedSubview(ramGraphView)

        // Add to main stack view
        stackView.addArrangedSubview(cpuStack)
        stackView.addArrangedSubview(ramStack)

        self.view = stackView

        // Start updating metrics
        startUpdatingMetrics()
    }

    func startUpdatingMetrics() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(updateMetrics), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common) // Ensure timer stays active while scrolling/touchbar in use
        updateMetrics() // Immediate initial update
    }

    @objc func updateMetrics() {
        let cpuUsage = Double(getCPUUsage())
        cpuLabel.stringValue = "CPU: \(Int(cpuUsage))%"
        cpuHistory.append(cpuUsage)
        if cpuHistory.count > maxHistoryPoints { cpuHistory.removeFirst() }
        cpuGraphView.data = cpuHistory
        cpuGraphView.setNeedsDisplay(cpuGraphView.bounds)

        let totalMemory = Double(ProcessInfo.processInfo.physicalMemory) / 1024.0 / 1024.0 / 1024.0

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let usedBytes = (UInt64(stats.active_count) + UInt64(stats.inactive_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * UInt64(vm_page_size)
            let usedGB = Double(usedBytes) / 1024.0 / 1024.0 / 1024.0
            let usedPercent = (usedGB / totalMemory) * 100.0
            ramLabel.stringValue = String(format: "RAM: %.0f%%", usedPercent)
            ramHistory.append(usedPercent)
            if ramHistory.count > maxHistoryPoints { ramHistory.removeFirst() }
            ramGraphView.data = ramHistory
            ramGraphView.setNeedsDisplay(ramGraphView.bounds)
        } else {
            ramLabel.stringValue = "RAM: Loading…"
        }
    }

    func getCPUUsage() -> Int {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var cpuInfo = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        if result != KERN_SUCCESS { return -1 }

        // Calculate deltas
        let user = Double(cpuInfo.cpu_ticks.0 - previousCPUTicks.cpu_ticks.0)
        let system = Double(cpuInfo.cpu_ticks.1 - previousCPUTicks.cpu_ticks.1)
        let idle = Double(cpuInfo.cpu_ticks.2 - previousCPUTicks.cpu_ticks.2)
        let nice = Double(cpuInfo.cpu_ticks.3 - previousCPUTicks.cpu_ticks.3)
        let totalTicks = user + system + idle + nice
        let usage = (user + system + nice) / totalTicks * 100.0

        previousCPUTicks = cpuInfo
        return Int(usage.rounded())
    }

    func getMemoryUsage() -> String {
        let total = ProcessInfo.processInfo.physicalMemory / 1024 / 1024 / 1024

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result != KERN_SUCCESS { return "0/\(total) GB" }

        let usedBytes = (UInt64(stats.active_count) + UInt64(stats.inactive_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * UInt64(vm_page_size)
        let usedGB = Double(usedBytes) / 1024.0 / 1024.0 / 1024.0

        return String(format: "%.1f/%.0f GB", usedGB, Double(total))
    }
}

// GraphView class to draw history line graphs
class GraphView: NSView {
    override var isOpaque: Bool { false } // Ensure transparent background

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
//        wantsLayer = true
        wantsLayer = true
        layer?.zPosition = 0
//        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.backgroundColor = nil
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.zPosition = 0
    }

    var data: [Double] = []
    var color: NSColor = .systemBlue

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard data.count > 1 else { return }

        let path = NSBezierPath()
        let stepX = bounds.width / CGFloat(max(data.count - 1, 1))
        for (i, value) in data.enumerated() {
            let x = CGFloat(i) * stepX
            var y: CGFloat
            if color == NSColor.systemGreen {
                // RAM graph: scale y so that 80-100% maps near top with padding
                let clampedValue = max(0, min(value, 100))
                let normalized = CGFloat((clampedValue - 80) / 20) // 0 to 1 for 80-100%
                y = max(0, min(normalized, 1)) * bounds.height * 0.9 + bounds.height * 0.05
                if clampedValue < 80 {
                    y = bounds.height * 0.05
                }
            } else {
                // CPU graph: scale y with padding
                y = CGFloat(value) / 100.0 * bounds.height * 0.9 + bounds.height * 0.05
            }
            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        color.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
