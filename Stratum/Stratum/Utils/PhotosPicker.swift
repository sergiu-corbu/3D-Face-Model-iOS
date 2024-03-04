//
//  MediaLoader.swift
//  Bond
//
//  Created by Sergiu Corbu on 26.10.2022.
//

import Foundation
import UIKit
import PhotosUI

enum MediaType {
    
    case image(UIImage?)
    case images([UIImage])
    case videoAssetIdentifier(String?)
}

protocol MediaLoaderDelegate: AnyObject {
    
    func didLoadMediaTypes(_ mediaTypes: [MediaType])
    func didReceiveError(_ error: Error)
    func didCancelOperation()
}

final class MediaLoader: NSObject {
    
    private weak var presentationController: UIViewController?
    private var pickerVC: PHPickerViewController?
    private let selectionLimit: Int
    private let filter: PHPickerFilter
    private let photoLibrary: PHPhotoLibrary = .shared()
    
    private weak var delegate: MediaLoaderDelegate?
    
    public init(
        presentationController: UIViewController?,
        selectionLimit: Int,
        filter: PHPickerFilter = .images,
        delegate: MediaLoaderDelegate
    ) {
        self.presentationController = presentationController
        self.selectionLimit = selectionLimit
        self.filter = filter
        self.delegate = delegate
        super.init()
    }
    
    func present(accessLevel: PHAccessLevel) {
        let authorizationStatus = PHPhotoLibrary.authorizationStatus(for: accessLevel)
        switch authorizationStatus {
        case .authorized: present()
        case .limited: presentLimitedSelectionOptions()
        case .denied: presentDeniedLibraryAccessAlert()
        case .notDetermined: requestAndHandleAuthorizationStatus(for: accessLevel)
        case .restricted: break
        @unknown default:
            break
        }
    }
    
    func present() {
        showPicker()
    }
    
    private func showPicker() {
        var configuration: PHPickerConfiguration = PHPickerConfiguration(photoLibrary: photoLibrary)
        configuration.filter = filter
        configuration.selectionLimit = selectionLimit /// when set to 0, there is no limit
        configuration.preferredAssetRepresentationMode = .current
        self.pickerVC = PHPickerViewController(configuration: configuration)
        self.pickerVC?.delegate = self
        presentationController?.present(pickerVC!, animated: true)
    }
}
       
//MARK: MediaLoading
private extension MediaLoader {
    
    func loadImages(_ phResults: [PHPickerResult]) async throws -> [UIImage] {
        return try await withThrowingTaskGroup(of: UIImage?.self, returning: [UIImage].self) { taskGroup in
            for phResult in phResults {
                taskGroup.addTask(priority: .background) { [weak self] in
                    try await self?.loadImage(phResult)
                }
            }
            return try await taskGroup.reduce(into: [UIImage]()) { partialResult, image in
                if let image {
                    partialResult.append(image)
                }
            }
        }
    }
    
    func loadImage(_ phResult: PHPickerResult) async throws -> UIImage? {
        let provider = phResult.itemProvider
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            return nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { (image, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: image as? UIImage)
            }
        }
    }
    
    func loadVideo(_ result: PHPickerResult) -> String? {
        return result.assetIdentifier
    }
}

private extension MediaLoader {
    
    func requestAndHandleAuthorizationStatus(for accessLevel: PHAccessLevel) {
        PHPhotoLibrary.requestAuthorization(for: accessLevel) { [weak self] authorizationStatus in
            DispatchQueue.main.async {
                switch authorizationStatus {
                case .authorized, .limited:
                    self?.present()
                default:
                    self?.delegate?.didCancelOperation()
                }
            }
        }
    }
    
    func presentLimitedSelectionOptions() {
        let actionSheet = UIAlertController(
            title: "Video Permission", message: nil,
            preferredStyle: .actionSheet
        )
        let selectMoreAction = UIAlertAction(title: "Select more", style: .default) { [weak self] _ in
            self?.handleLimitedLibrarySelection()
        }
        let keepSelectionAction = UIAlertAction(title: "Keep selection", style: .default) { [weak self] _ in
            self?.present()
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { [weak self] _ in
            self?.delegate?.didCancelOperation()
        })
        
        actionSheet.addAction(selectMoreAction)
        actionSheet.addAction(keepSelectionAction)
        actionSheet.addAction(cancelAction)
        
        presentationController?.present(actionSheet, animated: true)
    }
    
    func handleLimitedLibrarySelection() {
        guard let presentationController else {
            return
        }
        
        photoLibrary.presentLimitedLibraryPicker(from: presentationController) { [weak self] _ in
            self?.present()
        }
    }
    
    func presentDeniedLibraryAccessAlert() {
        let alertController = UIAlertController(title: nil, message: "Video Access", preferredStyle: .alert)
        let photosSettingsAction = UIAlertAction(title: "Settings", style: .default) { _ in
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alertController.addAction(photosSettingsAction)
        alertController.addAction(cancelAction)
        
        presentationController?.present(alertController, animated: true)
    }
}

//MARK: Delegate
extension MediaLoader: PHPickerViewControllerDelegate {

    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        guard !results.isEmpty else {
            delegate?.didCancelOperation()
            return
        }

        Task(priority: .background) {
            do {
                var mediaResults = [MediaType]()

                switch filter {
                case .videos:
                    if let result = results.first {
                        mediaResults.append(.videoAssetIdentifier(loadVideo(result)))
                    }
                case .images:
                    if results.count > 1 {
                        mediaResults.append(.images(try await loadImages(results)))
                    } else if let result = results.first {
                        mediaResults.append(.image(try await loadImage(result)))
                    }
                default:
                    return
                }
                await MainActor.run {
                    delegate?.didLoadMediaTypes(mediaResults)
                }
            } catch {
                await MainActor.run {
                    delegate?.didReceiveError(error)
                }
            }
        }
    }
}

