//
//  AppDelegate.swift
//  VGCameraVideo
//
//  Created by 周智伟 on 2020/11/13.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {


    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        window = UIWindow.init()
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
        return true
    }

}

