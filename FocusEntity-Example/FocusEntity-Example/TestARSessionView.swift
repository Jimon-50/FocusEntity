//
//  ARTestSessionView.swift
//  FocusEntity-Example
//
//  Created by 五十嵐卓也 on 2023/06/29.
//  Copyright © 2023 Max Cobb. All rights reserved.
//

import SwiftUI
import Combine


extension View {
    @ViewBuilder func isHidden(_ hidden: Bool, remove: Bool = false) -> some View {
        if hidden {
            if !remove {
                self.hidden()
            }
            // return nothing
        } else {
            self
        }
    }
}

struct TestARSessionView: View {
    @State var isShowingARView = false
    @State var sessionCounter: Int = 0
    @State var timeCounter: Int = 0
    @State var timer: Publishers.Autoconnect<Timer.TimerPublisher> = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var testResults: [String] = []
    @State var isAutoTest: Bool = false
    @State var isFlashButton: Bool = false
    @State var thermalState:String = "unknown"
    var maxDuration: Int = 3*60 // 3 minuites
    
    var body: some View {
        ZStack() {
            if isShowingARView {
                ZStack() {
                    ARSessionView(autoStartSec: isAutoTest ? 5: 0).edgesIgnoringSafeArea(.all)  // 5 seconds
                    VStack() {
                        VStack() {
                            Group() {
                                Text("Session: \(sessionCounter) Time: " + sec2String(timeCounter))
                                Text("Thermal State: " + thermalState)
                                
                            }
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.4))
            
                        Spacer()
                    }
                    .onAppear() {
                        timeCounter = 0
                        sessionCounter += 1
                        thermalState = termalState2String(ProcessInfo.processInfo.thermalState)
                        //Registering for Thermal Change notifications
                        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { notification in
                            let state = ProcessInfo.processInfo.thermalState
                            let df = DateFormatter()
                            df.dateFormat = "yyyy/MM/dd HH:mm:ss.SSS"
                            debugPrint("\(df.string(from: Date())) ProcessInfo.thermalStateDidChangeNotification state=\(state)")
                        }
                    }
                    .onDisappear() {
                        testResults.append("Session: \(sessionCounter) Time: \(sec2String(timeCounter)) TermalState: \(thermalState)")
                        timeCounter = 0
                    }
                }
            }
            VStack() {
                VStack() {
                    Text("AR Session Text Results")
                        .font(.system(size: 24))
                    ScrollView {
                        VStack {
                            ForEach(testResults, id: \.hashValue) {result in
                                Text(result).font(.system(size: 14))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .border(.gray)
                }.isHidden(isShowingARView)
                
                Spacer()
                
                ZStack() {
                    Button(action: {
                        isShowingARView.toggle()
                    }) {
                        Text(isShowingARView ? "Stop AR": "Start AR")
                            .font(.system(size: 24))
                            .foregroundColor(isFlashButton ? .red : .white)
                            .padding(10)
                            .frame(width: 120)
                    }
                    .background(.blue)
                    .cornerRadius(10)
                    
                    HStack() {
                        Spacer()
                        Toggle("Auto", isOn: $isAutoTest)
                            .frame(width: 100)
                            .padding(10)
                    }
                }
            }
            .onReceive(timer) { _ in
                timeCounter += 1
                if isAutoTest {
                    if timeCounter >= maxDuration {
                        isShowingARView = false
                    } else if timeCounter > 5 {
                        isShowingARView = true
                    }
                    withAnimation(.easeInOut.speed(0.5)) {
                        self.isFlashButton.toggle()
                    }
                }
            }
        }
    }
    
    func sec2String(_ sec: Int) -> String {
        let min = timeCounter/60
        return (min > 0 ? String(min) + "m": "") + String(timeCounter%60) + "s"
    }
    
    func termalState2String(_ state: ProcessInfo.ThermalState) -> String {
        var str = "unknown"
        switch state {
        case .nominal:
            str = "norminal"
            // No action required as such
        case .fair:
            str = "fair"
            // Starts getting heated up. Try reducing CPU expensive operations.
        case .serious:
            str = "serious"
            // Time to reduce the CPU usage and make sure you are not burning more
        case .critical:
            str = "critical"
            // Reduce every operations and make initiate device cool down.
        default:
            break
        }
        return str
    }
}

