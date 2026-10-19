//
//  ProfileStore.swift
//  LYFESTYL
//
//  The person's name and profile photo. Like goals, they belong to the
//  person, so they sync through iCloud key-value storage with a local copy.
//  The photo is the only image the app keeps, and only because it was chosen
//  on purpose: cropped square and shrunk to 256 px, about 25 KB.
//

import Foundation
import Observation
import UIKit

@Observable
final class ProfileStore {
    private static let nameKey = "profile.name"
    private static let photoKey = "profile.photo"
    static let photoSize: CGFloat = 256

    var name: String {
        didSet { if name != oldValue { write(name, key: Self.nameKey) } }
    }

    private(set) var photo: UIImage?

    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private let local = UserDefaults.standard
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init() {
        name = (NSUbiquitousKeyValueStore.default.string(forKey: Self.nameKey)
            ?? UserDefaults.standard.string(forKey: Self.nameKey)) ?? ""
        photo = Self.readPhoto()
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// "AJ" from "Armaan Jhajj", for the avatar when there's no photo.
    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// Crop to a centered square, shrink, and keep as a small JPEG.
    func setPhoto(from data: Data) {
        guard let image = UIImage(data: data) else { return }
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(
            x: (image.size.width - side) / 2,
            y: (image.size.height - side) / 2,
            width: side,
            height: side
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let target = CGSize(width: Self.photoSize, height: Self.photoSize)
        let square = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(
                x: -crop.minX * target.width / side,
                y: -crop.minY * target.height / side,
                width: image.size.width * target.width / side,
                height: image.size.height * target.height / side
            ))
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.8) else { return }
        photo = square
        cloud.set(jpeg, forKey: Self.photoKey)
        local.set(jpeg, forKey: Self.photoKey)
    }

    func removePhoto() {
        photo = nil
        cloud.removeObject(forKey: Self.photoKey)
        local.removeObject(forKey: Self.photoKey)
    }

    private func reload() {
        if let name = cloud.string(forKey: Self.nameKey), name != self.name { self.name = name }
        photo = Self.readPhoto()
    }

    private func write(_ value: String, key: String) {
        cloud.set(value, forKey: key)
        local.set(value, forKey: key)
    }

    private static func readPhoto() -> UIImage? {
        let data = NSUbiquitousKeyValueStore.default.data(forKey: photoKey) ?? UserDefaults.standard.data(forKey: photoKey)
        return data.flatMap(UIImage.init(data:))
    }
}
