//
//  ProfilePhotoButton.swift
//  LYFESTYL
//
//  The avatar with a camera badge. Tapping it offers Take Photo, Choose Photo
//  and Remove. Used in Account and onboarding.
//

import PhotosUI
import SwiftUI

struct ProfilePhotoButton: View {
    var size: CGFloat = 96

    @Environment(ProfileStore.self) private var profile
    @State private var item: PhotosPickerItem?
    @State private var choosing = false
    @State private var taking = false

    var body: some View {
        let chooseTitle = profile.photo == nil ? "Choose Photo" : "Change Photo"
        Menu {
            if CameraPicker.isAvailable {
                Button("Take Photo", systemImage: "camera") { taking = true }
            }
            Button(chooseTitle, systemImage: "photo.on.rectangle") { choosing = true }
            if profile.photo != nil {
                Button("Remove Photo", systemImage: "trash", role: .destructive) { profile.removePhoto() }
            }
        } label: {
            Avatar(photo: profile.photo, initials: profile.initials, size: size)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: size * 0.29))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.appBackground, Color.appAccent)
                        .offset(x: 2, y: 2)
                }
        }
        .accessibilityLabel("Profile photo")
        .photosPicker(isPresented: $choosing, selection: $item, matching: .images, photoLibrary: .shared())
        .fullScreenCover(isPresented: $taking) {
            CameraPicker { profile.setPhoto(from: $0) }
                .ignoresSafeArea()
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            item = nil
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self) { profile.setPhoto(from: data) }
            }
        }
    }
}
