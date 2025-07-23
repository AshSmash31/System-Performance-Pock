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

class helloWorldWidget: PKWidget {
    
    static var identifier: String = "com.ash31.HelloWorld"
    var customizationLabel: String = "HelloWorld"
    var view: NSView!
    
    required init() {
        self.view = PKButton(title: "HelloWorld", target: self, action: #selector(printMessage))
    }
    
    @objc private func printMessage() {
        NSLog("[helloWorldWidget]: Hello, World!")
    }
    
}
