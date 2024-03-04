//
//  ViewController.swift
//  Stratum
//
//  Created by Sergiu Corbu on 12.01.2024.
//

import Foundation
import UIKit
import RealityKit

class ViewController: UIViewController {
    
    lazy var mediaLoader = MediaLoader(
        presentationController: self, selectionLimit: 20, filter: .images, delegate: self
    )
    
    var imagesDirectory: URL {
        FileManager.default.rootImagesDirectoryPath
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.rightBarButtonItem = .init(title: "Generate 3DModel", style: .done, target: self, action: #selector(create3DModel))
        navigationItem.leftBarButtonItem = .init(title: "Select Photos", style: .done, target: self, action: #selector(selectPhotos))
    }
    
    func saveImagesToDisk(images: [UIImage]) {
        if images.isEmpty {
            return
        }
        
        if FileManager.default.fileExists(atPath: imagesDirectory.path) {
            try? FileManager.default.removeItem(at: imagesDirectory)
        }
        try! FileManager.default.createDirectory(atPath: imagesDirectory.path(), withIntermediateDirectories: false, attributes: nil)
        
        for (index, image) in images.enumerated() {
            if let data = image.jpegData(compressionQuality: 0.8) {
                do {
                    try data.write(to: imagesDirectory.appending(path: index.description), options: .atomic)
                    print("did write image to file")
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    @objc func selectPhotos() {
        mediaLoader.present(accessLevel: .readWrite)
    }
    
    @objc func create3DModel() {
        guard PhotogrammetrySession.isSupported else {
            return
        }
        
        var configuration = PhotogrammetrySession.Configuration()
        configuration.checkpointDirectory = imagesDirectory.appendingPathComponent("Snapshots/")
        do {
            let session = try PhotogrammetrySession(
                input: imagesDirectory,
                configuration: configuration)
            try session.process(requests: [.modelFile(url: imagesDirectory.appendingPathComponent("model.usdz"))
            ])
            Task {
                for try await output in session.outputs {
                    switch output {
                    case .processingComplete:
                        print("processed")
                    case .requestError(let request, let error):
                        print(error.localizedDescription)
                    case .requestComplete(let request, let result):
                        print("finished request")
                    case .requestProgress(let request, let fractionComplete):
                        print("Completed fraction: \(fractionComplete)")
                    case .inputComplete:
                        print("input complete")
                    case .invalidSample(let id, let reason):
                        print("Invalid sample")
                    case .skippedSample(let id):
                        print("skipped sample")
                    case .automaticDownsampling:
                        print("image was downsampled")
                    case .processingCancelled:
                        print("cancelled")
                    default:
                        break
                    }
                }
            }
        } catch {
            print(error.localizedDescription)
        }
    }
}

extension ViewController: MediaLoaderDelegate {
    func didLoadMediaTypes(_ mediaTypes: [MediaType]) {
        guard case .images(let images) = mediaTypes.first else {
            return
        }
        saveImagesToDisk(images: images)
    }
    
    func didReceiveError(_ error: Error) {}
    func didCancelOperation() {}
}
