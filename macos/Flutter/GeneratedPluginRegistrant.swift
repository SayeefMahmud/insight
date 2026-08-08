//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import device_info_plus
import flutter_secure_storage_darwin
import hotkey_manager_macos
import irondash_engine_context
import keypress_simulator_macos
import screen_retriever_macos
import shared_preferences_foundation
import super_native_extensions
import tray_manager
import window_manager

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  DeviceInfoPlusMacosPlugin.register(with: registry.registrar(forPlugin: "DeviceInfoPlusMacosPlugin"))
  FlutterSecureStorageDarwinPlugin.register(with: registry.registrar(forPlugin: "FlutterSecureStorageDarwinPlugin"))
  HotkeyManagerMacosPlugin.register(with: registry.registrar(forPlugin: "HotkeyManagerMacosPlugin"))
  IrondashEngineContextPlugin.register(with: registry.registrar(forPlugin: "IrondashEngineContextPlugin"))
  KeypressSimulatorMacosPlugin.register(with: registry.registrar(forPlugin: "KeypressSimulatorMacosPlugin"))
  ScreenRetrieverMacosPlugin.register(with: registry.registrar(forPlugin: "ScreenRetrieverMacosPlugin"))
  SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
  SuperNativeExtensionsPlugin.register(with: registry.registrar(forPlugin: "SuperNativeExtensionsPlugin"))
  TrayManagerPlugin.register(with: registry.registrar(forPlugin: "TrayManagerPlugin"))
  WindowManagerPlugin.register(with: registry.registrar(forPlugin: "WindowManagerPlugin"))
}
